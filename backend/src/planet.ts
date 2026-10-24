import { AuthAPIError } from "./auth";

export const PLANET_PATH = "/v1/planet";
export const PLANET_INVITES_PATH = "/v1/planet/invites";
export const PLANET_INVITE_ACCEPT_PATH = "/v1/planet/invites/accept";
export const PLANET_MEMBERSHIP_PATH = "/v1/planet/membership";
export const INVITE_LANDING_PATH = "/invite";
export const APPLE_APP_SITE_ASSOCIATION_PATH = "/.well-known/apple-app-site-association";

const MAX_REQUEST_BYTES = 4_096;
const INVITE_TTL_SECONDS = 7 * 24 * 60 * 60;
const RATE_WINDOW_SECONDS = 10 * 60;
const CREATE_RATE_LIMIT = 10;
const ACCEPT_RATE_LIMIT = 20;
const CROCKFORD_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const INVITE_DIGITS_PATTERN = /^[0-9A-HJKMNP-TV-Z]{26}$/;

type Relationship = "friend" | "bestie" | "couple";
type JSONValue = null | boolean | number | string | JSONValue[] | { [key: string]: JSONValue };

interface MembershipRow {
  planet_id: string;
}

interface PlanetRow {
  id: string;
  relationship: Relationship;
  created_at: number;
  updated_at: number;
}

interface PlanetMemberRow {
  account_id: string;
  joined_at: number;
  display_name: string | null;
  snapshot_json: string | null;
}

interface InviteRow {
  planet_id: string;
  created_by_account_id: string;
  expires_at: number;
  used_at: number | null;
  used_by_account_id: string | null;
  revoked_at: number | null;
}

interface CountRow {
  count: number;
}

interface RateLimitRow {
  attempts: number;
}

export function isPlanetPath(pathname: string): boolean {
  return pathname === PLANET_PATH
    || pathname === PLANET_INVITES_PATH
    || pathname === PLANET_INVITE_ACCEPT_PATH
    || pathname === PLANET_MEMBERSHIP_PATH;
}

export async function handlePlanetRoute(
  request: Request,
  url: URL,
  env: Env,
  accountID: string,
  requestID: string,
): Promise<Response> {
  if (url.search !== "") throw new AuthAPIError(400, "query_not_allowed");

  if (url.pathname === PLANET_PATH) {
    requireMethod(request, "GET");
    requireNoBody(request);
    const planet = await readPlanetForAccount(env.DB, accountID);
    return jsonResponse({ planet }, 200, requestID);
  }
  if (url.pathname === PLANET_INVITE_ACCEPT_PATH) {
    requireMethod(request, "POST");
    const code = await readCodeBody(request);
    await enforceRateLimit(env.DB, accountID, "accept", ACCEPT_RATE_LIMIT);
    return acceptInvite(env.DB, accountID, code, requestID);
  }
  if (url.pathname === PLANET_MEMBERSHIP_PATH) {
    requireMethod(request, "DELETE");
    requireNoBody(request);
    return leavePlanet(env.DB, accountID, requestID);
  }
  if (request.method === "POST") {
    const relationship = await readRelationshipBody(request);
    await enforceRateLimit(env.DB, accountID, "create", CREATE_RATE_LIMIT);
    return createInvite(env.DB, accountID, relationship, url.origin, requestID);
  }
  if (request.method === "DELETE") {
    const code = await readCodeBody(request);
    return revokeInvite(env.DB, accountID, code, requestID);
  }
  throw new AuthAPIError(405, "method_not_allowed", {
    headers: { Allow: "POST, DELETE" },
  });
}

export function inviteLandingResponse(requestID: string): Response {
  const nonce = encodeBase64URL(crypto.getRandomValues(new Uint8Array(18)));
  const html = `<!doctype html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <title>星伴邀請 · Star Companion</title>
  <style nonce="${nonce}">
    :root{color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}
    *{box-sizing:border-box}body{margin:0;min-height:100svh;display:grid;place-items:center;padding:24px;color:#fff;background:radial-gradient(circle at 30% 5%,#76518d 0,#2c2056 38%,#0d1232 100%)}
    main{width:min(100%,520px);padding:32px;border:1px solid #ffffff38;border-radius:32px;background:#17152dcc;box-shadow:0 24px 80px #0008;backdrop-filter:blur(24px)}
    .star{font-size:52px}h1{margin:12px 0 8px;font-size:30px}p{color:#ddd5e5;line-height:1.55}.code{margin:24px 0;padding:18px;border-radius:18px;background:#ffffff12;text-align:center;font:700 19px ui-monospace,SFMono-Regular,monospace;letter-spacing:.04em;overflow-wrap:anywhere}
    .actions{display:grid;gap:12px}button,a{appearance:none;border:0;border-radius:999px;padding:15px 18px;font:700 17px inherit;text-align:center;text-decoration:none;cursor:pointer}.open{color:#2a1730;background:#f5c8df}.copy{color:#fff;background:#ffffff18}.hint{font-size:13px}.hidden{display:none}
  </style>
</head>
<body><main>
  <div class="star">✦</div><h1>一起住進這顆星球</h1>
  <p>在星伴 App 開啟邀請；如果沒有自動跳轉，也可以複製邀請碼後手動貼上。</p>
  <div id="code" class="code">找不到邀請碼</div>
  <div class="actions"><a id="open" class="open hidden" href="#">在星伴中開啟</a><button id="copy" class="copy hidden" type="button">複製邀請碼</button></div>
  <p class="hint">邀請碼只存在這個頁面的 #fragment，不會送到伺服器或第三方。</p>
</main><script nonce="${nonce}">
(() => {
  const language = (navigator.language || "zh").toLowerCase();
  const words = language.startsWith("ko")
    ? ["ko", "같은 별에서 만나요", "별동무 앱에서 초대를 열어 주세요. 앱이 열리지 않으면 초대 코드를 복사해 직접 붙여넣을 수 있어요.", "초대 코드를 찾을 수 없어요", "별동무에서 열기", "초대 코드 복사", "복사했어요", "코드를 길게 눌러 복사해 주세요", "초대 코드는 이 페이지의 #fragment에서만 읽으며 서버나 제3자에게 보내지 않습니다."]
    : language.startsWith("zh")
      ? ["zh-Hant", "一起住進這顆星球", "在星伴 App 開啟邀請；如果沒有自動跳轉，也可以複製邀請碼後手動貼上。", "找不到邀請碼", "在星伴中開啟", "複製邀請碼", "已複製", "請長按邀請碼複製", "邀請碼只存在這個頁面的 #fragment，不會送到伺服器或第三方。"]
      : ["en", "Join my little planet", "Open this invitation in Star Companion. If the app doesn't open, copy the invitation code and paste it in the app.", "No invitation code found", "Open in Star Companion", "Copy invitation code", "Copied", "Press and hold the code to copy it", "The code is read only from this page's #fragment. It isn't sent to the server or third parties."];
  document.documentElement.lang = words[0]; document.title = words[1];
  document.querySelector("h1").textContent = words[1]; document.querySelector("main > p").textContent = words[2];
  document.getElementById("code").textContent = words[3]; document.getElementById("open").textContent = words[4];
  document.getElementById("copy").textContent = words[5]; document.querySelector(".hint").textContent = words[8];
  const value = new URLSearchParams(location.hash.slice(1)).get("code") || "";
  const code = value.trim().toUpperCase();
  if (!/^SC-(?:[0-9A-HJKMNP-TV-Z]{4}-){6}[0-9A-HJKMNP-TV-Z]{2}$/.test(code)) return;
  const output = document.getElementById("code"); const open = document.getElementById("open"); const copy = document.getElementById("copy");
  output.textContent = code; open.href = "starcompanion://invite?code=" + encodeURIComponent(code); open.classList.remove("hidden"); copy.classList.remove("hidden");
  copy.addEventListener("click", async () => { try { await navigator.clipboard.writeText(code); copy.textContent = words[6]; } catch { copy.textContent = words[7]; } });
})();
</script></body></html>`;
  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      Pragma: "no-cache",
      "Content-Security-Policy": `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; img-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "X-Request-ID": requestID,
    },
  });
}

export function appleAppSiteAssociationResponse(env: Env, requestID: string): Response {
  const teamID = env.APPLE_TEAM_ID?.trim() ?? "";
  const clientID = env.APPLE_CLIENT_ID?.trim() ?? "";
  if (!/^[A-Za-z0-9]{10}$/.test(teamID) || !/^[A-Za-z0-9.-]{3,255}$/.test(clientID)) {
    throw new AuthAPIError(503, "associated_domains_not_configured");
  }
  return new Response(JSON.stringify({
    applinks: {
      details: [{
        appIDs: [`${teamID}.${clientID}`],
        components: [{ "/": INVITE_LANDING_PATH }],
      }],
    },
  }), {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
      "X-Content-Type-Options": "nosniff",
      "X-Request-ID": requestID,
    },
  });
}

async function createInvite(
  db: D1Database,
  accountID: string,
  relationship: Relationship,
  origin: string,
  requestID: string,
): Promise<Response> {
  const now = Math.floor(Date.now() / 1_000);
  let membership = await readMembership(db, accountID);
  if (membership === null) {
    const candidatePlanetID = `pl_${encodeBase64URL(crypto.getRandomValues(new Uint8Array(18)))}`;
    try {
      await db.batch([
        db
          .prepare(
            `INSERT OR IGNORE INTO planets (id, relationship, created_at, updated_at)
             VALUES (?, ?, ?, ?)`,
          )
          .bind(candidatePlanetID, relationship, now, now),
        db
          .prepare(
            `INSERT OR IGNORE INTO planet_memberships (account_id, planet_id, slot, joined_at)
             SELECT ?, ?, 0, ?
             WHERE NOT EXISTS (
               SELECT 1 FROM account_deletion_locks WHERE account_id = ?
             )`,
          )
          .bind(accountID, candidatePlanetID, now, accountID),
      ]);
      membership = await readMembership(db, accountID);
      if (membership?.planet_id !== candidatePlanetID) {
        await db
          .prepare(
            `DELETE FROM planets WHERE id = ?
             AND NOT EXISTS (SELECT 1 FROM planet_memberships WHERE planet_id = ?)`,
          )
          .bind(candidatePlanetID, candidatePlanetID)
          .run();
      }
    } catch {
      throw new AuthAPIError(503, "storage_unavailable");
    }
  }
  if (membership === null) throw await pendingOrStorageError(db, accountID);

  const planet = await readPlanetRow(db, membership.planet_id);
  if (planet === null) throw new AuthAPIError(503, "storage_unavailable");
  if (planet.relationship !== relationship) {
    throw new AuthAPIError(409, "relationship_mismatch");
  }
  if (await memberCount(db, planet.id) >= 2) {
    throw new AuthAPIError(409, "planet_full");
  }

  const expiresAt = now + INVITE_TTL_SECONDS;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const code = generateInviteCode();
    const codeHash = await sha256Hex(canonicalCode(code));
    let results: D1Result<unknown>[];
    try {
      results = await db.batch([
        db
          .prepare(
            `INSERT OR IGNORE INTO planet_invites (
               code_sha256, planet_id, created_by_account_id, created_at, expires_at
             )
             SELECT ?, ?, ?, ?, ?
             WHERE EXISTS (
               SELECT 1 FROM planet_memberships
               WHERE account_id = ? AND planet_id = ?
             )
             AND NOT EXISTS (
               SELECT 1 FROM account_deletion_locks WHERE account_id = ?
             )
             AND (SELECT COUNT(*) FROM planet_memberships WHERE planet_id = ?) < 2`,
          )
          .bind(
            codeHash,
            planet.id,
            accountID,
            now,
            expiresAt,
            accountID,
            planet.id,
            accountID,
            planet.id,
          ),
        db
          .prepare(
            `UPDATE planet_invites
             SET revoked_at = ?
             WHERE created_by_account_id = ?
               AND planet_id = ?
               AND code_sha256 <> ?
               AND used_at IS NULL
               AND revoked_at IS NULL
               AND expires_at > ?
               AND changes() = 1`,
          )
          .bind(now, accountID, planet.id, codeHash, now),
      ]);
    } catch {
      throw new AuthAPIError(503, "storage_unavailable");
    }
    if ((results[0]?.meta.changes ?? 0) === 1) {
      const sharedPlanet = await readPlanetForAccount(db, accountID);
      if (sharedPlanet === null) throw new AuthAPIError(503, "storage_unavailable");
      return jsonResponse(
        {
          invite: {
            code,
            expiresAt: rfc3339(expiresAt),
            relationship,
            shareURL: `${origin}${INVITE_LANDING_PATH}#code=${encodeURIComponent(code)}`,
            deepLink: `starcompanion://invite?code=${encodeURIComponent(code)}`,
          },
          planet: sharedPlanet,
        },
        201,
        requestID,
      );
    }
    if (await memberCount(db, planet.id) >= 2) throw new AuthAPIError(409, "planet_full");
    const pending = await hasDeletionLock(db, accountID);
    if (pending) throw new AuthAPIError(409, "account_deletion_pending", { retryable: true });
  }
  throw new AuthAPIError(503, "storage_unavailable");
}

async function acceptInvite(
  db: D1Database,
  accountID: string,
  code: string,
  requestID: string,
): Promise<Response> {
  const codeHash = await sha256Hex(canonicalCode(code));
  const now = Math.floor(Date.now() / 1_000);
  let invite = await readInvite(db, codeHash);
  validateInviteForAcceptance(invite, accountID, now);
  if (invite === null) throw new AuthAPIError(404, "invite_not_found");

  if (invite.used_by_account_id === accountID) {
    const membership = await readMembership(db, accountID);
    if (membership?.planet_id === invite.planet_id) {
      const planet = await readPlanetForAccount(db, accountID);
      return jsonResponse({ accepted: true, planet }, 200, requestID);
    }
    throw new AuthAPIError(409, "invite_already_used");
  }
  if (invite.used_at !== null) throw new AuthAPIError(409, "invite_already_used");
  if (!await isInviteCreatorActive(db, invite)) {
    throw new AuthAPIError(404, "invite_not_found");
  }

  const currentMembership = await readMembership(db, accountID);
  if (currentMembership !== null && currentMembership.planet_id !== invite.planet_id) {
    throw new AuthAPIError(409, "already_in_planet");
  }
  if (currentMembership === null && await memberCount(db, invite.planet_id) >= 2) {
    throw new AuthAPIError(409, "planet_full");
  }

  try {
    await db.batch([
      db
        .prepare(
          `INSERT OR IGNORE INTO planet_memberships (account_id, planet_id, slot, joined_at)
           SELECT ?, i.planet_id,
                  CASE WHEN EXISTS (
                    SELECT 1 FROM planet_memberships
                    WHERE planet_id = i.planet_id AND slot = 0
                  ) THEN 1 ELSE 0 END,
                  ?
           FROM planet_invites AS i
           WHERE i.code_sha256 = ?
             AND i.created_by_account_id <> ?
             AND i.used_at IS NULL
             AND i.revoked_at IS NULL
             AND i.expires_at > ?
             AND EXISTS (
               SELECT 1 FROM planet_memberships AS creator_membership
               WHERE creator_membership.account_id = i.created_by_account_id
                 AND creator_membership.planet_id = i.planet_id
             )
             AND NOT EXISTS (
               SELECT 1 FROM account_deletion_locks AS creator_deletion
               WHERE creator_deletion.account_id = i.created_by_account_id
             )
             AND NOT EXISTS (
               SELECT 1 FROM planet_memberships WHERE account_id = ?
             )
             AND NOT EXISTS (
               SELECT 1 FROM account_deletion_locks WHERE account_id = ?
             )
             AND (SELECT COUNT(*) FROM planet_memberships WHERE planet_id = i.planet_id) < 2`,
        )
        .bind(accountID, now, codeHash, accountID, now, accountID, accountID),
      db
        .prepare(
          `UPDATE planet_invites
           SET used_at = ?, used_by_account_id = ?
           WHERE code_sha256 = ?
             AND used_at IS NULL
             AND revoked_at IS NULL
             AND expires_at > ?
             AND created_by_account_id <> ?
             AND EXISTS (
               SELECT 1 FROM planet_memberships AS creator_membership
               WHERE creator_membership.account_id = planet_invites.created_by_account_id
                 AND creator_membership.planet_id = planet_invites.planet_id
             )
             AND NOT EXISTS (
               SELECT 1 FROM account_deletion_locks AS creator_deletion
               WHERE creator_deletion.account_id = planet_invites.created_by_account_id
             )
             AND EXISTS (
               SELECT 1 FROM planet_memberships
               WHERE account_id = ? AND planet_id = planet_invites.planet_id
             )`,
        )
        .bind(now, accountID, codeHash, now, accountID, accountID),
      db
        .prepare(
          `UPDATE planets SET updated_at = ?
           WHERE id = (SELECT planet_id FROM planet_invites WHERE code_sha256 = ?)
             AND changes() = 1`,
        )
        .bind(now, codeHash),
    ]);
  } catch {
    throw new AuthAPIError(503, "storage_unavailable");
  }

  invite = await readInvite(db, codeHash);
  validateInviteForAcceptance(invite, accountID, now);
  if (invite?.used_by_account_id === accountID) {
    const membership = await readMembership(db, accountID);
    if (membership?.planet_id === invite.planet_id) {
      const planet = await readPlanetForAccount(db, accountID);
      return jsonResponse({ accepted: true, planet }, 200, requestID);
    }
  }
  if (invite?.used_at !== null) throw new AuthAPIError(409, "invite_already_used");
  if (invite !== null && !await isInviteCreatorActive(db, invite)) {
    throw new AuthAPIError(404, "invite_not_found");
  }
  const resultingMembership = await readMembership(db, accountID);
  if (resultingMembership !== null && resultingMembership.planet_id !== invite?.planet_id) {
    throw new AuthAPIError(409, "already_in_planet");
  }
  if (invite !== null && await memberCount(db, invite.planet_id) >= 2) {
    throw new AuthAPIError(409, "planet_full");
  }
  throw await pendingOrStorageError(db, accountID);
}

async function revokeInvite(
  db: D1Database,
  accountID: string,
  code: string,
  requestID: string,
): Promise<Response> {
  const codeHash = await sha256Hex(canonicalCode(code));
  const row = await db
    .prepare(
      `SELECT planet_id, created_by_account_id, expires_at, used_at,
              used_by_account_id, revoked_at
       FROM planet_invites
       WHERE code_sha256 = ? AND created_by_account_id = ?
       LIMIT 1`,
    )
    .bind(codeHash, accountID)
    .first<InviteRow>();
  if (row === null) throw new AuthAPIError(404, "invite_not_found");
  if (row.used_at !== null) throw new AuthAPIError(409, "invite_already_used");
  if (row.revoked_at === null) {
    let result: D1Result<unknown>;
    try {
      result = await db
        .prepare(
          `UPDATE planet_invites SET revoked_at = ?
           WHERE code_sha256 = ? AND created_by_account_id = ?
             AND used_at IS NULL AND revoked_at IS NULL`,
        )
        .bind(Math.floor(Date.now() / 1_000), codeHash, accountID)
        .run();
    } catch {
      throw new AuthAPIError(503, "storage_unavailable");
    }
    if ((result.meta.changes ?? 0) !== 1) {
      const raced = await db
        .prepare(
          `SELECT planet_id, created_by_account_id, expires_at, used_at,
                  used_by_account_id, revoked_at
           FROM planet_invites
           WHERE code_sha256 = ? AND created_by_account_id = ?
           LIMIT 1`,
        )
        .bind(codeHash, accountID)
        .first<InviteRow>();
      if (raced === null) throw new AuthAPIError(404, "invite_not_found");
      if (raced.used_at !== null) throw new AuthAPIError(409, "invite_already_used");
      if (raced.revoked_at === null) throw new AuthAPIError(503, "storage_unavailable");
    }
  }
  return jsonResponse({ revoked: true }, 200, requestID);
}

async function leavePlanet(
  db: D1Database,
  accountID: string,
  requestID: string,
): Promise<Response> {
  const membership = await readMembership(db, accountID);
  if (membership === null) {
    return jsonResponse({ left: true, planetDeleted: false }, 200, requestID);
  }
  const now = Math.floor(Date.now() / 1_000);
  try {
    await db.batch([
      db
        .prepare(
          `DELETE FROM planet_invites
           WHERE created_by_account_id = ? AND planet_id = ?`,
        )
        .bind(accountID, membership.planet_id),
      db
        .prepare(
          `DELETE FROM planet_memberships
           WHERE account_id = ? AND planet_id = ?`,
        )
        .bind(accountID, membership.planet_id),
      db.prepare("UPDATE planets SET updated_at = ? WHERE id = ?").bind(now, membership.planet_id),
      db
        .prepare(
          `DELETE FROM planets WHERE id = ?
           AND NOT EXISTS (SELECT 1 FROM planet_memberships WHERE planet_id = ?)`,
        )
        .bind(membership.planet_id, membership.planet_id),
    ]);
  } catch {
    throw new AuthAPIError(503, "storage_unavailable");
  }
  const remaining = await readPlanetRow(db, membership.planet_id);
  return jsonResponse({ left: true, planetDeleted: remaining === null }, 200, requestID);
}

async function readPlanetForAccount(
  db: D1Database,
  accountID: string,
): Promise<{ [key: string]: JSONValue } | null> {
  const membership = await readMembership(db, accountID);
  if (membership === null) return null;
  const planet = await readPlanetRow(db, membership.planet_id);
  if (planet === null) throw new AuthAPIError(503, "storage_unavailable");
  const rows = await db
    .prepare(
      `SELECT m.account_id, m.joined_at, i.display_name, s.snapshot_json
       FROM planet_memberships AS m
       LEFT JOIN account_identities AS i
         ON i.account_id = m.account_id AND i.provider = 'apple'
       LEFT JOIN account_snapshots AS s
         ON s.account_id = m.account_id AND s.deleted_at IS NULL
       WHERE m.planet_id = ?
       ORDER BY m.joined_at ASC, m.account_id ASC`,
    )
    .bind(planet.id)
    .all<PlanetMemberRow>();
  const members = rows.results.map((row) => memberResponse(row));
  return {
    id: planet.id,
    relationship: planet.relationship,
    members,
    createdAt: rfc3339(planet.created_at),
    updatedAt: rfc3339(planet.updated_at),
  };
}

function memberResponse(row: PlanetMemberRow): { [key: string]: JSONValue } {
  let profileName: string | null = null;
  let personaID: string | null = null;
  if (row.snapshot_json !== null) {
    try {
      const snapshot = JSON.parse(row.snapshot_json) as JSONValue;
      if (isJSONObject(snapshot)) {
        const profile = snapshot["profile"];
        const wardrobe = snapshot["wardrobe"];
        if (isJSONObject(profile)) profileName = cleanSharedString(profile["displayName"], 80);
        if (isJSONObject(wardrobe)) {
          personaID = cleanSharedString(wardrobe["selectedCollectionSkinID"], 160)
            ?? cleanSharedString(wardrobe["selectedPersona"], 160);
        }
      }
    } catch {
      // A malformed optional profile must not expose the rest of a snapshot.
    }
  }
  const response: { [key: string]: JSONValue } = {
    accountID: row.account_id,
    name: profileName ?? cleanSharedString(row.display_name, 80) ?? "Star friend",
  };
  if (personaID !== null) response["personaID"] = personaID;
  return response;
}

async function readMembership(db: D1Database, accountID: string): Promise<MembershipRow | null> {
  return db
    .prepare("SELECT planet_id FROM planet_memberships WHERE account_id = ? LIMIT 1")
    .bind(accountID)
    .first<MembershipRow>();
}

async function readPlanetRow(db: D1Database, planetID: string): Promise<PlanetRow | null> {
  return db
    .prepare(
      `SELECT id, relationship, created_at, updated_at
       FROM planets WHERE id = ? LIMIT 1`,
    )
    .bind(planetID)
    .first<PlanetRow>();
}

async function readInvite(db: D1Database, codeHash: string): Promise<InviteRow | null> {
  return db
    .prepare(
      `SELECT planet_id, created_by_account_id, expires_at, used_at,
              used_by_account_id, revoked_at
       FROM planet_invites WHERE code_sha256 = ? LIMIT 1`,
    )
    .bind(codeHash)
    .first<InviteRow>();
}

async function memberCount(db: D1Database, planetID: string): Promise<number> {
  const row = await db
    .prepare("SELECT COUNT(*) AS count FROM planet_memberships WHERE planet_id = ?")
    .bind(planetID)
    .first<CountRow>();
  if (row === null) throw new AuthAPIError(503, "storage_unavailable");
  return row.count;
}

async function isInviteCreatorActive(db: D1Database, invite: InviteRow): Promise<boolean> {
  const row = await db
    .prepare(
      `SELECT 1 AS active
       FROM planet_memberships AS m
       WHERE m.account_id = ? AND m.planet_id = ?
         AND NOT EXISTS (
           SELECT 1 FROM account_deletion_locks WHERE account_id = m.account_id
         )
       LIMIT 1`,
    )
    .bind(invite.created_by_account_id, invite.planet_id)
    .first<{ active: number }>();
  return row !== null;
}

function validateInviteForAcceptance(
  invite: InviteRow | null,
  accountID: string,
  now: number,
): void {
  if (invite === null || invite.revoked_at !== null) {
    throw new AuthAPIError(404, "invite_not_found");
  }
  if (invite.created_by_account_id === accountID) {
    throw new AuthAPIError(409, "cannot_accept_own_invite");
  }
  if (invite.expires_at <= now) throw new AuthAPIError(410, "invite_expired");
}

async function enforceRateLimit(
  db: D1Database,
  accountID: string,
  action: "create" | "accept",
  maximumAttempts: number,
): Promise<void> {
  const bucket = await sha256Hex(`planet\n${action}\n${accountID}`);
  const now = Math.floor(Date.now() / 1_000);
  const windowStart = Math.floor(now / RATE_WINDOW_SECONDS) * RATE_WINDOW_SECONDS;
  const expiresAt = windowStart + RATE_WINDOW_SECONDS;
  try {
    await db.batch([
      db.prepare("DELETE FROM planet_rate_limits WHERE expires_at <= ?").bind(now),
      db
        .prepare(
          `INSERT INTO planet_rate_limits (
             bucket_sha256, action, window_start, attempts, expires_at
           ) VALUES (?, ?, ?, 1, ?)
           ON CONFLICT(bucket_sha256, action, window_start)
           DO UPDATE SET attempts = attempts + 1`,
        )
        .bind(bucket, action, windowStart, expiresAt),
    ]);
    const row = await db
      .prepare(
        `SELECT attempts FROM planet_rate_limits
         WHERE bucket_sha256 = ? AND action = ? AND window_start = ?`,
      )
      .bind(bucket, action, windowStart)
      .first<RateLimitRow>();
    if (row === null) throw new Error("missing rate limit row");
    if (row.attempts > maximumAttempts) {
      const retryAfterSeconds = Math.max(1, expiresAt - now);
      throw new AuthAPIError(429, "rate_limited", {
        retryAfterSeconds,
        headers: { "Retry-After": String(retryAfterSeconds) },
      });
    }
  } catch (error) {
    if (error instanceof AuthAPIError) throw error;
    throw new AuthAPIError(503, "storage_unavailable");
  }
}

async function pendingOrStorageError(db: D1Database, accountID: string): Promise<AuthAPIError> {
  if (await hasDeletionLock(db, accountID)) {
    return new AuthAPIError(409, "account_deletion_pending", { retryable: true });
  }
  return new AuthAPIError(503, "storage_unavailable");
}

async function hasDeletionLock(db: D1Database, accountID: string): Promise<boolean> {
  const row = await db
    .prepare("SELECT 1 AS pending FROM account_deletion_locks WHERE account_id = ? LIMIT 1")
    .bind(accountID)
    .first<{ pending: number }>();
  return row !== null;
}

async function readRelationshipBody(request: Request): Promise<Relationship> {
  const value = await readStrictBody(request);
  if (!isJSONObject(value) || !hasExactKeys(value, ["relationship"])) {
    throw new AuthAPIError(422, "invalid_invite_request");
  }
  const relationship = value["relationship"];
  if (relationship !== "friend" && relationship !== "bestie" && relationship !== "couple") {
    throw new AuthAPIError(422, "invalid_relationship");
  }
  return relationship;
}

async function readCodeBody(request: Request): Promise<string> {
  const value = await readStrictBody(request);
  if (!isJSONObject(value) || !hasExactKeys(value, ["code"])) {
    throw new AuthAPIError(422, "invalid_invite_request");
  }
  const code = value["code"];
  if (typeof code !== "string") throw new AuthAPIError(422, "invalid_invite_code");
  return normalizeInviteCode(code);
}

async function readStrictBody(request: Request): Promise<JSONValue> {
  const contentType = request.headers.get("Content-Type");
  if (contentType?.split(";", 1)[0]?.trim().toLowerCase() !== "application/json") {
    throw new AuthAPIError(415, "unsupported_media_type");
  }
  const contentLength = request.headers.get("Content-Length");
  if (contentLength !== null) {
    const declared = Number(contentLength);
    if (!Number.isSafeInteger(declared) || declared < 0) {
      throw new AuthAPIError(400, "invalid_content_length");
    }
    if (declared > MAX_REQUEST_BYTES) throw new AuthAPIError(413, "payload_too_large");
  }
  if (request.body === null) throw new AuthAPIError(400, "invalid_json");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) break;
    total += next.value.byteLength;
    if (total > MAX_REQUEST_BYTES) {
      await reader.cancel();
      throw new AuthAPIError(413, "payload_too_large");
    }
    chunks.push(next.value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
    return JSON.parse(text) as JSONValue;
  } catch {
    throw new AuthAPIError(400, "invalid_json");
  }
}

function requireMethod(request: Request, method: "GET" | "POST" | "DELETE"): void {
  if (request.method !== method) {
    throw new AuthAPIError(405, "method_not_allowed", { headers: { Allow: method } });
  }
}

function requireNoBody(request: Request): void {
  if (request.body !== null) throw new AuthAPIError(400, "body_not_allowed");
}

function normalizeInviteCode(value: string): string {
  const compact = value.trim().toUpperCase().replace(/[\s-]/g, "");
  const digits = compact.length === 28 && compact.startsWith("SC")
    ? compact.slice(2)
    : compact;
  if (!INVITE_DIGITS_PATTERN.test(digits)) {
    throw new AuthAPIError(422, "invalid_invite_code");
  }
  return formatInviteDigits(digits);
}

function generateInviteCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  let buffer = 0;
  let bitCount = 0;
  let digits = "";
  for (const byte of bytes) {
    buffer = (buffer << 8) | byte;
    bitCount += 8;
    while (bitCount >= 5) {
      bitCount -= 5;
      digits += CROCKFORD_ALPHABET[(buffer >>> bitCount) & 31];
      buffer &= (1 << bitCount) - 1;
    }
  }
  if (bitCount > 0) digits += CROCKFORD_ALPHABET[(buffer << (5 - bitCount)) & 31];
  return formatInviteDigits(digits);
}

function formatInviteDigits(digits: string): string {
  const groups: string[] = [];
  for (let index = 0; index < 24; index += 4) groups.push(digits.slice(index, index + 4));
  groups.push(digits.slice(24));
  return `SC-${groups.join("-")}`;
}

function canonicalCode(formattedCode: string): string {
  return formattedCode.replace(/-/g, "");
}

function cleanSharedString(value: JSONValue | undefined, maximumLength: number): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length === 0 || normalized.length > maximumLength) return null;
  if (/[\u0000-\u001f\u007f]/.test(normalized)) return null;
  return normalized;
}

function hasExactKeys(value: { [key: string]: JSONValue }, keys: string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && actual.every((key) => keys.includes(key));
}

function isJSONObject(value: JSONValue | undefined): value is { [key: string]: JSONValue } {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function encodeBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function rfc3339(epochSeconds: number): string {
  return new Date(epochSeconds * 1_000).toISOString().replace(".000Z", "Z");
}

function jsonResponse(
  body: JSONValue,
  status: number,
  requestID: string,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      Pragma: "no-cache",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      "X-Request-ID": requestID,
    },
  });
}

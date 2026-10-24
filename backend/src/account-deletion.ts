import { AuthAPIError, revokeAppleCredentialForDeletion } from "./auth";

export const ACCOUNT_DELETION_PATH = "/v1/account";

const MAX_TOKEN_LENGTH = 16_384;
const MAX_DELETE_REQUEST_BYTES = 2_048;
const IDENTITY_TOMBSTONE_TTL_SECONDS = 10 * 60;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type JSONValue = null | boolean | number | string | JSONValue[] | { [key: string]: JSONValue };

interface DeletionReceiptRow {
  request_sha256: string;
  response_json: string;
}

interface DeletionLockRow {
  account_id: string;
  access_token_sha256: string;
  idempotency_key_sha256: string;
  request_sha256: string;
}

interface DeletionSessionRow {
  account_id: string;
}

interface MembershipRow {
  planet_id: string;
}

export async function handleAccountDeletion(
  request: Request,
  url: URL,
  env: Env,
  requestID: string,
): Promise<Response> {
  if (url.search !== "") throw new AuthAPIError(400, "query_not_allowed");
  if (request.method !== "DELETE") {
    throw new AuthAPIError(405, "method_not_allowed", { headers: { Allow: "DELETE" } });
  }
  requireJSONContentType(request);

  const rawToken = requireBearerToken(request);
  const tokenHash = await sha256Hex(rawToken);
  const idempotencyKey = requireDeletionIdempotencyKey(request);
  const idempotencyKeyHash = await sha256Hex(idempotencyKey.toLowerCase());
  const body = await readBoundedJSON(request, MAX_DELETE_REQUEST_BYTES);
  if (
    !isJSONObject(body)
    || Object.keys(body).length !== 1
    || body["confirmation"] !== "DELETE"
  ) {
    throw new AuthAPIError(422, "invalid_delete_confirmation");
  }
  const requestHash = await sha256Hex('DELETE\n{"confirmation":"DELETE"}');
  const now = Math.floor(Date.now() / 1_000);

  const receipt = await readDeletionReceipt(
    env.DB,
    tokenHash,
    idempotencyKeyHash,
  );
  if (receipt !== null) {
    if (receipt.request_sha256 !== requestHash) {
      throw new AuthAPIError(409, "idempotency_key_reused");
    }
    return rawJSONResponse(receipt.response_json, requestID);
  }

  let lock = await readDeletionLockByCredential(
    env.DB,
    tokenHash,
    idempotencyKeyHash,
  );
  if (lock !== null && lock.request_sha256 !== requestHash) {
    throw new AuthAPIError(409, "idempotency_key_reused");
  }

  if (lock === null) {
    const session = await authenticateInitialDeletion(env.DB, tokenHash, now);
    const existingLock = await readDeletionLockForAccount(env.DB, session.account_id);
    if (existingLock !== null) {
      throw new AuthAPIError(409, "account_deletion_pending", { retryable: true });
    }

    try {
      await env.DB
        .prepare(
          `INSERT INTO account_deletion_locks (
             account_id, access_token_sha256, idempotency_key_sha256,
             request_sha256, created_at, updated_at, retry_count
           ) VALUES (?, ?, ?, ?, ?, ?, 0)
           ON CONFLICT(account_id) DO NOTHING`,
        )
        .bind(
          session.account_id,
          tokenHash,
          idempotencyKeyHash,
          requestHash,
          now,
          now,
        )
        .run();
    } catch {
      throw new AuthAPIError(503, "storage_unavailable", { retryable: true });
    }
    lock = await readDeletionLockForAccount(env.DB, session.account_id);
    if (
      lock === null
      || lock.access_token_sha256 !== tokenHash
      || lock.idempotency_key_sha256 !== idempotencyKeyHash
      || lock.request_sha256 !== requestHash
    ) {
      throw new AuthAPIError(409, "account_deletion_pending", { retryable: true });
    }
  }

  try {
    await env.DB
      .prepare("DELETE FROM deleted_identity_tombstones WHERE expires_at <= ?")
      .bind(now)
      .run();
  } catch {
    throw new AuthAPIError(503, "storage_unavailable", { retryable: true });
  }

  const membership = await env.DB
    .prepare("SELECT planet_id FROM planet_memberships WHERE account_id = ? LIMIT 1")
    .bind(lock.account_id)
    .first<MembershipRow>();

  let providerSubjectHash: string;
  try {
    providerSubjectHash = await revokeAppleCredentialForDeletion(
      env.DB,
      lock.account_id,
      env,
    );
  } catch {
    await recordFailedAttempt(env.DB, lock.account_id, now);
    throw new AuthAPIError(503, "apple_revoke_failed", { retryable: true });
  }

  const responseJSON = JSON.stringify({ deleted: true });
  const planetCreateRateBucket = await sha256Hex(`planet\ncreate\n${lock.account_id}`);
  const planetAcceptRateBucket = await sha256Hex(`planet\naccept\n${lock.account_id}`);
  const statements: D1PreparedStatement[] = [
    env.DB
      .prepare(
        `INSERT INTO account_deletion_receipts (
           access_token_sha256, idempotency_key_sha256, request_sha256,
           response_json, created_at
         ) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(access_token_sha256, idempotency_key_sha256) DO NOTHING`,
      )
      .bind(
        tokenHash,
        idempotencyKeyHash,
        requestHash,
        responseJSON,
        now,
      ),
    env.DB
      .prepare(
        `INSERT INTO deleted_identity_tombstones (
           provider, provider_subject_sha256, created_at, expires_at
         ) VALUES ('apple', ?, ?, ?)
         ON CONFLICT(provider, provider_subject_sha256) DO UPDATE SET
           expires_at = MAX(expires_at, excluded.expires_at)`,
      )
      .bind(providerSubjectHash, now, now + IDENTITY_TOMBSTONE_TTL_SECONDS),
    env.DB
      .prepare("DELETE FROM planet_invites WHERE used_by_account_id = ?")
      .bind(lock.account_id),
    env.DB
      .prepare("DELETE FROM planet_rate_limits WHERE bucket_sha256 IN (?, ?)")
      .bind(planetCreateRateBucket, planetAcceptRateBucket),
    env.DB.prepare("DELETE FROM accounts WHERE id = ?").bind(lock.account_id),
  ];
  if (membership !== null) {
    statements.push(
      env.DB
        .prepare("UPDATE planets SET updated_at = ? WHERE id = ?")
        .bind(now, membership.planet_id),
      env.DB
        .prepare(
          `DELETE FROM planets
           WHERE id = ?
             AND NOT EXISTS (
               SELECT 1 FROM planet_memberships WHERE planet_id = ?
             )`,
        )
        .bind(membership.planet_id, membership.planet_id),
    );
  }

  try {
    // D1 batch executes these statements as one transaction. The replay receipt
    // cannot become visible without the account removal in the same commit.
    await env.DB.batch(statements);
  } catch {
    throw new AuthAPIError(503, "storage_unavailable", { retryable: true });
  }
  return rawJSONResponse(responseJSON, requestID);
}

async function authenticateInitialDeletion(
  db: D1Database,
  tokenHash: string,
  now: number,
): Promise<DeletionSessionRow> {
  const row = await db
    .prepare(
      `SELECT s.account_id
       FROM auth_sessions AS s
       INNER JOIN accounts AS a ON a.id = s.account_id
       WHERE s.token_sha256 = ?
         AND s.kind = 'access'
         AND s.revoked_at IS NULL
         AND (s.expires_at IS NULL OR s.expires_at > ?)
       LIMIT 1`,
    )
    .bind(tokenHash, now)
    .first<DeletionSessionRow>();
  if (row === null) throw unauthorized();
  return row;
}

async function readDeletionReceipt(
  db: D1Database,
  tokenHash: string,
  idempotencyKeyHash: string,
): Promise<DeletionReceiptRow | null> {
  return db
    .prepare(
      `SELECT request_sha256, response_json
       FROM account_deletion_receipts
       WHERE access_token_sha256 = ?
         AND idempotency_key_sha256 = ?
       LIMIT 1`,
    )
    .bind(tokenHash, idempotencyKeyHash)
    .first<DeletionReceiptRow>();
}

async function readDeletionLockByCredential(
  db: D1Database,
  tokenHash: string,
  idempotencyKeyHash: string,
): Promise<DeletionLockRow | null> {
  return db
    .prepare(
      `SELECT account_id, access_token_sha256, idempotency_key_sha256, request_sha256
       FROM account_deletion_locks
       WHERE access_token_sha256 = ? AND idempotency_key_sha256 = ?
       LIMIT 1`,
    )
    .bind(tokenHash, idempotencyKeyHash)
    .first<DeletionLockRow>();
}

async function readDeletionLockForAccount(
  db: D1Database,
  accountID: string,
): Promise<DeletionLockRow | null> {
  return db
    .prepare(
      `SELECT account_id, access_token_sha256, idempotency_key_sha256, request_sha256
       FROM account_deletion_locks
       WHERE account_id = ?
       LIMIT 1`,
    )
    .bind(accountID)
    .first<DeletionLockRow>();
}

async function recordFailedAttempt(db: D1Database, accountID: string, now: number): Promise<void> {
  try {
    await db
      .prepare(
        `UPDATE account_deletion_locks
         SET retry_count = retry_count + 1, updated_at = ?
         WHERE account_id = ?`,
      )
      .bind(now, accountID)
      .run();
  } catch {
    // The original failure remains retryable even if telemetry cannot be updated.
  }
}

function requireBearerToken(request: Request): string {
  const authorization = request.headers.get("Authorization");
  const match = authorization?.match(/^Bearer ([^\s\u0000-\u001f\u007f]+)$/i);
  if (!match?.[1] || match[1].length > MAX_TOKEN_LENGTH) throw unauthorized();
  return match[1];
}

function requireDeletionIdempotencyKey(request: Request): string {
  const value = request.headers.get("Idempotency-Key");
  if (value === null || !UUID_PATTERN.test(value)) {
    throw new AuthAPIError(400, "invalid_idempotency_key");
  }
  return value;
}

function requireJSONContentType(request: Request): void {
  const contentType = request.headers.get("Content-Type");
  if (contentType?.split(";", 1)[0]?.trim().toLowerCase() !== "application/json") {
    throw new AuthAPIError(415, "unsupported_media_type");
  }
}

async function readBoundedJSON(request: Request, maximumBytes: number): Promise<JSONValue> {
  const contentLength = request.headers.get("Content-Length");
  if (contentLength !== null) {
    const declared = Number(contentLength);
    if (!Number.isSafeInteger(declared) || declared < 0) {
      throw new AuthAPIError(400, "invalid_content_length");
    }
    if (declared > maximumBytes) throw new AuthAPIError(413, "payload_too_large");
  }
  if (request.body === null) throw new AuthAPIError(400, "invalid_json");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) break;
    total += next.value.byteLength;
    if (total > maximumBytes) {
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

function isJSONObject(value: JSONValue): value is { [key: string]: JSONValue } {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function unauthorized(): AuthAPIError {
  return new AuthAPIError(401, "unauthorized", {
    headers: { "WWW-Authenticate": 'Bearer realm="star-companion"' },
  });
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function rawJSONResponse(body: string, requestID: string): Response {
  return new Response(body, {
    status: 200,
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

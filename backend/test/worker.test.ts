import { env, exports } from "cloudflare:workers";
import { HttpResponse, http } from "msw";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { cleanupExpiredRecords } from "../src/maintenance";
import { network } from "./network";

const endpoint = "https://api.example.test/v1/account/snapshot";
const tokenA = "test-token-account-a";
const tokenB = "test-token-account-b";
const appleExchangeEndpoint = "https://api.example.test/v1/auth/apple/exchange";
const appRefreshEndpoint = "https://api.example.test/v1/auth/session/refresh";
const accountDeletionEndpoint = "https://api.example.test/v1/account";
const planetEndpoint = "https://api.example.test/v1/planet";
const planetInvitesEndpoint = "https://api.example.test/v1/planet/invites";
const planetAcceptEndpoint = "https://api.example.test/v1/planet/invites/accept";
const planetMembershipEndpoint = "https://api.example.test/v1/planet/membership";
const inviteLandingEndpoint = "https://api.example.test/invite";
const appleSubject = "001234.abcdef0123456789.1234";
const appleKeyID = "APPLE-TEST-KEY";
let appleSigningKeyPair: CryptoKeyPair;
let applePublicJWK: JsonWebKey;

beforeAll(async () => {
  const generatedKey = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  if (!("publicKey" in generatedKey)) throw new Error("expected RSA key pair");
  appleSigningKeyPair = generatedKey;
  const exportedKey = await crypto.subtle.exportKey("jwk", appleSigningKeyPair.publicKey);
  if (exportedKey instanceof ArrayBuffer) throw new Error("expected RSA JWK");
  applePublicJWK = exportedKey;
});

beforeEach(async () => {
  await caches.default.delete(new Request("https://star-companion.internal-cache/apple-jwks-v1"));
  await env.DB.batch([
    env.DB.prepare("DELETE FROM account_deletion_receipts"),
    env.DB.prepare("DELETE FROM deleted_identity_tombstones"),
    env.DB.prepare("DELETE FROM planet_rate_limits"),
    env.DB.prepare("DELETE FROM planet_invites"),
    env.DB.prepare("DELETE FROM planet_memberships"),
    env.DB.prepare("DELETE FROM planets"),
    env.DB.prepare("DELETE FROM account_deletion_locks"),
    env.DB.prepare("DELETE FROM account_snapshot_mutations"),
    env.DB.prepare("DELETE FROM account_snapshots"),
    env.DB.prepare("DELETE FROM auth_sessions"),
    env.DB.prepare("DELETE FROM apple_credentials"),
    env.DB.prepare("DELETE FROM account_identities"),
    env.DB.prepare("DELETE FROM auth_rate_limits"),
    env.DB.prepare("DELETE FROM accounts"),
  ]);
  await seedSession("account-a", tokenA);
  await seedSession("account-b", tokenB);
});

describe("Sign in with Apple API", () => {
  it("verifies Apple twice, creates one canonical account, and stores no plaintext tokens", async () => {
    const rawNonce = randomBase64URL(32);
    let jwksFetchCount = 0;
    installAppleHandlers(rawNonce, { onJWKFetch: () => { jwksFetchCount += 1; } });
    const identityToken = await makeAppleIdentityJWT(appleSubject, rawNonce);

    const response = await appleExchange(identityToken, rawNonce, appleSubject, "Ollie");
    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    const session = await response.json<Record<string, unknown>>();
    expect(Object.keys(session).sort()).toEqual([
      "accessToken", "assurance", "canonicalAccountID", "displayName", "expiresAt",
      "issuedAt", "providerSubject", "refreshToken",
    ].sort());
    expect(session).toMatchObject({
      assurance: "backendVerified",
      providerSubject: appleSubject,
      displayName: "Ollie",
    });
    expect(String(session.canonicalAccountID)).toMatch(/^acc_[A-Za-z0-9_-]{24}$/);
    expect(String(session.issuedAt)).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    expect(String(session.expiresAt)).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    expect(jwksFetchCount).toBe(1);

    const identity = await env.DB
      .prepare("SELECT account_id, provider_subject, display_name FROM account_identities")
      .first<{ account_id: string; provider_subject: string; display_name: string }>();
    expect(identity).toMatchObject({ provider_subject: appleSubject, display_name: "Ollie" });
    expect(identity?.account_id).toBe(session.canonicalAccountID);

    const credentials = await env.DB
      .prepare("SELECT refresh_token_ciphertext, refresh_token_nonce FROM apple_credentials")
      .first<{ refresh_token_ciphertext: string; refresh_token_nonce: string }>();
    expect(credentials?.refresh_token_ciphertext).not.toContain("apple-refresh-token");
    expect(credentials?.refresh_token_nonce).toMatch(/^[A-Za-z0-9_-]+$/);

    const storedSessions = await env.DB
      .prepare("SELECT token_sha256, kind FROM auth_sessions WHERE account_id = ? ORDER BY kind")
      .bind(session.canonicalAccountID)
      .all<{ token_sha256: string; kind: string }>();
    expect(storedSessions.results.map((row) => row.kind)).toEqual(["access", "refresh"]);
    expect(storedSessions.results.map((row) => row.token_sha256)).not.toContain(session.accessToken);
    expect(storedSessions.results.map((row) => row.token_sha256)).not.toContain(session.refreshToken);

    const snapshot = await exports.default.fetch(new Request(endpoint, {
      headers: { Authorization: `Bearer ${String(session.accessToken)}` },
    }));
    expect(snapshot.status).toBe(404);
    expect(await snapshot.json()).toMatchObject({ code: "snapshot_not_found" });

    const refreshCannotReadSnapshot = await exports.default.fetch(new Request(endpoint, {
      headers: { Authorization: `Bearer ${String(session.refreshToken)}` },
    }));
    expect(refreshCannotReadSnapshot.status).toBe(401);
    expect(await refreshCannotReadSnapshot.json()).toMatchObject({ code: "unauthorized" });
  });

  it("uses the signed subject and rejects a client-supplied subject mismatch", async () => {
    const rawNonce = randomBase64URL(32);
    installAppleHandlers(rawNonce);
    const identityToken = await makeAppleIdentityJWT(appleSubject, rawNonce);
    const response = await appleExchange(identityToken, rawNonce, "attacker-subject", null);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: "invalid_apple_credential" });
    const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM account_identities")
      .first<{ count: number }>();
    expect(count?.count).toBe(0);
  });

  it("rejects the wrong nonce before creating an account", async () => {
    const requestNonce = randomBase64URL(32);
    installAppleHandlers(requestNonce);
    const identityToken = await makeAppleIdentityJWT(appleSubject, randomBase64URL(32));
    const response = await appleExchange(identityToken, requestNonce, appleSubject, null);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: "invalid_apple_credential" });
  });

  it("rejects a correctly signed identity token with the wrong audience", async () => {
    const rawNonce = randomBase64URL(32);
    installAppleHandlers(rawNonce);
    const identityToken = await makeAppleIdentityJWT(
      appleSubject,
      rawNonce,
      appleKeyID,
      { aud: "com.attacker.App" },
    );
    const response = await appleExchange(identityToken, rawNonce, appleSubject, null);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: "invalid_apple_credential" });
  });

  it("rejects the exchange when any required Apple configuration is missing", async () => {
    const misconfiguredEnv: Env = {
      DB: env.DB,
      APPLE_CLIENT_ID: "",
      APPLE_TEAM_ID: env.APPLE_TEAM_ID,
      APPLE_KEY_ID: env.APPLE_KEY_ID,
      APPLE_PRIVATE_KEY: env.APPLE_PRIVATE_KEY,
      APPLE_REFRESH_TOKEN_ENCRYPTION_KEY: env.APPLE_REFRESH_TOKEN_ENCRYPTION_KEY,
      AUTH_RATE_LIMIT_SALT: env.AUTH_RATE_LIMIT_SALT,
    };
    const response = await worker.fetch(
      new Request(appleExchangeEndpoint, { method: "POST" }),
      misconfiguredEnv,
    );
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ code: "auth_not_configured" });
  });

  it("fails closed when Apple rejects a replayed or invalid authorization code", async () => {
    const rawNonce = randomBase64URL(32);
    installAppleHandlers(rawNonce, { rejectAuthorizationCode: true });
    const identityToken = await makeAppleIdentityJWT(appleSubject, rawNonce);
    const response = await appleExchange(identityToken, rawNonce, appleSubject, null);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: "invalid_apple_credential" });
    const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM accounts")
      .first<{ count: number }>();
    expect(count?.count).toBe(2);
  });

  it("rejects an Apple token response whose signed subject changed", async () => {
    const rawNonce = randomBase64URL(32);
    installAppleHandlers(rawNonce, { exchangedSubject: "different-signed-apple-subject" });
    const identityToken = await makeAppleIdentityJWT(appleSubject, rawNonce);
    const response = await appleExchange(identityToken, rawNonce, appleSubject, null);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: "invalid_apple_credential" });
  });

  it("force-refreshes Apple's cached JWK set when a new kid appears", async () => {
    const rotatedKeyID = "APPLE-ROTATED-KEY";
    await caches.default.put(
      new Request("https://star-companion.internal-cache/apple-jwks-v1"),
      HttpResponse.json({
        keys: [{ ...applePublicJWK, kid: "STALE-APPLE-KEY", alg: "RS256", use: "sig" }],
      }, { headers: { "Cache-Control": "public, max-age=3600" } }),
    );
    const rawNonce = randomBase64URL(32);
    let jwksFetchCount = 0;
    installAppleHandlers(rawNonce, {
      jwksKeyID: rotatedKeyID,
      onJWKFetch: () => { jwksFetchCount += 1; },
    });
    const identityToken = await makeAppleIdentityJWT(appleSubject, rawNonce, rotatedKeyID);
    const response = await appleExchange(identityToken, rawNonce, appleSubject, null);
    expect(response.status).toBe(200);
    expect(jwksFetchCount).toBe(1);
  });

  it("validates Apple again, rotates app refresh tokens, and rejects replay", async () => {
    const rawNonce = randomBase64URL(32);
    installAppleHandlers(rawNonce);
    const identityToken = await makeAppleIdentityJWT(appleSubject, rawNonce);
    const login = await appleExchange(identityToken, rawNonce, appleSubject, null);
    const firstSession = await login.json<Record<string, unknown>>();

    const refreshed = await exports.default.fetch(new Request(appRefreshEndpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100.77" },
      body: JSON.stringify({ refreshToken: firstSession.refreshToken }),
    }));
    expect(refreshed.status).toBe(200);
    const secondSession = await refreshed.json<Record<string, unknown>>();
    expect(secondSession.canonicalAccountID).toBe(firstSession.canonicalAccountID);
    expect(secondSession.refreshToken).not.toBe(firstSession.refreshToken);
    expect(secondSession.accessToken).not.toBe(firstSession.accessToken);

    const replay = await exports.default.fetch(new Request(appRefreshEndpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100.78" },
      body: JSON.stringify({ refreshToken: firstSession.refreshToken }),
    }));
    expect(replay.status).toBe(401);
    expect(await replay.json()).toMatchObject({ code: "unauthorized" });
  });

  it("rejects unknown exchange fields without contacting Apple", async () => {
    const response = await exports.default.fetch(new Request(appleExchangeEndpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100.90" },
      body: JSON.stringify({ accountID: "client-controlled" }),
    }));
    expect(response.status).toBe(422);
    expect(await response.json()).toMatchObject({ code: "invalid_apple_request" });
  });

  it("removes expired rate-limit buckets while handling auth traffic", async () => {
    await env.DB
      .prepare(
        `INSERT INTO auth_rate_limits (bucket_sha256, window_start, attempts, expires_at)
         VALUES (?, 1, 1, 2)`,
      )
      .bind("a".repeat(64))
      .run();
    const response = await exports.default.fetch(new Request(appleExchangeEndpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100.91" },
      body: "{}",
    }));
    expect(response.status).toBe(422);
    const expired = await env.DB
      .prepare("SELECT COUNT(*) AS count FROM auth_rate_limits WHERE expires_at <= 2")
      .first<{ count: number }>();
    expect(expired?.count).toBe(0);
  });

  it("enforces the Apple credential identity-to-account foreign key", async () => {
    await env.DB.prepare("INSERT OR IGNORE INTO accounts (id) VALUES ('wrong-account')").run();
    await expect(env.DB
      .prepare(
        `INSERT INTO apple_credentials (
           account_id, provider_subject, refresh_token_ciphertext, refresh_token_nonce,
           refresh_token_key_version, apple_access_expires_at, last_validated_at
         ) VALUES ('wrong-account', ?, 'ciphertext-long-enough', 'nonce-long-enough', 1, 2, 1)`,
      )
      .bind(appleSubject)
      .run()).rejects.toThrow();
  });
});

describe("account snapshot API", () => {
  it("rejects unauthenticated access without exposing details", async () => {
    const response = await exports.default.fetch(endpoint);
    expect(response.status).toBe(401);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(response.headers.get("WWW-Authenticate")).toContain("Bearer");
    expect(await response.json()).toMatchObject({ code: "unauthorized" });
  });

  it("creates and reads a first account snapshot", async () => {
    const body = snapshotEnvelope(null, "A");
    const put = await request("PUT", tokenA, {
      body,
      idempotencyKey: "put-a-1",
    });
    expect(put.status).toBe(201);
    expect(await put.json()).toMatchObject({ schemaVersion: 1, revision: 1 });
    expect(put.headers.get("ETag")).toBe('"1"');

    const get = await request("GET", tokenA);
    expect(get.status).toBe(200);
    expect(await get.json()).toMatchObject({
      schemaVersion: 1,
      revision: 1,
      snapshot: { profile: { displayName: "A" } },
    });
  });

  it("replays the same mutation idempotently", async () => {
    const body = snapshotEnvelope(null, "A");
    const first = await request("PUT", tokenA, {
      body,
      idempotencyKey: "same-mutation",
    });
    const firstText = await first.text();

    const retry = await request("PUT", tokenA, {
      body,
      idempotencyKey: "same-mutation",
    });
    expect(retry.status).toBe(201);
    expect(await retry.text()).toBe(firstText);

    const row = await env.DB
      .prepare("SELECT revision FROM account_snapshots WHERE account_id = ?")
      .bind("account-a")
      .first<{ revision: number }>();
    expect(row?.revision).toBe(1);
  });

  it("returns a revision conflict for a stale whole-document update", async () => {
    await request("PUT", tokenA, {
      body: snapshotEnvelope(null, "A1"),
      idempotencyKey: "put-a-1",
    });
    const second = await request("PUT", tokenA, {
      body: snapshotEnvelope(1, "A2"),
      idempotencyKey: "put-a-2",
    });
    expect(second.status).toBe(200);

    const stale = await request("PUT", tokenA, {
      body: snapshotEnvelope(1, "stale"),
      idempotencyKey: "put-a-stale",
    });
    expect(stale.status).toBe(409);
    expect(await stale.json()).toMatchObject({
      code: "snapshot_conflict",
      currentRevision: 2,
    });
  });

  it("isolates snapshots by the account derived from the bearer token", async () => {
    await request("PUT", tokenA, {
      body: snapshotEnvelope(null, "only-a"),
      idempotencyKey: "put-only-a",
    });

    const beforeB = await request("GET", tokenB);
    expect(beforeB.status).toBe(404);
    await request("PUT", tokenB, {
      body: snapshotEnvelope(null, "only-b"),
      idempotencyKey: "put-only-b",
    });

    const [getA, getB] = await Promise.all([
      request("GET", tokenA),
      request("GET", tokenB),
    ]);
    expect(await getA.json()).toMatchObject({ snapshot: { profile: { displayName: "only-a" } } });
    expect(await getB.json()).toMatchObject({ snapshot: { profile: { displayName: "only-b" } } });
  });

  it("deletes with revision CAS, leaves a tombstone, and replays safely", async () => {
    await request("PUT", tokenA, {
      body: snapshotEnvelope(null, "A"),
      idempotencyKey: "put-before-delete",
    });
    const firstDelete = await request("DELETE", tokenA, {
      idempotencyKey: "delete-a",
      ifMatch: '"1"',
    });
    expect(firstDelete.status).toBe(200);
    const firstDeleteText = await firstDelete.text();
    expect(JSON.parse(firstDeleteText)).toMatchObject({ deleted: true, revision: 2 });

    const retry = await request("DELETE", tokenA, {
      idempotencyKey: "delete-a",
      ifMatch: '"1"',
    });
    expect(await retry.text()).toBe(firstDeleteText);

    const get = await request("GET", tokenA);
    expect(get.status).toBe(404);
    expect(await get.json()).toMatchObject({
      code: "snapshot_not_found",
      currentRevision: 2,
    });

    const staleRecreate = await request("PUT", tokenA, {
      body: snapshotEnvelope(null, "stale-device"),
      idempotencyKey: "stale-recreate",
    });
    expect(staleRecreate.status).toBe(409);
  });

  it("rejects unknown JSON fields and bodies over 1 MiB", async () => {
    const strict = await request("PUT", tokenA, {
      body: JSON.stringify({
        ...JSON.parse(snapshotEnvelope(null, "A")),
        accountID: "account-b",
      }),
      idempotencyKey: "strict-envelope",
    });
    expect(strict.status).toBe(422);
    expect(await strict.json()).toMatchObject({ code: "invalid_snapshot_envelope" });

    const oversized = await request("PUT", tokenA, {
      body: "x".repeat(1_048_577),
      idempotencyKey: "oversized",
    });
    expect(oversized.status).toBe(413);
  });

  it("rejects reusing an idempotency key for a different mutation", async () => {
    await request("PUT", tokenA, {
      body: snapshotEnvelope(null, "A"),
      idempotencyKey: "single-purpose-key",
    });
    const reused = await request("PUT", tokenA, {
      body: snapshotEnvelope(null, "different"),
      idempotencyKey: "single-purpose-key",
    });
    expect(reused.status).toBe(409);
    expect(await reused.json()).toMatchObject({ code: "idempotency_key_reused" });
  });
});

describe("shared planet API", () => {
  it("allows only one of two simultaneous invite acceptors into the last slot", async () => {
    await seedSession("account-c", "test-token-account-c");
    const code = await createPlanetInvite(tokenA, "friend");
    const results = await Promise.all([
      apiRequest("POST", planetAcceptEndpoint, tokenB, { code }),
      apiRequest("POST", planetAcceptEndpoint, "test-token-account-c", { code }),
    ]);
    expect(results.map((response) => response.status).sort()).toEqual([200, 409]);
    const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM planet_memberships")
      .first<{ count: number }>();
    expect(count?.count).toBe(2);
  });

  it("never reports both acceptance and revocation as successful in a race", async () => {
    const code = await createPlanetInvite(tokenA, "friend");
    const [accepted, revoked] = await Promise.all([
      apiRequest("POST", planetAcceptEndpoint, tokenB, { code }),
      apiRequest("DELETE", planetInvitesEndpoint, tokenA, { code }),
    ]);
    if (accepted.status === 200) {
      expect(revoked.status).toBe(409);
      expect(await revoked.json()).toMatchObject({ code: "invite_already_used" });
    } else {
      expect(accepted.status).toBe(404);
      expect(revoked.status).toBe(200);
      expect(await revoked.json()).toEqual({ revoked: true });
    }
  });

  it("keeps only one active code after concurrent replacement requests", async () => {
    await createPlanetInvite(tokenA, "friend");
    const results = await Promise.all([
      apiRequest("POST", planetInvitesEndpoint, tokenA, { relationship: "friend" }),
      apiRequest("POST", planetInvitesEndpoint, tokenA, { relationship: "friend" }),
    ]);
    expect(results.map((response) => response.status)).toEqual([201, 201]);
    const count = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM planet_invites WHERE used_at IS NULL AND revoked_at IS NULL"
    ).first<{ count: number }>();
    expect(count?.count).toBe(1);
  });

  it("creates a hash-only invite, joins two accounts, and makes same-account replay idempotent", async () => {
    await seedSession("account-c", "test-token-account-c");
    await request("PUT", tokenA, {
      body: snapshotEnvelope(null, "Aster", "aurora"),
      idempotencyKey: "profile-a",
    });
    await request("PUT", tokenB, {
      body: snapshotEnvelope(null, "Bibi", "moonveil"),
      idempotencyKey: "profile-b",
    });

    const empty = await apiRequest("GET", planetEndpoint, tokenB);
    expect(empty.status).toBe(200);
    expect(await empty.json()).toEqual({ planet: null });

    const created = await apiRequest("POST", planetInvitesEndpoint, tokenA, {
      relationship: "bestie",
    });
    expect(created.status).toBe(201);
    const createdBody = await created.json<Record<string, unknown>>();
    const invite = createdBody.invite as Record<string, unknown>;
    const code = String(invite.code);
    expect(code).toMatch(/^SC-(?:[0-9A-HJKMNP-TV-Z]{4}-){6}[0-9A-HJKMNP-TV-Z]{2}$/);
    expect(invite.shareURL).toBe(`${inviteLandingEndpoint}#code=${code}`);
    expect(invite.deepLink).toBe(`starcompanion://invite?code=${code}`);

    const storedInvite = await env.DB
      .prepare("SELECT code_sha256 FROM planet_invites")
      .first<{ code_sha256: string }>();
    expect(storedInvite?.code_sha256).toMatch(/^[0-9a-f]{64}$/);
    expect(storedInvite?.code_sha256).not.toContain(code);

    const cannotRevokeAnotherAccountsInvite = await apiRequest(
      "DELETE",
      planetInvitesEndpoint,
      tokenB,
      { code },
    );
    expect(cannotRevokeAnotherAccountsInvite.status).toBe(404);

    const compactCode = code.replace(/-/g, "").toLowerCase();
    const accepted = await apiRequest("POST", planetAcceptEndpoint, tokenB, {
      code: compactCode,
    });
    expect(accepted.status).toBe(200);
    expect(await accepted.json()).toMatchObject({
      accepted: true,
      planet: {
        relationship: "bestie",
        members: [
          { accountID: "account-a", name: "Aster", personaID: "aurora" },
          { accountID: "account-b", name: "Bibi", personaID: "moonveil" },
        ],
      },
    });
    const joinedPlanet = (await (await apiRequest("GET", planetEndpoint, tokenA))
      .json<Record<string, unknown>>()).planet as Record<string, unknown>;
    await expect(
      env.DB
        .prepare(
          `INSERT INTO planet_memberships (account_id, planet_id, slot, joined_at)
           VALUES ('account-c', ?, 1, 1)`,
        )
        .bind(String(joinedPlanet.id))
        .run(),
    ).rejects.toThrow();

    const replay = await apiRequest("POST", planetAcceptEndpoint, tokenB, { code });
    expect(replay.status).toBe(200);
    expect(await replay.json()).toMatchObject({ accepted: true });

    const replayByAnotherAccount = await apiRequest(
      "POST",
      planetAcceptEndpoint,
      "test-token-account-c",
      { code },
    );
    expect(replayByAnotherAccount.status).toBe(409);
    expect(await replayByAnotherAccount.json()).toMatchObject({ code: "invite_already_used" });

    const isolated = await apiRequest("GET", planetEndpoint, "test-token-account-c");
    expect(await isolated.json()).toEqual({ planet: null });
  });

  it("rejects expired codes, cross-planet moves, self-acceptance, and brute-force bursts", async () => {
    await seedSession("account-c", "test-token-account-c");

    const expiring = await createPlanetInvite(tokenA, "friend");
    await env.DB
      .prepare("UPDATE planet_invites SET created_at = 1, expires_at = 2 WHERE code_sha256 = ?")
      .bind(await sha256Hex(expiring.replace(/-/g, "")))
      .run();
    const expired = await apiRequest("POST", planetAcceptEndpoint, tokenB, { code: expiring });
    expect(expired.status).toBe(410);
    expect(await expired.json()).toMatchObject({ code: "invite_expired" });

    const own = await apiRequest("POST", planetAcceptEndpoint, tokenA, { code: expiring });
    expect(own.status).toBe(409);
    expect(await own.json()).toMatchObject({ code: "cannot_accept_own_invite" });

    const cInvite = await createPlanetInvite("test-token-account-c", "couple");
    const joinC = await apiRequest("POST", planetAcceptEndpoint, tokenB, { code: cInvite });
    expect(joinC.status).toBe(200);
    const replacementForA = await createPlanetInvite(tokenA, "friend");
    const cannotMove = await apiRequest("POST", planetAcceptEndpoint, tokenB, {
      code: replacementForA,
    });
    expect(cannotMove.status).toBe(409);
    expect(await cannotMove.json()).toMatchObject({ code: "already_in_planet" });

    const plausibleUnknownCode = "SC-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AA";
    let finalResponse: Response | null = null;
    for (let attempt = 0; attempt < 20; attempt += 1) {
      finalResponse = await apiRequest("POST", planetAcceptEndpoint, tokenA, {
        code: plausibleUnknownCode,
      });
    }
    expect(finalResponse?.status).toBe(429);
    expect(await finalResponse?.json()).toMatchObject({ code: "rate_limited" });
  });

  it("revokes only the creator's unused code and preserves the other member when leaving", async () => {
    const firstCode = await createPlanetInvite(tokenA, "couple");
    const revoked = await apiRequest("DELETE", planetInvitesEndpoint, tokenA, { code: firstCode });
    expect(revoked.status).toBe(200);
    expect(await revoked.json()).toEqual({ revoked: true });
    const revokedRetry = await apiRequest("DELETE", planetInvitesEndpoint, tokenA, { code: firstCode });
    expect(await revokedRetry.json()).toEqual({ revoked: true });
    const cannotUse = await apiRequest("POST", planetAcceptEndpoint, tokenB, { code: firstCode });
    expect(cannotUse.status).toBe(404);

    const secondCode = await createPlanetInvite(tokenA, "couple");
    expect((await apiRequest("POST", planetAcceptEndpoint, tokenB, { code: secondCode })).status)
      .toBe(200);
    const leaveB = await apiRequest("DELETE", planetMembershipEndpoint, tokenB);
    expect(await leaveB.json()).toEqual({ left: true, planetDeleted: false });
    expect(await (await apiRequest("GET", planetEndpoint, tokenB)).json()).toEqual({ planet: null });
    const remainingA = await (await apiRequest("GET", planetEndpoint, tokenA)).json<Record<string, unknown>>();
    expect(remainingA).toMatchObject({ planet: { members: [{ accountID: "account-a" }] } });

    const leaveA = await apiRequest("DELETE", planetMembershipEndpoint, tokenA);
    expect(await leaveA.json()).toEqual({ left: true, planetDeleted: true });
    const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM planets").first<{ count: number }>();
    expect(count?.count).toBe(0);
  });

  it("atomically invalidates an older unused code when its creator makes a replacement", async () => {
    const olderCode = await createPlanetInvite(tokenA, "friend");
    const newerCode = await createPlanetInvite(tokenA, "friend");
    expect(newerCode).not.toBe(olderCode);

    const oldAttempt = await apiRequest("POST", planetAcceptEndpoint, tokenB, {
      code: olderCode,
    });
    expect(oldAttempt.status).toBe(404);
    expect(await oldAttempt.json()).toMatchObject({ code: "invite_not_found" });
    expect((await apiRequest("POST", planetAcceptEndpoint, tokenB, { code: newerCode })).status)
      .toBe(200);
  });

  it("serves a no-network fragment landing page without putting an invite in server-visible HTML", async () => {
    const response = await exports.default.fetch(new Request(`${inviteLandingEndpoint}#code=SECRET-CODE`));
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Security-Policy")).toContain("connect-src 'none'");
    expect(response.headers.get("Referrer-Policy")).toBe("no-referrer");
    const html = await response.text();
    expect(html).toContain("location.hash");
    expect(html).toContain("starcompanion://invite?code=");
    expect(html).not.toContain("SECRET-CODE");
  });

  it("serves AASA only from configured Apple identifiers", async () => {
    const configured = await exports.default.fetch(
      new Request("https://api.example.test/.well-known/apple-app-site-association"),
    );
    expect(configured.status).toBe(200);
    expect(configured.headers.get("Content-Type")).toContain("application/json");
    expect(await configured.json()).toEqual({
      applinks: {
        details: [{
          appIDs: ["TEAMID1234.com.example.StarCompanion"],
          components: [{ "/": "/invite" }],
        }],
      },
    });

    const unconfigured = await worker.fetch(
      new Request("https://api.example.test/.well-known/apple-app-site-association"),
      { DB: env.DB },
    );
    expect(unconfigured.status).toBe(503);
    expect(await unconfigured.json()).toMatchObject({ code: "associated_domains_not_configured" });
  });
});

describe("complete account deletion API", () => {
  it("keeps data when Apple revoke fails, then deletes atomically and replays after token expiry", async () => {
    const rawNonce = randomBase64URL(32);
    let revocationStatus = 204;
    let revokeCalls = 0;
    installAppleHandlers(rawNonce, {
      revocationStatus: () => revocationStatus,
      onRevoke: () => { revokeCalls += 1; },
    });
    const identityToken = await makeAppleIdentityJWT(appleSubject, rawNonce);
    const login = await appleExchange(identityToken, rawNonce, appleSubject, "Deleting Star");
    const session = await login.json<Record<string, unknown>>();
    const accountID = String(session.canonicalAccountID);
    const accessToken = String(session.accessToken);
    const refreshToken = String(session.refreshToken);

    await request("PUT", tokenB, {
      body: snapshotEnvelope(null, "Survivor", "moonveil"),
      idempotencyKey: "survivor-profile",
    });
    await apiRequest("PUT", endpoint, accessToken, JSON.parse(snapshotEnvelope(
      null,
      "Deleting Star",
      "aurora",
    )), { "Idempotency-Key": "deleting-profile" });
    const invite = await createPlanetInvite(accessToken, "bestie");
    expect((await apiRequest("POST", planetAcceptEndpoint, tokenB, { code: invite })).status).toBe(200);

    const deletionKey = "123e4567-e89b-42d3-a456-426614174000";
    const first = await deleteAccount(accessToken, deletionKey);
    expect(first.status).toBe(503);
    expect(await first.json()).toMatchObject({ code: "apple_revoke_failed", retryable: true });
    expect(revokeCalls).toBe(1);
    const accountStillExists = await env.DB
      .prepare("SELECT COUNT(*) AS count FROM accounts WHERE id = ?")
      .bind(accountID)
      .first<{ count: number }>();
    expect(accountStillExists?.count).toBe(1);

    const blockedSnapshot = await request("GET", accessToken);
    expect(blockedSnapshot.status).toBe(409);
    expect(await blockedSnapshot.json()).toMatchObject({ code: "account_deletion_pending" });
    const blockedRefresh = await exports.default.fetch(new Request(appRefreshEndpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100.113" },
      body: JSON.stringify({ refreshToken }),
    }));
    expect(blockedRefresh.status).toBe(409);
    expect(await blockedRefresh.json()).toMatchObject({ code: "account_deletion_pending" });
    const blockedLogin = await appleExchange(identityToken, rawNonce, appleSubject, null);
    expect(blockedLogin.status).toBe(409);
    expect(await blockedLogin.json()).toMatchObject({ code: "account_deletion_pending" });

    const accessHash = await sha256Hex(accessToken);
    await env.DB
      .prepare("UPDATE auth_sessions SET expires_at = 1 WHERE token_sha256 = ?")
      .bind(accessHash)
      .run();
    revocationStatus = 200;
    const retry = await deleteAccount(accessToken, deletionKey);
    expect(retry.status).toBe(200);
    expect(await retry.json()).toEqual({ deleted: true });
    expect(revokeCalls).toBe(2);

    const rows = await env.DB
      .prepare(
        `SELECT
           (SELECT COUNT(*) FROM accounts WHERE id = ?) AS accounts,
           (SELECT COUNT(*) FROM auth_sessions WHERE account_id = ?) AS sessions,
           (SELECT COUNT(*) FROM account_snapshots WHERE account_id = ?) AS snapshots,
           (SELECT COUNT(*) FROM account_identities WHERE account_id = ?) AS identities,
           (SELECT COUNT(*) FROM apple_credentials WHERE account_id = ?) AS credentials,
           (SELECT COUNT(*) FROM planet_memberships WHERE account_id = ?) AS memberships,
           (SELECT COUNT(*) FROM planet_invites WHERE created_by_account_id = ?) AS invites`,
      )
      .bind(accountID, accountID, accountID, accountID, accountID, accountID, accountID)
      .first<Record<string, number>>();
    expect(rows).toMatchObject({
      accounts: 0,
      sessions: 0,
      snapshots: 0,
      identities: 0,
      credentials: 0,
      memberships: 0,
      invites: 0,
    });

    const survivorPlanet = await apiRequest("GET", planetEndpoint, tokenB);
    expect(survivorPlanet.status).toBe(200);
    expect(await survivorPlanet.json()).toMatchObject({
      planet: { members: [{ accountID: "account-b", name: "Survivor" }] },
    });
    await env.DB
      .prepare("UPDATE account_deletion_receipts SET created_at = 1")
      .run();
    const replay = await deleteAccount(accessToken, deletionKey);
    expect(replay.status).toBe(200);
    expect(await replay.json()).toEqual({ deleted: true });
    expect(revokeCalls).toBe(2);

    const reloginDuringTombstone = await appleExchange(identityToken, rawNonce, appleSubject, null);
    expect(reloginDuringTombstone.status).toBe(409);
    expect(await reloginDuringTombstone.json()).toMatchObject({ code: "account_deletion_pending" });

    await env.DB
      .prepare(
        `UPDATE deleted_identity_tombstones
         SET created_at = 1, expires_at = 2
         WHERE provider = 'apple'`,
      )
      .run();
    const freshRegistration = await appleExchange(identityToken, rawNonce, appleSubject, null);
    expect(freshRegistration.status).toBe(200);
    const freshSession = await freshRegistration.json<Record<string, unknown>>();
    expect(freshSession.canonicalAccountID).not.toBe(accountID);
    expect(String(freshSession.canonicalAccountID)).toMatch(/^acc_[A-Za-z0-9_-]{24}$/);
    expect((await request("GET", accessToken)).status).toBe(401);
    expect((await request("GET", String(freshSession.accessToken))).status).toBe(404);

    const crossAccount = await deleteAccount(tokenB, deletionKey);
    expect(crossAccount.status).toBe(503);
    expect(await crossAccount.json()).toMatchObject({ code: "apple_revoke_failed" });
    const survivorStillExists = await env.DB
      .prepare("SELECT COUNT(*) AS count FROM accounts WHERE id = 'account-b'")
      .first<{ count: number }>();
    expect(survivorStillExists?.count).toBe(1);
  });

  it("requires the exact confirmation body and a UUID idempotency key", async () => {
    const badConfirmation = await apiRequest(
      "DELETE",
      accountDeletionEndpoint,
      tokenA,
      { confirmation: "DELETE", extra: true },
      { "Idempotency-Key": "123e4567-e89b-42d3-a456-426614174000" },
    );
    expect(badConfirmation.status).toBe(422);
    const badKey = await apiRequest(
      "DELETE",
      accountDeletionEndpoint,
      tokenA,
      { confirmation: "DELETE" },
      { "Idempotency-Key": "not-a-uuid" },
    );
    expect(badKey.status).toBe(400);
  });
});

describe("scheduled retention cleanup", () => {
  it("deletes expired TTL rows while retaining anonymous account-deletion receipts", async () => {
    await env.DB.batch([
      env.DB
        .prepare(
          `INSERT INTO deleted_identity_tombstones
             (provider, provider_subject_sha256, created_at, expires_at)
           VALUES ('apple', ?, 1, 2)`,
        )
        .bind("a".repeat(64)),
      env.DB
        .prepare(
          `INSERT INTO auth_rate_limits
             (bucket_sha256, window_start, attempts, expires_at)
           VALUES (?, 1, 1, 2)`,
        )
        .bind("b".repeat(64)),
      env.DB
        .prepare(
          `INSERT INTO planet_rate_limits
             (bucket_sha256, action, window_start, attempts, expires_at)
           VALUES (?, 'create', 1, 1, 2)`,
        )
        .bind("c".repeat(64)),
      env.DB
        .prepare(
          `INSERT INTO account_snapshot_mutations
             (account_id, idempotency_key, method, request_sha256,
              response_status, response_json, created_at, expires_at)
           VALUES ('account-a', 'expired-mutation', 'PUT', ?, 200, '{}', 1, 2)`,
        )
        .bind("d".repeat(64)),
      env.DB
        .prepare(
          `INSERT INTO account_deletion_receipts
             (access_token_sha256, idempotency_key_sha256, request_sha256,
              response_json, created_at)
           VALUES (?, ?, ?, '{"deleted":true}', 1)`,
        )
        .bind("e".repeat(64), "f".repeat(64), "0".repeat(64)),
    ]);

    await cleanupExpiredRecords(env.DB, 3);

    const counts = await env.DB
      .prepare(
        `SELECT
           (SELECT COUNT(*) FROM deleted_identity_tombstones) AS tombstones,
           (SELECT COUNT(*) FROM auth_rate_limits) AS auth_limits,
           (SELECT COUNT(*) FROM planet_rate_limits) AS planet_limits,
           (SELECT COUNT(*) FROM account_snapshot_mutations) AS mutations,
           (SELECT COUNT(*) FROM account_deletion_receipts) AS receipts`,
      )
      .first<Record<string, number>>();
    expect(counts).toMatchObject({
      tombstones: 0,
      auth_limits: 0,
      planet_limits: 0,
      mutations: 0,
      receipts: 1,
    });
  });
});

async function request(
  method: "GET" | "PUT" | "DELETE",
  token: string,
  options: { body?: string; idempotencyKey?: string; ifMatch?: string } = {},
): Promise<Response> {
  const headers = new Headers({ Authorization: `Bearer ${token}` });
  if (options.body !== undefined) headers.set("Content-Type", "application/json");
  if (options.idempotencyKey !== undefined) headers.set("Idempotency-Key", options.idempotencyKey);
  if (options.ifMatch !== undefined) headers.set("If-Match", options.ifMatch);
  return exports.default.fetch(new Request(endpoint, { method, headers, body: options.body }));
}

async function apiRequest(
  method: "GET" | "POST" | "PUT" | "DELETE",
  url: string,
  token: string,
  body?: Record<string, unknown>,
  extraHeaders: Record<string, string> = {},
): Promise<Response> {
  const headers = new Headers({ Authorization: `Bearer ${token}`, ...extraHeaders });
  let encodedBody: string | undefined;
  if (body !== undefined) {
    headers.set("Content-Type", "application/json");
    encodedBody = JSON.stringify(body);
  }
  return exports.default.fetch(new Request(url, { method, headers, body: encodedBody }));
}

async function createPlanetInvite(
  token: string,
  relationship: "friend" | "bestie" | "couple",
): Promise<string> {
  const response = await apiRequest("POST", planetInvitesEndpoint, token, { relationship });
  expect(response.status).toBe(201);
  const body = await response.json<{ invite: { code: string } }>();
  return body.invite.code;
}

async function deleteAccount(token: string, idempotencyKey: string): Promise<Response> {
  return apiRequest(
    "DELETE",
    accountDeletionEndpoint,
    token,
    { confirmation: "DELETE" },
    { "Idempotency-Key": idempotencyKey },
  );
}

async function seedSession(accountID: string, token: string): Promise<void> {
  const tokenHash = await sha256Hex(token);
  await env.DB.batch([
    env.DB.prepare("INSERT INTO accounts (id) VALUES (?)").bind(accountID),
    env.DB
      .prepare("INSERT INTO auth_sessions (token_sha256, account_id) VALUES (?, ?)")
      .bind(tokenHash, accountID),
  ]);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function snapshotEnvelope(
  baseRevision: number | null,
  displayName: string,
  personaID = "classic",
): string {
  return JSON.stringify({
    schemaVersion: 1,
    baseRevision,
    snapshot: {
      schemaVersion: 1,
      profile: { displayName },
      savedGuides: [],
      readingHistory: [],
      planet: {},
      visitStreak: 0,
      lastVisitDate: null,
      dailyGuideRevealDate: null,
      tarotDrawDate: null,
      wardrobe: { selectedPersona: personaID },
      starLife: {},
    },
  });
}

async function appleExchange(
  identityJWT: string,
  rawNonce: string,
  providerSubject: string,
  displayName: string | null,
): Promise<Response> {
  const body: Record<string, unknown> = {
    providerSubject,
    identityToken: standardBase64(identityJWT),
    authorizationCode: standardBase64("apple-auth-code"),
    nonce: rawNonce,
    state: randomBase64URL(24),
  };
  if (displayName !== null) body.displayName = displayName;
  return exports.default.fetch(new Request(appleExchangeEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100.42" },
    body: JSON.stringify(body),
  }));
}

function installAppleHandlers(
  rawNonce: string,
  options: {
    rejectAuthorizationCode?: boolean;
    exchangedSubject?: string;
    jwksKeyID?: string;
    onJWKFetch?: () => void;
    revocationStatus?: () => number;
    onRevoke?: () => void;
  } = {},
): void {
  const jwksKeyID = options.jwksKeyID ?? appleKeyID;
  network.use(
    http.get("https://appleid.apple.com/auth/keys", () => {
      options.onJWKFetch?.();
      return HttpResponse.json({
        keys: [{ ...applePublicJWK, kid: jwksKeyID, alg: "RS256", use: "sig" }],
      });
    }),
    http.post("https://appleid.apple.com/auth/token", async ({ request }) => {
      const posted = await request.formData();
      const form = new URLSearchParams();
      for (const [key, value] of posted) {
        if (typeof value === "string") form.append(key, value);
      }
      expect(form.get("client_id")).toBe("com.example.StarCompanion");
      expect(form.get("client_secret")?.split(".")).toHaveLength(3);
      if (form.get("grant_type") === "authorization_code") {
        expect(form.get("code")).toBe("apple-auth-code");
        if (options.rejectAuthorizationCode === true) {
          return HttpResponse.json({ error: "invalid_grant" }, { status: 400 });
        }
        return HttpResponse.json({
          access_token: "apple-access-token",
          token_type: "Bearer",
          expires_in: 3600,
          refresh_token: "apple-refresh-token",
          id_token: await makeAppleIdentityJWT(
            options.exchangedSubject ?? appleSubject,
            rawNonce,
            jwksKeyID,
          ),
        });
      }
      expect(form.get("grant_type")).toBe("refresh_token");
      expect(form.get("refresh_token")).toBe("apple-refresh-token");
      return HttpResponse.json({
        access_token: "apple-refreshed-access-token",
        token_type: "Bearer",
        expires_in: 3600,
        id_token: await makeAppleIdentityJWT(appleSubject, null, jwksKeyID),
      });
    }),
    http.post("https://appleid.apple.com/auth/revoke", async ({ request }) => {
      options.onRevoke?.();
      const posted = await request.formData();
      expect(posted.get("client_id")).toBe("com.example.StarCompanion");
      expect(String(posted.get("client_secret"))?.split(".")).toHaveLength(3);
      expect(posted.get("token")).toBe("apple-refresh-token");
      expect(posted.get("token_type_hint")).toBe("refresh_token");
      return HttpResponse.text("", { status: options.revocationStatus?.() ?? 200 });
    }),
  );
}

async function makeAppleIdentityJWT(
  subject: string,
  rawNonce: string | null,
  keyID = appleKeyID,
  claimOverrides: Record<string, unknown> = {},
): Promise<string> {
  const now = Math.floor(Date.now() / 1_000);
  const header = base64URL(JSON.stringify({ alg: "RS256", kid: keyID }));
  const claims: Record<string, unknown> = {
    iss: "https://appleid.apple.com",
    aud: "com.example.StarCompanion",
    sub: subject,
    iat: now,
    exp: now + 5 * 60,
  };
  if (rawNonce !== null) claims.nonce = await sha256Hex(rawNonce);
  Object.assign(claims, claimOverrides);
  const payload = base64URL(JSON.stringify(claims));
  const input = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    appleSigningKeyPair.privateKey,
    new TextEncoder().encode(input),
  );
  return `${input}.${base64URL(new Uint8Array(signature))}`;
}

function randomBase64URL(byteLength: number): string {
  return base64URL(crypto.getRandomValues(new Uint8Array(byteLength)));
}

function standardBase64(value: string): string {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64URL(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

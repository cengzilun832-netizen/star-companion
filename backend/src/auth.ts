const APPLE_EXCHANGE_PATH = "/v1/auth/apple/exchange";
const SESSION_REFRESH_PATH = "/v1/auth/session/refresh";
const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_JWKS_CACHE_URL = "https://star-companion.internal-cache/apple-jwks-v1";
const APPLE_JWKS_CACHE_SECONDS = 60 * 60;
const MAX_AUTH_REQUEST_BYTES = 64 * 1024;
const MAX_UPSTREAM_RESPONSE_BYTES = 128 * 1024;
const ACCESS_TOKEN_TTL_SECONDS = 60 * 60;
const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;
const AUTH_RATE_WINDOW_SECONDS = 10 * 60;
const AUTH_RATE_MAX_ATTEMPTS = 10;

type JSONObject = { [key: string]: JSONValue };
type JSONValue = null | boolean | number | string | JSONValue[] | JSONObject;

interface AppleConfiguration {
  clientID: string;
  teamID: string;
  keyID: string;
  privateKeyPEM: string;
  refreshTokenEncryptionKey: CryptoKey;
  rateLimitSalt: string;
}

interface AppleExchangeRequest {
  providerSubject: string;
  displayName: string | null;
  identityToken: string;
  authorizationCode: string;
  nonce: string;
  state: string;
}

interface VerifiedAppleIdentity {
  subject: string;
}

interface AppleTokenResponse {
  accessToken: string;
  expiresIn: number;
  identityToken: string;
  refreshToken: string | null;
}

interface RefreshSessionRow {
  account_id: string;
  session_family_id: string;
  provider_subject: string;
  display_name: string | null;
  refresh_token_ciphertext: string;
  refresh_token_nonce: string;
  refresh_token_key_version: number;
  deletion_pending: number;
}

interface AppleCredentialForDeletionRow {
  provider_subject: string;
  refresh_token_ciphertext: string;
  refresh_token_nonce: string;
  refresh_token_key_version: number;
}

interface IssuedAppSession {
  accessToken: string;
  refreshToken: string;
  accessTokenHash: string;
  refreshTokenHash: string;
  familyID: string;
  issuedAtSeconds: number;
  accessExpiresAtSeconds: number;
  refreshExpiresAtSeconds: number;
}

interface EncryptedToken {
  ciphertext: string;
  nonce: string;
}

interface IdentityDisplayRow {
  account_id: string;
  display_name: string | null;
}

export class AuthAPIError extends Error {
  readonly status: number;
  readonly code: string;
  readonly headers?: HeadersInit;
  readonly retryAfterSeconds?: number;
  readonly retryable?: boolean;

  constructor(
    status: number,
    code: string,
    options?: { headers?: HeadersInit; retryAfterSeconds?: number; retryable?: boolean },
  ) {
    super(code);
    this.name = "AuthAPIError";
    this.status = status;
    this.code = code;
    this.headers = options?.headers;
    this.retryAfterSeconds = options?.retryAfterSeconds;
    this.retryable = options?.retryable;
  }
}

export function isAuthPath(pathname: string): boolean {
  return pathname === APPLE_EXCHANGE_PATH || pathname === SESSION_REFRESH_PATH;
}

export async function handleAuthRoute(
  request: Request,
  url: URL,
  env: Env,
  requestID: string,
): Promise<Response> {
  if (url.search !== "") throw new AuthAPIError(400, "query_not_allowed");
  if (request.method !== "POST") {
    throw new AuthAPIError(405, "method_not_allowed", { headers: { Allow: "POST" } });
  }

  const configuration = await requireAppleConfiguration(env);
  await enforceAuthRateLimit(request, env.DB, configuration.rateLimitSalt);

  if (url.pathname === APPLE_EXCHANGE_PATH) {
    return exchangeAppleCredential(request, env.DB, configuration, requestID);
  }
  return refreshAppSession(request, env.DB, configuration, requestID);
}

export function responseForAuthError(error: AuthAPIError, requestID: string): Response {
  const body: JSONObject = { code: error.code, requestID };
  if (error.retryAfterSeconds !== undefined) {
    body["retryAfterSeconds"] = error.retryAfterSeconds;
  }
  if (error.retryable !== undefined) body["retryable"] = error.retryable;
  return jsonResponse(body, error.status, requestID, error.headers);
}

async function exchangeAppleCredential(
  request: Request,
  db: D1Database,
  configuration: AppleConfiguration,
  requestID: string,
): Promise<Response> {
  requireJSONContentType(request);
  const body = parseAppleExchangeRequest(await readBoundedJSON(request, MAX_AUTH_REQUEST_BYTES));
  const rawNonceDigest = await sha256Hex(new TextEncoder().encode(body.nonce));
  const clientIdentityJWT = decodeClientBase64(body.identityToken, 32 * 1024);

  const initialIdentity = await verifyAppleIdentityToken(
    clientIdentityJWT,
    configuration.clientID,
    rawNonceDigest,
  );
  if (initialIdentity.subject !== body.providerSubject) {
    throw invalidAppleCredential();
  }

  const authorizationCode = decodeClientBase64(body.authorizationCode, 16 * 1024);
  const appleTokens = await exchangeAuthorizationCode(
    authorizationCode,
    configuration,
  );
  if (appleTokens.refreshToken === null) throw invalidAppleCredential();

  const exchangedIdentity = await verifyAppleIdentityToken(
    appleTokens.identityToken,
    configuration.clientID,
    rawNonceDigest,
  );
  if (exchangedIdentity.subject !== initialIdentity.subject) {
    throw invalidAppleCredential();
  }

  const providerSubjectHash = await sha256Hex(new TextEncoder().encode(initialIdentity.subject));
  const displayName = normalizedDisplayName(body.displayName);
  const accountID = await resolveAppleAccountID(
    db,
    initialIdentity.subject,
    providerSubjectHash,
    displayName,
  );
  const encryptedAppleRefreshToken = await encryptToken(
    appleTokens.refreshToken,
    accountID,
    configuration.refreshTokenEncryptionKey,
  );
  const appSession = await issueAppSession();

  try {
    await db.batch([
      db
        .prepare(
          `UPDATE account_identities
           SET display_name = CASE
             WHEN (display_name IS NULL OR display_name = '') AND ? IS NOT NULL THEN ?
             ELSE display_name
           END,
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
           WHERE provider = 'apple' AND provider_subject = ? AND account_id = ?
             AND NOT EXISTS (
               SELECT 1 FROM account_deletion_locks WHERE account_id = ?
             )
             AND NOT EXISTS (
               SELECT 1 FROM deleted_identity_tombstones
               WHERE provider = 'apple' AND provider_subject_sha256 = ? AND expires_at > ?
             )`,
        )
        .bind(
          displayName,
          displayName,
          initialIdentity.subject,
          accountID,
          accountID,
          providerSubjectHash,
          appSession.issuedAtSeconds,
        ),
      db
        .prepare(
          `INSERT INTO apple_credentials (
             account_id, provider_subject, refresh_token_ciphertext,
             refresh_token_nonce, refresh_token_key_version,
             apple_access_expires_at, last_validated_at, updated_at
           )
           SELECT ?, ?, ?, ?, 1, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
           WHERE NOT EXISTS (
             SELECT 1 FROM account_deletion_locks WHERE account_id = ?
           )
           AND NOT EXISTS (
             SELECT 1 FROM deleted_identity_tombstones
             WHERE provider = 'apple' AND provider_subject_sha256 = ? AND expires_at > ?
           )
           ON CONFLICT(account_id) DO UPDATE SET
             provider_subject = excluded.provider_subject,
             refresh_token_ciphertext = excluded.refresh_token_ciphertext,
             refresh_token_nonce = excluded.refresh_token_nonce,
             refresh_token_key_version = excluded.refresh_token_key_version,
             apple_access_expires_at = excluded.apple_access_expires_at,
             last_validated_at = excluded.last_validated_at,
             updated_at = excluded.updated_at
           WHERE NOT EXISTS (
             SELECT 1 FROM account_deletion_locks WHERE account_id = excluded.account_id
           )`,
        )
        .bind(
          accountID,
          initialIdentity.subject,
          encryptedAppleRefreshToken.ciphertext,
          encryptedAppleRefreshToken.nonce,
          appSession.issuedAtSeconds + appleTokens.expiresIn,
          appSession.issuedAtSeconds,
          accountID,
          providerSubjectHash,
          appSession.issuedAtSeconds,
        ),
      ...sessionInsertStatements(
        db,
        accountID,
        providerSubjectHash,
        appSession,
      ),
    ]);
  } catch {
    throw new AuthAPIError(503, "storage_unavailable");
  }

  const storedIdentity = await db
    .prepare(
      `SELECT account_id, display_name
       FROM account_identities
       WHERE provider = 'apple' AND provider_subject = ?
       LIMIT 1`,
    )
    .bind(initialIdentity.subject)
    .first<IdentityDisplayRow>();
  const storedSessions = await db
    .prepare(
      `SELECT COUNT(*) AS count FROM auth_sessions
       WHERE token_sha256 IN (?, ?) AND account_id = ? AND revoked_at IS NULL`,
    )
    .bind(appSession.accessTokenHash, appSession.refreshTokenHash, accountID)
    .first<{ count: number }>();
  if (
    storedIdentity === null
    || storedIdentity.account_id !== accountID
    || storedSessions?.count !== 2
  ) {
    await assertAppleIdentityCanAuthenticate(db, accountID, providerSubjectHash);
    throw new AuthAPIError(503, "storage_unavailable");
  }

  return sessionResponse(
    accountID,
    initialIdentity.subject,
    normalizedDisplayName(storedIdentity.display_name) ?? "Apple Stargazer",
    appSession,
    requestID,
  );
}

async function refreshAppSession(
  request: Request,
  db: D1Database,
  configuration: AppleConfiguration,
  requestID: string,
): Promise<Response> {
  requireJSONContentType(request);
  const value = await readBoundedJSON(request, 20 * 1024);
  if (!isJSONObject(value) || !hasExactKeys(value, ["refreshToken"])) {
    throw new AuthAPIError(422, "invalid_refresh_request");
  }
  const refreshToken = value["refreshToken"];
  if (typeof refreshToken !== "string" || !isOpaqueToken(refreshToken)) {
    throw new AuthAPIError(422, "invalid_refresh_request");
  }

  const refreshHash = await sha256Hex(new TextEncoder().encode(refreshToken));
  const now = Math.floor(Date.now() / 1_000);
  const row = await db
    .prepare(
      `SELECT s.account_id,
              s.session_family_id,
              i.provider_subject,
              i.display_name,
              c.refresh_token_ciphertext,
              c.refresh_token_nonce,
              c.refresh_token_key_version,
              EXISTS(
                SELECT 1 FROM account_deletion_locks AS d
                WHERE d.account_id = s.account_id
              ) AS deletion_pending
       FROM auth_sessions AS s
       INNER JOIN account_identities AS i
         ON i.account_id = s.account_id AND i.provider = 'apple'
       INNER JOIN apple_credentials AS c ON c.account_id = s.account_id
       WHERE s.token_sha256 = ?
         AND s.kind = 'refresh'
         AND s.revoked_at IS NULL
         AND s.expires_at > ?
       LIMIT 1`,
    )
    .bind(refreshHash, now)
    .first<RefreshSessionRow>();
  if (row === null || row.session_family_id.length === 0 || row.refresh_token_key_version !== 1) {
    throw unauthorized();
  }
  if (row.deletion_pending === 1) throw accountDeletionPending();

  let appleRefreshToken: string;
  try {
    appleRefreshToken = await decryptToken(
      row.refresh_token_ciphertext,
      row.refresh_token_nonce,
      row.account_id,
      configuration.refreshTokenEncryptionKey,
    );
  } catch {
    throw new AuthAPIError(503, "credential_unavailable");
  }

  const appleTokens = await validateAppleRefreshToken(appleRefreshToken, configuration);
  const appleIdentity = await verifyAppleIdentityToken(
    appleTokens.identityToken,
    configuration.clientID,
    null,
  );
  if (appleIdentity.subject !== row.provider_subject) throw unauthorized();

  const nextSession = await issueAppSession(row.session_family_id);
  let results: D1Result<unknown>[];
  try {
    results = await db.batch([
      db
        .prepare(
          `UPDATE auth_sessions
           SET revoked_at = ?
           WHERE token_sha256 = ? AND kind = 'refresh'
             AND revoked_at IS NULL AND expires_at > ?
             AND NOT EXISTS (
               SELECT 1 FROM account_deletion_locks
               WHERE account_id = auth_sessions.account_id
             )`,
        )
        .bind(now, refreshHash, now),
      db
        .prepare(
          `INSERT INTO auth_sessions (
             token_sha256, account_id, expires_at, kind, session_family_id
           )
           SELECT ?, ?, ?, 'access', ? WHERE changes() = 1`,
        )
        .bind(
          nextSession.accessTokenHash,
          row.account_id,
          nextSession.accessExpiresAtSeconds,
          nextSession.familyID,
        ),
      db
        .prepare(
          `INSERT INTO auth_sessions (
             token_sha256, account_id, expires_at, kind, session_family_id
           )
           SELECT ?, ?, ?, 'refresh', ? WHERE changes() = 1`,
        )
        .bind(
          nextSession.refreshTokenHash,
          row.account_id,
          nextSession.refreshExpiresAtSeconds,
          nextSession.familyID,
        ),
      db
        .prepare(
          `UPDATE apple_credentials
           SET apple_access_expires_at = ?, last_validated_at = ?,
               updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
           WHERE account_id = ? AND changes() = 1`,
        )
        .bind(now + appleTokens.expiresIn, now, row.account_id),
    ]);
  } catch {
    throw new AuthAPIError(503, "storage_unavailable");
  }
  if ((results[0]?.meta.changes ?? 0) !== 1 || (results[1]?.meta.changes ?? 0) !== 1
      || (results[2]?.meta.changes ?? 0) !== 1) {
    const pending = await db
      .prepare("SELECT 1 AS pending FROM account_deletion_locks WHERE account_id = ? LIMIT 1")
      .bind(row.account_id)
      .first<{ pending: number }>();
    if (pending !== null) throw accountDeletionPending();
    throw unauthorized();
  }

  return sessionResponse(
    row.account_id,
    row.provider_subject,
    normalizedDisplayName(row.display_name) ?? "Apple Stargazer",
    nextSession,
    requestID,
  );
}

async function requireAppleConfiguration(env: Env): Promise<AppleConfiguration> {
  const clientID = cleanConfigurationValue(env.APPLE_CLIENT_ID, 255);
  const teamID = cleanConfigurationValue(env.APPLE_TEAM_ID, 64);
  const keyID = cleanConfigurationValue(env.APPLE_KEY_ID, 64);
  const privateKeyPEM = normalizePrivateKeyPEM(env.APPLE_PRIVATE_KEY);
  const encryptionKeyValue = cleanConfigurationValue(
    env.APPLE_REFRESH_TOKEN_ENCRYPTION_KEY,
    128,
  );
  const rateLimitSalt = cleanConfigurationValue(env.AUTH_RATE_LIMIT_SALT, 512);
  if (
    clientID === null || !/^[A-Za-z0-9.-]{3,255}$/.test(clientID)
    || teamID === null || !/^[A-Za-z0-9]{10}$/.test(teamID)
    || keyID === null || !/^[A-Za-z0-9]{10}$/.test(keyID)
    || privateKeyPEM === null
    || encryptionKeyValue === null
    || rateLimitSalt === null || rateLimitSalt.length < 32
  ) {
    throw new AuthAPIError(503, "auth_not_configured");
  }
  let refreshTokenEncryptionKey: CryptoKey;
  try {
    const keyBytes = decodeBase64URL(encryptionKeyValue, 32);
    if (keyBytes.byteLength !== 32) throw new Error("invalid key length");
    refreshTokenEncryptionKey = await crypto.subtle.importKey(
      "raw",
      keyBytes,
      { name: "AES-GCM" },
      false,
      ["encrypt", "decrypt"],
    );
  } catch {
    throw new AuthAPIError(503, "auth_not_configured");
  }
  return { clientID, teamID, keyID, privateKeyPEM, refreshTokenEncryptionKey, rateLimitSalt };
}

export async function revokeAppleCredentialForDeletion(
  db: D1Database,
  accountID: string,
  env: Env,
): Promise<string> {
  const configuration = await requireAppleConfiguration(env);
  const row = await db
    .prepare(
      `SELECT i.provider_subject,
              c.refresh_token_ciphertext,
              c.refresh_token_nonce,
              c.refresh_token_key_version
       FROM account_identities AS i
       INNER JOIN apple_credentials AS c ON c.account_id = i.account_id
       WHERE i.account_id = ? AND i.provider = 'apple'
       LIMIT 1`,
    )
    .bind(accountID)
    .first<AppleCredentialForDeletionRow>();
  if (row === null || row.refresh_token_key_version !== 1) {
    throw new AuthAPIError(503, "credential_unavailable", { retryable: true });
  }

  let refreshToken: string;
  try {
    refreshToken = await decryptToken(
      row.refresh_token_ciphertext,
      row.refresh_token_nonce,
      accountID,
      configuration.refreshTokenEncryptionKey,
    );
  } catch {
    throw new AuthAPIError(503, "credential_unavailable", { retryable: true });
  }

  const clientSecret = await makeAppleClientSecret(configuration);
  const form = new URLSearchParams({
    client_id: configuration.clientID,
    client_secret: clientSecret,
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  let response: Response;
  try {
    response = await fetch(APPLE_REVOKE_URL, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form.toString(),
      redirect: "manual",
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new AuthAPIError(503, "apple_revoke_failed", { retryable: true });
  }
  await discardBoundedBody(response, MAX_UPSTREAM_RESPONSE_BYTES);
  if (response.status !== 200) {
    throw new AuthAPIError(503, "apple_revoke_failed", { retryable: true });
  }
  return sha256Hex(new TextEncoder().encode(row.provider_subject));
}

async function resolveAppleAccountID(
  db: D1Database,
  providerSubject: string,
  providerSubjectHash: string,
  displayName: string | null,
): Promise<string> {
  const now = Math.floor(Date.now() / 1_000);
  await deleteExpiredIdentityTombstones(db, now);
  const existing = await db
    .prepare(
      `SELECT account_id, display_name
       FROM account_identities
       WHERE provider = 'apple' AND provider_subject = ?
       LIMIT 1`,
    )
    .bind(providerSubject)
    .first<IdentityDisplayRow>();
  if (existing !== null) {
    await assertAppleIdentityCanAuthenticate(db, existing.account_id, providerSubjectHash);
    return existing.account_id;
  }

  await assertIdentityTombstoneAbsent(db, providerSubjectHash, now);
  const candidateAccountID = `acc_${randomOpaqueToken(18)}`;
  try {
    await db.batch([
      db
        .prepare(
          `INSERT OR IGNORE INTO accounts (id)
           SELECT ?
           WHERE NOT EXISTS (
             SELECT 1 FROM deleted_identity_tombstones
             WHERE provider = 'apple' AND provider_subject_sha256 = ? AND expires_at > ?
           )`,
        )
        .bind(candidateAccountID, providerSubjectHash, now),
      db
        .prepare(
          `INSERT OR IGNORE INTO account_identities (
             provider, provider_subject, account_id, display_name
           )
           SELECT 'apple', ?, ?, ?
           WHERE EXISTS (SELECT 1 FROM accounts WHERE id = ?)
             AND NOT EXISTS (
               SELECT 1 FROM deleted_identity_tombstones
               WHERE provider = 'apple' AND provider_subject_sha256 = ? AND expires_at > ?
             )`,
        )
        .bind(
          providerSubject,
          candidateAccountID,
          displayName,
          candidateAccountID,
          providerSubjectHash,
          now,
        ),
    ]);
  } catch {
    throw new AuthAPIError(503, "storage_unavailable");
  }

  const resolved = await db
    .prepare(
      `SELECT account_id, display_name
       FROM account_identities
       WHERE provider = 'apple' AND provider_subject = ?
       LIMIT 1`,
    )
    .bind(providerSubject)
    .first<IdentityDisplayRow>();
  if (resolved === null) {
    await assertIdentityTombstoneAbsent(db, providerSubjectHash, now);
    throw new AuthAPIError(503, "storage_unavailable");
  }
  if (resolved.account_id !== candidateAccountID) {
    try {
      await db
        .prepare(
          `DELETE FROM accounts WHERE id = ?
           AND NOT EXISTS (SELECT 1 FROM account_identities WHERE account_id = ?)`,
        )
        .bind(candidateAccountID, candidateAccountID)
        .run();
    } catch {
      // A harmless orphan candidate can be cleaned by maintenance later.
    }
  }
  await assertAppleIdentityCanAuthenticate(db, resolved.account_id, providerSubjectHash);
  return resolved.account_id;
}

async function assertAppleIdentityCanAuthenticate(
  db: D1Database,
  accountID: string,
  providerSubjectHash: string,
): Promise<void> {
  const now = Math.floor(Date.now() / 1_000);
  try {
    await deleteExpiredIdentityTombstones(db, now);
    const pending = await db
      .prepare(
        `SELECT
           EXISTS(
             SELECT 1 FROM account_deletion_locks WHERE account_id = ?
           ) AS account_pending,
           EXISTS(
             SELECT 1 FROM deleted_identity_tombstones
             WHERE provider = 'apple' AND provider_subject_sha256 = ? AND expires_at > ?
           ) AS identity_pending`,
      )
      .bind(accountID, providerSubjectHash, now)
      .first<{ account_pending: number; identity_pending: number }>();
    if (pending?.account_pending === 1 || pending?.identity_pending === 1) {
      throw accountDeletionPending();
    }
  } catch (error) {
    if (error instanceof AuthAPIError) throw error;
    throw new AuthAPIError(503, "storage_unavailable");
  }
}

async function deleteExpiredIdentityTombstones(db: D1Database, now: number): Promise<void> {
  try {
    await db
      .prepare("DELETE FROM deleted_identity_tombstones WHERE expires_at <= ?")
      .bind(now)
      .run();
  } catch {
    throw new AuthAPIError(503, "storage_unavailable");
  }
}

async function assertIdentityTombstoneAbsent(
  db: D1Database,
  providerSubjectHash: string,
  now: number,
): Promise<void> {
  const tombstone = await db
    .prepare(
      `SELECT 1 AS pending FROM deleted_identity_tombstones
       WHERE provider = 'apple' AND provider_subject_sha256 = ? AND expires_at > ?
       LIMIT 1`,
    )
    .bind(providerSubjectHash, now)
    .first<{ pending: number }>();
  if (tombstone !== null) throw accountDeletionPending();
}

function cleanConfigurationValue(
  value: string | undefined,
  maximumLength: number,
  permitsNewlines = false,
): string | null {
  if (typeof value !== "string" || value.length === 0 || value.length > maximumLength) return null;
  if (value !== value.trim() || value.includes("CONFIGURE_")) return null;
  if (!permitsNewlines && /[\s\u0000-\u001f\u007f]/.test(value)) return null;
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value)) return null;
  return value;
}

function normalizePrivateKeyPEM(value: string | undefined): string | null {
  if (typeof value !== "string" || value.length === 0 || value.length > 16 * 1024) return null;
  const normalized = value.trim();
  if (
    normalized.length === 0
    || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(normalized)
    || !normalized.startsWith("-----BEGIN PRIVATE KEY-----")
    || !normalized.endsWith("-----END PRIVATE KEY-----")
  ) {
    return null;
  }
  return normalized;
}

async function enforceAuthRateLimit(
  request: Request,
  db: D1Database,
  salt: string,
): Promise<void> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "unavailable";
  const bucket = await sha256Hex(new TextEncoder().encode(`${salt}\n${ip}`));
  const now = Math.floor(Date.now() / 1_000);
  const windowStart = Math.floor(now / AUTH_RATE_WINDOW_SECONDS) * AUTH_RATE_WINDOW_SECONDS;
  const expiresAt = windowStart + AUTH_RATE_WINDOW_SECONDS;
  try {
    await db
      .prepare("DELETE FROM auth_rate_limits WHERE expires_at <= ?")
      .bind(now)
      .run();
    await db
      .prepare(
        `INSERT INTO auth_rate_limits (bucket_sha256, window_start, attempts, expires_at)
         VALUES (?, ?, 1, ?)
         ON CONFLICT(bucket_sha256, window_start)
         DO UPDATE SET attempts = attempts + 1`,
      )
      .bind(bucket, windowStart, expiresAt)
      .run();
    const row = await db
      .prepare(
        `SELECT attempts FROM auth_rate_limits
         WHERE bucket_sha256 = ? AND window_start = ?`,
      )
      .bind(bucket, windowStart)
      .first<{ attempts: number }>();
    if (row === null) throw new Error("missing rate row");
    if (row.attempts > AUTH_RATE_MAX_ATTEMPTS) {
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

function parseAppleExchangeRequest(value: JSONValue): AppleExchangeRequest {
  if (!isJSONObject(value)) throw invalidAppleRequest();
  const allowed = [
    "providerSubject", "displayName", "identityToken", "authorizationCode", "nonce", "state",
  ];
  const required = ["providerSubject", "identityToken", "authorizationCode", "nonce", "state"];
  if (!hasOnlyAllowedKeys(value, allowed) || !required.every((key) => key in value)) {
    throw invalidAppleRequest();
  }
  const providerSubject = value["providerSubject"];
  const displayName = value["displayName"] ?? null;
  const identityToken = value["identityToken"];
  const authorizationCode = value["authorizationCode"];
  const nonce = value["nonce"];
  const state = value["state"];
  if (
    typeof providerSubject !== "string" || !isCleanString(providerSubject, 512, false)
    || (displayName !== null && (typeof displayName !== "string" || !isCleanString(displayName, 160, true)))
    || typeof identityToken !== "string" || identityToken.length > 48 * 1024
    || typeof authorizationCode !== "string" || authorizationCode.length > 24 * 1024
    || typeof nonce !== "string" || !isBase64URLOfByteLength(nonce, 32)
    || typeof state !== "string" || !isBase64URLOfByteLength(state, 24)
  ) {
    throw invalidAppleRequest();
  }
  return { providerSubject, displayName, identityToken, authorizationCode, nonce, state };
}

function normalizedDisplayName(value: string | null): string | null {
  if (value === null) return null;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length === 0 ? null : normalized.slice(0, 160);
}

function invalidAppleRequest(): AuthAPIError {
  return new AuthAPIError(422, "invalid_apple_request");
}

function invalidAppleCredential(): AuthAPIError {
  return new AuthAPIError(401, "invalid_apple_credential");
}

function unauthorized(): AuthAPIError {
  return new AuthAPIError(401, "unauthorized", {
    headers: { "WWW-Authenticate": 'Bearer realm="star-companion"' },
  });
}

function accountDeletionPending(): AuthAPIError {
  return new AuthAPIError(409, "account_deletion_pending", { retryable: true });
}

async function exchangeAuthorizationCode(
  authorizationCode: string,
  configuration: AppleConfiguration,
): Promise<AppleTokenResponse> {
  const clientSecret = await makeAppleClientSecret(configuration);
  const form = new URLSearchParams({
    client_id: configuration.clientID,
    client_secret: clientSecret,
    code: authorizationCode,
    grant_type: "authorization_code",
  });
  return requestAppleTokens(form, true);
}

async function validateAppleRefreshToken(
  refreshToken: string,
  configuration: AppleConfiguration,
): Promise<AppleTokenResponse> {
  const clientSecret = await makeAppleClientSecret(configuration);
  const form = new URLSearchParams({
    client_id: configuration.clientID,
    client_secret: clientSecret,
    refresh_token: refreshToken,
    grant_type: "refresh_token",
  });
  return requestAppleTokens(form, false);
}

async function requestAppleTokens(
  form: URLSearchParams,
  requiresRefreshToken: boolean,
): Promise<AppleTokenResponse> {
  let response: Response;
  try {
    response = await fetch(APPLE_TOKEN_URL, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form.toString(),
      redirect: "manual",
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new AuthAPIError(503, "apple_unavailable");
  }
  if (response.status !== 200) {
    await discardBoundedBody(response, MAX_UPSTREAM_RESPONSE_BYTES);
    if (response.status >= 500) throw new AuthAPIError(503, "apple_unavailable");
    throw invalidAppleCredential();
  }
  let value: JSONValue;
  try {
    value = await readBoundedResponseJSON(response, MAX_UPSTREAM_RESPONSE_BYTES);
  } catch {
    throw new AuthAPIError(503, "apple_unavailable");
  }
  if (!isJSONObject(value)) throw invalidAppleCredential();
  const allowed = ["access_token", "token_type", "expires_in", "refresh_token", "id_token"];
  const required = ["access_token", "token_type", "expires_in", "id_token"];
  if (!hasOnlyAllowedKeys(value, allowed) || !required.every((key) => key in value)) {
    throw invalidAppleCredential();
  }
  const accessToken = value["access_token"];
  const tokenType = value["token_type"];
  const expiresIn = value["expires_in"];
  const identityToken = value["id_token"];
  const refreshToken = value["refresh_token"] ?? null;
  if (
    typeof accessToken !== "string" || !isCleanString(accessToken, 16_384, false)
    || typeof tokenType !== "string" || tokenType.toLowerCase() !== "bearer"
    || typeof expiresIn !== "number" || !Number.isSafeInteger(expiresIn)
    || expiresIn < 1 || expiresIn > 24 * 60 * 60
    || typeof identityToken !== "string" || !isCleanString(identityToken, 32 * 1024, false)
    || (refreshToken !== null
      && (typeof refreshToken !== "string" || !isCleanString(refreshToken, 16_384, false)))
    || (requiresRefreshToken && refreshToken === null)
  ) {
    throw invalidAppleCredential();
  }
  return { accessToken, expiresIn, identityToken, refreshToken };
}

async function makeAppleClientSecret(configuration: AppleConfiguration): Promise<string> {
  const now = Math.floor(Date.now() / 1_000);
  const header = encodeJWTPart({ alg: "ES256", kid: configuration.keyID, typ: "JWT" });
  const claims = encodeJWTPart({
    iss: configuration.teamID,
    iat: now - 5,
    exp: now + 5 * 60,
    aud: APPLE_ISSUER,
    sub: configuration.clientID,
  });
  const signingInput = `${header}.${claims}`;
  let key: CryptoKey;
  try {
    const bytes = decodePEM(configuration.privateKeyPEM, "PRIVATE KEY", 8 * 1024);
    key = await crypto.subtle.importKey(
      "pkcs8",
      bytes,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
  } catch {
    throw new AuthAPIError(503, "auth_not_configured");
  }
  let signature: ArrayBuffer;
  try {
    signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(signingInput),
    );
  } catch {
    throw new AuthAPIError(503, "auth_not_configured");
  }
  const signatureBytes = new Uint8Array(signature);
  if (signatureBytes.byteLength !== 64) throw new AuthAPIError(503, "auth_not_configured");
  return `${signingInput}.${encodeBase64URL(signatureBytes)}`;
}

async function verifyAppleIdentityToken(
  jwt: string,
  clientID: string,
  expectedNonce: string | null,
): Promise<VerifiedAppleIdentity> {
  const parts = jwt.split(".");
  if (parts.length !== 3 || parts.some((part) => part.length === 0)) throw invalidAppleCredential();
  let header: JSONValue;
  let claims: JSONValue;
  let signature: Uint8Array;
  try {
    const [encodedHeader, encodedClaims, encodedSignature] = parts as [string, string, string];
    header = parseBase64URLJSON(encodedHeader, 4 * 1024);
    claims = parseBase64URLJSON(encodedClaims, 16 * 1024);
    signature = decodeBase64URL(encodedSignature, 1_024);
  } catch {
    throw invalidAppleCredential();
  }
  if (!isJSONObject(header) || header["alg"] !== "RS256") throw invalidAppleCredential();
  const kid = header["kid"];
  if (typeof kid !== "string" || !isCleanString(kid, 128, false)) throw invalidAppleCredential();

  const key = await fetchAppleVerificationKey(kid);
  let verified = false;
  try {
    verified = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      key,
      signature,
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
  } catch {
    throw invalidAppleCredential();
  }
  if (!verified || !isJSONObject(claims)) throw invalidAppleCredential();

  const issuer = claims["iss"];
  const audience = claims["aud"];
  const subject = claims["sub"];
  const expiry = claims["exp"];
  const issuedAt = claims["iat"];
  const nonce = claims["nonce"];
  const notBefore = claims["nbf"];
  const now = Math.floor(Date.now() / 1_000);
  const audienceMatches = audience === clientID
    || (Array.isArray(audience) && audience.includes(clientID));
  if (
    issuer !== APPLE_ISSUER || !audienceMatches
    || typeof subject !== "string" || !isCleanString(subject, 512, false)
    || typeof expiry !== "number" || !Number.isSafeInteger(expiry) || expiry <= now - 30
    || typeof issuedAt !== "number" || !Number.isSafeInteger(issuedAt)
    || issuedAt > now + 5 * 60 || issuedAt < now - 24 * 60 * 60
    || (notBefore !== undefined
      && (typeof notBefore !== "number" || !Number.isSafeInteger(notBefore) || notBefore > now + 30))
    || (expectedNonce !== null && nonce !== expectedNonce)
  ) {
    throw invalidAppleCredential();
  }
  if (Array.isArray(audience) && audience.length > 1 && claims["azp"] !== clientID) {
    throw invalidAppleCredential();
  }
  return { subject };
}

async function fetchAppleVerificationKey(kid: string): Promise<CryptoKey> {
  let keySet = await readAppleJWKSetFromCache();
  let jwk = keySet === null ? null : findAppleJWK(keySet, kid);
  if (jwk === null) {
    keySet = await fetchFreshAppleJWKSet();
    jwk = findAppleJWK(keySet, kid);
  }
  if (jwk === null) throw invalidAppleCredential();
  try {
    return await crypto.subtle.importKey(
      "jwk",
      { kty: "RSA", n: jwk.modulus, e: jwk.exponent },
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
  } catch {
    throw new AuthAPIError(503, "apple_unavailable");
  }
}

interface AppleJWK {
  keyID: string;
  modulus: string;
  exponent: string;
}

async function readAppleJWKSetFromCache(): Promise<JSONValue | null> {
  let response: Response | undefined;
  try {
    response = await caches.default.match(new Request(APPLE_JWKS_CACHE_URL));
  } catch {
    return null;
  }
  if (response === undefined) return null;
  try {
    return await readBoundedResponseJSON(response, MAX_UPSTREAM_RESPONSE_BYTES);
  } catch {
    await caches.default.delete(new Request(APPLE_JWKS_CACHE_URL));
    return null;
  }
}

async function fetchFreshAppleJWKSet(): Promise<JSONValue> {
  let response: Response;
  try {
    response = await fetch(APPLE_JWKS_URL, {
      method: "GET",
      headers: { Accept: "application/json" },
      redirect: "manual",
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new AuthAPIError(503, "apple_unavailable");
  }
  if (response.status !== 200) {
    await discardBoundedBody(response, MAX_UPSTREAM_RESPONSE_BYTES);
    throw new AuthAPIError(503, "apple_unavailable");
  }
  let value: JSONValue;
  try {
    value = await readBoundedResponseJSON(response, MAX_UPSTREAM_RESPONSE_BYTES);
  } catch {
    throw new AuthAPIError(503, "apple_unavailable");
  }
  if (!isJSONObject(value) || !Array.isArray(value["keys"]) || value["keys"].length > 32) {
    throw new AuthAPIError(503, "apple_unavailable");
  }
  try {
    await caches.default.put(
      new Request(APPLE_JWKS_CACHE_URL),
      new Response(JSON.stringify(value), {
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": `public, max-age=${APPLE_JWKS_CACHE_SECONDS}`,
        },
      }),
    );
  } catch {
    // A cache failure must not turn a valid Apple login into an outage.
  }
  return value;
}

function findAppleJWK(value: JSONValue, kid: string): AppleJWK | null {
  if (!isJSONObject(value) || !Array.isArray(value["keys"])) return null;
  const jwk = value["keys"].find((candidate) => {
    return isJSONObject(candidate)
      && candidate["kid"] === kid
      && candidate["kty"] === "RSA"
      && candidate["alg"] === "RS256"
      && candidate["use"] === "sig"
      && typeof candidate["n"] === "string"
      && typeof candidate["e"] === "string";
  });
  if (!isJSONObject(jwk)) return null;
  return { keyID: kid, modulus: String(jwk["n"]), exponent: String(jwk["e"]) };
}

async function issueAppSession(existingFamilyID?: string): Promise<IssuedAppSession> {
  const accessToken = randomOpaqueToken(32);
  const refreshToken = randomOpaqueToken(48);
  const issuedAtSeconds = Math.floor(Date.now() / 1_000);
  return {
    accessToken,
    refreshToken,
    accessTokenHash: await sha256Hex(new TextEncoder().encode(accessToken)),
    refreshTokenHash: await sha256Hex(new TextEncoder().encode(refreshToken)),
    familyID: existingFamilyID ?? crypto.randomUUID(),
    issuedAtSeconds,
    accessExpiresAtSeconds: issuedAtSeconds + ACCESS_TOKEN_TTL_SECONDS,
    refreshExpiresAtSeconds: issuedAtSeconds + REFRESH_TOKEN_TTL_SECONDS,
  };
}

function sessionInsertStatements(
  db: D1Database,
  accountID: string,
  providerSubjectHash: string,
  session: IssuedAppSession,
): D1PreparedStatement[] {
  return [
    db
      .prepare(
        `INSERT INTO auth_sessions (
           token_sha256, account_id, expires_at, kind, session_family_id
         )
         SELECT ?, ?, ?, 'access', ?
         WHERE EXISTS (SELECT 1 FROM accounts WHERE id = ?)
           AND NOT EXISTS (
             SELECT 1 FROM account_deletion_locks WHERE account_id = ?
           )
           AND NOT EXISTS (
             SELECT 1 FROM deleted_identity_tombstones
             WHERE provider = 'apple' AND provider_subject_sha256 = ? AND expires_at > ?
           )`,
      )
      .bind(
        session.accessTokenHash,
        accountID,
        session.accessExpiresAtSeconds,
        session.familyID,
        accountID,
        accountID,
        providerSubjectHash,
        session.issuedAtSeconds,
      ),
    db
      .prepare(
        `INSERT INTO auth_sessions (
           token_sha256, account_id, expires_at, kind, session_family_id
         )
         SELECT ?, ?, ?, 'refresh', ?
         WHERE EXISTS (SELECT 1 FROM accounts WHERE id = ?)
           AND NOT EXISTS (
             SELECT 1 FROM account_deletion_locks WHERE account_id = ?
           )
           AND NOT EXISTS (
             SELECT 1 FROM deleted_identity_tombstones
             WHERE provider = 'apple' AND provider_subject_sha256 = ? AND expires_at > ?
           )`,
      )
      .bind(
        session.refreshTokenHash,
        accountID,
        session.refreshExpiresAtSeconds,
        session.familyID,
        accountID,
        accountID,
        providerSubjectHash,
        session.issuedAtSeconds,
      ),
  ];
}

function sessionResponse(
  accountID: string,
  providerSubject: string,
  displayName: string,
  session: IssuedAppSession,
  requestID: string,
): Response {
  return jsonResponse(
    {
      assurance: "backendVerified",
      canonicalAccountID: accountID,
      providerSubject,
      displayName,
      issuedAt: rfc3339(session.issuedAtSeconds),
      expiresAt: rfc3339(session.accessExpiresAtSeconds),
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    },
    200,
    requestID,
  );
}

async function encryptToken(token: string, accountID: string, key: CryptoKey): Promise<EncryptedToken> {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, additionalData: new TextEncoder().encode(accountID) },
    key,
    new TextEncoder().encode(token),
  );
  return { ciphertext: encodeBase64URL(new Uint8Array(ciphertext)), nonce: encodeBase64URL(nonce) };
}

async function decryptToken(
  ciphertext: string,
  nonce: string,
  accountID: string,
  key: CryptoKey,
): Promise<string> {
  const plaintext = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: decodeBase64URL(nonce, 64),
      additionalData: new TextEncoder().encode(accountID),
    },
    key,
    decodeBase64URL(ciphertext, 32 * 1024),
  );
  return new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(plaintext);
}

function randomOpaqueToken(byteLength: number): string {
  return encodeBase64URL(crypto.getRandomValues(new Uint8Array(byteLength)));
}

function isOpaqueToken(value: string): boolean {
  return value.length >= 32 && value.length <= 16_384 && /^[A-Za-z0-9_-]+$/.test(value);
}

function rfc3339(epochSeconds: number): string {
  return new Date(epochSeconds * 1_000).toISOString().replace(".000Z", "Z");
}

function encodeJWTPart(value: JSONObject): string {
  return encodeBase64URL(new TextEncoder().encode(JSON.stringify(value)));
}

function parseBase64URLJSON(value: string, maximumBytes: number): JSONValue {
  const bytes = decodeBase64URL(value, maximumBytes);
  const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  return JSON.parse(text) as JSONValue;
}

function encodeBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function decodeBase64URL(value: string, maximumBytes: number): Uint8Array {
  if (value.length === 0 || !/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("invalid base64url");
  const padding = (4 - (value.length % 4)) % 4;
  if (value.length % 4 === 1) throw new Error("invalid base64url");
  const binary = atob(value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat(padding));
  if (binary.length > maximumBytes) throw new Error("decoded value too large");
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function decodeClientBase64(value: string, maximumBytes: number): string {
  if (value.length === 0 || value.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) {
    throw invalidAppleRequest();
  }
  let binary: string;
  try {
    binary = atob(value);
  } catch {
    throw invalidAppleRequest();
  }
  if (binary.length === 0 || binary.length > maximumBytes) throw invalidAppleRequest();
  let decoded: string;
  try {
    decoded = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(
      Uint8Array.from(binary, (character) => character.charCodeAt(0)),
    );
  } catch {
    throw invalidAppleRequest();
  }
  if (!isCleanString(decoded, maximumBytes, false)) throw invalidAppleRequest();
  return decoded;
}

function decodePEM(value: string, label: string, maximumBytes: number): Uint8Array {
  const prefix = `-----BEGIN ${label}-----`;
  const suffix = `-----END ${label}-----`;
  if (!value.startsWith(prefix) || !value.endsWith(suffix)) throw new Error("invalid PEM");
  const body = value.slice(prefix.length, -suffix.length).replace(/[\r\n]/g, "");
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(body)) throw new Error("invalid PEM");
  const binary = atob(body);
  if (binary.length === 0 || binary.length > maximumBytes) throw new Error("invalid PEM");
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function isBase64URLOfByteLength(value: string, byteLength: number): boolean {
  try {
    return decodeBase64URL(value, byteLength).byteLength === byteLength;
  } catch {
    return false;
  }
}

function isCleanString(value: string, maximumLength: number, permitsWhitespace: boolean): boolean {
  return value.length > 0
    && value.length <= maximumLength
    && value === value.trim()
    && !/[\u0000-\u001f\u007f]/.test(value)
    && (permitsWhitespace || !/\s/.test(value));
}

async function readBoundedJSON(request: Request, maximumBytes: number): Promise<JSONValue> {
  if (request.body === null) throw new AuthAPIError(400, "invalid_json");
  const declared = request.headers.get("Content-Length");
  if (declared !== null) {
    const length = Number(declared);
    if (!Number.isSafeInteger(length) || length < 0) throw new AuthAPIError(400, "invalid_content_length");
    if (length > maximumBytes) throw new AuthAPIError(413, "payload_too_large");
  }
  const bytes = await readBoundedStream(request.body, maximumBytes);
  try {
    const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
    return JSON.parse(text) as JSONValue;
  } catch {
    throw new AuthAPIError(400, "invalid_json");
  }
}

async function readBoundedResponseJSON(response: Response, maximumBytes: number): Promise<JSONValue> {
  const contentType = response.headers.get("Content-Type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (contentType !== "application/json" || response.body === null) {
    throw new AuthAPIError(503, "apple_unavailable");
  }
  const bytes = await readBoundedStream(response.body, maximumBytes);
  try {
    const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
    return JSON.parse(text) as JSONValue;
  } catch {
    throw new AuthAPIError(503, "apple_unavailable");
  }
}

async function discardBoundedBody(response: Response, maximumBytes: number): Promise<void> {
  if (response.body === null) return;
  try {
    await readBoundedStream(response.body, maximumBytes);
  } catch {
    await response.body.cancel();
  }
}

async function readBoundedStream(stream: ReadableStream<Uint8Array>, maximumBytes: number): Promise<Uint8Array> {
  const reader = stream.getReader();
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
  return bytes;
}

function requireJSONContentType(request: Request): void {
  const contentType = request.headers.get("Content-Type");
  if (contentType?.split(";", 1)[0]?.trim().toLowerCase() !== "application/json") {
    throw new AuthAPIError(415, "unsupported_media_type");
  }
}

function isJSONObject(value: JSONValue | undefined): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: JSONObject, expected: string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === expected.length && actual.every((key) => expected.includes(key));
}

function hasOnlyAllowedKeys(value: JSONObject, allowed: string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function jsonResponse(
  body: JSONValue,
  status: number,
  requestID: string,
  extraHeaders?: HeadersInit,
): Response {
  const headers = new Headers(extraHeaders);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.set("Pragma", "no-cache");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("X-Request-ID", requestID);
  return new Response(JSON.stringify(body), { status, headers });
}

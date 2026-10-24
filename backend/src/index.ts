import {
  AuthAPIError,
  handleAuthRoute,
  isAuthPath,
  responseForAuthError,
} from "./auth";
import { ACCOUNT_DELETION_PATH, handleAccountDeletion } from "./account-deletion";
import { cleanupExpiredRecords } from "./maintenance";
import {
  appleAppSiteAssociationResponse,
  APPLE_APP_SITE_ASSOCIATION_PATH,
  handlePlanetRoute,
  inviteLandingResponse,
  INVITE_LANDING_PATH,
  isPlanetPath,
} from "./planet";

const SNAPSHOT_PATH = "/v1/account/snapshot";
const MAX_REQUEST_BYTES = 1_048_576;
const MAX_TOKEN_LENGTH = 16_384;
const IDEMPOTENCY_TTL_SECONDS = 24 * 60 * 60;
const ACCOUNT_SCHEMA_VERSION = 1;

const SNAPSHOT_KEYS = new Set([
  "schemaVersion",
  "profile",
  "savedGuides",
  "readingHistory",
  "planet",
  "visitStreak",
  "lastVisitDate",
  "dailyGuideRevealDate",
  "tarotDrawDate",
  "wardrobe",
  "starLife",
]);

type JSONObject = { [key: string]: JSONValue };
type JSONValue = null | boolean | number | string | JSONValue[] | JSONObject;

interface SnapshotEnvelope {
  schemaVersion: number;
  baseRevision: number | null;
  snapshot: JSONObject;
}

interface AuthenticatedAccountRow {
  account_id: string;
  deletion_pending: number;
}

interface SnapshotRow {
  schema_version: number;
  revision: number;
  snapshot_json: string | null;
  updated_at: string;
  deleted_at: string | null;
}

interface IdempotencyRow {
  method: "PUT" | "DELETE";
  request_sha256: string;
  response_status: number;
  response_json: string;
}

interface APIErrorBody {
  code: string;
  requestID: string;
  currentRevision?: number;
  updatedAt?: string;
}

class APIError extends Error {
  readonly status: number;
  readonly code: string;
  readonly headers?: HeadersInit;
  readonly metadata?: Pick<APIErrorBody, "currentRevision" | "updatedAt">;

  constructor(
    status: number,
    code: string,
    options?: {
      headers?: HeadersInit;
      metadata?: Pick<APIErrorBody, "currentRevision" | "updatedAt">;
    },
  ) {
    super(code);
    this.name = "APIError";
    this.status = status;
    this.code = code;
    this.headers = options?.headers;
    this.metadata = options?.metadata;
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const requestID = crypto.randomUUID();
    const url = new URL(request.url);
    let response: Response;

    try {
      response = await route(request, url, env, requestID);
    } catch (error) {
      if (error instanceof AuthAPIError) {
        response = responseForAuthError(error, requestID);
      } else if (error instanceof APIError) {
        response = errorResponse(error.status, error.code, requestID, error.headers, error.metadata);
      } else {
        console.error(
          JSON.stringify({
            event: "request_failed",
            requestID,
            method: request.method,
            path: url.pathname,
            errorType: error instanceof Error ? error.name : "UnknownError",
          }),
        );
        response = errorResponse(500, "internal_error", requestID);
      }
    }

    console.log(
      JSON.stringify({
        event: "request_complete",
        requestID,
        method: request.method,
        path: url.pathname,
        status: response.status,
      }),
    );
    return response;
  },
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    await cleanupExpiredRecords(env.DB, Math.floor(Date.now() / 1_000));
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, url: URL, env: Env, requestID: string): Promise<Response> {
  if (isAuthPath(url.pathname)) {
    return handleAuthRoute(request, url, env, requestID);
  }
  if (url.pathname === INVITE_LANDING_PATH) {
    if (url.search !== "") throw new APIError(400, "query_not_allowed");
    if (request.method !== "GET") {
      throw new APIError(405, "method_not_allowed", { headers: { Allow: "GET" } });
    }
    return inviteLandingResponse(requestID);
  }
  if (url.pathname === APPLE_APP_SITE_ASSOCIATION_PATH) {
    if (url.search !== "") throw new APIError(400, "query_not_allowed");
    if (request.method !== "GET") {
      throw new APIError(405, "method_not_allowed", { headers: { Allow: "GET" } });
    }
    return appleAppSiteAssociationResponse(env, requestID);
  }
  if (url.pathname === ACCOUNT_DELETION_PATH) {
    return handleAccountDeletion(request, url, env, requestID);
  }
  if (url.pathname !== SNAPSHOT_PATH && !isPlanetPath(url.pathname)) {
    throw new APIError(404, "route_not_found");
  }
  if (url.search !== "") {
    throw new APIError(400, "query_not_allowed");
  }
  if (
    url.pathname === SNAPSHOT_PATH
    && !(["GET", "PUT", "DELETE"] as const).some((method) => method === request.method)
  ) {
    throw new APIError(405, "method_not_allowed", {
      headers: { Allow: "GET, PUT, DELETE" },
    });
  }

  const accountID = await authenticate(request, env.DB);
  if (isPlanetPath(url.pathname)) {
    return handlePlanetRoute(request, url, env, accountID, requestID);
  }
  if (request.method === "GET") {
    return getSnapshot(env.DB, accountID, requestID);
  }
  if (request.method === "PUT") {
    return putSnapshot(request, env.DB, accountID, requestID);
  }
  return deleteSnapshot(request, env.DB, accountID, requestID);
}

async function authenticate(request: Request, db: D1Database): Promise<string> {
  const authorization = request.headers.get("Authorization");
  const match = authorization?.match(/^Bearer ([^\s\u0000-\u001f\u007f]+)$/i);
  if (!match?.[1] || match[1].length > MAX_TOKEN_LENGTH) {
    throw unauthorized();
  }

  const tokenHash = await sha256Hex(new TextEncoder().encode(match[1]));
  const now = Math.floor(Date.now() / 1_000);
  const row = await db
    .prepare(
      `SELECT a.id AS account_id,
              EXISTS(
                SELECT 1 FROM account_deletion_locks AS d
                WHERE d.account_id = a.id
              ) AS deletion_pending
       FROM auth_sessions AS s
       INNER JOIN accounts AS a ON a.id = s.account_id
       WHERE s.token_sha256 = ?
         AND s.kind = 'access'
         AND s.revoked_at IS NULL
         AND (s.expires_at IS NULL OR s.expires_at > ?)
       LIMIT 1`,
    )
    .bind(tokenHash, now)
    .first<AuthenticatedAccountRow>();

  if (row === null) {
    throw unauthorized();
  }
  if (row.deletion_pending === 1) {
    throw new APIError(409, "account_deletion_pending");
  }
  return row.account_id;
}

function unauthorized(): APIError {
  return new APIError(401, "unauthorized", {
    headers: { "WWW-Authenticate": 'Bearer realm="star-companion"' },
  });
}

async function getSnapshot(db: D1Database, accountID: string, requestID: string): Promise<Response> {
  const row = await readSnapshotRow(db, accountID);
  if (row === null) {
    return errorResponse(404, "snapshot_not_found", requestID);
  }
  if (row.snapshot_json === null || row.deleted_at !== null) {
    return errorResponse(
      404,
      "snapshot_not_found",
      requestID,
      { ETag: quoteETag(row.revision) },
      { currentRevision: row.revision, updatedAt: row.updated_at },
    );
  }

  const snapshot = parseStoredSnapshot(row.snapshot_json);
  return jsonResponse(
    {
      schemaVersion: row.schema_version,
      revision: row.revision,
      updatedAt: row.updated_at,
      snapshot,
    },
    200,
    requestID,
    { ETag: quoteETag(row.revision) },
  );
}

async function putSnapshot(
  request: Request,
  db: D1Database,
  accountID: string,
  requestID: string,
): Promise<Response> {
  requireJSONContentType(request);
  const idempotencyKey = requireIdempotencyKey(request);
  const { bytes, value } = await readBoundedJSON(request);
  const envelope = validateSnapshotEnvelope(value);
  const requestHash = await mutationHash("PUT", bytes);

  const previous = await readIdempotency(db, accountID, idempotencyKey);
  if (previous !== null) {
    return replayIdempotency(previous, "PUT", requestHash, requestID);
  }

  const nowSeconds = Math.floor(Date.now() / 1_000);
  await deleteExpiredIdempotency(db, accountID, nowSeconds);

  const updatedAt = new Date().toISOString();
  const resultingRevision = envelope.baseRevision === null ? 1 : envelope.baseRevision + 1;
  if (!Number.isSafeInteger(resultingRevision)) {
    throw new APIError(422, "invalid_revision");
  }
  const responseStatus = envelope.baseRevision === null ? 201 : 200;
  const responseJSON = JSON.stringify({
    schemaVersion: ACCOUNT_SCHEMA_VERSION,
    revision: resultingRevision,
    updatedAt,
  });
  const snapshotJSON = JSON.stringify(envelope.snapshot);

  const mutationStatement = envelope.baseRevision === null
    ? db
        .prepare(
          `INSERT INTO account_snapshots (
             account_id, schema_version, revision, snapshot_json, updated_at, deleted_at
           )
           SELECT ?, ?, 1, ?, ?, NULL
           WHERE NOT EXISTS (
             SELECT 1 FROM account_deletion_locks WHERE account_id = ?
           )
           ON CONFLICT(account_id) DO NOTHING`,
        )
        .bind(accountID, ACCOUNT_SCHEMA_VERSION, snapshotJSON, updatedAt, accountID)
    : db
        .prepare(
          `UPDATE account_snapshots
           SET schema_version = ?,
               revision = revision + 1,
               snapshot_json = ?,
               updated_at = ?,
               deleted_at = NULL
           WHERE account_id = ? AND revision = ?
             AND NOT EXISTS (
               SELECT 1 FROM account_deletion_locks WHERE account_id = ?
             )`,
        )
        .bind(
          ACCOUNT_SCHEMA_VERSION,
          snapshotJSON,
          updatedAt,
          accountID,
          envelope.baseRevision,
          accountID,
        );

  try {
    const results = await db.batch([
      mutationStatement,
      db
        .prepare(
          `INSERT INTO account_snapshot_mutations (
             account_id, idempotency_key, method, request_sha256,
             response_status, response_json, created_at, expires_at
           )
           SELECT ?, ?, 'PUT', ?, ?, ?, ?, ?
           WHERE changes() = 1`,
        )
        .bind(
          accountID,
          idempotencyKey,
          requestHash,
          responseStatus,
          responseJSON,
          nowSeconds,
          nowSeconds + IDEMPOTENCY_TTL_SECONDS,
        ),
    ]);

    if ((results[0]?.meta.changes ?? 0) === 1) {
      return rawJSONResponse(responseJSON, responseStatus, requestID, {
        ETag: quoteETag(resultingRevision),
      });
    }
  } catch {
    const raced = await readIdempotency(db, accountID, idempotencyKey);
    if (raced !== null) {
      return replayIdempotency(raced, "PUT", requestHash, requestID);
    }
    throw new APIError(503, "storage_unavailable");
  }

  const raced = await readIdempotency(db, accountID, idempotencyKey);
  if (raced !== null) {
    return replayIdempotency(raced, "PUT", requestHash, requestID);
  }
  throw await revisionConflict(db, accountID);
}

async function deleteSnapshot(
  request: Request,
  db: D1Database,
  accountID: string,
  requestID: string,
): Promise<Response> {
  if (request.body !== null) {
    throw new APIError(400, "body_not_allowed");
  }
  const idempotencyKey = requireIdempotencyKey(request);
  const baseRevision = requireIfMatch(request);
  const requestHash = await mutationHash(
    "DELETE",
    new TextEncoder().encode(String(baseRevision)),
  );

  const previous = await readIdempotency(db, accountID, idempotencyKey);
  if (previous !== null) {
    return replayIdempotency(previous, "DELETE", requestHash, requestID);
  }

  const nowSeconds = Math.floor(Date.now() / 1_000);
  await deleteExpiredIdempotency(db, accountID, nowSeconds);
  const updatedAt = new Date().toISOString();
  const resultingRevision = baseRevision + 1;
  if (!Number.isSafeInteger(resultingRevision)) {
    throw new APIError(422, "invalid_revision");
  }
  const responseJSON = JSON.stringify({
    deleted: true,
    revision: resultingRevision,
    updatedAt,
  });

  try {
    const results = await db.batch([
      db
        .prepare(
          `UPDATE account_snapshots
           SET revision = revision + 1,
               snapshot_json = NULL,
               updated_at = ?,
               deleted_at = ?
           WHERE account_id = ? AND revision = ? AND snapshot_json IS NOT NULL
             AND NOT EXISTS (
               SELECT 1 FROM account_deletion_locks WHERE account_id = ?
             )`,
        )
        .bind(updatedAt, updatedAt, accountID, baseRevision, accountID),
      db
        .prepare(
          `INSERT INTO account_snapshot_mutations (
             account_id, idempotency_key, method, request_sha256,
             response_status, response_json, created_at, expires_at
           )
           SELECT ?, ?, 'DELETE', ?, 200, ?, ?, ?
           WHERE changes() = 1`,
        )
        .bind(
          accountID,
          idempotencyKey,
          requestHash,
          responseJSON,
          nowSeconds,
          nowSeconds + IDEMPOTENCY_TTL_SECONDS,
        ),
    ]);

    if ((results[0]?.meta.changes ?? 0) === 1) {
      return rawJSONResponse(responseJSON, 200, requestID, {
        ETag: quoteETag(resultingRevision),
      });
    }
  } catch {
    const raced = await readIdempotency(db, accountID, idempotencyKey);
    if (raced !== null) {
      return replayIdempotency(raced, "DELETE", requestHash, requestID);
    }
    throw new APIError(503, "storage_unavailable");
  }

  const raced = await readIdempotency(db, accountID, idempotencyKey);
  if (raced !== null) {
    return replayIdempotency(raced, "DELETE", requestHash, requestID);
  }
  throw await revisionConflict(db, accountID);
}

async function readSnapshotRow(db: D1Database, accountID: string): Promise<SnapshotRow | null> {
  return db
    .prepare(
      `SELECT schema_version, revision, snapshot_json, updated_at, deleted_at
       FROM account_snapshots
       WHERE account_id = ?
       LIMIT 1`,
    )
    .bind(accountID)
    .first<SnapshotRow>();
}

async function readIdempotency(
  db: D1Database,
  accountID: string,
  idempotencyKey: string,
): Promise<IdempotencyRow | null> {
  const now = Math.floor(Date.now() / 1_000);
  return db
    .prepare(
      `SELECT method, request_sha256, response_status, response_json
       FROM account_snapshot_mutations
       WHERE account_id = ? AND idempotency_key = ? AND expires_at > ?
       LIMIT 1`,
    )
    .bind(accountID, idempotencyKey, now)
    .first<IdempotencyRow>();
}

async function deleteExpiredIdempotency(
  db: D1Database,
  accountID: string,
  now: number,
): Promise<void> {
  await db
    .prepare(
      `DELETE FROM account_snapshot_mutations
       WHERE account_id = ? AND expires_at <= ?`,
    )
    .bind(accountID, now)
    .run();
}

function replayIdempotency(
  row: IdempotencyRow,
  method: "PUT" | "DELETE",
  requestHash: string,
  requestID: string,
): Response {
  if (row.method !== method || row.request_sha256 !== requestHash) {
    throw new APIError(409, "idempotency_key_reused");
  }
  return rawJSONResponse(row.response_json, row.response_status, requestID);
}

async function revisionConflict(db: D1Database, accountID: string): Promise<APIError> {
  const pending = await db
    .prepare("SELECT 1 AS pending FROM account_deletion_locks WHERE account_id = ? LIMIT 1")
    .bind(accountID)
    .first<{ pending: number }>();
  if (pending !== null) return new APIError(409, "account_deletion_pending");
  const current = await readSnapshotRow(db, accountID);
  return new APIError(409, "snapshot_conflict", {
    metadata: current === null
      ? undefined
      : { currentRevision: current.revision, updatedAt: current.updated_at },
  });
}

function requireJSONContentType(request: Request): void {
  const contentType = request.headers.get("Content-Type");
  if (contentType?.split(";", 1)[0]?.trim().toLowerCase() !== "application/json") {
    throw new APIError(415, "unsupported_media_type");
  }
}

function requireIdempotencyKey(request: Request): string {
  const key = request.headers.get("Idempotency-Key");
  if (key === null || !/^[A-Za-z0-9._:-]{1,128}$/.test(key)) {
    throw new APIError(400, "invalid_idempotency_key");
  }
  return key;
}

function requireIfMatch(request: Request): number {
  const header = request.headers.get("If-Match");
  if (header === null) {
    throw new APIError(428, "precondition_required");
  }
  const match = header.match(/^"([1-9][0-9]*)"$/);
  const revision = match?.[1] === undefined ? Number.NaN : Number(match[1]);
  if (!Number.isSafeInteger(revision) || revision < 1) {
    throw new APIError(400, "invalid_if_match");
  }
  return revision;
}

async function readBoundedJSON(request: Request): Promise<{ bytes: Uint8Array; value: JSONValue }> {
  const contentLength = request.headers.get("Content-Length");
  if (contentLength !== null) {
    const declaredLength = Number(contentLength);
    if (!Number.isSafeInteger(declaredLength) || declaredLength < 0) {
      throw new APIError(400, "invalid_content_length");
    }
    if (declaredLength > MAX_REQUEST_BYTES) {
      throw new APIError(413, "payload_too_large");
    }
  }
  if (request.body === null) {
    throw new APIError(400, "invalid_json");
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) break;
    total += next.value.byteLength;
    if (total > MAX_REQUEST_BYTES) {
      await reader.cancel();
      throw new APIError(413, "payload_too_large");
    }
    chunks.push(next.value);
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch {
    throw new APIError(400, "invalid_json");
  }
  try {
    return { bytes, value: JSON.parse(text) as JSONValue };
  } catch {
    throw new APIError(400, "invalid_json");
  }
}

function validateSnapshotEnvelope(value: JSONValue): SnapshotEnvelope {
  if (!isJSONObject(value) || !hasExactKeys(value, ["schemaVersion", "baseRevision", "snapshot"])) {
    throw new APIError(422, "invalid_snapshot_envelope");
  }
  const schemaVersion = value["schemaVersion"];
  const baseRevision = value["baseRevision"];
  const snapshot = value["snapshot"];
  if (schemaVersion !== ACCOUNT_SCHEMA_VERSION) {
    throw new APIError(422, "unsupported_schema_version");
  }
  if (
    baseRevision !== null
    && (typeof baseRevision !== "number" || !Number.isSafeInteger(baseRevision) || baseRevision < 1)
  ) {
    throw new APIError(422, "invalid_revision");
  }
  if (!isJSONObject(snapshot) || !validateAccountSnapshot(snapshot)) {
    throw new APIError(422, "invalid_snapshot");
  }
  return {
    schemaVersion,
    baseRevision,
    snapshot,
  };
}

function validateAccountSnapshot(snapshot: JSONObject): boolean {
  if (!hasExactKeys(snapshot, [...SNAPSHOT_KEYS])) return false;
  const profile = snapshot["profile"];
  const visitStreak = snapshot["visitStreak"];
  if (snapshot["schemaVersion"] !== ACCOUNT_SCHEMA_VERSION) return false;
  if (profile !== null && !isJSONObject(profile)) return false;
  if (!Array.isArray(snapshot["savedGuides"]) || !Array.isArray(snapshot["readingHistory"])) return false;
  if (
    !isJSONObject(snapshot["planet"])
    || !isJSONObject(snapshot["wardrobe"])
    || !isJSONObject(snapshot["starLife"])
  ) {
    return false;
  }
  if (typeof visitStreak !== "number" || !Number.isSafeInteger(visitStreak) || visitStreak < 0) return false;
  if (!isNullableShortString(snapshot["lastVisitDate"])) return false;
  if (!isNullableShortString(snapshot["dailyGuideRevealDate"])) return false;
  if (!isNullableShortString(snapshot["tarotDrawDate"])) return false;
  return hasSafeJSONShape(snapshot);
}

function hasSafeJSONShape(root: JSONValue): boolean {
  const pending: Array<{ value: JSONValue; depth: number }> = [{ value: root, depth: 0 }];
  let nodes = 0;
  while (pending.length > 0) {
    const current = pending.pop();
    if (current === undefined) break;
    nodes += 1;
    if (nodes > 100_000 || current.depth > 64) return false;
    if (typeof current.value === "number" && !Number.isFinite(current.value)) return false;
    if (typeof current.value === "string" && current.value.length > 65_536) return false;
    if (Array.isArray(current.value)) {
      for (const child of current.value) pending.push({ value: child, depth: current.depth + 1 });
    } else if (isJSONObject(current.value)) {
      for (const [key, child] of Object.entries(current.value)) {
        if (key.length === 0 || key.length > 256) return false;
        pending.push({ value: child, depth: current.depth + 1 });
      }
    }
  }
  return true;
}

function isJSONObject(value: JSONValue | undefined): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: JSONObject, expected: string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === expected.length && actual.every((key) => expected.includes(key));
}

function isNullableShortString(value: JSONValue | undefined): value is string | null {
  return value === null || (typeof value === "string" && value.length <= 64);
}

function parseStoredSnapshot(raw: string): JSONObject {
  try {
    const value = JSON.parse(raw) as JSONValue;
    if (isJSONObject(value) && validateAccountSnapshot(value)) return value;
  } catch {
    // Stored corruption is deliberately mapped to an opaque server failure.
  }
  throw new APIError(500, "stored_snapshot_invalid");
}

async function mutationHash(method: "PUT" | "DELETE", bytes: Uint8Array): Promise<string> {
  const prefix = new TextEncoder().encode(`${method}\n`);
  const input = new Uint8Array(prefix.byteLength + bytes.byteLength);
  input.set(prefix, 0);
  input.set(bytes, prefix.byteLength);
  return sha256Hex(input);
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function quoteETag(revision: number): string {
  return `"${revision}"`;
}

function rawJSONResponse(
  body: string,
  status: number,
  requestID: string,
  headers?: HeadersInit,
): Response {
  return new Response(body, {
    status,
    headers: responseHeaders(requestID, headers),
  });
}

function jsonResponse(
  body: JSONValue,
  status: number,
  requestID: string,
  headers?: HeadersInit,
): Response {
  return rawJSONResponse(JSON.stringify(body), status, requestID, headers);
}

function errorResponse(
  status: number,
  code: string,
  requestID: string,
  headers?: HeadersInit,
  metadata?: Pick<APIErrorBody, "currentRevision" | "updatedAt">,
): Response {
  return jsonResponse({ code, requestID, ...metadata }, status, requestID, headers);
}

function responseHeaders(requestID: string, extra?: HeadersInit): Headers {
  const headers = new Headers(extra);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.set("Pragma", "no-cache");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("X-Request-ID", requestID);
  return headers;
}

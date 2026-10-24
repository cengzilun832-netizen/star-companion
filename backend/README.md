# Star Companion account and Apple sign-in API

Cloudflare Worker + D1 implementation for Sign in with Apple, account-bound
whole-document snapshot sync, account deletion, and the two-person shared
planet/invite flow. The iOS client keeps an account-scoped offline cache; D1 is
the cross-device source of truth.

## Security contract

- Clients send only `Authorization: Bearer <access token>`. The Worker hashes the
  opaque token with SHA-256 and resolves `auth_sessions.account_id` server-side.
- App refresh tokens are one-time rotating credentials. They cannot be used as
  Bearer tokens against the snapshot endpoint.
- No endpoint accepts a client-supplied account or canonical account ID. Account
  IDs are opaque random identifiers; the Apple subject-to-account mapping stays
  server-side. A deleted Apple identity receives a new account ID if it registers
  again after the short deletion tombstone expires.
- Apple identity JWTs are verified with Apple's RS256 JWK using the signed
  issuer, audience, expiry, issued-at time and SHA-256 nonce. The request's
  `providerSubject` is never used as the identity source.
- The one-time Apple authorization code must also pass Apple's `/auth/token`
  endpoint. The returned identity token is verified again and must resolve to
  the same signed subject and nonce. Missing Apple configuration fails closed.
- App access and refresh credentials are stored only as SHA-256 hashes. Apple's
  long-lived refresh token is encrypted with AES-256-GCM and account-bound
  authenticated data before it is stored in D1.
- Plain tokens, authorization codes, identity JWTs, snapshot bodies and account
  IDs are never written to Worker logs.
- Request JSON is bounded to 1 MiB and validated against the exact v1 envelope and
  `AccountLocalData` top-level keys.
- Mutations use whole-document revision compare-and-swap. D1 `batch()` atomically
  couples a successful mutation with its 24-hour idempotency record.
- DELETE leaves a revisioned tombstone so an offline device cannot recreate
  deleted data as a new revision-zero document.

## HTTP API

All responses are JSON with `Cache-Control: no-store` and `X-Request-ID`.

### `POST /v1/auth/apple/exchange`

Accepts the existing iOS wire format. `identityToken` and `authorizationCode`
are standard Base64 wrappers around the bytes returned by AuthenticationServices.
`displayName` may be omitted; unknown fields are rejected.

```json
{
  "providerSubject": "client value checked only against the signed sub",
  "displayName": "Ollie",
  "identityToken": "base64(jwt bytes)",
  "authorizationCode": "base64(code bytes)",
  "nonce": "the 32-byte raw base64url nonce",
  "state": "the 24-byte base64url state"
}
```

A successful exchange returns the exact flat session expected by iOS:

```json
{
  "assurance": "backendVerified",
  "canonicalAccountID": "acc_<opaque random identifier>",
  "providerSubject": "signed Apple sub",
  "displayName": "Ollie",
  "issuedAt": "2026-09-02T12:34:56Z",
  "expiresAt": "2026-09-02T13:34:56Z",
  "accessToken": "opaque app token",
  "refreshToken": "opaque rotating app refresh token"
}
```

The app access token lasts one hour. The app refresh token lasts 30 days.

### `POST /v1/auth/session/refresh`

Accepts the exact body `{ "refreshToken": "opaque token" }`. Before rotating
the app session, the Worker decrypts the stored Apple refresh token, validates it
with Apple, verifies the new Apple identity token and checks that its signed
subject still matches the account. A used refresh token is revoked and cannot be
replayed. The success response is the same flat session schema shown above.

Main auth errors are `invalid_apple_credential` or `unauthorized` (`401`),
`rate_limited` (`429` with `Retry-After`), and `auth_not_configured`,
`apple_unavailable`, `credential_unavailable` or `storage_unavailable` (`503`).

### `GET /v1/account/snapshot`

Returns `200` with `{ schemaVersion, revision, updatedAt, snapshot }`. A missing
or deleted snapshot returns `404 snapshot_not_found`; a tombstone also returns its
current revision so a newer authorized client can deliberately recreate it.

### `PUT /v1/account/snapshot`

Requires `Content-Type: application/json` and `Idempotency-Key`.

```json
{
  "schemaVersion": 1,
  "baseRevision": null,
  "snapshot": {
    "schemaVersion": 1,
    "profile": null,
    "savedGuides": [],
    "readingHistory": [],
    "planet": {},
    "visitStreak": 0,
    "lastVisitDate": null,
    "dailyGuideRevealDate": null,
    "tarotDrawDate": null,
    "wardrobe": {},
    "starLife": {}
  }
}
```

Use `baseRevision: null` only for the first write. Later writes send the revision
returned by GET/PUT. A stale revision returns `409 snapshot_conflict`.

### `DELETE /v1/account/snapshot`

Requires `Idempotency-Key` and `If-Match: "<current revision>"`. A successful
delete increments the revision and returns `{ deleted, revision, updatedAt }`.

### `DELETE /v1/account`

Permanently deletes the signed-in account. It requires a valid access Bearer,
`Content-Type: application/json`, a UUID `Idempotency-Key`, and the exact body:

```json
{ "confirmation": "DELETE" }
```

Before deleting D1 data, the Worker revokes the encrypted Apple refresh token
with Apple's `/auth/revoke`. If Apple cannot confirm revocation, it returns
`503 apple_revoke_failed` with `retryable: true` and keeps the account data. The
deletion lock blocks refresh, sign-in, snapshot writes, and planet writes while
the request is pending. Retrying the same Bearer and idempotency key is allowed
even if that access token has since expired. Success is `{ "deleted": true }`.

A hash-only success receipt is retained so the same request can always recover a
lost success response after the account and session have gone. It contains no
account ID, Apple identity, or plaintext credential; only the access-token hash,
idempotency-key hash, canonical request hash, fixed success response, and creation
time. A hashed Apple-identity tombstone blocks immediate re-registration for 10
minutes. A scheduled Worker job removes expired tombstones and other TTL records
every 15 minutes; authentication traffic also removes expired identity tombstones.

### Shared planet and invitations

All `/v1/planet` routes require a valid access Bearer. D1 memberships are the
server-owned source of truth; a planet holds at most two accounts.

- `GET /v1/planet` returns `{ "planet": null }` when the account has no planet,
  otherwise the planet and its members. Member output includes only `accountID`,
  display `name`, selected `personaID` when present, and join metadata.
- `POST /v1/planet/invites` accepts
  `{ "relationship": "friend" | "bestie" | "couple" }`. It creates or reuses
  the caller's matching planet and returns `{ invite, planet }` with `201`.
  Creating a replacement atomically revokes that caller's older unused active
  invitation for the same planet.
- `POST /v1/planet/invites/accept` accepts `{ "code": "SC-..." }`. Codes are
  128-bit random values, expire after seven days, are stored only as SHA-256
  hashes, and are single-use. Input is case-insensitive and may omit hyphens.
  Retrying the same account/code is idempotent; a replay by another account is
  rejected.
- `DELETE /v1/planet/invites` accepts `{ "code": "SC-..." }` and revokes the
  caller's unused invitation.
- `DELETE /v1/planet/membership` leaves the current planet. The other member's
  account and data remain intact; an empty planet is removed.

Invite creation is limited to 10 attempts and acceptance to 20 attempts per
account per 10-minute window. `/invite#code=...` is a no-store landing page that
reads the code only from the URL fragment and offers
`starcompanion://invite?code=...`; the fragment is not sent in the HTTP request.

`GET /.well-known/apple-app-site-association` exposes `/invite` only when valid
`APPLE_TEAM_ID` and `APPLE_CLIENT_ID` settings exist. Otherwise it fails closed
with `503 associated_domains_not_configured`. Universal Links additionally need
the real App ID capability and Associated Domains entitlement on Apple's side.

## Local verification

```sh
npm install
npm run typecheck
npm test
npm run check:deploy
```

Tests run inside the Workers runtime using Cloudflare's current Vitest plugin and
apply the real D1 migrations before execution.

The Worker includes a 15-minute cron cleanup for expired identity tombstones,
rate-limit buckets, unused invitations, and snapshot-mutation idempotency rows.
Permanent anonymous account-deletion success receipts are intentionally excluded.

## Production deployment

- Worker: `https://star-companion-account-api.cloudocrworker.workers.dev`
- D1: `star-companion-production`, APAC location hint
- Migrations `0001`, `0002`, and `0003_account_deletion_and_planets.sql`: applied
- Account deletion, shared-planet routes, localized invitation landing page, and
  15-minute retention cleanup: deployed on 2026-09-07
- Current deployed version: `c4340f61-7ea2-4315-843d-48c644e8e830`
- Verification: 32 Worker tests, TypeScript, and deployment dry-run passed.
  Direct HTTPS smoke tests from the development network failed during TLS
  connection establishment (`SSL_ERROR_SYSCALL`); public reachability and real
  two-account Apple verification are not yet signed off.
- Snapshot API: deployed and responding
- Apple auth and rotating-session routes: deployed, fail-closed until secrets are installed

The deployed Worker checks all six Apple settings before it reads an auth body,
contacts Apple or writes auth data. Until the real values are installed, Apple
auth returns `503 auth_not_configured`; snapshot sync remains available to
existing backend-verified sessions. Local preview sessions are never accepted
or uploaded.

## Provisioning and redeployment

1. Replace the placeholder iOS bundle identifier with the production App ID and
   enable Sign in with Apple for it in Certificates, Identifiers & Profiles.
2. Create a Sign in with Apple key and note the Apple Team ID and Key ID. Keep the
   downloaded `.p8` file outside this repository.
3. Set the required Worker secrets. `APPLE_CLIENT_ID` must exactly match the
   production App ID used as the identity token audience.

   ```sh
   npx wrangler secret put APPLE_CLIENT_ID
   npx wrangler secret put APPLE_TEAM_ID
   npx wrangler secret put APPLE_KEY_ID
   npx wrangler secret put APPLE_PRIVATE_KEY < /secure/path/AuthKey_KEYID.p8
   openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n' | npx wrangler secret put APPLE_REFRESH_TOKEN_ENCRYPTION_KEY
   openssl rand -base64 48 | tr -d '\n' | npx wrangler secret put AUTH_RATE_LIMIT_SALT
   ```

4. For a fresh environment, apply D1 migrations before deploying code that uses
   them. The account-deletion and shared-planet routes require migration `0003`.
   Production currently has only migrations `0001` and `0002`, so review the
   migration and create a D1 backup before applying it:

   ```sh
   npx wrangler d1 migrations apply star-companion-production --remote
   ```

5. Run `npm run typecheck`, `npm test`, and `npm run check:deploy`. Then deploy
   with `npx wrangler deploy` only after reviewing the production identifiers,
   privacy policy, retention and account-deletion procedure.

The binding names are declared as optional TypeScript bindings so the snapshot
API can stay online while Apple setup is incomplete. Runtime validation still
requires all six values together and fails closed when any value is absent; no
secret values belong in `wrangler.jsonc`. The private key loader accepts the
normal trailing newline in an Apple `.p8` file. Apple's public JWK set is cached
for one hour and force-refetched when a token presents an unknown `kid`. Auth
attempts are limited to 10 per source-IP hash per 10-minute window; the IP is
salted before storage and expired buckets are removed during auth traffic.

## Remaining production work

- Register and process Apple's server-to-server account-change notifications.
- Decide the Apple refresh-token validation schedule for dormant accounts. The
  app refresh endpoint validates Apple on every use; no background job exists.
- Define an operations recovery procedure for deletion requests that cannot
  decrypt or revoke their Apple credential. The API intentionally leaves those
  accounts locked and retryable instead of deleting before Apple revocation.
- Consider requiring a fresh Sign in with Apple authorization immediately before
  this destructive operation. The current API uses a valid one-hour app access
  session plus the explicit confirmation body and idempotency key.
- Invitation creation does not accept an idempotency key. A client retry after a
  lost response creates a replacement and invalidates that caller's previous
  unused code, so the UI must tell the user that only the newest code works.

The backend intentionally does not implement phone OTP. A real SMS provider,
abuse controls and an explicit account-linking policy are required before those
endpoints can become production auth issuers.

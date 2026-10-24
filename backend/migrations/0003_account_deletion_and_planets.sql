PRAGMA foreign_keys = ON;

CREATE TABLE account_deletion_locks (
    account_id TEXT PRIMARY KEY NOT NULL
        REFERENCES accounts(id) ON DELETE CASCADE,
    access_token_sha256 TEXT NOT NULL
        CHECK (length(access_token_sha256) = 64 AND access_token_sha256 NOT GLOB '*[^0-9a-f]*'),
    idempotency_key_sha256 TEXT NOT NULL
        CHECK (length(idempotency_key_sha256) = 64 AND idempotency_key_sha256 NOT GLOB '*[^0-9a-f]*'),
    request_sha256 TEXT NOT NULL
        CHECK (length(request_sha256) = 64 AND request_sha256 NOT GLOB '*[^0-9a-f]*'),
    created_at INTEGER NOT NULL CHECK (created_at > 0),
    updated_at INTEGER NOT NULL CHECK (updated_at >= created_at),
    retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    UNIQUE (access_token_sha256, idempotency_key_sha256)
) STRICT;

CREATE TABLE account_deletion_receipts (
    access_token_sha256 TEXT NOT NULL
        CHECK (length(access_token_sha256) = 64 AND access_token_sha256 NOT GLOB '*[^0-9a-f]*'),
    idempotency_key_sha256 TEXT NOT NULL
        CHECK (length(idempotency_key_sha256) = 64 AND idempotency_key_sha256 NOT GLOB '*[^0-9a-f]*'),
    request_sha256 TEXT NOT NULL
        CHECK (length(request_sha256) = 64 AND request_sha256 NOT GLOB '*[^0-9a-f]*'),
    response_json TEXT NOT NULL CHECK (json_valid(response_json)),
    created_at INTEGER NOT NULL CHECK (created_at > 0),
    PRIMARY KEY (access_token_sha256, idempotency_key_sha256)
) STRICT, WITHOUT ROWID;

CREATE TABLE deleted_identity_tombstones (
    provider TEXT NOT NULL CHECK (provider = 'apple'),
    provider_subject_sha256 TEXT NOT NULL
        CHECK (length(provider_subject_sha256) = 64 AND provider_subject_sha256 NOT GLOB '*[^0-9a-f]*'),
    created_at INTEGER NOT NULL CHECK (created_at > 0),
    expires_at INTEGER NOT NULL CHECK (expires_at > created_at),
    PRIMARY KEY (provider, provider_subject_sha256)
) STRICT, WITHOUT ROWID;

CREATE INDEX deleted_identity_tombstones_expiry_idx
    ON deleted_identity_tombstones(expires_at);

CREATE TABLE planets (
    id TEXT PRIMARY KEY NOT NULL CHECK (length(id) BETWEEN 20 AND 128),
    relationship TEXT NOT NULL CHECK (relationship IN ('friend', 'bestie', 'couple')),
    created_at INTEGER NOT NULL CHECK (created_at > 0),
    updated_at INTEGER NOT NULL CHECK (updated_at >= created_at)
) STRICT;

CREATE TABLE planet_memberships (
    account_id TEXT PRIMARY KEY NOT NULL
        REFERENCES accounts(id) ON DELETE CASCADE,
    planet_id TEXT NOT NULL
        REFERENCES planets(id) ON DELETE CASCADE,
    slot INTEGER NOT NULL CHECK (slot IN (0, 1)),
    joined_at INTEGER NOT NULL CHECK (joined_at > 0),
    UNIQUE (planet_id, account_id),
    UNIQUE (planet_id, slot)
) STRICT;

CREATE INDEX planet_memberships_planet_idx
    ON planet_memberships(planet_id, joined_at);

CREATE TABLE planet_invites (
    code_sha256 TEXT PRIMARY KEY NOT NULL
        CHECK (length(code_sha256) = 64 AND code_sha256 NOT GLOB '*[^0-9a-f]*'),
    planet_id TEXT NOT NULL REFERENCES planets(id) ON DELETE CASCADE,
    created_by_account_id TEXT NOT NULL,
    created_at INTEGER NOT NULL CHECK (created_at > 0),
    expires_at INTEGER NOT NULL CHECK (expires_at > created_at),
    used_at INTEGER,
    used_by_account_id TEXT,
    revoked_at INTEGER,
    CHECK (
        (used_at IS NULL AND used_by_account_id IS NULL)
        OR (used_at IS NOT NULL AND used_by_account_id IS NOT NULL)
    ),
    CHECK (used_at IS NULL OR used_at >= created_at),
    CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CHECK (used_at IS NULL OR revoked_at IS NULL),
    FOREIGN KEY (planet_id, created_by_account_id)
        REFERENCES planet_memberships(planet_id, account_id) ON DELETE CASCADE,
    FOREIGN KEY (planet_id, used_by_account_id)
        REFERENCES planet_memberships(planet_id, account_id) ON DELETE CASCADE
) STRICT;

CREATE INDEX planet_invites_creator_idx
    ON planet_invites(created_by_account_id, created_at);
CREATE INDEX planet_invites_expiry_idx
    ON planet_invites(expires_at)
    WHERE used_at IS NULL AND revoked_at IS NULL;

CREATE TABLE planet_rate_limits (
    bucket_sha256 TEXT NOT NULL
        CHECK (length(bucket_sha256) = 64 AND bucket_sha256 NOT GLOB '*[^0-9a-f]*'),
    action TEXT NOT NULL CHECK (action IN ('create', 'accept')),
    window_start INTEGER NOT NULL CHECK (window_start > 0),
    attempts INTEGER NOT NULL CHECK (attempts > 0),
    expires_at INTEGER NOT NULL CHECK (expires_at > window_start),
    PRIMARY KEY (bucket_sha256, action, window_start)
) STRICT, WITHOUT ROWID;

CREATE INDEX planet_rate_limits_expiry_idx
    ON planet_rate_limits(expires_at);

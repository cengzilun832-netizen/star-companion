PRAGMA foreign_keys = ON;

CREATE TABLE accounts (
    id TEXT PRIMARY KEY NOT NULL
        CHECK (length(id) BETWEEN 1 AND 256),
    created_at TEXT NOT NULL
        DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE TABLE auth_sessions (
    token_sha256 TEXT PRIMARY KEY NOT NULL
        CHECK (
            length(token_sha256) = 64
            AND token_sha256 NOT GLOB '*[^0-9a-f]*'
        ),
    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    expires_at INTEGER,
    revoked_at INTEGER,
    created_at TEXT NOT NULL
        DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CHECK (expires_at IS NULL OR expires_at > 0),
    CHECK (revoked_at IS NULL OR revoked_at > 0)
) STRICT;

CREATE INDEX auth_sessions_account_id_idx ON auth_sessions(account_id);
CREATE INDEX auth_sessions_expiry_idx ON auth_sessions(expires_at)
    WHERE expires_at IS NOT NULL AND revoked_at IS NULL;

CREATE TABLE account_snapshots (
    account_id TEXT PRIMARY KEY NOT NULL
        REFERENCES accounts(id) ON DELETE CASCADE,
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    revision INTEGER NOT NULL CHECK (revision >= 1),
    snapshot_json TEXT,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    CHECK (snapshot_json IS NULL OR (json_valid(snapshot_json) AND json_type(snapshot_json) = 'object')),
    CHECK (
        (snapshot_json IS NOT NULL AND deleted_at IS NULL)
        OR (snapshot_json IS NULL AND deleted_at IS NOT NULL)
    )
) STRICT;

CREATE TABLE account_snapshot_mutations (
    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
    method TEXT NOT NULL CHECK (method IN ('PUT', 'DELETE')),
    request_sha256 TEXT NOT NULL
        CHECK (
            length(request_sha256) = 64
            AND request_sha256 NOT GLOB '*[^0-9a-f]*'
        ),
    response_status INTEGER NOT NULL CHECK (response_status BETWEEN 200 AND 299),
    response_json TEXT NOT NULL CHECK (json_valid(response_json)),
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL CHECK (expires_at > created_at),
    PRIMARY KEY (account_id, idempotency_key)
) STRICT, WITHOUT ROWID;

CREATE INDEX account_snapshot_mutations_expiry_idx
    ON account_snapshot_mutations(expires_at);

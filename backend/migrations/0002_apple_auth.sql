PRAGMA foreign_keys = ON;

ALTER TABLE auth_sessions ADD COLUMN kind TEXT NOT NULL DEFAULT 'access'
    CHECK (kind IN ('access', 'refresh'));
ALTER TABLE auth_sessions ADD COLUMN session_family_id TEXT
    CHECK (session_family_id IS NULL OR length(session_family_id) BETWEEN 1 AND 128);

CREATE INDEX auth_sessions_kind_expiry_idx
    ON auth_sessions(kind, expires_at)
    WHERE revoked_at IS NULL;
CREATE INDEX auth_sessions_family_idx
    ON auth_sessions(session_family_id)
    WHERE session_family_id IS NOT NULL;

CREATE TABLE account_identities (
    provider TEXT NOT NULL CHECK (provider IN ('apple')),
    provider_subject TEXT NOT NULL CHECK (length(provider_subject) BETWEEN 1 AND 512),
    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    display_name TEXT CHECK (display_name IS NULL OR length(display_name) BETWEEN 1 AND 160),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    PRIMARY KEY (provider, provider_subject),
    UNIQUE (provider, account_id),
    UNIQUE (provider, provider_subject, account_id)
) STRICT, WITHOUT ROWID;

CREATE INDEX account_identities_account_idx ON account_identities(account_id);

CREATE TABLE apple_credentials (
    account_id TEXT PRIMARY KEY NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'apple' CHECK (provider = 'apple'),
    provider_subject TEXT NOT NULL CHECK (length(provider_subject) BETWEEN 1 AND 512),
    refresh_token_ciphertext TEXT NOT NULL
        CHECK (length(refresh_token_ciphertext) BETWEEN 16 AND 32768),
    refresh_token_nonce TEXT NOT NULL
        CHECK (length(refresh_token_nonce) BETWEEN 16 AND 32),
    refresh_token_key_version INTEGER NOT NULL CHECK (refresh_token_key_version >= 1),
    apple_access_expires_at INTEGER NOT NULL CHECK (apple_access_expires_at > 0),
    last_validated_at INTEGER NOT NULL CHECK (last_validated_at > 0),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    FOREIGN KEY (provider, provider_subject, account_id)
        REFERENCES account_identities(provider, provider_subject, account_id) ON DELETE CASCADE
) STRICT;

CREATE TABLE auth_rate_limits (
    bucket_sha256 TEXT NOT NULL
        CHECK (length(bucket_sha256) = 64 AND bucket_sha256 NOT GLOB '*[^0-9a-f]*'),
    window_start INTEGER NOT NULL CHECK (window_start > 0),
    attempts INTEGER NOT NULL CHECK (attempts > 0),
    expires_at INTEGER NOT NULL CHECK (expires_at > window_start),
    PRIMARY KEY (bucket_sha256, window_start)
) STRICT, WITHOUT ROWID;

CREATE INDEX auth_rate_limits_expiry_idx ON auth_rate_limits(expires_at);

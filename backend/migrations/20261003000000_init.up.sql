-- Fase 0: usuários, sessões e convites.
-- IDs são UUID v7 gerados pela aplicação.

CREATE TABLE users (
    id            UUID PRIMARY KEY,
    username      TEXT NOT NULL,
    email         TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    invited_by    UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT users_username_format CHECK (username ~ '^[a-z0-9_]{3,30}$'),
    CONSTRAINT users_email_lowercase CHECK (email = lower(email)),
    CONSTRAINT users_email_length    CHECK (char_length(email) BETWEEN 3 AND 254)
);

CREATE UNIQUE INDEX users_username_key ON users (username);
CREATE UNIQUE INDEX users_email_key    ON users (email);

CREATE TABLE sessions (
    id          UUID PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- SHA-256 do token; o token em claro nunca é armazenado.
    token_hash  BYTEA NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT sessions_token_hash_len CHECK (octet_length(token_hash) = 32)
);

CREATE UNIQUE INDEX sessions_token_hash_key ON sessions (token_hash);
CREATE INDEX sessions_user_id_idx ON sessions (user_id);

CREATE TABLE invites (
    id          UUID PRIMARY KEY,
    -- SHA-256 do código de convite.
    code_hash   BYTEA NOT NULL,
    -- NULL = criado pelo administrador via CLI.
    created_by  UUID REFERENCES users (id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL,
    used_by     UUID REFERENCES users (id) ON DELETE SET NULL,
    used_at     TIMESTAMPTZ,

    CONSTRAINT invites_code_hash_len CHECK (octet_length(code_hash) = 32)
);

CREATE UNIQUE INDEX invites_code_hash_key ON invites (code_hash);
CREATE INDEX invites_created_by_idx ON invites (created_by) WHERE used_at IS NULL;

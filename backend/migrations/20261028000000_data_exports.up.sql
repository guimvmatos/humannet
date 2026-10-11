-- Links de uso único para "Baixar meus dados" (10 minutos).
CREATE TABLE data_exports (
    token_hash BYTEA PRIMARY KEY CHECK (octet_length(token_hash) = 32),
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX data_exports_user_idx ON data_exports (user_id);
CREATE INDEX likes_user_idx ON likes (user_id, created_at DESC);

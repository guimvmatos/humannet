-- Beta lote 2: papéis, suspensão, redefinição de senha assistida, log de moderação.

ALTER TABLE users
    ADD COLUMN role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    ADD COLUMN suspended_at TIMESTAMPTZ;

-- Código de redefinição gerado por um administrador (sem e-mail no beta).
CREATE TABLE password_resets (
    user_id    UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    code_hash  BYTEA NOT NULL CHECK (octet_length(code_hash) = 32),
    created_by UUID REFERENCES users (id) ON DELETE SET NULL,
    attempts   INT NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ NOT NULL
);

-- Toda ação de moderação fica registrada (quem, o quê, quando).
CREATE TABLE moderation_actions (
    id          UUID PRIMARY KEY,
    admin_id    UUID REFERENCES users (id) ON DELETE SET NULL,
    action      TEXT NOT NULL,
    target_kind TEXT NOT NULL,
    target_id   UUID NOT NULL,
    report_id   UUID REFERENCES reports (id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

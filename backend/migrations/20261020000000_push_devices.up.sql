-- Aparelhos que recebem notificações push (Firebase Cloud Messaging).
-- O token muda de dono se outra conta entrar no mesmo aparelho.
CREATE TABLE push_devices (
    token TEXT PRIMARY KEY CHECK (length(token) BETWEEN 1 AND 4096),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX push_devices_user_idx ON push_devices (user_id, updated_at DESC);

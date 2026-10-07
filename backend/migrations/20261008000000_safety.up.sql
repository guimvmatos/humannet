-- Fase 1b: bloqueio e denúncias.

CREATE TABLE blocks (
    blocker_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT blocks_not_self CHECK (blocker_id <> blocked_id)
);

CREATE INDEX blocks_blocked_idx ON blocks (blocked_id);

CREATE TABLE reports (
    id          UUID PRIMARY KEY,
    -- Denúncia sobrevive à exclusão de quem denunciou (moderação).
    reporter_id UUID REFERENCES users (id) ON DELETE SET NULL,
    target_kind TEXT NOT NULL CHECK (target_kind IN ('post', 'user')),
    -- Sem FK: o alvo pode ser apagado, a denúncia permanece.
    target_id   UUID NOT NULL,
    -- Cópia do conteúdo denunciado no momento da denúncia (evidência).
    snapshot    TEXT NOT NULL DEFAULT '' CHECK (char_length(snapshot) <= 5000),
    reason      TEXT NOT NULL CHECK (reason IN (
                    'spam', 'harassment', 'hate', 'violence', 'sexual',
                    'minor_safety', 'self_harm', 'misinformation', 'impersonation', 'other')),
    details     TEXT NOT NULL DEFAULT '' CHECK (char_length(details) <= 1000),
    status      TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open', 'reviewing', 'actioned', 'dismissed')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

-- Uma denúncia aberta por pessoa por alvo.
CREATE UNIQUE INDEX reports_open_unique
    ON reports (reporter_id, target_kind, target_id) WHERE status = 'open';
CREATE INDEX reports_queue_idx ON reports (status, created_at);

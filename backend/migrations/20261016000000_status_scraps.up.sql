-- Beta lote 10: status/subnick (com validade) e recados no perfil.

ALTER TABLE users
    ADD COLUMN status_text TEXT NOT NULL DEFAULT '' CHECK (char_length(status_text) <= 80),
    -- NULL = sem validade.
    ADD COLUMN status_expires_at TIMESTAMPTZ;

-- Recados (estilo "scrap"): só amigos escrevem; sem aprovação; o dono do
-- perfil e o autor podem apagar.
CREATE TABLE scraps (
    id           UUID PRIMARY KEY,
    recipient_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    author_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    body         TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT scraps_not_self CHECK (author_id <> recipient_id)
);

CREATE INDEX scraps_recipient_idx ON scraps (recipient_id, id DESC);
CREATE INDEX scraps_author_idx ON scraps (author_id, created_at);

ALTER TABLE reports DROP CONSTRAINT reports_target_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_kind_check
    CHECK (target_kind IN ('post', 'user', 'comment', 'topic', 'reply', 'community',
                           'testimonial', 'scrap'));

-- Beta lote 5: depoimentos (SPEC 4.2). Um amigo escreve sobre o outro; o dono
-- do perfil aprova antes de aparecer. Um depoimento por autor e destinatário.

CREATE TABLE testimonials (
    id           UUID PRIMARY KEY,
    author_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    body         TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
    status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_at  TIMESTAMPTZ,
    UNIQUE (author_id, recipient_id),
    CONSTRAINT testimonials_not_self CHECK (author_id <> recipient_id)
);

CREATE INDEX testimonials_recipient_idx ON testimonials (recipient_id, status, approved_at DESC);

ALTER TABLE reports DROP CONSTRAINT reports_target_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_kind_check
    CHECK (target_kind IN ('post', 'user', 'comment', 'topic', 'reply', 'community', 'testimonial'));

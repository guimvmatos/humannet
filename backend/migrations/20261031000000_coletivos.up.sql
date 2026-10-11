-- Coletivos estudantis (república, atlética, CA, grupo) podem criar eventos
-- sem CNPJ, depois de aprovados pela administração (com e-mail institucional).
ALTER TABLE pages ALTER COLUMN cnpj DROP NOT NULL;
ALTER TABLE pages
    ADD COLUMN kind TEXT NOT NULL DEFAULT 'empresa' CHECK (kind IN ('empresa', 'coletivo')),
    ADD CONSTRAINT pages_kind_cnpj CHECK ((kind = 'empresa') = (cnpj IS NOT NULL));
ALTER TABLE pages DROP CONSTRAINT pages_category_check;
ALTER TABLE pages ADD CONSTRAINT pages_category_check CHECK (category IN (
    'bar', 'restaurante', 'cafe', 'casa_de_show', 'balada', 'teatro', 'cinema',
    'espaco_cultural', 'livraria', 'esporte', 'outro',
    'republica', 'atletica', 'centro_academico', 'coletivo'));

-- Eventos de coletivos novos passam por revisão; endereço pode ficar só
-- para quem marcou "vou".
ALTER TABLE events
    ADD COLUMN status TEXT NOT NULL DEFAULT 'published'
        CHECK (status IN ('pending_review', 'published', 'rejected')),
    ADD COLUMN address_hidden BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE organizer_requests (
    id                    UUID PRIMARY KEY,
    user_id               UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name                  TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 80),
    category              TEXT NOT NULL CHECK (category IN ('republica', 'atletica', 'centro_academico', 'coletivo')),
    description           TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 1000),
    institution_email     TEXT NOT NULL CHECK (char_length(institution_email) <= 254),
    email_code_hash       BYTEA,
    email_code_expires_at TIMESTAMPTZ,
    email_verified_at     TIMESTAMPTZ,
    status                TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reason                TEXT NOT NULL DEFAULT '' CHECK (char_length(reason) <= 300),
    decided_by            UUID REFERENCES users (id) ON DELETE SET NULL,
    decided_at            TIMESTAMPTZ,
    page_id               UUID REFERENCES pages (id) ON DELETE SET NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX organizer_requests_open_idx ON organizer_requests (user_id) WHERE status = 'pending';
CREATE INDEX organizer_requests_status_idx ON organizer_requests (status, created_at);

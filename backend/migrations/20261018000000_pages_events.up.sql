-- Beta lote 12: páginas de lugares (com CNPJ) e eventos com "tenho interesse".
-- Sem venda de ingresso: só registro de interesse.

CREATE TABLE pages (
    id          UUID PRIMARY KEY,
    slug        TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
    name        TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 80),
    category    TEXT NOT NULL CHECK (category IN (
                    'bar', 'restaurante', 'cafe', 'casa_de_show', 'balada', 'teatro',
                    'cinema', 'espaco_cultural', 'livraria', 'esporte', 'outro')),
    description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 2000),
    address     TEXT NOT NULL DEFAULT '' CHECK (char_length(address) <= 200),
    city        TEXT NOT NULL DEFAULT '' CHECK (char_length(city) <= 80),
    -- CNPJ só com dígitos; uma página por CNPJ. Dado público de empresa.
    cnpj        CHAR(14) NOT NULL UNIQUE CHECK (cnpj ~ '^[0-9]{14}$'),
    -- Conferido pela administração da HumanNet.
    verified_at TIMESTAMPTZ,
    created_by  UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
);

CREATE INDEX pages_name_idx ON pages (lower(name)) WHERE deleted_at IS NULL;

CREATE TABLE page_admins (
    page_id    UUID NOT NULL REFERENCES pages (id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role       TEXT NOT NULL CHECK (role IN ('owner', 'admin')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (page_id, user_id)
);
CREATE UNIQUE INDEX page_one_owner ON page_admins (page_id) WHERE role = 'owner';
CREATE INDEX page_admins_user_idx ON page_admins (user_id);

-- Acompanhar um lugar: única relação unilateral permitida (ADR-0006).
CREATE TABLE page_followers (
    page_id    UUID NOT NULL REFERENCES pages (id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (page_id, user_id)
);
CREATE INDEX page_followers_user_idx ON page_followers (user_id);

CREATE TABLE events (
    id           UUID PRIMARY KEY,
    page_id      UUID NOT NULL REFERENCES pages (id) ON DELETE CASCADE,
    title        TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 120),
    description  TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 3000),
    starts_at    TIMESTAMPTZ NOT NULL,
    ends_at      TIMESTAMPTZ CHECK (ends_at IS NULL OR ends_at > starts_at),
    -- Vazio = endereço da página.
    location     TEXT NOT NULL DEFAULT '' CHECK (char_length(location) <= 200),
    created_by   UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    cancelled_at TIMESTAMPTZ,
    deleted_at   TIMESTAMPTZ
);
CREATE INDEX events_page_idx ON events (page_id, starts_at) WHERE deleted_at IS NULL;
CREATE INDEX events_starts_idx ON events (starts_at) WHERE deleted_at IS NULL;

CREATE TABLE event_interests (
    event_id   UUID NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- interested = "tenho interesse"; going = "vou".
    status     TEXT NOT NULL CHECK (status IN ('interested', 'going')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, user_id)
);
CREATE INDEX event_interests_user_idx ON event_interests (user_id);

ALTER TABLE reports DROP CONSTRAINT reports_target_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_kind_check
    CHECK (target_kind IN ('post', 'user', 'comment', 'topic', 'reply', 'community',
                           'testimonial', 'scrap', 'page', 'event'));

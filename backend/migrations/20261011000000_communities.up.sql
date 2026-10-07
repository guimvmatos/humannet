-- Beta lote 4: comunidades-fórum (SPEC 4.5) e denúncias de mais tipos de conteúdo.

CREATE TABLE communities (
    id          UUID PRIMARY KEY,
    -- Endereço curto e estável: letras minúsculas, dígitos e hífen.
    slug        TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
    name        TEXT NOT NULL CHECK (char_length(name) BETWEEN 3 AND 60),
    description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 2000),
    rules       TEXT NOT NULL DEFAULT '' CHECK (char_length(rules) <= 2000),
    theme       TEXT NOT NULL CHECK (theme IN (
                    'tecnologia', 'musica', 'cinema', 'series', 'livros', 'games',
                    'esportes', 'arte', 'culinaria', 'viagens', 'ciencia', 'humor',
                    'cidade', 'educacao', 'trabalho', 'familia', 'outros')),
    -- public: qualquer um lê e entra. closed: entrar exige aprovação; só membros leem.
    visibility  TEXT NOT NULL CHECK (visibility IN ('public', 'closed')),
    created_by  UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
);

CREATE INDEX communities_name_idx ON communities (lower(name)) WHERE deleted_at IS NULL;

CREATE TABLE community_members (
    community_id UUID NOT NULL REFERENCES communities (id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role         TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'moderator', 'member')),
    -- pending: pediu para entrar (comunidade fechada). banned: removido, não volta.
    status       TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'pending', 'banned')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (community_id, user_id),
    CONSTRAINT owner_is_active CHECK (role = 'member' OR status = 'active')
);

-- Exatamente um dono por comunidade (garantido aqui e no código).
CREATE UNIQUE INDEX community_one_owner ON community_members (community_id) WHERE role = 'owner';
CREATE INDEX community_members_user_idx ON community_members (user_id, status);

CREATE TABLE topics (
    id               UUID PRIMARY KEY,
    community_id     UUID NOT NULL REFERENCES communities (id) ON DELETE CASCADE,
    author_id        UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title            TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 150),
    body             TEXT NOT NULL CHECK (char_length(body) <= 5000),
    pinned           BOOLEAN NOT NULL DEFAULT false,
    locked           BOOLEAN NOT NULL DEFAULT false,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Última resposta (ou criação): ordena a lista de tópicos.
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);

CREATE INDEX topics_list_idx ON topics (community_id, pinned DESC, last_activity_at DESC, id DESC)
    WHERE deleted_at IS NULL;

CREATE TABLE topic_replies (
    id         UUID PRIMARY KEY,
    topic_id   UUID NOT NULL REFERENCES topics (id) ON DELETE CASCADE,
    author_id  UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    body       TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 5000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX topic_replies_topic_idx ON topic_replies (topic_id, id);

-- Denúncias: comentário, tópico, resposta e comunidade. `target_user_id` guarda
-- o autor (ou o perfil) no momento da denúncia, para suspender sem depender
-- do conteúdo ainda existir.
ALTER TABLE reports DROP CONSTRAINT reports_target_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_kind_check
    CHECK (target_kind IN ('post', 'user', 'comment', 'topic', 'reply', 'community'));
ALTER TABLE reports ADD COLUMN target_user_id UUID REFERENCES users (id) ON DELETE SET NULL;
UPDATE reports r SET target_user_id = CASE
    WHEN r.target_kind = 'user' THEN (SELECT id FROM users WHERE id = r.target_id)
    ELSE (SELECT author_id FROM posts WHERE id = r.target_id) END;

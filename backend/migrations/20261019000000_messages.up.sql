-- Beta lote 13: mensagens diretas (1:1 e em grupo) entre amigos.

CREATE TABLE conversations (
    id              UUID PRIMARY KEY,
    kind            TEXT NOT NULL CHECK (kind IN ('direct', 'group')),
    -- Grupo: nome. Conversa 1:1: vazio.
    title           TEXT NOT NULL DEFAULT '' CHECK (char_length(title) <= 60),
    -- 1:1: "menor-uuid:maior-uuid", para existir uma só conversa por par.
    direct_key      TEXT UNIQUE,
    created_by      UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_message_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT direct_has_key CHECK ((kind = 'direct') = (direct_key IS NOT NULL))
);

CREATE TABLE conversation_members (
    conversation_id UUID NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role            TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'member')),
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_read_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX conversation_members_user_idx ON conversation_members (user_id);

CREATE TABLE messages (
    id              UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    author_id       UUID REFERENCES users (id) ON DELETE SET NULL,
    body            TEXT NOT NULL CHECK (char_length(body) <= 4000),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ
);
CREATE INDEX messages_conversation_idx ON messages (conversation_id, id DESC);

ALTER TABLE reports DROP CONSTRAINT reports_target_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_kind_check
    CHECK (target_kind IN ('post', 'user', 'comment', 'topic', 'reply', 'community',
                           'testimonial', 'scrap', 'page', 'event', 'message'));

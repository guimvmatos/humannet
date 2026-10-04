-- Fase 1a: perfil básico, seguir, posts de texto.

ALTER TABLE users
    ADD COLUMN display_name TEXT,
    ADD COLUMN bio          TEXT NOT NULL DEFAULT '',
    ADD CONSTRAINT users_display_name_length CHECK (display_name IS NULL OR char_length(display_name) BETWEEN 1 AND 50),
    ADD CONSTRAINT users_bio_length          CHECK (char_length(bio) <= 300);

CREATE TABLE follows (
    follower_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    followee_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (follower_id, followee_id),
    CONSTRAINT follows_not_self CHECK (follower_id <> followee_id)
);

CREATE INDEX follows_followee_idx ON follows (followee_id);

CREATE TABLE posts (
    -- UUID v7: a ordem do id é a ordem cronológica (usado como cursor do feed).
    id          UUID PRIMARY KEY,
    author_id   UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    body        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    edited_at   TIMESTAMPTZ,
    deleted_at  TIMESTAMPTZ,

    CONSTRAINT posts_body_length CHECK (char_length(body) BETWEEN 1 AND 5000)
);

CREATE INDEX posts_author_id_idx ON posts (author_id, id DESC) WHERE deleted_at IS NULL;

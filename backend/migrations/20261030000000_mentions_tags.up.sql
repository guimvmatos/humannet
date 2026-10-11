-- Marcações: @menções no texto (post e comentário) e "com fulano" (marcar
-- amigos no post, só aparece depois que a pessoa aprova).
ALTER TABLE users ADD COLUMN mention_policy TEXT NOT NULL DEFAULT 'everyone'
    CHECK (mention_policy IN ('everyone', 'friends', 'nobody'));

CREATE TABLE mentions (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    actor_id   UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    post_id    UUID NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
    comment_id UUID REFERENCES comments (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT mentions_not_self CHECK (user_id <> actor_id)
);
CREATE INDEX mentions_user_idx ON mentions (user_id, created_at DESC);

CREATE TABLE post_tags (
    post_id     UUID NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status      TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_at TIMESTAMPTZ,
    PRIMARY KEY (post_id, user_id)
);
CREATE INDEX post_tags_user_idx ON post_tags (user_id, status, post_id DESC);

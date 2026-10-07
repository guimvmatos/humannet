-- Beta lote 9: fotos (posts com até 4, avatar e Foto do dia).
-- Os arquivos ficam no armazenamento de objetos (S3); aqui só os metadados.

CREATE TABLE media (
    id          UUID PRIMARY KEY,
    owner_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind        TEXT NOT NULL CHECK (kind IN ('post', 'avatar', 'daily')),
    -- Chave do objeto no bucket.
    key         TEXT NOT NULL UNIQUE,
    width       INT NOT NULL CHECK (width > 0),
    height      INT NOT NULL CHECK (height > 0),
    bytes       INT NOT NULL CHECK (bytes > 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Preenchido quando a foto passa a ser usada (post, avatar ou Foto do dia).
    attached_at TIMESTAMPTZ
);

CREATE INDEX media_owner_idx ON media (owner_id, created_at DESC);

CREATE TABLE post_media (
    post_id  UUID NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
    media_id UUID NOT NULL UNIQUE REFERENCES media (id) ON DELETE CASCADE,
    position SMALLINT NOT NULL CHECK (position BETWEEN 0 AND 3),
    PRIMARY KEY (post_id, position)
);

-- Post pode ser só foto (texto vazio). A regra "texto ou foto" fica no código.
ALTER TABLE posts DROP CONSTRAINT posts_body_length;
ALTER TABLE posts ADD CONSTRAINT posts_body_length CHECK (char_length(body) <= 5000);

ALTER TABLE users ADD COLUMN avatar_media_id UUID REFERENCES media (id) ON DELETE SET NULL;

-- Foto do dia: uma por pessoa por dia (horário de Brasília).
CREATE TABLE daily_photos (
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    day        DATE NOT NULL,
    media_id   UUID NOT NULL REFERENCES media (id) ON DELETE CASCADE,
    caption    TEXT NOT NULL DEFAULT '' CHECK (char_length(caption) <= 200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, day)
);

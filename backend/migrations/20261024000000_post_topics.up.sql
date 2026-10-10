-- Beta lote 19: temas (lista fixa, marcados pelo autor) e hashtags dos posts,
-- para o feed "Para você" (ordenado no aparelho, ADR-0004/0007).
ALTER TABLE posts
    ADD COLUMN topics   TEXT[] NOT NULL DEFAULT '{}' CHECK (cardinality(topics) <= 3),
    ADD COLUMN hashtags TEXT[] NOT NULL DEFAULT '{}' CHECK (cardinality(hashtags) <= 10);
CREATE INDEX posts_topics_idx ON posts USING gin (topics) WHERE deleted_at IS NULL;

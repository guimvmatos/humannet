-- Posts globais (ADR-0008): quem escreve não escolhe público. Todo post
-- pessoal leva a célula aproximada (com desvio fixo de até ~1,5 km) quando o
-- aparelho deu a posição; quem lê escolhe Cronológico, Para você ou Regional.
DROP INDEX IF EXISTS posts_region_idx;
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_region_cell;
ALTER TABLE posts DROP COLUMN audience;
ALTER TABLE posts ADD CONSTRAINT posts_cell_pair
    CHECK ((cell_lat IS NULL) = (cell_lng IS NULL));
CREATE INDEX posts_cell_idx ON posts (cell_lat, cell_lng, id DESC)
    WHERE cell_lat IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX posts_recent_topics_idx ON posts (id DESC)
    WHERE deleted_at IS NULL AND page_id IS NULL
      AND (cardinality(topics) > 0 OR cardinality(hashtags) > 0);

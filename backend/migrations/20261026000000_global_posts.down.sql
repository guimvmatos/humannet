DROP INDEX IF EXISTS posts_recent_topics_idx;
DROP INDEX IF EXISTS posts_cell_idx;
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_cell_pair;
ALTER TABLE posts ADD COLUMN audience TEXT NOT NULL DEFAULT 'friends'
    CHECK (audience IN ('friends', 'region'));
UPDATE posts SET audience = 'region' WHERE cell_lat IS NOT NULL;
ALTER TABLE posts ADD CONSTRAINT posts_region_cell
    CHECK ((audience = 'region') = (cell_lat IS NOT NULL AND cell_lng IS NOT NULL));
CREATE INDEX posts_region_idx ON posts (cell_lat, cell_lng, id DESC)
    WHERE audience = 'region' AND deleted_at IS NULL;

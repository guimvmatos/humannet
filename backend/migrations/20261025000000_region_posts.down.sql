DROP INDEX posts_region_idx;
ALTER TABLE posts DROP CONSTRAINT posts_region_cell, DROP COLUMN cell_lng, DROP COLUMN cell_lat, DROP COLUMN audience;

DROP INDEX pages_geo_idx;
ALTER TABLE pages DROP CONSTRAINT pages_geo_range, DROP CONSTRAINT pages_geo_pair,
    DROP COLUMN geo_source, DROP COLUMN lng, DROP COLUMN lat;

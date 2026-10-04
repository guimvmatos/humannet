DROP TABLE IF EXISTS posts;
DROP TABLE IF EXISTS follows;
ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_bio_length,
    DROP CONSTRAINT IF EXISTS users_display_name_length,
    DROP COLUMN IF EXISTS bio,
    DROP COLUMN IF EXISTS display_name;

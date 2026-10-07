DROP TABLE IF EXISTS moderation_actions;
DROP TABLE IF EXISTS password_resets;
ALTER TABLE users DROP COLUMN IF EXISTS suspended_at, DROP COLUMN IF EXISTS role;

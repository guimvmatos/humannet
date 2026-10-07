DROP TABLE daily_photos;
ALTER TABLE users DROP COLUMN avatar_media_id;
DELETE FROM posts WHERE char_length(body) = 0;
ALTER TABLE posts DROP CONSTRAINT posts_body_length;
ALTER TABLE posts ADD CONSTRAINT posts_body_length CHECK (char_length(body) BETWEEN 1 AND 5000);
DROP TABLE post_media;
DROP TABLE media;

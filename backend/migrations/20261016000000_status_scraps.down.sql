DELETE FROM reports WHERE target_kind = 'scrap';
ALTER TABLE reports DROP CONSTRAINT reports_target_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_kind_check
    CHECK (target_kind IN ('post', 'user', 'comment', 'topic', 'reply', 'community', 'testimonial'));
DROP TABLE scraps;
ALTER TABLE users DROP COLUMN status_text, DROP COLUMN status_expires_at;

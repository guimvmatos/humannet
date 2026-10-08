DELETE FROM reports WHERE target_kind IN ('page', 'event');
ALTER TABLE reports DROP CONSTRAINT reports_target_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_kind_check
    CHECK (target_kind IN ('post', 'user', 'comment', 'topic', 'reply', 'community',
                           'testimonial', 'scrap'));
DROP TABLE event_interests;
DROP TABLE events;
DROP TABLE page_followers;
DROP TABLE page_admins;
DROP TABLE pages;

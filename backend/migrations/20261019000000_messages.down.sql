DELETE FROM reports WHERE target_kind = 'message';
ALTER TABLE reports DROP CONSTRAINT reports_target_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_kind_check
    CHECK (target_kind IN ('post', 'user', 'comment', 'topic', 'reply', 'community',
                           'testimonial', 'scrap', 'page', 'event'));
DROP TABLE messages;
DROP TABLE conversation_members;
DROP TABLE conversations;

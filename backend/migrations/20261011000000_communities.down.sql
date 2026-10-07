DELETE FROM reports WHERE target_kind NOT IN ('post', 'user');
ALTER TABLE reports DROP COLUMN target_user_id;
ALTER TABLE reports DROP CONSTRAINT reports_target_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_kind_check CHECK (target_kind IN ('post', 'user'));
DROP TABLE topic_replies;
DROP TABLE topics;
DROP TABLE community_members;
DROP TABLE communities;

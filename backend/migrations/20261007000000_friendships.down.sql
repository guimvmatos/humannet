CREATE TABLE follows (
    follower_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    followee_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id),
    CONSTRAINT follows_not_self CHECK (follower_id <> followee_id)
);
CREATE INDEX follows_followee_idx ON follows (followee_id);

INSERT INTO follows (follower_id, followee_id, created_at)
SELECT user_id, friend_id, created_at FROM friends;
INSERT INTO follows (follower_id, followee_id, created_at)
SELECT from_id, to_id, created_at FROM friend_requests ON CONFLICT DO NOTHING;

DROP VIEW friends;
DROP TABLE friendships;
DROP TABLE friend_requests;

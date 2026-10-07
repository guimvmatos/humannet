-- ADR-0006: amizade mútua substitui "seguir".

CREATE TABLE friend_requests (
    from_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    to_id      UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (from_id, to_id),
    CONSTRAINT friend_requests_not_self CHECK (from_id <> to_id)
);

CREATE INDEX friend_requests_to_idx ON friend_requests (to_id, created_at DESC);

-- Uma linha por amizade, com o par ordenado: não existe "meia amizade".
CREATE TABLE friendships (
    user_a     UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    user_b     UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_a, user_b),
    CONSTRAINT friendships_ordered CHECK (user_a < user_b)
);

CREATE INDEX friendships_user_b_idx ON friendships (user_b);

-- Visão simétrica: (user_id, friend_id) nos dois sentidos.
CREATE VIEW friends AS
    SELECT user_a AS user_id, user_b AS friend_id, created_at FROM friendships
    UNION ALL
    SELECT user_b AS user_id, user_a AS friend_id, created_at FROM friendships;

-- Migração dos dados de teste: seguir mútuo vira amizade; unilateral vira pedido.
INSERT INTO friendships (user_a, user_b, created_at)
SELECT LEAST(f1.follower_id, f1.followee_id), GREATEST(f1.follower_id, f1.followee_id),
       GREATEST(f1.created_at, f2.created_at)
FROM follows f1
JOIN follows f2 ON f2.follower_id = f1.followee_id AND f2.followee_id = f1.follower_id
WHERE f1.follower_id < f1.followee_id;

INSERT INTO friend_requests (from_id, to_id, created_at)
SELECT f1.follower_id, f1.followee_id, f1.created_at
FROM follows f1
WHERE NOT EXISTS (
    SELECT 1 FROM follows f2
    WHERE f2.follower_id = f1.followee_id AND f2.followee_id = f1.follower_id
);

DROP TABLE follows;

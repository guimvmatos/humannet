-- Beta lote 6: avisos no app. Guarda até quando a pessoa já viu as novidades.
ALTER TABLE users ADD COLUMN activity_seen_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Para buscar respostas recentes por tópico e comentários recentes por post.
CREATE INDEX topic_replies_author_idx ON topic_replies (author_id, topic_id);

-- Beta lote 8: sugestão de amigos. Campos opcionais do perfil (visíveis no
-- perfil) que ajudam a reencontrar pessoas, e sugestões dispensadas.
ALTER TABLE users
    ADD COLUMN hometown TEXT NOT NULL DEFAULT '' CHECK (char_length(hometown) <= 80),
    ADD COLUMN city     TEXT NOT NULL DEFAULT '' CHECK (char_length(city) <= 80),
    ADD COLUMN school   TEXT NOT NULL DEFAULT '' CHECK (char_length(school) <= 80);

CREATE INDEX users_hometown_idx ON users (lower(hometown)) WHERE hometown <> '';
CREATE INDEX users_city_idx ON users (lower(city)) WHERE city <> '';
CREATE INDEX users_school_idx ON users (lower(school)) WHERE school <> '';

CREATE TABLE suggestion_dismissals (
    user_id      UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    dismissed_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, dismissed_id)
);

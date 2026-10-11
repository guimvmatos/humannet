-- "Quem visitou meu perfil": recíproco (quem desliga não vê nem aparece),
-- ligado por padrão (decisão do produto). Guarda só a última visita de cada
-- pessoa, por até 30 dias.
ALTER TABLE users ADD COLUMN visits_enabled BOOLEAN NOT NULL DEFAULT true;
CREATE TABLE profile_visits (
    profile_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    visitor_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    visited_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (profile_id, visitor_id),
    CONSTRAINT profile_visits_not_self CHECK (profile_id <> visitor_id)
);
CREATE INDEX profile_visits_recent_idx ON profile_visits (profile_id, visited_at DESC);
CREATE INDEX profile_visits_visitor_idx ON profile_visits (visitor_id);

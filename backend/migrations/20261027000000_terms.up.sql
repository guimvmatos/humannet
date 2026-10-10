-- Aceite dos Termos de Uso e da Política de Privacidade (versão aceita).
ALTER TABLE users
    ADD COLUMN terms_version SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN terms_accepted_at TIMESTAMPTZ;

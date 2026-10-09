-- Beta lote 15: páginas 2.0 — logo, capa, CEP, mural e mensagens para a página.

-- Fotos de capa (largas). Logo usa o tipo 'avatar' (quadrado).
ALTER TABLE media DROP CONSTRAINT media_kind_check;
ALTER TABLE media ADD CONSTRAINT media_kind_check
    CHECK (kind IN ('post', 'avatar', 'daily', 'cover'));

ALTER TABLE pages
    ADD COLUMN logo_media_id  UUID REFERENCES media (id) ON DELETE SET NULL,
    ADD COLUMN cover_media_id UUID REFERENCES media (id) ON DELETE SET NULL,
    ADD COLUMN cep            CHAR(8) CHECK (cep ~ '^[0-9]{8}$');

-- Mural: post da página (o autor é quem administra e publicou).
ALTER TABLE posts ADD COLUMN page_id UUID REFERENCES pages (id) ON DELETE CASCADE;
CREATE INDEX posts_page_idx ON posts (page_id, id DESC)
    WHERE page_id IS NOT NULL AND deleted_at IS NULL;

-- Mensagens para a página: uma conversa por (página, pessoa). Quem
-- administra entra como membro 'page' e responde como a página.
ALTER TABLE conversations DROP CONSTRAINT conversations_kind_check;
ALTER TABLE conversations ADD CONSTRAINT conversations_kind_check
    CHECK (kind IN ('direct', 'group', 'page'));
ALTER TABLE conversations
    ADD COLUMN page_id     UUID REFERENCES pages (id) ON DELETE CASCADE,
    ADD COLUMN customer_id UUID REFERENCES users (id) ON DELETE CASCADE,
    ADD CONSTRAINT page_conversation_fields
        CHECK ((kind = 'page') = (page_id IS NOT NULL AND customer_id IS NOT NULL)),
    ADD CONSTRAINT page_conversation_unique UNIQUE (page_id, customer_id);

ALTER TABLE conversation_members DROP CONSTRAINT conversation_members_role_check;
ALTER TABLE conversation_members ADD CONSTRAINT conversation_members_role_check
    CHECK (role IN ('owner', 'member', 'page'));

ALTER TABLE messages ADD COLUMN as_page BOOLEAN NOT NULL DEFAULT false;

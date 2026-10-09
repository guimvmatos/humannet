ALTER TABLE messages DROP COLUMN as_page;
DELETE FROM conversations WHERE kind = 'page';
ALTER TABLE conversation_members DROP CONSTRAINT conversation_members_role_check;
ALTER TABLE conversation_members ADD CONSTRAINT conversation_members_role_check
    CHECK (role IN ('owner', 'member'));
ALTER TABLE conversations DROP CONSTRAINT page_conversation_unique,
    DROP CONSTRAINT page_conversation_fields, DROP COLUMN customer_id, DROP COLUMN page_id;
ALTER TABLE conversations DROP CONSTRAINT conversations_kind_check;
ALTER TABLE conversations ADD CONSTRAINT conversations_kind_check CHECK (kind IN ('direct', 'group'));
DELETE FROM posts WHERE page_id IS NOT NULL;
ALTER TABLE posts DROP COLUMN page_id;
ALTER TABLE pages DROP COLUMN cep, DROP COLUMN cover_media_id, DROP COLUMN logo_media_id;
DELETE FROM media WHERE kind = 'cover';
ALTER TABLE media DROP CONSTRAINT media_kind_check;
ALTER TABLE media ADD CONSTRAINT media_kind_check CHECK (kind IN ('post', 'avatar', 'daily'));

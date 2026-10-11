DROP TABLE organizer_requests;
ALTER TABLE events DROP COLUMN address_hidden, DROP COLUMN status;
DELETE FROM pages WHERE kind = 'coletivo';
ALTER TABLE pages DROP CONSTRAINT pages_category_check;
ALTER TABLE pages ADD CONSTRAINT pages_category_check CHECK (category IN (
    'bar', 'restaurante', 'cafe', 'casa_de_show', 'balada', 'teatro', 'cinema',
    'espaco_cultural', 'livraria', 'esporte', 'outro'));
ALTER TABLE pages DROP CONSTRAINT pages_kind_cnpj, DROP COLUMN kind;
ALTER TABLE pages ALTER COLUMN cnpj SET NOT NULL;

-- Beta lote 20: posts para a região (feed regional C1/C2, ADR-0007).
-- A posição do post é arredondada para uma célula de ~500 m (grade de
-- 0,005°): nunca guardamos o ponto exato, nem mostramos distância.
ALTER TABLE posts
    ADD COLUMN audience TEXT NOT NULL DEFAULT 'friends' CHECK (audience IN ('friends', 'region')),
    ADD COLUMN cell_lat DOUBLE PRECISION,
    ADD COLUMN cell_lng DOUBLE PRECISION,
    ADD CONSTRAINT posts_region_cell
        CHECK ((audience = 'region') = (cell_lat IS NOT NULL AND cell_lng IS NOT NULL));
CREATE INDEX posts_region_idx ON posts (cell_lat, cell_lng, id DESC)
    WHERE audience = 'region' AND deleted_at IS NULL;

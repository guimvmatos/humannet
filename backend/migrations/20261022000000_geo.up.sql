-- Beta lote 16: coordenadas das páginas (para o mapa de eventos).
-- Só o LUGAR tem coordenada. A posição de quem usa o app nunca vai ao servidor.
ALTER TABLE pages
    ADD COLUMN lat DOUBLE PRECISION,
    ADD COLUMN lng DOUBLE PRECISION,
    -- auto: achada pelo endereço; manual: marcada no mapa por quem administra.
    ADD COLUMN geo_source TEXT CHECK (geo_source IN ('auto', 'manual')),
    ADD CONSTRAINT pages_geo_pair CHECK ((lat IS NULL) = (lng IS NULL)),
    ADD CONSTRAINT pages_geo_range CHECK (lat BETWEEN -90 AND 90 AND lng BETWEEN -180 AND 180);

CREATE INDEX pages_geo_idx ON pages (lat, lng) WHERE lat IS NOT NULL AND deleted_at IS NULL;

-- Beta lote 18: "Minha história" (linha do tempo) e sugestões de reencontro.
-- Dados estruturados para casar pessoas: municípios do IBGE, instituições
-- (escola, faculdade, empresa) num catálogo comum sem duplicatas, e cursos.

CREATE TABLE municipalities (
    code   INT PRIMARY KEY CHECK (code BETWEEN 1000000 AND 9999999),
    name   TEXT NOT NULL,
    uf     CHAR(2) NOT NULL,
    lat    DOUBLE PRECISION,
    lng    DOUBLE PRECISION,
    -- Nome normalizado (minúsculo, sem acento) para busca.
    search TEXT NOT NULL
);
CREATE INDEX municipalities_search_idx ON municipalities (search text_pattern_ops);

-- Escolas, faculdades e empresas. Uma por (tipo, nome normalizado, município).
CREATE TABLE orgs (
    id                UUID PRIMARY KEY,
    kind              TEXT NOT NULL CHECK (kind IN ('escola', 'faculdade', 'empresa')),
    name              TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 120),
    search            TEXT NOT NULL,
    municipality_code INT REFERENCES municipalities (code),
    -- Código oficial quando importado (INEP, e-MEC, CNPJ).
    official_code     TEXT,
    created_by        UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT orgs_unique UNIQUE NULLS NOT DISTINCT (kind, search, municipality_code)
);
CREATE INDEX orgs_search_idx ON orgs (kind, search text_pattern_ops);

CREATE TABLE courses (
    id     SERIAL PRIMARY KEY,
    name   TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 100),
    search TEXT NOT NULL UNIQUE
);

-- Itens da história de cada pessoa. Anos, nunca datas exatas (R5).
CREATE TABLE life_entries (
    id                UUID PRIMARY KEY,
    user_id           UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind              TEXT NOT NULL CHECK (kind IN ('nasceu', 'morou', 'escola', 'faculdade', 'trabalho')),
    municipality_code INT REFERENCES municipalities (code),
    org_id            UUID REFERENCES orgs (id),
    course_id         INT REFERENCES courses (id),
    -- Escola: fundamental | medio | tecnico. Faculdade: graduacao | pos.
    level             TEXT CHECK (level IN ('fundamental', 'medio', 'tecnico', 'graduacao', 'pos')),
    start_year        SMALLINT CHECK (start_year BETWEEN 1920 AND 2100),
    -- Nulo = até hoje.
    end_year          SMALLINT CHECK (end_year BETWEEN 1920 AND 2100),
    -- friends: amigos veem; suggestions: só para sugestões, nunca exibido; private: só eu.
    visibility        TEXT NOT NULL DEFAULT 'friends' CHECK (visibility IN ('friends', 'suggestions', 'private')),
    -- "Quero ser encontrado por este item."
    discoverable      BOOLEAN NOT NULL DEFAULT true,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT life_years CHECK (end_year IS NULL OR start_year IS NULL OR end_year >= start_year),
    CONSTRAINT life_shape CHECK (
        (kind IN ('nasceu', 'morou') AND municipality_code IS NOT NULL AND org_id IS NULL)
        OR (kind IN ('escola', 'faculdade', 'trabalho') AND org_id IS NOT NULL))
);
CREATE INDEX life_entries_user_idx ON life_entries (user_id);
CREATE INDEX life_entries_org_idx ON life_entries (org_id) WHERE org_id IS NOT NULL AND discoverable;
CREATE INDEX life_entries_mun_idx ON life_entries (kind, municipality_code) WHERE discoverable;

-- Cursos de graduação mais comuns (lista inicial; novos entram pelo app).
INSERT INTO courses (name, search) VALUES
('Administração','administracao'),
('Agronomia','agronomia'),
('Análise e Desenvolvimento de Sistemas','analise e desenvolvimento de sistemas'),
('Arquitetura e Urbanismo','arquitetura e urbanismo'),
('Artes Visuais','artes visuais'),
('Biblioteconomia','biblioteconomia'),
('Biomedicina','biomedicina'),
('Ciência da Computação','ciencia da computacao'),
('Ciências Biológicas','ciencias biologicas'),
('Ciências Contábeis','ciencias contabeis'),
('Ciências Econômicas','ciencias economicas'),
('Ciências Sociais','ciencias sociais'),
('Cinema e Audiovisual','cinema e audiovisual'),
('Comércio Exterior','comercio exterior'),
('Comunicação Social','comunicacao social'),
('Dança','danca'),
('Design','design'),
('Design de Moda','design de moda'),
('Design Gráfico','design grafico'),
('Direito','direito'),
('Educação Física','educacao fisica'),
('Enfermagem','enfermagem'),
('Engenharia Aeronáutica','engenharia aeronautica'),
('Engenharia Agrícola','engenharia agricola'),
('Engenharia Ambiental','engenharia ambiental'),
('Engenharia Biomédica','engenharia biomedica'),
('Engenharia Civil','engenharia civil'),
('Engenharia de Alimentos','engenharia de alimentos'),
('Engenharia de Computação','engenharia de computacao'),
('Engenharia de Controle e Automação','engenharia de controle e automacao'),
('Engenharia de Materiais','engenharia de materiais'),
('Engenharia de Petróleo','engenharia de petroleo'),
('Engenharia de Produção','engenharia de producao'),
('Engenharia de Software','engenharia de software'),
('Engenharia Elétrica','engenharia eletrica'),
('Engenharia Eletrônica','engenharia eletronica'),
('Engenharia Florestal','engenharia florestal'),
('Engenharia Física','engenharia fisica'),
('Engenharia Mecânica','engenharia mecanica'),
('Engenharia Mecatrônica','engenharia mecatronica'),
('Engenharia Metalúrgica','engenharia metalurgica'),
('Engenharia Naval','engenharia naval'),
('Engenharia Química','engenharia quimica'),
('Engenharia de Telecomunicações','engenharia de telecomunicacoes'),
('Estatística','estatistica'),
('Farmácia','farmacia'),
('Filosofia','filosofia'),
('Física','fisica'),
('Fisioterapia','fisioterapia'),
('Fonoaudiologia','fonoaudiologia'),
('Gastronomia','gastronomia'),
('Geografia','geografia'),
('Geologia','geologia'),
('Gestão Ambiental','gestao ambiental'),
('Gestão de Recursos Humanos','gestao de recursos humanos'),
('Gestão Pública','gestao publica'),
('História','historia'),
('Jornalismo','jornalismo'),
('Letras','letras'),
('Letras - Inglês','letras ingles'),
('Letras - Português','letras portugues'),
('Linguística','linguistica'),
('Logística','logistica'),
('Marketing','marketing'),
('Matemática','matematica'),
('Medicina','medicina'),
('Medicina Veterinária','medicina veterinaria'),
('Meteorologia','meteorologia'),
('Música','musica'),
('Nutrição','nutricao'),
('Oceanografia','oceanografia'),
('Odontologia','odontologia'),
('Pedagogia','pedagogia'),
('Psicologia','psicologia'),
('Publicidade e Propaganda','publicidade e propaganda'),
('Química','quimica'),
('Rádio, TV e Internet','radio tv e internet'),
('Redes de Computadores','redes de computadores'),
('Relações Internacionais','relacoes internacionais'),
('Relações Públicas','relacoes publicas'),
('Saúde Coletiva','saude coletiva'),
('Secretariado Executivo','secretariado executivo'),
('Serviço Social','servico social'),
('Sistemas de Informação','sistemas de informacao'),
('Teatro','teatro'),
('Terapia Ocupacional','terapia ocupacional'),
('Tradução e Interpretação','traducao e interpretacao'),
('Turismo','turismo'),
('Zootecnia','zootecnia'),
('Biotecnologia','biotecnologia'),
('Ciência de Dados','ciencia de dados'),
('Inteligência Artificial','inteligencia artificial'),
('Engenharia de Bioprocessos','engenharia de bioprocessos'),
('Engenharia de Energia','engenharia de energia'),
('Ciências Atuariais','ciencias atuariais'),
('Museologia','museologia'),
('Arquivologia','arquivologia'),
('Educação do Campo','educacao do campo'),
('Licenciatura em Química','licenciatura em quimica'),
('Licenciatura em Física','licenciatura em fisica'),
('Licenciatura em Matemática','licenciatura em matematica'),
('Licenciatura em Ciências Biológicas','licenciatura em ciencias biologicas'),
('Licenciatura em Geografia','licenciatura em geografia'),
('Licenciatura em História','licenciatura em historia'),
('Licenciatura em Pedagogia','licenciatura em pedagogia'),
('Gestão da Tecnologia da Informação','gestao da tecnologia da informacao'),
('Segurança da Informação','seguranca da informacao'),
('Jogos Digitais','jogos digitais'),
('Banco de Dados','banco de dados'),
('Gestão Comercial','gestao comercial'),
('Gestão Financeira','gestao financeira'),
('Processos Gerenciais','processos gerenciais'),
('Radiologia','radiologia'),
('Estética e Cosmética','estetica e cosmetica'),
('Biomedicina Estética','biomedicina estetica'),
('Ciências Aeronáuticas','ciencias aeronauticas'),
('Ciências Agrárias','ciencias agrarias'),
('Engenharia de Pesca','engenharia de pesca'),
('Engenharia Sanitária','engenharia sanitaria'),
('Física Médica','fisica medica'),
('Química Industrial','quimica industrial'),
('Ciência e Tecnologia','ciencia e tecnologia'),
('Bacharelado Interdisciplinar','bacharelado interdisciplinar');

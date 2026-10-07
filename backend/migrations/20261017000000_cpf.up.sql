-- Beta lote 11: uma conta por CPF. Não guardamos o CPF: só um HMAC-SHA256
-- com chave secreta do servidor (CPF_HMAC_KEY), para checar repetição.
ALTER TABLE users ADD COLUMN cpf_hmac BYTEA UNIQUE CHECK (octet_length(cpf_hmac) = 32);

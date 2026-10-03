//! Primitivas criptográficas: hash de senha (Argon2id) e tokens opacos.
//! Ver docs/adr/0005-autenticacao-sessoes-opacas.md.

use std::sync::OnceLock;

use anyhow::anyhow;
use argon2::{
    Argon2,
    password_hash::{PasswordHasher, PasswordVerifier, phc::PasswordHash},
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use sha2::{Digest, Sha256};

/// Argon2id v19 com os parâmetros padrão do crate (m=19 MiB, t=2, p=1),
/// que coincidem com o mínimo recomendado pela OWASP.
fn argon2() -> Argon2<'static> {
    Argon2::default()
}

/// Gera o hash PHC de uma senha. CPU-intensivo: chamar via `spawn_blocking`.
pub fn hash_password(password: &str) -> anyhow::Result<String> {
    argon2()
        .hash_password(password.as_bytes())
        .map(|h| h.to_string())
        .map_err(|e| anyhow!("argon2 hash failed: {e}"))
}

/// Verifica uma senha contra um hash PHC. Hash malformado = falha.
pub fn verify_password(password: &str, phc: &str) -> bool {
    let Ok(parsed) = PasswordHash::new(phc) else {
        return false;
    };
    argon2()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok()
}

/// Hash fictício usado quando o usuário não existe, para que o tempo de resposta
/// do login não revele se uma conta existe.
pub fn dummy_hash() -> &'static str {
    static DUMMY: OnceLock<String> = OnceLock::new();
    DUMMY.get_or_init(|| {
        hash_password("dummy-password-for-timing-equalization").expect("argon2 must work")
    })
}

/// Gera um segredo aleatório de `N` bytes (CSPRNG), codificado em base64url.
fn random_secret<const N: usize>() -> String {
    let mut bytes = [0u8; N];
    rand::fill(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

/// Token de sessão: 256 bits.
pub fn new_session_token() -> String {
    random_secret::<32>()
}

/// Código de convite: 128 bits (mais curto para ser digitável/compartilhável).
pub fn new_invite_code() -> String {
    random_secret::<16>()
}

/// SHA-256 de um segredo (token ou código). É o que vai para o banco.
pub fn sha256(secret: &str) -> Vec<u8> {
    Sha256::digest(secret.as_bytes()).to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn password_roundtrip() {
        let h = hash_password("correct horse battery staple").unwrap();
        assert!(h.starts_with("$argon2id$"));
        assert!(verify_password("correct horse battery staple", &h));
        assert!(!verify_password("wrong", &h));
    }

    #[test]
    fn malformed_hash_fails_closed() {
        assert!(!verify_password("x", "not-a-phc-string"));
    }

    #[test]
    fn tokens_are_unique_and_sized() {
        let a = new_session_token();
        let b = new_session_token();
        assert_ne!(a, b);
        assert_eq!(a.len(), 43); // 32 bytes em base64url sem padding
        assert_eq!(new_invite_code().len(), 22); // 16 bytes
        assert_eq!(sha256(&a).len(), 32);
    }
}

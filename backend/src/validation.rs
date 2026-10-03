//! Validação e normalização de entrada. Regras espelham os CHECKs do banco.

use crate::error::AppError;

pub const PASSWORD_MIN: usize = 12;
pub const PASSWORD_MAX: usize = 128;

/// Normaliza (trim + minúsculas) e valida o nome de usuário: `[a-z0-9_]{3,30}`.
pub fn username(raw: &str) -> Result<String, AppError> {
    let u = raw.trim().to_ascii_lowercase();
    let ok_len = (3..=30).contains(&u.len());
    let ok_chars = u
        .bytes()
        .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_');
    if ok_len && ok_chars {
        Ok(u)
    } else {
        Err(AppError::Validation("invalid_username"))
    }
}

/// Normaliza e faz uma validação estrutural mínima do e-mail. A validação real
/// (posse do endereço) virá com o fluxo de confirmação por e-mail.
pub fn email(raw: &str) -> Result<String, AppError> {
    let e = raw.trim().to_lowercase();
    let valid = (3..=254).contains(&e.len())
        && !e.chars().any(char::is_whitespace)
        && matches!(e.split_once('@'), Some((local, domain))
            if !local.is_empty() && domain.contains('.') && !domain.starts_with('.')
               && !domain.ends_with('.') && !domain.contains('@'));
    if valid {
        Ok(e)
    } else {
        Err(AppError::Validation("invalid_email"))
    }
}

/// Senha: 12–128 caracteres (contados em chars, não bytes).
pub fn password(raw: &str) -> Result<(), AppError> {
    let n = raw.chars().count();
    if (PASSWORD_MIN..=PASSWORD_MAX).contains(&n) {
        Ok(())
    } else {
        Err(AppError::Validation("invalid_password"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn usernames() {
        assert_eq!(username("  Gui_123 ").unwrap(), "gui_123");
        assert!(username("ab").is_err());
        assert!(username("a".repeat(31).as_str()).is_err());
        assert!(username("gui.matos").is_err());
        assert!(username("gui matos").is_err());
        assert!(username("guí").is_err());
    }

    #[test]
    fn emails() {
        assert_eq!(email(" Gui@Example.COM ").unwrap(), "gui@example.com");
        assert!(email("gui").is_err());
        assert!(email("@example.com").is_err());
        assert!(email("gui@localhost").is_err());
        assert!(email("gui@.com").is_err());
        assert!(email("g ui@example.com").is_err());
        assert!(email("a@b@c.com").is_err());
    }

    #[test]
    fn passwords() {
        assert!(password("short").is_err());
        assert!(password("exatamente12").is_ok());
        assert!(password(&"x".repeat(129)).is_err());
        // 12 caracteres multibyte contam como 12
        assert!(password("çççççççççççç").is_ok());
    }
}

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

pub const DISPLAY_NAME_MAX: usize = 50;
pub const BIO_MAX: usize = 300;
pub const POST_MAX: usize = 5000;

/// Nome de exibição: 1–50 caracteres, sem caracteres de controle.
/// String vazia (após trim) significa "remover" → `None`.
pub fn display_name(raw: &str) -> Result<Option<String>, AppError> {
    let v = raw.trim();
    if v.is_empty() {
        return Ok(None);
    }
    if v.chars().count() > DISPLAY_NAME_MAX || v.chars().any(char::is_control) {
        return Err(AppError::Validation("invalid_display_name"));
    }
    Ok(Some(v.to_owned()))
}

/// Bio: até 300 caracteres; permite quebra de linha.
pub fn bio(raw: &str) -> Result<String, AppError> {
    let v = normalize_newlines(raw);
    let v = v.trim();
    if v.chars().count() > BIO_MAX || has_forbidden_control(v) {
        return Err(AppError::Validation("invalid_bio"));
    }
    Ok(v.to_owned())
}

/// Corpo de post: 1–5000 caracteres; permite quebra de linha e tab.
pub fn post_body(raw: &str) -> Result<String, AppError> {
    let v = normalize_newlines(raw);
    let v = v.trim();
    let n = v.chars().count();
    if n == 0 || n > POST_MAX || has_forbidden_control(v) {
        return Err(AppError::Validation("invalid_post_body"));
    }
    Ok(v.to_owned())
}

/// CRLF/CR → LF, para que textos vindos de qualquer plataforma sejam aceitos.
fn normalize_newlines(raw: &str) -> String {
    raw.replace("\r\n", "\n").replace('\r', "\n")
}

/// Caracteres de controle, exceto \n e \t. Inclui NUL, que o Postgres rejeita.
fn has_forbidden_control(v: &str) -> bool {
    v.chars().any(|c| c.is_control() && c != '\n' && c != '\t')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_names() {
        assert_eq!(display_name("  Gui  ").unwrap().as_deref(), Some("Gui"));
        assert_eq!(display_name("   ").unwrap(), None);
        assert!(display_name(&"x".repeat(51)).is_err());
        assert!(display_name("a\nb").is_err());
        assert!(display_name("Guilherme Matos 🌱").is_ok());
    }

    #[test]
    fn bios_and_posts() {
        assert!(bio("linha 1\nlinha 2").is_ok());
        assert!(bio(&"x".repeat(301)).is_err());
        assert!(post_body("   ").is_err());
        assert!(post_body("a\u{0}b").is_err());
        assert!(post_body("olá\n\tmundo").is_ok());
        assert_eq!(post_body("a\r\nb").unwrap(), "a\nb");
        assert!(post_body(&"é".repeat(5000)).is_ok());
        assert!(post_body(&"é".repeat(5001)).is_err());
    }

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

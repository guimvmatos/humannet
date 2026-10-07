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

pub const COMMENT_MAX: usize = 2000;

/// Comentário: 1–2000 caracteres; permite quebra de linha.
pub fn comment_body(raw: &str) -> Result<String, AppError> {
    let v = normalize_newlines(raw);
    let v = v.trim();
    let n = v.chars().count();
    if n == 0 || n > COMMENT_MAX || has_forbidden_control(v) {
        return Err(AppError::Validation("invalid_comment_body"));
    }
    Ok(v.to_owned())
}

// ---------------------------------------------------------------- comunidades

pub const COMMUNITY_TEXT_MAX: usize = 2000;
pub const TOPIC_TITLE_MAX: usize = 150;

pub const COMMUNITY_THEMES: &[&str] = &[
    "tecnologia",
    "musica",
    "cinema",
    "series",
    "livros",
    "games",
    "esportes",
    "arte",
    "culinaria",
    "viagens",
    "ciencia",
    "humor",
    "cidade",
    "educacao",
    "trabalho",
    "familia",
    "outros",
];

/// Endereço da comunidade: `[a-z0-9-]{3,40}`, sem hífen nas pontas.
pub fn community_slug(raw: &str) -> Result<String, AppError> {
    let s = raw.trim().to_ascii_lowercase();
    let ok = (3..=40).contains(&s.len())
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        && !s.starts_with('-')
        && !s.ends_with('-');
    if ok {
        Ok(s)
    } else {
        Err(AppError::Validation("invalid_community_slug"))
    }
}

/// Gera um endereço a partir do nome ("Música de Sampa!" → "musica-de-sampa").
pub fn slugify(name: &str) -> String {
    let mut out = String::new();
    for c in name.chars().flat_map(char::to_lowercase) {
        let c = match c {
            'á' | 'à' | 'â' | 'ã' | 'ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'í' | 'ì' | 'î' | 'ï' => 'i',
            'ó' | 'ò' | 'ô' | 'õ' | 'ö' => 'o',
            'ú' | 'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            'ñ' => 'n',
            c => c,
        };
        if c.is_ascii_alphanumeric() {
            out.push(c);
        } else if !out.is_empty() && !out.ends_with('-') {
            out.push('-');
        }
    }
    let mut s: String = out.trim_end_matches('-').chars().take(40).collect();
    while s.ends_with('-') {
        s.pop();
    }
    s
}

/// Nome da comunidade: 3–60 caracteres, sem caracteres de controle.
pub fn community_name(raw: &str) -> Result<String, AppError> {
    let v = raw.trim();
    let n = v.chars().count();
    if !(3..=60).contains(&n) || v.chars().any(char::is_control) {
        return Err(AppError::Validation("invalid_community_name"));
    }
    Ok(v.to_owned())
}

/// Descrição e regras: até 2000 caracteres, com quebras de linha.
pub fn community_text(raw: &str) -> Result<String, AppError> {
    let v = normalize_newlines(raw);
    let v = v.trim();
    if v.chars().count() > COMMUNITY_TEXT_MAX || has_forbidden_control(v) {
        return Err(AppError::Validation("invalid_community_text"));
    }
    Ok(v.to_owned())
}

pub fn community_theme(raw: &str) -> Result<String, AppError> {
    let v = raw.trim();
    if COMMUNITY_THEMES.contains(&v) {
        Ok(v.to_owned())
    } else {
        Err(AppError::Validation("invalid_community_theme"))
    }
}

/// Título de tópico: 3–150 caracteres, uma linha.
pub fn topic_title(raw: &str) -> Result<String, AppError> {
    let v = raw.trim();
    let n = v.chars().count();
    if !(3..=TOPIC_TITLE_MAX).contains(&n) || v.chars().any(char::is_control) {
        return Err(AppError::Validation("invalid_topic_title"));
    }
    Ok(v.to_owned())
}

/// Texto do tópico: até 5000 caracteres (pode ser vazio: só o título).
pub fn topic_body(raw: &str) -> Result<String, AppError> {
    let v = normalize_newlines(raw);
    let v = v.trim();
    if v.chars().count() > POST_MAX || has_forbidden_control(v) {
        return Err(AppError::Validation("invalid_topic_body"));
    }
    Ok(v.to_owned())
}

/// Resposta em tópico: 1–5000 caracteres.
pub fn reply_body(raw: &str) -> Result<String, AppError> {
    let v = normalize_newlines(raw);
    let v = v.trim();
    let n = v.chars().count();
    if n == 0 || n > POST_MAX || has_forbidden_control(v) {
        return Err(AppError::Validation("invalid_reply_body"));
    }
    Ok(v.to_owned())
}

/// Cidade natal, cidade atual, escola: até 80 caracteres, uma linha. "" = vazio.
pub fn place(raw: &str) -> Result<String, AppError> {
    let v = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    if v.chars().count() > 80 || v.chars().any(char::is_control) {
        return Err(AppError::Validation("invalid_place"));
    }
    Ok(v)
}

/// CPF: aceita com ou sem pontuação; confere os dígitos verificadores.
/// Devolve só os 11 dígitos. Não prova que o CPF é de quem digitou.
pub fn cpf(raw: &str) -> Result<String, AppError> {
    let d: Vec<u32> = raw
        .chars()
        .filter(|c| !matches!(c, '.' | '-' | ' '))
        .map(|c| c.to_digit(10))
        .collect::<Option<_>>()
        .ok_or(AppError::Validation("invalid_cpf"))?;
    if d.len() != 11 || d.iter().all(|x| *x == d[0]) {
        return Err(AppError::Validation("invalid_cpf"));
    }
    let check = |n: usize| {
        let sum: u32 = (0..n).map(|i| d[i] * (n as u32 + 1 - i as u32)).sum();
        let r = (sum * 10) % 11;
        if r == 10 { 0 } else { r }
    };
    if check(9) != d[9] || check(10) != d[10] {
        return Err(AppError::Validation("invalid_cpf"));
    }
    Ok(d.iter()
        .map(|x| char::from_digit(*x, 10).unwrap_or('0'))
        .collect())
}

pub const TESTIMONIAL_MAX: usize = 1000;

/// Depoimento: 1–1000 caracteres, com quebras de linha.
pub fn testimonial_body(raw: &str) -> Result<String, AppError> {
    let v = normalize_newlines(raw);
    let v = v.trim();
    let n = v.chars().count();
    if n == 0 || n > TESTIMONIAL_MAX || has_forbidden_control(v) {
        return Err(AppError::Validation("invalid_testimonial_body"));
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
    #[test]
    fn cpf_check_digits() {
        assert_eq!(super::cpf("529.982.247-25").unwrap(), "52998224725");
        assert!(super::cpf("529.982.247-24").is_err());
        assert!(super::cpf("111.111.111-11").is_err());
        assert!(super::cpf("1234").is_err());
        assert!(super::cpf("abc").is_err());
    }

    #[test]
    fn slugs() {
        assert_eq!(super::slugify("Música de Sampa!"), "musica-de-sampa");
        assert_eq!(super::slugify("  --Ação 2026--  "), "acao-2026");
        assert!(super::community_slug("ab").is_err());
        assert!(super::community_slug("-abc").is_err());
        assert_eq!(super::community_slug(" Rock-SP ").unwrap(), "rock-sp");
    }

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

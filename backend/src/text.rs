//! Normalização de nomes para busca e para evitar duplicatas
//! ("E.E. Prof. Júlio" e "ee prof julio" viram a mesma coisa).

/// Minúsculo, sem acento, sem pontuação, espaços simples.
/// Igual ao script que gerou os municípios (migrations).
pub fn normalize(raw: &str) -> String {
    let mut s = String::with_capacity(raw.len());
    for c in raw.to_lowercase().chars() {
        let c = match c {
            '.' => continue,
            'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' => 'a',
            'ç' => 'c',
            'è' | 'é' | 'ê' | 'ë' => 'e',
            'ì' | 'í' | 'î' | 'ï' => 'i',
            'ñ' => 'n',
            'ò' | 'ó' | 'ô' | 'õ' | 'ö' => 'o',
            'ù' | 'ú' | 'û' | 'ü' => 'u',
            'ý' | 'ÿ' => 'y',
            c if c.is_ascii_alphanumeric() => c,
            _ => ' ',
        };
        s.push(c);
    }
    let mut out = s.split_whitespace().collect::<Vec<_>>().join(" ");
    for (long, short) in [("escola estadual ", "ee "), ("escola municipal ", "em ")] {
        if let Some(rest) = out.strip_prefix(long) {
            out = format!("{short}{rest}");
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::normalize;

    #[test]
    fn normalizes_like_the_seed() {
        assert_eq!(normalize("São José dos Campos"), "sao jose dos campos");
        assert_eq!(normalize("E.E. Prof. Júlio"), "ee prof julio");
        assert_eq!(normalize("Escola Estadual  Dom Pedro"), "ee dom pedro");
        assert_eq!(normalize("  UFSCar - Sorocaba "), "ufscar sorocaba");
    }
}

//! Temas dos posts: lista fixa (tema → subtemas), marcada pelo autor ao
//! postar (até 3). O app usa os temas e as hashtags para o feed "Para você",
//! ordenado no próprio aparelho (ADR-0004, ADR-0007).

use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct Topic {
    pub id: &'static str,
    pub label: &'static str,
    pub sub: &'static [(&'static str, &'static str)],
}

pub const TOPICS: &[Topic] = &[
    Topic {
        id: "politica",
        label: "Política",
        sub: &[
            ("brasil", "Brasil"),
            ("mundo", "Mundo"),
            ("economia", "Economia"),
            ("eleicoes", "Eleições"),
        ],
    },
    Topic {
        id: "esportes",
        label: "Esportes",
        sub: &[
            ("futebol", "Futebol"),
            ("volei", "Vôlei"),
            ("basquete", "Basquete"),
            ("lutas", "Lutas"),
            ("corrida", "Corrida"),
        ],
    },
    Topic {
        id: "musica",
        label: "Música",
        sub: &[],
    },
    Topic {
        id: "cinema-series",
        label: "Cinema e séries",
        sub: &[],
    },
    Topic {
        id: "games",
        label: "Games",
        sub: &[],
    },
    Topic {
        id: "tecnologia",
        label: "Tecnologia",
        sub: &[],
    },
    Topic {
        id: "ciencia",
        label: "Ciência",
        sub: &[],
    },
    Topic {
        id: "universidade",
        label: "Faculdade e estudos",
        sub: &[],
    },
    Topic {
        id: "trabalho",
        label: "Trabalho e carreira",
        sub: &[],
    },
    Topic {
        id: "humor",
        label: "Humor",
        sub: &[],
    },
    Topic {
        id: "comida",
        label: "Comida",
        sub: &[],
    },
    Topic {
        id: "viagem",
        label: "Viagem",
        sub: &[],
    },
    Topic {
        id: "natureza",
        label: "Natureza e animais",
        sub: &[],
    },
    Topic {
        id: "saude",
        label: "Saúde e bem-estar",
        sub: &[],
    },
    Topic {
        id: "arte",
        label: "Arte e cultura",
        sub: &[],
    },
    Topic {
        id: "eventos",
        label: "Eventos e rolês",
        sub: &[],
    },
    Topic {
        id: "cidade",
        label: "Cidade e bairro",
        sub: &[
            ("transito", "Trânsito"),
            ("clima", "Clima e alertas"),
            ("seguranca", "Segurança"),
        ],
    },
    Topic {
        id: "vida",
        label: "Vida pessoal",
        sub: &[],
    },
];

/// "politica" ou "politica.eleicoes" válidos.
pub fn valid(id: &str) -> bool {
    let (main, sub) = match id.split_once('.') {
        Some((m, s)) => (m, Some(s)),
        None => (id, None),
    };
    TOPICS
        .iter()
        .any(|t| t.id == main && sub.is_none_or(|s| t.sub.iter().any(|(sid, _)| *sid == s)))
}

/// Hashtags do texto: minúsculas, sem acento, até 10, sem repetir.
pub fn hashtags(body: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for word in body.split(|c: char| c.is_whitespace()) {
        let Some(tag) = word.strip_prefix('#') else {
            continue;
        };
        let tag: String = crate::text::normalize(tag)
            .chars()
            .filter(char::is_ascii_alphanumeric)
            .take(40)
            .collect();
        if tag.len() >= 2 && !tag.chars().all(|c| c.is_ascii_digit()) && !out.contains(&tag) {
            out.push(tag);
        }
        if out.len() == 10 {
            break;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn topics_and_hashtags() {
        assert!(valid("politica"));
        assert!(valid("politica.eleicoes"));
        assert!(valid("cidade.transito"));
        assert!(!valid("politica.esquerda"));
        assert!(!valid("nada"));
        assert_eq!(
            hashtags("Chuva forte! #Alagamento na #Itavuvu #alagamento #2026 #ReformaTributária."),
            vec!["alagamento", "itavuvu", "reformatributaria"]
        );
    }
}

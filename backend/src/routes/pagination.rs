use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const DEFAULT_LIMIT: i64 = 20;
pub const MAX_LIMIT: i64 = 50;

/// Paginação por cursor: `before` é o id (UUID v7) do último item recebido.
/// Mais estável que offset para listas que crescem no topo.
#[derive(Debug, Deserialize)]
pub struct PageQuery {
    pub before: Option<Uuid>,
    pub limit: Option<i64>,
}

impl PageQuery {
    pub fn limit(&self) -> i64 {
        self.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
    }
}

#[derive(Debug, Serialize)]
pub struct Page<T> {
    pub items: Vec<T>,
    /// `None` = fim da lista. O app mostra "você está em dia" (sem rolagem infinita, R6).
    pub next_cursor: Option<Uuid>,
}

impl<T> Page<T> {
    /// Recebe até `limit + 1` itens; o item extra só indica que há próxima página.
    pub fn from_overfetch(mut items: Vec<T>, limit: i64, id_of: impl Fn(&T) -> Uuid) -> Self {
        let limit = usize::try_from(limit).unwrap_or(0);
        let has_more = items.len() > limit;
        items.truncate(limit);
        let next_cursor = if has_more {
            items.last().map(id_of)
        } else {
            None
        };
        Self { items, next_cursor }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overfetch() {
        let ids: Vec<Uuid> = (0..3).map(|_| Uuid::now_v7()).collect();
        let p = Page::from_overfetch(ids.clone(), 2, |u| *u);
        assert_eq!(p.items.len(), 2);
        assert_eq!(p.next_cursor, Some(ids[1]));

        let p = Page::from_overfetch(ids[..2].to_vec(), 2, |u| *u);
        assert_eq!(p.next_cursor, None);
    }

    #[test]
    fn limit_is_clamped() {
        let q = |l| PageQuery {
            before: None,
            limit: l,
        };
        assert_eq!(q(None).limit(), DEFAULT_LIMIT);
        assert_eq!(q(Some(0)).limit(), 1);
        assert_eq!(q(Some(1000)).limit(), MAX_LIMIT);
    }
}

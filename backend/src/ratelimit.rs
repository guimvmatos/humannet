//! Limite de tentativas falhas em memória (janela deslizante).
//!
//! Suficiente para uma instância única (beta). Com várias instâncias, migrar
//! para um armazenamento compartilhado (ex.: tabela no Postgres ou Redis).

use std::{
    collections::{HashMap, VecDeque},
    sync::Mutex,
    time::{Duration, Instant},
};

use axum::http::HeaderMap;

pub struct FailureLimiter {
    max: usize,
    window: Duration,
    hits: Mutex<HashMap<String, VecDeque<Instant>>>,
}

/// Teto de chaves guardadas, para não crescer sem limite sob ataque.
const MAX_KEYS: usize = 100_000;

impl FailureLimiter {
    pub fn new(max: usize, window: Duration) -> Self {
        Self {
            max,
            window,
            hits: Mutex::new(HashMap::new()),
        }
    }

    fn prune(q: &mut VecDeque<Instant>, now: Instant, window: Duration) {
        while q.front().is_some_and(|t| now.duration_since(*t) > window) {
            q.pop_front();
        }
    }

    /// `true` se a chave já atingiu o limite de falhas na janela.
    pub fn is_blocked(&self, key: &str) -> bool {
        let now = Instant::now();
        let mut map = self.hits.lock().expect("limiter lock");
        match map.get_mut(key) {
            Some(q) => {
                Self::prune(q, now, self.window);
                q.len() >= self.max
            }
            None => false,
        }
    }

    pub fn record_failure(&self, key: &str) {
        let now = Instant::now();
        let mut map = self.hits.lock().expect("limiter lock");
        if map.len() >= MAX_KEYS {
            let window = self.window;
            map.retain(|_, q| {
                Self::prune(q, now, window);
                !q.is_empty()
            });
            if map.len() >= MAX_KEYS {
                map.clear();
            }
        }
        let q = map.entry(key.to_owned()).or_default();
        Self::prune(q, now, self.window);
        q.push_back(now);
    }

    pub fn clear(&self, key: &str) {
        self.hits.lock().expect("limiter lock").remove(key);
    }
}

/// Limites de autenticação.
pub struct AuthLimits {
    /// Falhas de login por conta.
    pub per_login: FailureLimiter,
    /// Falhas de login/redefinição por IP.
    pub per_ip: FailureLimiter,
}

impl Default for AuthLimits {
    fn default() -> Self {
        let window = Duration::from_secs(15 * 60);
        Self {
            per_login: FailureLimiter::new(10, window),
            per_ip: FailureLimiter::new(50, window),
        }
    }
}

/// IP do cliente. Atrás do proxy do Render, é o primeiro valor de
/// `X-Forwarded-For`; sem o cabeçalho, todos caem na mesma chave.
pub fn client_ip(headers: &HeaderMap) -> String {
    headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next())
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty() && s.len() <= 64)
        .unwrap_or_else(|| "unknown".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_after_max_and_clears() {
        let l = FailureLimiter::new(3, Duration::from_secs(60));
        for _ in 0..3 {
            assert!(!l.is_blocked("k"));
            l.record_failure("k");
        }
        assert!(l.is_blocked("k"));
        assert!(!l.is_blocked("outra"));
        l.clear("k");
        assert!(!l.is_blocked("k"));
    }

    #[test]
    fn window_expires() {
        let l = FailureLimiter::new(1, Duration::from_millis(20));
        l.record_failure("k");
        assert!(l.is_blocked("k"));
        std::thread::sleep(Duration::from_millis(30));
        assert!(!l.is_blocked("k"));
    }

    #[test]
    fn forwarded_for() {
        let mut h = HeaderMap::new();
        assert_eq!(client_ip(&h), "unknown");
        h.insert("x-forwarded-for", "1.2.3.4, 10.0.0.1".parse().unwrap());
        assert_eq!(client_ip(&h), "1.2.3.4");
    }
}

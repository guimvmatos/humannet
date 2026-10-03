use std::{env, net::SocketAddr, str::FromStr};

use anyhow::{Context, Result};

#[derive(Clone, Debug)]
pub struct Config {
    pub database_url: String,
    pub bind_addr: SocketAddr,
    pub log_json: bool,
    pub session_ttl_days: i64,
    pub invite_ttl_days: i64,
    pub max_active_invites: i64,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        Ok(Self {
            database_url: env::var("DATABASE_URL").context("DATABASE_URL não definida")?,
            bind_addr: parse_or("BIND_ADDR", "0.0.0.0:8080")?,
            log_json: env::var("LOG_FORMAT").is_ok_and(|v| v == "json"),
            session_ttl_days: parse_or("SESSION_TTL_DAYS", "30")?,
            invite_ttl_days: parse_or("INVITE_TTL_DAYS", "14")?,
            max_active_invites: parse_or("MAX_ACTIVE_INVITES", "5")?,
        })
    }
}

/// Políticas de negócio usadas pelos handlers (separadas do Config de infraestrutura
/// para facilitar testes).
#[derive(Clone, Debug)]
pub struct Policy {
    pub session_ttl_days: i64,
    pub invite_ttl_days: i64,
    pub max_active_invites: i64,
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            session_ttl_days: 30,
            invite_ttl_days: 14,
            max_active_invites: 5,
        }
    }
}

impl From<&Config> for Policy {
    fn from(c: &Config) -> Self {
        Self {
            session_ttl_days: c.session_ttl_days,
            invite_ttl_days: c.invite_ttl_days,
            max_active_invites: c.max_active_invites,
        }
    }
}

fn parse_or<T>(key: &str, default: &str) -> Result<T>
where
    T: FromStr,
    T::Err: std::error::Error + Send + Sync + 'static,
{
    let raw = env::var(key).unwrap_or_else(|_| default.to_owned());
    raw.parse::<T>()
        .with_context(|| format!("valor inválido para {key}"))
}

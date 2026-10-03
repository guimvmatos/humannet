//! Extractor de usuário autenticado (Bearer token opaco).

use axum::{
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts},
};
use uuid::Uuid;

use crate::{AppState, crypto, error::AppError};

/// Usuário autenticado na requisição. Use como argumento de handler para
/// exigir autenticação.
#[derive(Clone, Debug)]
pub struct AuthUser {
    pub user_id: Uuid,
    pub session_id: Uuid,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let token = bearer_token(parts).ok_or(AppError::Unauthorized)?;
        let token_hash = crypto::sha256(token);

        let row = sqlx::query!(
            r#"
            SELECT id, user_id
            FROM sessions
            WHERE token_hash = $1 AND expires_at > now()
            "#,
            token_hash
        )
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::Unauthorized)?;

        Ok(Self {
            user_id: row.user_id,
            session_id: row.id,
        })
    }
}

fn bearer_token(parts: &Parts) -> Option<&str> {
    let value = parts.headers.get(AUTHORIZATION)?.to_str().ok()?;
    let (scheme, token) = value.split_once(' ')?;
    if !scheme.eq_ignore_ascii_case("bearer") {
        return None;
    }
    let token = token.trim();
    // Tokens válidos têm 43 chars base64url; rejeita lixo antes de ir ao banco.
    (token.len() == 43
        && token
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_'))
    .then_some(token)
}

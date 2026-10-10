//! Termos de Uso e Política de Privacidade: textos públicos e aceite.

use axum::{
    Json,
    extract::State,
    http::{StatusCode, header},
    response::IntoResponse,
};
use serde::Deserialize;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
};

/// Versão vigente. Subir quando os textos mudarem de forma importante: o app
/// pede novo aceite a quem aceitou uma versão anterior.
pub const TERMS_VERSION: i16 = 1;

pub const TERMS: &str = include_str!("../../legal/termos.md");
pub const PRIVACY: &str = include_str!("../../legal/privacidade.md");

fn markdown(body: &'static str) -> impl IntoResponse {
    (
        [
            (header::CONTENT_TYPE, "text/markdown; charset=utf-8"),
            (header::CACHE_CONTROL, "public, max-age=3600"),
        ],
        body,
    )
}

/// GET /legal/termos — público (link para a loja e para o cadastro).
pub async fn terms() -> impl IntoResponse {
    markdown(TERMS)
}

/// GET /legal/privacidade — público.
pub async fn privacy() -> impl IntoResponse {
    markdown(PRIVACY)
}

/// Confere o aceite enviado no cadastro ou em `PUT /v1/me/terms`.
pub fn check(version: Option<i16>) -> AppResult<()> {
    if version == Some(TERMS_VERSION) {
        Ok(())
    } else {
        Err(AppError::Validation("terms_required"))
    }
}

#[derive(Deserialize)]
pub struct AcceptTerms {
    pub version: i16,
}

/// PUT /v1/me/terms `{version}` — aceita a versão vigente.
pub async fn accept(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<AcceptTerms>,
) -> AppResult<StatusCode> {
    check(Some(req.version))?;
    sqlx::query!(
        "UPDATE users SET terms_version = $2, terms_accepted_at = now() WHERE id = $1",
        user.user_id,
        req.version
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

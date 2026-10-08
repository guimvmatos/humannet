//! Registro dos aparelhos para notificações push.

use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use serde::Deserialize;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
};

/// Aparelhos por conta; o mais antigo sai quando passa disso.
const MAX_DEVICES: i64 = 10;

#[derive(Deserialize)]
pub struct DeviceReq {
    pub token: String,
}

fn valid_token(raw: &str) -> AppResult<&str> {
    let t = raw.trim();
    let ok = (1..=4096).contains(&t.len())
        && t.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_:.".contains(&b));
    if ok {
        Ok(t)
    } else {
        Err(AppError::Validation("invalid_device_token"))
    }
}

/// PUT /v1/me/devices `{token}` — este aparelho passa a receber avisos desta
/// conta (se outra conta usava o mesmo aparelho, deixa de receber).
pub async fn register(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<DeviceReq>,
) -> AppResult<StatusCode> {
    let token = valid_token(&req.token)?;
    sqlx::query!(
        "INSERT INTO push_devices (token, user_id) VALUES ($1, $2)
         ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, updated_at = now()",
        token,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    sqlx::query!(
        "DELETE FROM push_devices WHERE user_id = $1 AND token NOT IN (
           SELECT token FROM push_devices WHERE user_id = $1
           ORDER BY updated_at DESC LIMIT $2)",
        user.user_id,
        MAX_DEVICES
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/me/devices/{token} — ao sair da conta. Idempotente.
pub async fn unregister(
    State(state): State<AppState>,
    user: AuthUser,
    Path(token): Path<String>,
) -> AppResult<StatusCode> {
    let token = valid_token(&token)?;
    sqlx::query!(
        "DELETE FROM push_devices WHERE token = $1 AND user_id = $2",
        token,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

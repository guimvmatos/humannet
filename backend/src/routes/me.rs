use axum::{Json, extract::State};
use serde::Serialize;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{AppState, auth::AuthUser, error::AppResult};

/// Dados do próprio usuário. Contém o e-mail: nunca usar para exibir terceiros.
#[derive(Debug, Serialize)]
pub struct UserDto {
    pub id: Uuid,
    pub username: String,
    pub email: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
}

/// GET /v1/me
pub async fn get(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<UserDto>> {
    let me = sqlx::query_as!(
        UserDto,
        "SELECT id, username, email, created_at FROM users WHERE id = $1",
        user.user_id
    )
    .fetch_one(&state.db)
    .await?;
    Ok(Json(me))
}

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
    pub display_name: Option<String>,
    pub bio: String,
    /// "user" ou "admin".
    pub role: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    /// Conta antiga sem CPF, com CPF obrigatório: o app pede antes de seguir.
    pub needs_cpf: bool,
}

impl UserDto {
    /// `needs_cpf` só vale se o servidor exige CPF.
    pub fn with_policy(mut self, state: &AppState) -> Self {
        self.needs_cpf &= state.policy.cpf_key.is_some();
        self
    }
}

/// GET /v1/me
pub async fn get(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<UserDto>> {
    let me = sqlx::query_as!(
        UserDto,
        r#"SELECT id, username, email, display_name, bio, role, created_at,
                  (cpf_hmac IS NULL) AS "needs_cpf!"
           FROM users WHERE id = $1"#,
        user.user_id
    )
    .fetch_one(&state.db)
    .await?;
    Ok(Json(me.with_policy(&state)))
}

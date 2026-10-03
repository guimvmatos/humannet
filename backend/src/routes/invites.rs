use axum::{Json, extract::State, http::StatusCode};
use serde::Serialize;
use sqlx::PgExecutor;
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

use crate::{AppState, auth::AuthUser, crypto, error::AppResult};

#[derive(Debug, Serialize)]
pub struct InviteCreated {
    /// O código em claro só é devolvido uma vez, na criação.
    pub code: String,
    #[serde(with = "time::serde::rfc3339")]
    pub expires_at: OffsetDateTime,
}

/// Cria um convite. `created_by = None` é usado pela CLI de administração.
pub async fn create_invite<'e>(
    db: impl PgExecutor<'e>,
    created_by: Option<Uuid>,
    ttl_days: i64,
) -> sqlx::Result<InviteCreated> {
    let code = crypto::new_invite_code();
    let expires_at = OffsetDateTime::now_utc() + Duration::days(ttl_days);
    sqlx::query!(
        "INSERT INTO invites (id, code_hash, created_by, expires_at) VALUES ($1, $2, $3, $4)",
        Uuid::now_v7(),
        crypto::sha256(&code),
        created_by,
        expires_at,
    )
    .execute(db)
    .await?;
    Ok(InviteCreated { code, expires_at })
}

/// POST /v1/invites — usuário autenticado gera um convite, até o limite de ativos.
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<(StatusCode, Json<InviteCreated>)> {
    // Lock por usuário evita corrida entre duas requisições simultâneas
    // ultrapassando o limite.
    let mut tx = state.db.begin().await?;
    sqlx::query!(
        "SELECT id FROM users WHERE id = $1 FOR UPDATE",
        user.user_id
    )
    .fetch_one(&mut *tx)
    .await?;

    let active = sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "count!"
        FROM invites
        WHERE created_by = $1 AND used_at IS NULL AND expires_at > now()
        "#,
        user.user_id
    )
    .fetch_one(&mut *tx)
    .await?;

    if active >= state.policy.max_active_invites {
        return Err(crate::error::AppError::LimitReached("invite_limit"));
    }

    let invite = create_invite(&mut *tx, Some(user.user_id), state.policy.invite_ttl_days).await?;
    tx.commit().await?;

    Ok((StatusCode::CREATED, Json(invite)))
}

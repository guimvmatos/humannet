use axum::{
    Json,
    extract::{Path, State},
};
use serde::{Deserialize, Serialize};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    routes::{
        friends::{self, Relation},
        me::UserDto,
    },
    validation,
};

/// Perfil visto por qualquer usuário autenticado.
#[derive(Debug, Serialize)]
pub struct ProfileDto {
    pub id: Uuid,
    pub username: String,
    pub display_name: Option<String>,
    pub bio: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    pub is_self: bool,
    /// self | none | friends | request_sent | request_received (ADR-0006).
    pub relation: Relation,
    /// Contagens são privadas (R3): só presentes no próprio perfil.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stats: Option<ProfileStats>,
}

#[derive(Debug, Serialize)]
pub struct ProfileStats {
    pub friends: i64,
    pub posts: i64,
    /// Pedidos de amizade recebidos e ainda não respondidos.
    pub pending_requests: i64,
}

/// Resolve um username (normalizado) para id. Username inválido = não encontrado.
pub async fn user_id_by_username(state: &AppState, raw: &str) -> AppResult<Uuid> {
    let username = validation::username(raw).map_err(|_| AppError::NotFound)?;
    sqlx::query_scalar!("SELECT id FROM users WHERE username = $1", username)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)
}

/// GET /v1/users/{username}
pub async fn get(
    State(state): State<AppState>,
    viewer: AuthUser,
    Path(username): Path<String>,
) -> AppResult<Json<ProfileDto>> {
    let id = user_id_by_username(&state, &username).await?;

    let row = sqlx::query!(
        r#"
        SELECT u.id, u.username, u.display_name, u.bio, u.created_at
        FROM users u
        WHERE u.id = $1
        "#,
        id
    )
    .fetch_one(&state.db)
    .await?;

    let relation = friends::relation(&state.db, viewer.user_id, row.id).await?;
    let is_self = relation == Relation::Myself;
    let stats = if is_self {
        Some(
            sqlx::query_as!(
                ProfileStats,
                r#"
                SELECT
                  (SELECT count(*) FROM friends WHERE user_id = $1) AS "friends!",
                  (SELECT count(*) FROM posts WHERE author_id = $1 AND deleted_at IS NULL) AS "posts!",
                  (SELECT count(*) FROM friend_requests WHERE to_id = $1) AS "pending_requests!"
                "#,
                row.id
            )
            .fetch_one(&state.db)
            .await?,
        )
    } else {
        None
    };

    Ok(Json(ProfileDto {
        id: row.id,
        username: row.username,
        display_name: row.display_name,
        bio: row.bio,
        created_at: row.created_at,
        is_self,
        relation,
        stats,
    }))
}

#[derive(Debug, Deserialize)]
pub struct UpdateProfile {
    /// Ausente = não altera; "" = remove.
    pub display_name: Option<String>,
    /// Ausente = não altera.
    pub bio: Option<String>,
}

/// PATCH /v1/me/profile
pub async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<UpdateProfile>,
) -> AppResult<Json<UserDto>> {
    let display_name = req
        .display_name
        .as_deref()
        .map(validation::display_name)
        .transpose()?;
    let bio = req.bio.as_deref().map(validation::bio).transpose()?;

    let me = sqlx::query_as!(
        UserDto,
        r#"
        UPDATE users SET
          display_name = CASE WHEN $2 THEN $3 ELSE display_name END,
          bio          = COALESCE($4, bio)
        WHERE id = $1
        RETURNING id, username, email, display_name, bio, created_at
        "#,
        user.user_id,
        display_name.is_some(),
        display_name.flatten(),
        bio,
    )
    .fetch_one(&state.db)
    .await?;

    Ok(Json(me))
}

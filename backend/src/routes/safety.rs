//! Fase 1b: bloqueio e denúncias.
//!
//! Bloqueio: bidirecional e invisível. Desfaz amizade e pedidos; nenhum dos
//! dois encontra o outro (perfil, posts, pedido de amizade → "não encontrado").

use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use serde::Deserialize;
use sqlx::PgExecutor;
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    routes::{
        friends::{self, ListDto},
        posts::AuthorDto,
        profiles::user_id_by_username,
    },
};

/// Máximo de denúncias por pessoa em 24 h (anti-abuso do próprio botão).
pub const MAX_REPORTS_PER_DAY: i64 = 20;

pub async fn is_blocked_either_way<'e>(
    db: impl PgExecutor<'e>,
    a: Uuid,
    b: Uuid,
) -> sqlx::Result<bool> {
    sqlx::query_scalar!(
        r#"
        SELECT EXISTS (
          SELECT 1 FROM blocks
          WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)
        ) AS "e!"
        "#,
        a,
        b
    )
    .fetch_one(db)
    .await
}

/// PUT /v1/users/{username}/block — idempotente.
pub async fn block(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
) -> AppResult<StatusCode> {
    let me = user.user_id;
    let other = user_id_by_username(&state, &username).await?;
    if other == me {
        return Err(AppError::Validation("cannot_block_self"));
    }
    let mut tx = state.db.begin().await?;
    friends::lock_pair(&mut tx, me, other).await?;
    sqlx::query!(
        "INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        me,
        other
    )
    .execute(&mut *tx)
    .await?;
    let (a, b) = if me < other { (me, other) } else { (other, me) };
    sqlx::query!(
        "DELETE FROM friendships WHERE user_a = $1 AND user_b = $2",
        a,
        b
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "DELETE FROM friend_requests WHERE (from_id = $1 AND to_id = $2) OR (from_id = $2 AND to_id = $1)",
        me,
        other
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    tracing::info!(blocker = %me, "user blocked");
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/users/{username}/block — idempotente. A amizade não volta.
pub async fn unblock(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
) -> AppResult<StatusCode> {
    let other = user_id_by_username(&state, &username).await?;
    sqlx::query!(
        "DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2",
        user.user_id,
        other
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /v1/blocks — quem eu bloqueei.
pub async fn list_blocks(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<AuthorDto>>> {
    let items = sqlx::query_as!(
        AuthorDto,
        r#"
        SELECT u.id, u.username, u.display_name
        FROM blocks b JOIN users u ON u.id = b.blocked_id
        WHERE b.blocker_id = $1
        ORDER BY b.created_at DESC
        "#,
        user.user_id
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto { items }))
}

// ---------------------------------------------------------------- denúncias

const REASONS: &[&str] = &[
    "spam",
    "harassment",
    "hate",
    "violence",
    "sexual",
    "minor_safety",
    "self_harm",
    "misinformation",
    "impersonation",
    "other",
];

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ReportTarget {
    Post { post_id: Uuid },
    User { username: String },
}

#[derive(Debug, Deserialize)]
pub struct CreateReport {
    #[serde(flatten)]
    pub target: ReportTarget,
    pub reason: String,
    #[serde(default)]
    pub details: String,
}

/// POST /v1/reports — 202 Accepted. Idempotente enquanto a denúncia estiver aberta.
pub async fn report(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreateReport>,
) -> AppResult<StatusCode> {
    let me = user.user_id;
    if !REASONS.contains(&req.reason.as_str()) {
        return Err(AppError::Validation("invalid_report_reason"));
    }
    let details = req.details.trim();
    if details.chars().count() > 1000 {
        return Err(AppError::Validation("invalid_report_details"));
    }

    // Resolve o alvo e guarda uma cópia do conteúdo (evidência para moderação).
    let (kind, target_id, snapshot) = match &req.target {
        ReportTarget::Post { post_id } => {
            let post = sqlx::query!(
                "SELECT author_id, body FROM posts WHERE id = $1 AND deleted_at IS NULL",
                post_id
            )
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
            if post.author_id == me {
                return Err(AppError::Validation("cannot_report_self"));
            }
            // Só denuncia o que consegue ver.
            if !friends::can_see_content(&state.db, me, post.author_id).await? {
                return Err(AppError::NotFound);
            }
            ("post", *post_id, post.body)
        }
        ReportTarget::User { username } => {
            let id = user_id_by_username(&state, username).await?;
            if id == me {
                return Err(AppError::Validation("cannot_report_self"));
            }
            let profile = sqlx::query!(
                "SELECT username, coalesce(display_name, '') AS \"display_name!\", bio FROM users WHERE id = $1",
                id
            )
            .fetch_one(&state.db)
            .await?;
            let snap = format!(
                "@{} | {} | {}",
                profile.username, profile.display_name, profile.bio
            );
            ("user", id, snap)
        }
    };

    let recent = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM reports
           WHERE reporter_id = $1 AND created_at > now() - interval '24 hours'"#,
        me
    )
    .fetch_one(&state.db)
    .await?;
    if recent >= MAX_REPORTS_PER_DAY {
        return Err(AppError::LimitReached("report_limit"));
    }

    let snapshot: String = snapshot.chars().take(5000).collect();
    sqlx::query!(
        r#"
        INSERT INTO reports (id, reporter_id, target_kind, target_id, snapshot, reason, details)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (reporter_id, target_kind, target_id) WHERE status = 'open' DO NOTHING
        "#,
        Uuid::now_v7(),
        me,
        kind,
        target_id,
        snapshot,
        req.reason,
        details,
    )
    .execute(&state.db)
    .await?;
    tracing::info!(kind, reason = %req.reason, "report received");
    Ok(StatusCode::ACCEPTED)
}

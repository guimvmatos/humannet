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
        communities,
        friends::{self, ListDto},
        posts::{AuthorDto, visible_post_author},
        profiles::user_id_by_username,
        topics,
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
    sqlx::query!(
        "DELETE FROM testimonials WHERE (author_id = $1 AND recipient_id = $2) OR (author_id = $2 AND recipient_id = $1)",
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
        SELECT u.id, u.username, u.display_name, NULL::text AS avatar_url
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
    Comment { comment_id: Uuid },
    Topic { topic_id: Uuid },
    Reply { reply_id: Uuid },
    Community { slug: String },
    Testimonial { testimonial_id: Uuid },
    Scrap { scrap_id: Uuid },
    Page { slug: String },
    Event { event_id: Uuid },
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
    // Só se denuncia o que se consegue ver.
    let (kind, target_id, snapshot, target_user) = match &req.target {
        ReportTarget::Post { post_id } => {
            let post = sqlx::query!(
                "SELECT author_id, body FROM posts WHERE id = $1 AND deleted_at IS NULL",
                post_id
            )
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
            if !friends::can_see_content(&state.db, me, post.author_id).await? {
                return Err(AppError::NotFound);
            }
            ("post", *post_id, post.body, post.author_id)
        }
        ReportTarget::User { username } => {
            let id = user_id_by_username(&state, username).await?;
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
            ("user", id, snap, id)
        }
        ReportTarget::Comment { comment_id } => {
            let c = sqlx::query!(
                "SELECT post_id, author_id, body FROM comments WHERE id = $1 AND deleted_at IS NULL",
                comment_id
            )
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
            visible_post_author(&state, me, c.post_id).await?;
            if is_blocked_either_way(&state.db, me, c.author_id).await? {
                return Err(AppError::NotFound);
            }
            ("comment", *comment_id, c.body, c.author_id)
        }
        ReportTarget::Topic { topic_id } => {
            let t = topics::get(State(state.clone()), user.clone(), Path(*topic_id))
                .await?
                .0;
            (
                "topic",
                *topic_id,
                format!("{}\n\n{}", t.title, t.body),
                t.author.id,
            )
        }
        ReportTarget::Reply { reply_id } => {
            let r = sqlx::query!(
                "SELECT topic_id, author_id, body FROM topic_replies WHERE id = $1 AND deleted_at IS NULL",
                reply_id
            )
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
            // Garante que quem denuncia consegue ler o tópico.
            topics::ensure_readable(&state, &user, r.topic_id).await?;
            if is_blocked_either_way(&state.db, me, r.author_id).await? {
                return Err(AppError::NotFound);
            }
            ("reply", *reply_id, r.body, r.author_id)
        }
        ReportTarget::Community { slug } => {
            let c = communities::load_by_slug(&state, slug).await?;
            let owner = sqlx::query_scalar!(
                "SELECT user_id FROM community_members WHERE community_id = $1 AND role = 'owner'",
                c.id
            )
            .fetch_one(&state.db)
            .await?;
            let snap = format!(
                "{} ({})\n\n{}\n\nRegras: {}",
                c.name, c.slug, c.description, c.rules
            );
            ("community", c.id, snap, owner)
        }
        ReportTarget::Testimonial { testimonial_id } => {
            // Visível para quem consegue ler: dono do perfil, amigos (se aprovado) e autor.
            let t = sqlx::query!(
                "SELECT author_id, recipient_id, body, status FROM testimonials WHERE id = $1",
                testimonial_id
            )
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
            let visible = me == t.recipient_id
                || (t.status == "approved"
                    && friends::can_see_content(&state.db, me, t.recipient_id).await?
                    && !is_blocked_either_way(&state.db, me, t.author_id).await?);
            if !visible {
                return Err(AppError::NotFound);
            }
            ("testimonial", *testimonial_id, t.body, t.author_id)
        }
        ReportTarget::Scrap { scrap_id } => {
            let s = sqlx::query!(
                "SELECT author_id, recipient_id, body FROM scraps WHERE id = $1",
                scrap_id
            )
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
            if !friends::can_see_content(&state.db, me, s.recipient_id).await?
                || is_blocked_either_way(&state.db, me, s.author_id).await?
            {
                return Err(AppError::NotFound);
            }
            ("scrap", *scrap_id, s.body, s.author_id)
        }
        ReportTarget::Page { slug } => {
            let p = crate::routes::pages::load(&state, slug).await?;
            let owner = sqlx::query_scalar!(
                "SELECT user_id FROM page_admins WHERE page_id = $1 AND role = 'owner'",
                p.id
            )
            .fetch_optional(&state.db)
            .await?
            .unwrap_or(Uuid::nil());
            let snap = format!(
                "{} ({}) CNPJ {}\n\n{}",
                p.name, p.slug, p.cnpj, p.description
            );
            ("page", p.id, snap, owner)
        }
        ReportTarget::Event { event_id } => {
            let e = sqlx::query!(
                "SELECT e.title, e.description, e.page_id, e.created_by FROM events e
                 WHERE e.id = $1 AND e.deleted_at IS NULL",
                event_id
            )
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
            let author = e.created_by.unwrap_or(Uuid::nil());
            (
                "event",
                *event_id,
                format!("{}\n\n{}", e.title, e.description),
                author,
            )
        }
    };
    if target_user == me {
        return Err(AppError::Validation("cannot_report_self"));
    }

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
        INSERT INTO reports (id, reporter_id, target_kind, target_id, snapshot, reason, details,
                             target_user_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (reporter_id, target_kind, target_id) WHERE status = 'open' DO NOTHING
        "#,
        Uuid::now_v7(),
        me,
        kind,
        target_id,
        snapshot,
        req.reason,
        details,
        (!target_user.is_nil()).then_some(target_user),
    )
    .execute(&state.db)
    .await?;
    tracing::info!(kind, reason = %req.reason, "report received");
    Ok(StatusCode::ACCEPTED)
}

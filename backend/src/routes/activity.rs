//! Avisos no app (sem push): contadores para as bolinhas das abas e a lista
//! de novidades — comentários nos meus posts e respostas nos tópicos em que
//! participo. Sem curtidas (R3/R6: nada de métrica de vaidade).

use axum::{Json, extract::State, http::StatusCode};
use serde::Serialize;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    error::AppResult,
    routes::{friends::ListDto, posts::AuthorDto},
};

/// Janela das novidades.
const WINDOW_DAYS: i32 = 30;

#[derive(Debug, Serialize)]
pub struct CountsDto {
    /// Pedidos de amizade recebidos.
    pub friend_requests: i64,
    /// Depoimentos esperando minha aprovação.
    pub pending_testimonials: i64,
    /// Pedidos para entrar em comunidades que eu modero.
    pub community_requests: i64,
    /// Novidades (comentários e respostas) ainda não vistas.
    pub unread_activity: i64,
}

/// GET /v1/me/counts
pub async fn counts(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<CountsDto>> {
    let me = user.user_id;
    let r = sqlx::query!(
        r#"
        WITH seen AS (SELECT activity_seen_at AS t FROM users WHERE id = $1)
        SELECT
          (SELECT count(*) FROM friend_requests WHERE to_id = $1) AS "friend_requests!",
          (SELECT count(*) FROM testimonials
            WHERE recipient_id = $1 AND status = 'pending') AS "pending_testimonials!",
          (SELECT count(*) FROM community_members p
            JOIN community_members m ON m.community_id = p.community_id
            JOIN communities c ON c.id = p.community_id AND c.deleted_at IS NULL
            WHERE m.user_id = $1 AND m.status = 'active' AND m.role IN ('owner', 'moderator')
              AND p.status = 'pending') AS "community_requests!",
          (SELECT count(*) FROM comments c JOIN posts p ON p.id = c.post_id
            WHERE p.author_id = $1 AND c.author_id <> $1
              AND c.deleted_at IS NULL AND p.deleted_at IS NULL
              AND c.created_at > (SELECT t FROM seen)
              AND NOT EXISTS (SELECT 1 FROM blocks b
                WHERE (b.blocker_id = $1 AND b.blocked_id = c.author_id)
                   OR (b.blocker_id = c.author_id AND b.blocked_id = $1)))
          +
          (SELECT count(*) FROM topic_replies r JOIN topics t ON t.id = r.topic_id
            JOIN communities co ON co.id = t.community_id AND co.deleted_at IS NULL
            WHERE r.author_id <> $1 AND r.deleted_at IS NULL AND t.deleted_at IS NULL
              AND r.created_at > (SELECT t FROM seen)
              AND (t.author_id = $1 OR EXISTS (
                SELECT 1 FROM topic_replies mine
                WHERE mine.topic_id = t.id AND mine.author_id = $1 AND mine.id < r.id))
              AND NOT EXISTS (SELECT 1 FROM blocks b
                WHERE (b.blocker_id = $1 AND b.blocked_id = r.author_id)
                   OR (b.blocker_id = r.author_id AND b.blocked_id = $1)))
          AS "unread_activity!"
        "#,
        me
    )
    .fetch_one(&state.db)
    .await?;
    Ok(Json(CountsDto {
        friend_requests: r.friend_requests,
        pending_testimonials: r.pending_testimonials,
        community_requests: r.community_requests,
        unread_activity: r.unread_activity,
    }))
}

#[derive(Debug, Serialize)]
pub struct ActivityDto {
    /// comment | reply
    pub kind: String,
    pub actor: AuthorDto,
    /// Post (comment) ou tópico (reply).
    pub target_id: Uuid,
    /// Título do tópico; vazio para comentário.
    pub target_title: String,
    pub excerpt: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    pub unread: bool,
}

/// GET /v1/me/activity — últimos 30 dias, até 50, mais recentes primeiro.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<ActivityDto>>> {
    let rows = sqlx::query!(
        r#"
        WITH seen AS (SELECT activity_seen_at AS t FROM users WHERE id = $1),
        ev AS (
          SELECT 'comment' AS kind, c.author_id AS actor_id, c.post_id AS target_id,
                 '' AS title, c.body, c.created_at
          FROM comments c JOIN posts p ON p.id = c.post_id
          WHERE p.author_id = $1 AND c.author_id <> $1
            AND c.deleted_at IS NULL AND p.deleted_at IS NULL
            AND c.created_at > now() - make_interval(days => $2)
          UNION ALL
          SELECT 'reply', r.author_id, t.id, t.title, r.body, r.created_at
          FROM topic_replies r JOIN topics t ON t.id = r.topic_id
          JOIN communities co ON co.id = t.community_id AND co.deleted_at IS NULL
          WHERE r.author_id <> $1 AND r.deleted_at IS NULL AND t.deleted_at IS NULL
            AND r.created_at > now() - make_interval(days => $2)
            AND (t.author_id = $1 OR EXISTS (
              SELECT 1 FROM topic_replies mine
              WHERE mine.topic_id = t.id AND mine.author_id = $1 AND mine.id < r.id))
        )
        SELECT ev.kind AS "kind!", ev.target_id AS "target_id!", ev.title AS "title!",
               ev.body AS "body!", ev.created_at AS "created_at!",
               u.id, u.username, u.display_name,
               (ev.created_at > (SELECT t FROM seen)) AS "unread!"
        FROM ev JOIN users u ON u.id = ev.actor_id
        WHERE NOT EXISTS (SELECT 1 FROM blocks b
          WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
             OR (b.blocker_id = u.id AND b.blocked_id = $1))
        ORDER BY ev.created_at DESC
        LIMIT 50
        "#,
        user.user_id,
        WINDOW_DAYS
    )
    .fetch_all(&state.db)
    .await?;
    let items = rows
        .into_iter()
        .map(|r| {
            let excerpt: String = r.body.chars().take(140).collect();
            ActivityDto {
                kind: r.kind,
                actor: AuthorDto {
                    id: r.id,
                    username: r.username,
                    display_name: r.display_name,
                },
                target_id: r.target_id,
                target_title: r.title,
                excerpt,
                created_at: r.created_at,
                unread: r.unread,
            }
        })
        .collect();
    Ok(Json(ListDto { items }))
}

/// POST /v1/me/activity/seen — marca tudo como visto.
pub async fn mark_seen(State(state): State<AppState>, user: AuthUser) -> AppResult<StatusCode> {
    sqlx::query!(
        "UPDATE users SET activity_seen_at = now() WHERE id = $1",
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

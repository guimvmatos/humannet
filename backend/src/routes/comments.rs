//! Comentários em posts. Quem vê o post pode comentar (autor e amigos).

use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    routes::{
        friends::ListDto,
        posts::{AuthorDto, visible_post_author},
    },
    validation,
};

#[derive(Debug, Serialize)]
pub struct CommentDto {
    pub id: Uuid,
    pub post_id: Uuid,
    pub author: AuthorDto,
    pub body: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    /// Autor do comentário ou autor do post.
    pub can_delete: bool,
}

#[derive(Deserialize)]
pub struct CreateComment {
    pub body: String,
}

/// POST /v1/posts/{id}/comments
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Path(post_id): Path<Uuid>,
    Json(req): Json<CreateComment>,
) -> AppResult<(StatusCode, Json<CommentDto>)> {
    let body = validation::comment_body(&req.body)?;
    let post_author = visible_post_author(&state, user.user_id, post_id).await?;
    let r = sqlx::query!(
        r#"
        WITH c AS (
          INSERT INTO comments (id, post_id, author_id, body) VALUES ($1, $2, $3, $4)
          RETURNING id, post_id, body, created_at
        )
        SELECT c.id, c.post_id, c.body, c.created_at, u.username, u.display_name
        FROM c JOIN users u ON u.id = $3
        "#,
        Uuid::now_v7(),
        post_id,
        user.user_id,
        body
    )
    .fetch_one(&state.db)
    .await?;
    state.push.notify(
        &state.db,
        user.user_id,
        vec![post_author],
        crate::push::Kind::Comment { post: post_id },
    );
    Ok((
        StatusCode::CREATED,
        Json(CommentDto {
            id: r.id,
            post_id: r.post_id,
            author: AuthorDto {
                id: user.user_id,
                username: r.username,
                display_name: r.display_name,
                avatar_url: None,
            },
            body: r.body,
            created_at: r.created_at,
            can_delete: true,
        }),
    ))
}

/// GET /v1/posts/{id}/comments — do mais antigo ao mais novo (até 500).
/// Comentários de quem tem bloqueio com quem vê ficam ocultos.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Path(post_id): Path<Uuid>,
) -> AppResult<Json<ListDto<CommentDto>>> {
    let (post_author, page_id) =
        crate::routes::posts::visible_post(&state, user.user_id, post_id).await?;
    let moderator = post_author == user.user_id
        || match page_id {
            Some(pg) => crate::routes::posts::is_page_admin(&state.db, pg, user.user_id).await?,
            None => false,
        };
    let rows = sqlx::query!(
        r#"
        SELECT c.id, c.post_id, c.body, c.created_at,
               u.id AS author_id, u.username, u.display_name
        FROM comments c JOIN users u ON u.id = c.author_id
        WHERE c.post_id = $1 AND c.deleted_at IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM blocks b
            WHERE (b.blocker_id = $2 AND b.blocked_id = c.author_id)
               OR (b.blocker_id = c.author_id AND b.blocked_id = $2)
          )
        ORDER BY c.id ASC
        LIMIT 500
        "#,
        post_id,
        user.user_id
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<CommentDto> = rows
        .into_iter()
        .map(|r| CommentDto {
            id: r.id,
            post_id: r.post_id,
            can_delete: r.author_id == user.user_id || moderator,
            author: AuthorDto {
                id: r.author_id,
                username: r.username,
                display_name: r.display_name,
                avatar_url: None,
            },
            body: r.body,
            created_at: r.created_at,
        })
        .collect();
    crate::routes::posts::fill_avatars(&state, items.iter_mut().map(|c| &mut c.author)).await?;
    Ok(Json(ListDto { items }))
}

/// DELETE /v1/comments/{id} — autor do comentário ou do post. O texto é apagado.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let row = sqlx::query!(
        r#"
        SELECT c.author_id, p.author_id AS post_author, p.page_id
        FROM comments c JOIN posts p ON p.id = c.post_id
        WHERE c.id = $1 AND c.deleted_at IS NULL
        "#,
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    let page_admin = match row.page_id {
        Some(pg) => crate::routes::posts::is_page_admin(&state.db, pg, user.user_id).await?,
        None => false,
    };
    if row.author_id != user.user_id && row.post_author != user.user_id && !page_admin {
        return Err(AppError::Forbidden);
    }
    sqlx::query!(
        "UPDATE comments SET deleted_at = now(), body = '[removido]' WHERE id = $1",
        id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

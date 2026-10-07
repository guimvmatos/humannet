use axum::{
    Json,
    extract::{Path, Query, State},
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
        friends,
        pagination::{Page, PageQuery},
        profiles::user_id_by_username,
    },
    validation,
};

#[derive(Debug, Serialize)]
pub struct AuthorDto {
    pub id: Uuid,
    pub username: String,
    pub display_name: Option<String>,
}

/// Post como o app o recebe. Sem contagens públicas (R3).
#[derive(Debug, Serialize)]
pub struct PostDto {
    pub id: Uuid,
    pub author: AuthorDto,
    pub body: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    #[serde(with = "time::serde::rfc3339::option")]
    pub edited_at: Option<OffsetDateTime>,
}

/// Linha "achatada" vinda do banco.
struct PostRow {
    id: Uuid,
    body: String,
    created_at: OffsetDateTime,
    edited_at: Option<OffsetDateTime>,
    author_id: Uuid,
    author_username: String,
    author_display_name: Option<String>,
}

impl From<PostRow> for PostDto {
    fn from(r: PostRow) -> Self {
        Self {
            id: r.id,
            author: AuthorDto {
                id: r.author_id,
                username: r.author_username,
                display_name: r.author_display_name,
            },
            body: r.body,
            created_at: r.created_at,
            edited_at: r.edited_at,
        }
    }
}

fn page(rows: Vec<PostRow>, limit: i64) -> Page<PostDto> {
    let items: Vec<PostDto> = rows.into_iter().map(PostDto::from).collect();
    Page::from_overfetch(items, limit, |p| p.id)
}

#[derive(Debug, Deserialize)]
pub struct CreatePost {
    pub body: String,
}

/// POST /v1/posts
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreatePost>,
) -> AppResult<(StatusCode, Json<PostDto>)> {
    let body = validation::post_body(&req.body)?;
    let row = sqlx::query_as!(
        PostRow,
        r#"
        WITH p AS (
          INSERT INTO posts (id, author_id, body) VALUES ($1, $2, $3)
          RETURNING id, author_id, body, created_at, edited_at
        )
        SELECT p.id, p.body, p.created_at, p.edited_at,
               u.id AS author_id, u.username AS author_username,
               u.display_name AS author_display_name
        FROM p JOIN users u ON u.id = p.author_id
        "#,
        Uuid::now_v7(),
        user.user_id,
        body
    )
    .fetch_one(&state.db)
    .await?;
    Ok((StatusCode::CREATED, Json(row.into())))
}

/// GET /v1/posts/{id} — só o autor e os amigos dele. Para os demais, 404
/// (não revela que o post existe).
pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<PostDto>> {
    let row = sqlx::query_as!(
        PostRow,
        r#"
        SELECT p.id, p.body, p.created_at, p.edited_at,
               u.id AS author_id, u.username AS author_username,
               u.display_name AS author_display_name
        FROM posts p JOIN users u ON u.id = p.author_id
        WHERE p.id = $1 AND p.deleted_at IS NULL
        "#,
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    if !friends::can_see_content(&state.db, user.user_id, row.author_id).await? {
        return Err(AppError::NotFound);
    }
    Ok(Json(row.into()))
}

/// DELETE /v1/posts/{id} — só o autor. Exclusão lógica.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let author = sqlx::query_scalar!(
        "SELECT author_id FROM posts WHERE id = $1 AND deleted_at IS NULL",
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    if author != user.user_id {
        return Err(AppError::Forbidden);
    }

    // Apaga também o conteúdo: exclusão lógica não deve reter o texto.
    sqlx::query!(
        "UPDATE posts SET deleted_at = now(), body = '[removido]' WHERE id = $1",
        id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /v1/users/{username}/posts — só para o próprio e amigos (ADR-0006).
pub async fn list_by_user(
    State(state): State<AppState>,
    viewer: AuthUser,
    Path(username): Path<String>,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Page<PostDto>>> {
    let author = user_id_by_username(&state, &username).await?;
    if !friends::can_see_content(&state.db, viewer.user_id, author).await? {
        return Err(AppError::Forbidden);
    }
    let limit = q.limit();
    let rows = sqlx::query_as!(
        PostRow,
        r#"
        SELECT p.id, p.body, p.created_at, p.edited_at,
               u.id AS author_id, u.username AS author_username,
               u.display_name AS author_display_name
        FROM posts p JOIN users u ON u.id = p.author_id
        WHERE p.author_id = $1
          AND p.deleted_at IS NULL
          AND ($2::uuid IS NULL OR p.id < $2)
        ORDER BY p.id DESC
        LIMIT $3
        "#,
        author,
        q.before,
        limit + 1
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(page(rows, limit)))
}

/// GET /v1/feed — modo cronológico (padrão, R2): meus amigos + eu.
/// Sem ranking. A ordem é a de publicação.
pub async fn feed(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Page<PostDto>>> {
    let limit = q.limit();
    let rows = sqlx::query_as!(
        PostRow,
        r#"
        SELECT p.id, p.body, p.created_at, p.edited_at,
               u.id AS author_id, u.username AS author_username,
               u.display_name AS author_display_name
        FROM posts p JOIN users u ON u.id = p.author_id
        WHERE p.deleted_at IS NULL
          AND (p.author_id = $1
               OR p.author_id IN (SELECT friend_id FROM friends WHERE user_id = $1))
          AND ($2::uuid IS NULL OR p.id < $2)
        ORDER BY p.id DESC
        LIMIT $3
        "#,
        user.user_id,
        q.before,
        limit + 1
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(page(rows, limit)))
}

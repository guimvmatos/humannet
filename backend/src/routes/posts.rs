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
    media::Kind,
    routes::{
        friends,
        pagination::{Page, PageQuery},
        photos::{self, MediaDto},
        profiles::visible_user_id,
    },
    validation,
};

#[derive(Debug, Serialize)]
pub struct AuthorDto {
    pub id: Uuid,
    pub username: String,
    pub display_name: Option<String>,
    /// Foto de perfil (link assinado). Preenchida por `fill_avatars`.
    pub avatar_url: Option<String>,
}

/// Preenche `avatar_url` de vários autores numa consulta só.
pub async fn fill_avatars<'a>(
    state: &AppState,
    authors: impl IntoIterator<Item = &'a mut AuthorDto>,
) -> sqlx::Result<()> {
    let mut authors: Vec<&mut AuthorDto> = authors.into_iter().collect();
    if authors.is_empty() {
        return Ok(());
    }
    let mut ids: Vec<Uuid> = authors.iter().map(|a| a.id).collect();
    ids.sort();
    ids.dedup();
    let rows = sqlx::query!(
        "SELECT u.id, m.key FROM users u JOIN media m ON m.id = u.avatar_media_id
         WHERE u.id = ANY($1)",
        &ids
    )
    .fetch_all(&state.db)
    .await?;
    let keys: std::collections::HashMap<Uuid, String> =
        rows.into_iter().map(|r| (r.id, r.key)).collect();
    for a in &mut authors {
        a.avatar_url = keys.get(&a.id).map(|k| state.media.url(k));
    }
    Ok(())
}

/// Post como o app o recebe.
/// Curtidas: só o autor vê o número (R3). Os outros sabem só se curtiram.
#[derive(Debug, Serialize)]
pub struct PostDto {
    pub id: Uuid,
    pub author: AuthorDto,
    pub body: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    #[serde(with = "time::serde::rfc3339::option")]
    pub edited_at: Option<OffsetDateTime>,
    pub comment_count: i64,
    pub liked_by_me: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub like_count: Option<i64>,
    /// Até 4 fotos, na ordem.
    pub images: Vec<MediaDto>,
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
                avatar_url: None,
            },
            body: r.body,
            created_at: r.created_at,
            edited_at: r.edited_at,
            comment_count: 0,
            liked_by_me: false,
            like_count: None,
            images: Vec::new(),
        }
    }
}

/// Preenche comentários/curtidas de vários posts numa única consulta.
async fn enrich(state: &AppState, viewer: Uuid, posts: &mut [PostDto]) -> sqlx::Result<()> {
    let db = &state.db;
    if posts.is_empty() {
        return Ok(());
    }
    let ids: Vec<Uuid> = posts.iter().map(|p| p.id).collect();
    let rows = sqlx::query!(
        r#"
        SELECT p.id AS "id!",
               (SELECT count(*) FROM comments c
                 WHERE c.post_id = p.id AND c.deleted_at IS NULL) AS "comment_count!",
               EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.user_id = $2) AS "liked!",
               CASE WHEN p.author_id = $2
                    THEN (SELECT count(*) FROM likes l WHERE l.post_id = p.id) END AS like_count
        FROM posts p
        WHERE p.id = ANY($1)
        "#,
        &ids,
        viewer
    )
    .fetch_all(db)
    .await?;
    for r in rows {
        if let Some(p) = posts.iter_mut().find(|p| p.id == r.id) {
            p.comment_count = r.comment_count;
            p.liked_by_me = r.liked;
            p.like_count = r.like_count;
        }
    }
    fill_avatars(state, posts.iter_mut().map(|p| &mut p.author)).await?;
    let mut images = photos::for_posts(db, &state.media, &ids).await?;
    for p in posts.iter_mut() {
        p.images = images.remove(&p.id).unwrap_or_default();
    }
    Ok(())
}

async fn page(
    state: &AppState,
    viewer: Uuid,
    rows: Vec<PostRow>,
    limit: i64,
) -> sqlx::Result<Page<PostDto>> {
    let mut items: Vec<PostDto> = rows.into_iter().map(PostDto::from).collect();
    enrich(state, viewer, &mut items).await?;
    Ok(Page::from_overfetch(items, limit, |p| p.id))
}

/// Post visível para `viewer` (autor ou amigo). 404 caso contrário.
pub(crate) async fn visible_post_author(
    state: &AppState,
    viewer: Uuid,
    post_id: Uuid,
) -> AppResult<Uuid> {
    let author = sqlx::query_scalar!(
        "SELECT author_id FROM posts WHERE id = $1 AND deleted_at IS NULL",
        post_id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    if !friends::can_see_content(&state.db, viewer, author).await? {
        return Err(AppError::NotFound);
    }
    Ok(author)
}

#[derive(Debug, Deserialize)]
pub struct CreatePost {
    #[serde(default)]
    pub body: String,
    /// Fotos enviadas antes em POST /v1/media?kind=post (até 4).
    #[serde(default)]
    pub media_ids: Vec<Uuid>,
}

/// Fotos por post.
pub const MAX_IMAGES: usize = 4;

/// POST /v1/posts
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreatePost>,
) -> AppResult<(StatusCode, Json<PostDto>)> {
    if req.media_ids.len() > MAX_IMAGES {
        return Err(AppError::Validation("too_many_images"));
    }
    // Só foto é um post válido; só texto também. Vazio, não.
    let body = if req.media_ids.is_empty() || !req.body.trim().is_empty() {
        validation::post_body(&req.body)?
    } else {
        String::new()
    };
    let mut tx = state.db.begin().await?;
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
    .fetch_one(&mut *tx)
    .await?;
    if !req.media_ids.is_empty() {
        photos::claim(&mut tx, user.user_id, Kind::Post, &req.media_ids).await?;
        for (i, m) in req.media_ids.iter().enumerate() {
            sqlx::query!(
                "INSERT INTO post_media (post_id, media_id, position) VALUES ($1, $2, $3)",
                row.id,
                m,
                i16::try_from(i).unwrap_or(0)
            )
            .execute(&mut *tx)
            .await?;
        }
    }
    tx.commit().await?;
    let mut items = [PostDto::from(row)];
    enrich(&state, user.user_id, &mut items).await?;
    let [dto] = items;
    Ok((StatusCode::CREATED, Json(dto)))
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
    let mut items = [PostDto::from(row)];
    enrich(&state, user.user_id, &mut items).await?;
    let [dto] = items;
    Ok(Json(dto))
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

    // Apaga também o conteúdo: exclusão lógica não deve reter o texto nem as fotos.
    sqlx::query!(
        "UPDATE posts SET deleted_at = now(), body = '[removido]' WHERE id = $1",
        id
    )
    .execute(&state.db)
    .await?;
    photos::delete_post_media(&state, id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /v1/users/{username}/posts — só para o próprio e amigos (ADR-0006).
pub async fn list_by_user(
    State(state): State<AppState>,
    viewer: AuthUser,
    Path(username): Path<String>,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Page<PostDto>>> {
    let author = visible_user_id(&state, viewer.user_id, &username).await?;
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
    Ok(Json(page(&state, viewer.user_id, rows, limit).await?))
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
    Ok(Json(page(&state, user.user_id, rows, limit).await?))
}

/// PUT /v1/posts/{id}/like — idempotente.
pub async fn like(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    visible_post_author(&state, user.user_id, id).await?;
    sqlx::query!(
        "INSERT INTO likes (post_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/posts/{id}/like — idempotente.
pub async fn unlike(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    sqlx::query!(
        "DELETE FROM likes WHERE post_id = $1 AND user_id = $2",
        id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

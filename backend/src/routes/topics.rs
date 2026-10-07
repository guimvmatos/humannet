//! Tópicos e respostas das comunidades (fórum).
//!
//! Ler: quem pode ler a comunidade. Escrever: membros ativos. Tópico trancado:
//! só quem modera responde. Conteúdo de quem tem bloqueio com quem lê fica oculto.

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
        communities::{self, Access, Community},
        pagination::{Page, PageQuery},
        posts::AuthorDto,
    },
    validation,
};

/// Tamanho do trecho do texto mostrado na lista de tópicos.
const EXCERPT_CHARS: usize = 280;

#[derive(Debug, Serialize)]
pub struct TopicDto {
    pub id: Uuid,
    pub community_slug: String,
    pub community_name: String,
    pub author: AuthorDto,
    pub title: String,
    /// Na lista, só um trecho; em GET /topics/{id}, o texto inteiro.
    pub body: String,
    pub pinned: bool,
    pub locked: bool,
    pub reply_count: i64,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    #[serde(with = "time::serde::rfc3339")]
    pub last_activity_at: OffsetDateTime,
    pub can_reply: bool,
    pub can_delete: bool,
    pub can_moderate: bool,
}

#[derive(Debug, Serialize)]
pub struct ReplyDto {
    pub id: Uuid,
    pub topic_id: Uuid,
    pub author: AuthorDto,
    pub body: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    pub can_delete: bool,
}

fn excerpt(body: &str) -> String {
    if body.chars().count() <= EXCERPT_CHARS {
        body.to_owned()
    } else {
        let mut s: String = body.chars().take(EXCERPT_CHARS).collect();
        s.push('…');
        s
    }
}

/// Tópico visível para quem pede, com a comunidade e o acesso.
struct TopicCtx {
    community: Community,
    access: Access,
    author_id: Uuid,
    locked: bool,
}

async fn topic_ctx(state: &AppState, user: &AuthUser, topic_id: Uuid) -> AppResult<TopicCtx> {
    let row = sqlx::query!(
        r#"
        SELECT t.author_id, t.locked,
               c.id AS cid, c.slug, c.name, c.description, c.rules, c.theme,
               c.visibility, c.created_at AS c_created
        FROM topics t JOIN communities c ON c.id = t.community_id
        WHERE t.id = $1 AND t.deleted_at IS NULL AND c.deleted_at IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM blocks b
            WHERE (b.blocker_id = $2 AND b.blocked_id = t.author_id)
               OR (b.blocker_id = t.author_id AND b.blocked_id = $2))
        "#,
        topic_id,
        user.user_id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    let community = Community {
        id: row.cid,
        slug: row.slug,
        name: row.name,
        description: row.description,
        rules: row.rules,
        theme: row.theme,
        visibility: row.visibility,
        created_at: row.c_created,
    };
    let access = communities::access(&state.db, &community, user).await?;
    if !access.can_read() {
        return Err(AppError::NotFound);
    }
    Ok(TopicCtx {
        community,
        access,
        author_id: row.author_id,
        locked: row.locked,
    })
}

/// NotFound se quem pede não pode ler o tópico.
pub async fn ensure_readable(state: &AppState, user: &AuthUser, topic_id: Uuid) -> AppResult<()> {
    topic_ctx(state, user, topic_id).await.map(|_| ())
}

// ---------------------------------------------------------------- tópicos

/// GET /v1/communities/{slug}/topics?before=&limit= — fixados primeiro, depois
/// pela última atividade.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Query(page): Query<PageQuery>,
) -> AppResult<Json<Page<TopicDto>>> {
    let c = communities::load_by_slug(&state, &slug).await?;
    let a = communities::access(&state.db, &c, &user).await?;
    if !a.can_read() {
        return Err(AppError::Forbidden);
    }
    let limit = page.limit();
    let rows = sqlx::query!(
        r#"
        SELECT t.id, t.title, t.body, t.pinned, t.locked, t.created_at, t.last_activity_at,
               u.id AS author_id, u.username, u.display_name,
               (SELECT count(*) FROM topic_replies r
                 WHERE r.topic_id = t.id AND r.deleted_at IS NULL) AS "reply_count!"
        FROM topics t JOIN users u ON u.id = t.author_id
        WHERE t.community_id = $1 AND t.deleted_at IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM blocks b
            WHERE (b.blocker_id = $2 AND b.blocked_id = t.author_id)
               OR (b.blocker_id = t.author_id AND b.blocked_id = $2))
          AND ($3::uuid IS NULL OR (t.pinned, t.last_activity_at, t.id) <
               (SELECT pinned, last_activity_at, id FROM topics WHERE id = $3))
        ORDER BY t.pinned DESC, t.last_activity_at DESC, t.id DESC
        LIMIT $4
        "#,
        c.id,
        user.user_id,
        page.before,
        limit + 1
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<TopicDto> = rows
        .into_iter()
        .map(|r| TopicDto {
            id: r.id,
            community_slug: c.slug.clone(),
            community_name: c.name.clone(),
            can_reply: a.can_post() && (!r.locked || a.is_mod()),
            can_delete: r.author_id == user.user_id || a.is_mod(),
            can_moderate: a.is_mod(),
            author: AuthorDto {
                id: r.author_id,
                username: r.username,
                display_name: r.display_name,
                avatar_url: None,
            },
            title: r.title,
            body: excerpt(&r.body),
            pinned: r.pinned,
            locked: r.locked,
            reply_count: r.reply_count,
            created_at: r.created_at,
            last_activity_at: r.last_activity_at,
        })
        .collect();
    crate::routes::posts::fill_avatars(&state, items.iter_mut().map(|t| &mut t.author)).await?;
    Ok(Json(Page::from_overfetch(items, limit, |t| t.id)))
}

#[derive(Debug, Deserialize)]
pub struct CreateTopic {
    pub title: String,
    #[serde(default)]
    pub body: String,
}

/// POST /v1/communities/{slug}/topics — membros ativos.
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Json(req): Json<CreateTopic>,
) -> AppResult<(StatusCode, Json<TopicDto>)> {
    let title = validation::topic_title(&req.title)?;
    let body = validation::topic_body(&req.body)?;
    let c = communities::load_by_slug(&state, &slug).await?;
    let a = communities::access(&state.db, &c, &user).await?;
    if !a.can_post() {
        return Err(AppError::Forbidden);
    }
    let r = sqlx::query!(
        r#"
        WITH t AS (
          INSERT INTO topics (id, community_id, author_id, title, body)
          VALUES ($1, $2, $3, $4, $5)
          RETURNING id, title, body, created_at, last_activity_at
        )
        SELECT t.id, t.title, t.body, t.created_at, t.last_activity_at, u.username, u.display_name
        FROM t JOIN users u ON u.id = $3
        "#,
        Uuid::now_v7(),
        c.id,
        user.user_id,
        title,
        body
    )
    .fetch_one(&state.db)
    .await?;
    Ok((
        StatusCode::CREATED,
        Json(TopicDto {
            id: r.id,
            community_slug: c.slug,
            community_name: c.name,
            author: AuthorDto {
                id: user.user_id,
                username: r.username,
                display_name: r.display_name,
                avatar_url: None,
            },
            title: r.title,
            body: r.body,
            pinned: false,
            locked: false,
            reply_count: 0,
            created_at: r.created_at,
            last_activity_at: r.last_activity_at,
            can_reply: true,
            can_delete: true,
            can_moderate: a.is_mod(),
        }),
    ))
}

/// GET /v1/topics/{id} — texto completo.
pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<TopicDto>> {
    let ctx = topic_ctx(&state, &user, id).await?;
    let r = sqlx::query!(
        r#"
        SELECT t.id, t.title, t.body, t.pinned, t.locked, t.created_at, t.last_activity_at,
               u.id AS author_id, u.username, u.display_name,
               (SELECT count(*) FROM topic_replies r
                 WHERE r.topic_id = t.id AND r.deleted_at IS NULL) AS "reply_count!"
        FROM topics t JOIN users u ON u.id = t.author_id
        WHERE t.id = $1
        "#,
        id
    )
    .fetch_one(&state.db)
    .await?;
    let a = &ctx.access;
    let mut dto = TopicDto {
        id: r.id,
        community_slug: ctx.community.slug.clone(),
        community_name: ctx.community.name.clone(),
        can_reply: a.can_post() && (!r.locked || a.is_mod()),
        can_delete: r.author_id == user.user_id || a.is_mod(),
        can_moderate: a.is_mod(),
        author: AuthorDto {
            id: r.author_id,
            username: r.username,
            display_name: r.display_name,
            avatar_url: None,
        },
        title: r.title,
        body: r.body,
        pinned: r.pinned,
        locked: r.locked,
        reply_count: r.reply_count,
        created_at: r.created_at,
        last_activity_at: r.last_activity_at,
    };
    crate::routes::posts::fill_avatars(&state, [&mut dto.author]).await?;
    Ok(Json(dto))
}

#[derive(Debug, Deserialize)]
pub struct UpdateTopic {
    pub pinned: Option<bool>,
    pub locked: Option<bool>,
}

/// PATCH /v1/topics/{id} — fixar/trancar (quem modera).
pub async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateTopic>,
) -> AppResult<StatusCode> {
    let ctx = topic_ctx(&state, &user, id).await?;
    if !ctx.access.is_mod() {
        return Err(AppError::Forbidden);
    }
    sqlx::query!(
        "UPDATE topics SET pinned = coalesce($2, pinned), locked = coalesce($3, locked)
         WHERE id = $1",
        id,
        req.pinned,
        req.locked
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/topics/{id} — autor ou quem modera. O texto é apagado.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let ctx = topic_ctx(&state, &user, id).await?;
    if ctx.author_id != user.user_id && !ctx.access.is_mod() {
        return Err(AppError::Forbidden);
    }
    sqlx::query!(
        "UPDATE topics SET deleted_at = now(), title = '[removido]', body = '' WHERE id = $1",
        id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------- respostas

#[derive(Debug, Deserialize)]
pub struct RepliesQuery {
    /// Id da última resposta recebida (a lista vai da mais antiga à mais nova).
    pub after: Option<Uuid>,
    pub limit: Option<i64>,
}

/// GET /v1/topics/{id}/replies?after=&limit= — da mais antiga à mais nova.
pub async fn replies(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Query(q): Query<RepliesQuery>,
) -> AppResult<Json<Page<ReplyDto>>> {
    let ctx = topic_ctx(&state, &user, id).await?;
    let limit = q.limit.unwrap_or(50).clamp(1, 100);
    let rows = sqlx::query!(
        r#"
        SELECT r.id, r.body, r.created_at, u.id AS author_id, u.username, u.display_name
        FROM topic_replies r JOIN users u ON u.id = r.author_id
        WHERE r.topic_id = $1 AND r.deleted_at IS NULL
          AND ($2::uuid IS NULL OR r.id > $2)
          AND NOT EXISTS (
            SELECT 1 FROM blocks b
            WHERE (b.blocker_id = $3 AND b.blocked_id = r.author_id)
               OR (b.blocker_id = r.author_id AND b.blocked_id = $3))
        ORDER BY r.id ASC
        LIMIT $4
        "#,
        id,
        q.after,
        user.user_id,
        limit + 1
    )
    .fetch_all(&state.db)
    .await?;
    let is_mod = ctx.access.is_mod();
    let mut items: Vec<ReplyDto> = rows
        .into_iter()
        .map(|r| ReplyDto {
            id: r.id,
            topic_id: id,
            can_delete: r.author_id == user.user_id || is_mod,
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
    crate::routes::posts::fill_avatars(&state, items.iter_mut().map(|r| &mut r.author)).await?;
    Ok(Json(Page::from_overfetch(items, limit, |r| r.id)))
}

#[derive(Debug, Deserialize)]
pub struct CreateReply {
    pub body: String,
}

/// POST /v1/topics/{id}/replies — membros; tópico trancado só aceita de quem modera.
pub async fn reply(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<CreateReply>,
) -> AppResult<(StatusCode, Json<ReplyDto>)> {
    let body = validation::reply_body(&req.body)?;
    let ctx = topic_ctx(&state, &user, id).await?;
    if !ctx.access.can_post() {
        return Err(AppError::Forbidden);
    }
    if ctx.locked && !ctx.access.is_mod() {
        return Err(AppError::Validation("topic_locked"));
    }
    let mut tx = state.db.begin().await?;
    let r = sqlx::query!(
        r#"
        WITH r AS (
          INSERT INTO topic_replies (id, topic_id, author_id, body) VALUES ($1, $2, $3, $4)
          RETURNING id, body, created_at
        )
        SELECT r.id, r.body, r.created_at, u.username, u.display_name
        FROM r JOIN users u ON u.id = $3
        "#,
        Uuid::now_v7(),
        id,
        user.user_id,
        body
    )
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query!(
        "UPDATE topics SET last_activity_at = $2 WHERE id = $1",
        id,
        r.created_at
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok((
        StatusCode::CREATED,
        Json(ReplyDto {
            id: r.id,
            topic_id: id,
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

/// DELETE /v1/replies/{id} — autor ou quem modera.
pub async fn delete_reply(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let row = sqlx::query!(
        "SELECT topic_id, author_id FROM topic_replies WHERE id = $1 AND deleted_at IS NULL",
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    let ctx = topic_ctx(&state, &user, row.topic_id).await?;
    if row.author_id != user.user_id && !ctx.access.is_mod() {
        return Err(AppError::Forbidden);
    }
    sqlx::query!(
        "UPDATE topic_replies SET deleted_at = now(), body = '[removido]' WHERE id = $1",
        id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

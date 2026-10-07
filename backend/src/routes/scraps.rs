//! Recados no perfil (estilo "scrap" do Orkut) e status/subnick.
//!
//! Recados: só amigos escrevem (R9), sem aprovação; aparecem para quem vê o
//! conteúdo do perfil (dono e amigos). O dono do perfil e o autor apagam.
//! Status: frase curta com validade (padrão 24 h), visível para amigos.

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
        posts::{AuthorDto, fill_avatars},
        profiles::visible_user_id,
    },
};

const SCRAP_MAX: usize = 1000;
const SCRAPS_PER_DAY: i64 = 100;
const STATUS_MAX: usize = 80;

#[derive(Debug, Serialize)]
pub struct ScrapDto {
    pub id: Uuid,
    pub author: AuthorDto,
    pub body: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    pub can_delete: bool,
}

fn scrap_body(raw: &str) -> AppResult<String> {
    let v = raw.replace("\r\n", "\n").replace('\r', "\n");
    let v = v.trim();
    let n = v.chars().count();
    if n == 0 || n > SCRAP_MAX || v.chars().any(|c| c.is_control() && c != '\n' && c != '\t') {
        return Err(AppError::Validation("invalid_scrap_body"));
    }
    Ok(v.to_owned())
}

/// GET /v1/users/{username}/scraps?before= — mais novos primeiro.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Page<ScrapDto>>> {
    let me = user.user_id;
    let owner = visible_user_id(&state, me, &username).await?;
    if !friends::can_see_content(&state.db, me, owner).await? {
        return Err(AppError::Forbidden);
    }
    let limit = q.limit();
    let rows = sqlx::query!(
        r#"
        SELECT s.id, s.body, s.created_at, u.id AS author_id, u.username, u.display_name
        FROM scraps s JOIN users u ON u.id = s.author_id
        WHERE s.recipient_id = $1
          AND ($2::uuid IS NULL OR s.id < $2)
          AND NOT EXISTS (SELECT 1 FROM blocks b
            WHERE (b.blocker_id = $3 AND b.blocked_id = s.author_id)
               OR (b.blocker_id = s.author_id AND b.blocked_id = $3))
        ORDER BY s.id DESC
        LIMIT $4
        "#,
        owner,
        q.before,
        me,
        limit + 1
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<ScrapDto> = rows
        .into_iter()
        .map(|r| ScrapDto {
            id: r.id,
            can_delete: r.author_id == me || owner == me,
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
    fill_avatars(&state, items.iter_mut().map(|s| &mut s.author)).await?;
    Ok(Json(Page::from_overfetch(items, limit, |s| s.id)))
}

#[derive(Debug, Deserialize)]
pub struct WriteScrap {
    pub body: String,
}

/// POST /v1/users/{username}/scraps — deixar um recado (só amigos).
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
    Json(req): Json<WriteScrap>,
) -> AppResult<(StatusCode, Json<ScrapDto>)> {
    let me = user.user_id;
    let body = scrap_body(&req.body)?;
    let owner = visible_user_id(&state, me, &username).await?;
    if owner == me {
        return Err(AppError::Validation("cannot_scrap_self"));
    }
    if !friends::can_see_content(&state.db, me, owner).await? {
        return Err(AppError::Forbidden);
    }
    let today = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM scraps
           WHERE author_id = $1 AND created_at > now() - interval '24 hours'"#,
        me
    )
    .fetch_one(&state.db)
    .await?;
    if today >= SCRAPS_PER_DAY {
        return Err(AppError::LimitReached("scrap_limit"));
    }
    let r = sqlx::query!(
        r#"
        WITH s AS (
          INSERT INTO scraps (id, recipient_id, author_id, body) VALUES ($1, $2, $3, $4)
          RETURNING id, body, created_at
        )
        SELECT s.id, s.body, s.created_at, u.username, u.display_name
        FROM s JOIN users u ON u.id = $3
        "#,
        Uuid::now_v7(),
        owner,
        me,
        body
    )
    .fetch_one(&state.db)
    .await?;
    let mut dto = ScrapDto {
        id: r.id,
        author: AuthorDto {
            id: me,
            username: r.username,
            display_name: r.display_name,
            avatar_url: None,
        },
        body: r.body,
        created_at: r.created_at,
        can_delete: true,
    };
    fill_avatars(&state, [&mut dto.author]).await?;
    Ok((StatusCode::CREATED, Json(dto)))
}

/// DELETE /v1/scraps/{id} — dono do perfil ou autor.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let n = sqlx::query!(
        "DELETE FROM scraps WHERE id = $1 AND (recipient_id = $2 OR author_id = $2)",
        id,
        user.user_id
    )
    .execute(&state.db)
    .await?
    .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound);
    }
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------- status

#[derive(Debug, Deserialize)]
pub struct SetStatus {
    pub text: String,
    /// Validade em horas: 24 (padrão), 72, 168; 0 = sem validade.
    #[serde(default = "default_hours")]
    pub hours: i64,
}

fn default_hours() -> i64 {
    24
}

#[derive(Debug, Serialize)]
pub struct StatusDto {
    pub text: String,
    #[serde(with = "time::serde::rfc3339::option")]
    pub expires_at: Option<OffsetDateTime>,
}

/// PUT /v1/me/status `{text, hours?}` — "" apaga.
pub async fn set_status(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<SetStatus>,
) -> AppResult<Json<StatusDto>> {
    let text = req.text.split_whitespace().collect::<Vec<_>>().join(" ");
    if text.chars().count() > STATUS_MAX || text.chars().any(char::is_control) {
        return Err(AppError::Validation("invalid_status"));
    }
    let expires_at = match req.hours {
        0 => None,
        24 | 72 | 168 => Some(OffsetDateTime::now_utc() + time::Duration::hours(req.hours)),
        _ => return Err(AppError::Validation("invalid_status_hours")),
    };
    let expires_at = if text.is_empty() { None } else { expires_at };
    sqlx::query!(
        "UPDATE users SET status_text = $2, status_expires_at = $3 WHERE id = $1",
        user.user_id,
        text,
        expires_at
    )
    .execute(&state.db)
    .await?;
    Ok(Json(StatusDto { text, expires_at }))
}

/// Status vigente (vazio se expirou).
pub fn current_status(text: String, expires_at: Option<OffsetDateTime>) -> Option<String> {
    if text.is_empty() || expires_at.is_some_and(|e| e <= OffsetDateTime::now_utc()) {
        None
    } else {
        Some(text)
    }
}

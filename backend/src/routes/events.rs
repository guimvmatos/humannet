//! Eventos das páginas de lugares. Sem ingresso: as pessoas marcam
//! "tenho interesse" ou "vou".
//!
//! Privacidade (R3): números totais só para quem administra a página. Para os
//! outros, mostramos só quais **amigos** marcaram interesse.

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
        friends::ListDto,
        pages,
        posts::{AuthorDto, fill_avatars},
    },
    validation,
};

/// Eventos criados por página por dia.
const MAX_EVENTS_PER_DAY: i64 = 20;

#[derive(Debug, Serialize)]
pub struct PageRef {
    pub slug: String,
    pub name: String,
}

#[derive(Debug, Serialize)]
pub struct EventDto {
    pub id: Uuid,
    pub page: PageRef,
    pub title: String,
    pub description: String,
    #[serde(with = "time::serde::rfc3339")]
    pub starts_at: OffsetDateTime,
    #[serde(with = "time::serde::rfc3339::option")]
    pub ends_at: Option<OffsetDateTime>,
    /// Local do evento (ou endereço da página).
    pub location: String,
    pub cancelled: bool,
    /// interested | going | null
    pub my_interest: Option<String>,
    /// Amigos que marcaram interesse (até 10).
    pub friends: Vec<AuthorDto>,
    pub friends_count: i64,
    /// Só para quem administra a página (R3).
    pub interested_count: Option<i64>,
    pub going_count: Option<i64>,
    pub can_edit: bool,
}

struct Row {
    id: Uuid,
    page_id: Uuid,
    page_slug: String,
    page_name: String,
    title: String,
    description: String,
    starts_at: OffsetDateTime,
    ends_at: Option<OffsetDateTime>,
    location: String,
    cancelled: bool,
    my_interest: Option<String>,
}

async fn build(state: &AppState, user: &AuthUser, rows: Vec<Row>) -> AppResult<Vec<EventDto>> {
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let friends = sqlx::query!(
        r#"
        SELECT i.event_id, u.id, u.username, u.display_name
        FROM event_interests i
        JOIN friends f ON f.user_id = $2 AND f.friend_id = i.user_id
        JOIN users u ON u.id = i.user_id
        WHERE i.event_id = ANY($1)
        ORDER BY i.created_at
        "#,
        &ids,
        user.user_id
    )
    .fetch_all(&state.db)
    .await?;
    let admin_pages: Vec<Uuid> = sqlx::query_scalar!(
        "SELECT page_id FROM page_admins WHERE user_id = $1",
        user.user_id
    )
    .fetch_all(&state.db)
    .await?;
    let counts = sqlx::query!(
        r#"SELECT event_id,
                  count(*) FILTER (WHERE status = 'interested') AS "interested!",
                  count(*) FILTER (WHERE status = 'going') AS "going!"
           FROM event_interests WHERE event_id = ANY($1) GROUP BY event_id"#,
        &ids
    )
    .fetch_all(&state.db)
    .await?;

    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        let is_admin = user.is_admin || admin_pages.contains(&r.page_id);
        let mine: Vec<AuthorDto> = friends
            .iter()
            .filter(|f| f.event_id == r.id)
            .map(|f| AuthorDto {
                id: f.id,
                username: f.username.clone(),
                display_name: f.display_name.clone(),
                avatar_url: None,
            })
            .collect();
        let friends_count = i64::try_from(mine.len()).unwrap_or(0);
        let c = counts.iter().find(|c| c.event_id == r.id);
        out.push(EventDto {
            id: r.id,
            page: PageRef {
                slug: r.page_slug,
                name: r.page_name,
            },
            title: r.title,
            description: r.description,
            starts_at: r.starts_at,
            ends_at: r.ends_at,
            location: r.location,
            cancelled: r.cancelled,
            my_interest: r.my_interest,
            friends: mine.into_iter().take(10).collect(),
            friends_count,
            interested_count: is_admin.then(|| c.map_or(0, |c| c.interested)),
            going_count: is_admin.then(|| c.map_or(0, |c| c.going)),
            can_edit: is_admin,
        });
    }
    let all = out.iter_mut().flat_map(|e| e.friends.iter_mut());
    fill_avatars(state, all).await?;
    Ok(out)
}

#[derive(Debug, Deserialize)]
pub struct PageEventsQuery {
    /// true = já passaram (mais recentes primeiro).
    #[serde(default)]
    pub past: bool,
}

/// GET /v1/pages/{slug}/events?past=
pub async fn list_for_page(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Query(q): Query<PageEventsQuery>,
) -> AppResult<Json<ListDto<EventDto>>> {
    let p = pages::load(&state, &slug).await?;
    let rows = sqlx::query_as!(
        Row,
        r#"
        SELECT e.id, e.page_id, p.slug AS page_slug, p.name AS page_name, e.title, e.description,
               e.starts_at, e.ends_at,
               CASE WHEN e.location = '' THEN p.address ELSE e.location END AS "location!",
               (e.cancelled_at IS NOT NULL) AS "cancelled!",
               i.status AS "my_interest?"
        FROM events e JOIN pages p ON p.id = e.page_id
        LEFT JOIN event_interests i ON i.event_id = e.id AND i.user_id = $2
        WHERE e.page_id = $1 AND e.deleted_at IS NULL
          AND (CASE WHEN $3 THEN coalesce(e.ends_at, e.starts_at) < now()
                    ELSE coalesce(e.ends_at, e.starts_at + interval '6 hours') >= now() END)
        ORDER BY CASE WHEN $3 THEN NULL ELSE e.starts_at END ASC,
                 CASE WHEN $3 THEN e.starts_at END DESC
        LIMIT 100
        "#,
        p.id,
        user.user_id,
        q.past
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto {
        items: build(&state, &user, rows).await?,
    }))
}

/// GET /v1/events — agenda: próximos eventos das páginas que acompanho ou
/// administro e dos que marquei interesse.
pub async fn agenda(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<EventDto>>> {
    let rows = sqlx::query_as!(
        Row,
        r#"
        SELECT e.id, e.page_id, p.slug AS page_slug, p.name AS page_name, e.title, e.description,
               e.starts_at, e.ends_at,
               CASE WHEN e.location = '' THEN p.address ELSE e.location END AS "location!",
               (e.cancelled_at IS NOT NULL) AS "cancelled!",
               i.status AS "my_interest?"
        FROM events e JOIN pages p ON p.id = e.page_id AND p.deleted_at IS NULL
        LEFT JOIN event_interests i ON i.event_id = e.id AND i.user_id = $1
        WHERE e.deleted_at IS NULL
          AND coalesce(e.ends_at, e.starts_at + interval '6 hours') >= now()
          AND (i.user_id IS NOT NULL
               OR EXISTS (SELECT 1 FROM page_followers f WHERE f.page_id = p.id AND f.user_id = $1)
               OR EXISTS (SELECT 1 FROM page_admins a WHERE a.page_id = p.id AND a.user_id = $1))
        ORDER BY e.starts_at ASC
        LIMIT 100
        "#,
        user.user_id
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto {
        items: build(&state, &user, rows).await?,
    }))
}

async fn load_row(state: &AppState, user: &AuthUser, id: Uuid) -> AppResult<Row> {
    sqlx::query_as!(
        Row,
        r#"
        SELECT e.id, e.page_id, p.slug AS page_slug, p.name AS page_name, e.title, e.description,
               e.starts_at, e.ends_at,
               CASE WHEN e.location = '' THEN p.address ELSE e.location END AS "location!",
               (e.cancelled_at IS NOT NULL) AS "cancelled!",
               i.status AS "my_interest?"
        FROM events e JOIN pages p ON p.id = e.page_id AND p.deleted_at IS NULL
        LEFT JOIN event_interests i ON i.event_id = e.id AND i.user_id = $2
        WHERE e.id = $1 AND e.deleted_at IS NULL
        "#,
        id,
        user.user_id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)
}

async fn one(state: &AppState, user: &AuthUser, id: Uuid) -> AppResult<EventDto> {
    let row = load_row(state, user, id).await?;
    let mut v = build(state, user, vec![row]).await?;
    v.pop().ok_or(AppError::NotFound)
}

/// GET /v1/events/{id}
pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<EventDto>> {
    Ok(Json(one(&state, &user, id).await?))
}

#[derive(Debug, Deserialize)]
pub struct EventInput {
    pub title: Option<String>,
    pub description: Option<String>,
    #[serde(default, with = "time::serde::rfc3339::option")]
    pub starts_at: Option<OffsetDateTime>,
    #[serde(default, with = "time::serde::rfc3339::option")]
    pub ends_at: Option<OffsetDateTime>,
    pub location: Option<String>,
    /// Só no PATCH: true cancela, false reabre.
    pub cancelled: Option<bool>,
}

fn check_times(starts: OffsetDateTime, ends: Option<OffsetDateTime>) -> AppResult<()> {
    if ends.is_some_and(|e| e <= starts) {
        return Err(AppError::Validation("invalid_event_time"));
    }
    if ends.is_some_and(|e| e - starts > time::Duration::days(14)) {
        return Err(AppError::Validation("invalid_event_time"));
    }
    Ok(())
}

/// POST /v1/pages/{slug}/events — quem administra a página.
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Json(req): Json<EventInput>,
) -> AppResult<(StatusCode, Json<EventDto>)> {
    let p = pages::load(&state, &slug).await?;
    if pages::role(&state, p.id, &user).await?.is_none() {
        return Err(AppError::Forbidden);
    }
    let title = validation::line(
        req.title.as_deref().unwrap_or(""),
        3,
        120,
        "invalid_event_title",
    )?;
    let description = validation::long_text(
        req.description.as_deref().unwrap_or(""),
        3000,
        "invalid_event_description",
    )?;
    let location = validation::line(
        req.location.as_deref().unwrap_or(""),
        0,
        200,
        "invalid_address",
    )?;
    let starts = req
        .starts_at
        .ok_or(AppError::Validation("invalid_event_time"))?;
    if starts < OffsetDateTime::now_utc() - time::Duration::hours(1) {
        return Err(AppError::Validation("invalid_event_time"));
    }
    check_times(starts, req.ends_at)?;
    let today = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM events
           WHERE page_id = $1 AND created_at > now() - interval '24 hours'"#,
        p.id
    )
    .fetch_one(&state.db)
    .await?;
    if today >= MAX_EVENTS_PER_DAY {
        return Err(AppError::LimitReached("event_limit"));
    }
    let id = Uuid::now_v7();
    sqlx::query!(
        "INSERT INTO events (id, page_id, title, description, starts_at, ends_at, location, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
        id,
        p.id,
        title,
        description,
        starts,
        req.ends_at,
        location,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok((StatusCode::CREATED, Json(one(&state, &user, id).await?)))
}

/// PATCH /v1/events/{id} — editar ou cancelar (quem administra a página).
pub async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<EventInput>,
) -> AppResult<Json<EventDto>> {
    let row = load_row(&state, &user, id).await?;
    if pages::role(&state, row.page_id, &user).await?.is_none() {
        return Err(AppError::Forbidden);
    }
    let cur = sqlx::query!(
        "SELECT title, description, starts_at, ends_at, location FROM events WHERE id = $1",
        id
    )
    .fetch_one(&state.db)
    .await?;
    let title = match &req.title {
        Some(v) => validation::line(v, 3, 120, "invalid_event_title")?,
        None => cur.title,
    };
    let description = match &req.description {
        Some(v) => validation::long_text(v, 3000, "invalid_event_description")?,
        None => cur.description,
    };
    let location = match &req.location {
        Some(v) => validation::line(v, 0, 200, "invalid_address")?,
        None => cur.location,
    };
    let starts = req.starts_at.unwrap_or(cur.starts_at);
    let ends = if req.starts_at.is_some() || req.ends_at.is_some() {
        req.ends_at
    } else {
        cur.ends_at
    };
    check_times(starts, ends)?;
    sqlx::query!(
        "UPDATE events SET title = $2, description = $3, location = $4, starts_at = $5,
           ends_at = $6,
           cancelled_at = CASE WHEN $7::bool IS NULL THEN cancelled_at
                               WHEN $7 THEN coalesce(cancelled_at, now()) ELSE NULL END
         WHERE id = $1",
        id,
        title,
        description,
        location,
        starts,
        ends,
        req.cancelled
    )
    .execute(&state.db)
    .await?;
    Ok(Json(one(&state, &user, id).await?))
}

/// DELETE /v1/events/{id}
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let row = load_row(&state, &user, id).await?;
    if pages::role(&state, row.page_id, &user).await?.is_none() {
        return Err(AppError::Forbidden);
    }
    sqlx::query!("UPDATE events SET deleted_at = now() WHERE id = $1", id)
        .execute(&state.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
pub struct Interest {
    /// interested | going
    pub status: String,
}

/// PUT /v1/events/{id}/interest `{status}`
pub async fn set_interest(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<Interest>,
) -> AppResult<Json<EventDto>> {
    if !matches!(req.status.as_str(), "interested" | "going") {
        return Err(AppError::Validation("invalid_interest"));
    }
    let row = load_row(&state, &user, id).await?;
    if row.cancelled {
        return Err(AppError::Validation("event_cancelled"));
    }
    sqlx::query!(
        "INSERT INTO event_interests (event_id, user_id, status) VALUES ($1, $2, $3)
         ON CONFLICT (event_id, user_id) DO UPDATE SET status = EXCLUDED.status",
        id,
        user.user_id,
        req.status
    )
    .execute(&state.db)
    .await?;
    Ok(Json(one(&state, &user, id).await?))
}

/// DELETE /v1/events/{id}/interest
pub async fn clear_interest(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    sqlx::query!(
        "DELETE FROM event_interests WHERE event_id = $1 AND user_id = $2",
        id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

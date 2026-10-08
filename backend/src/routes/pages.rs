//! Páginas de lugares (bar, restaurante, casa de show…), com CNPJ.
//!
//! - Qualquer pessoa cria (até 3), informando o CNPJ (um por página). A
//!   administração da HumanNet pode marcar como verificada.
//! - Página tem dono e administradores; eles criam eventos.
//! - Pessoas "acompanham" páginas (única relação unilateral, ADR-0006).
//!   Número de quem acompanha: só para quem administra (R3).

use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    AppState,
    auth::{AdminUser, AuthUser},
    error::{AppError, AppResult},
    routes::{friends::ListDto, profiles::user_id_by_username},
    validation,
};

pub const MAX_OWNED: i64 = 3;

pub const CATEGORIES: &[&str] = &[
    "bar",
    "restaurante",
    "cafe",
    "casa_de_show",
    "balada",
    "teatro",
    "cinema",
    "espaco_cultural",
    "livraria",
    "esporte",
    "outro",
];

pub struct Page {
    pub id: Uuid,
    pub slug: String,
    pub name: String,
    pub category: String,
    pub description: String,
    pub address: String,
    pub city: String,
    pub cnpj: String,
    pub verified: bool,
}

pub async fn load(state: &AppState, raw: &str) -> AppResult<Page> {
    let slug = validation::community_slug(raw).map_err(|_| AppError::NotFound)?;
    sqlx::query_as!(
        Page,
        r#"SELECT id, slug, name, category, description, address, city, cnpj,
                  (verified_at IS NOT NULL) AS "verified!"
           FROM pages WHERE slug = $1 AND deleted_at IS NULL"#,
        slug
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)
}

/// Papel de quem pede: owner | admin | None. Admin da plataforma conta como admin.
pub async fn role(
    state: &AppState,
    page_id: Uuid,
    user: &AuthUser,
) -> sqlx::Result<Option<String>> {
    let r = sqlx::query_scalar!(
        "SELECT role FROM page_admins WHERE page_id = $1 AND user_id = $2",
        page_id,
        user.user_id
    )
    .fetch_optional(&state.db)
    .await?;
    Ok(r.or_else(|| user.is_admin.then(|| "admin".to_owned())))
}

fn format_cnpj(d: &str) -> String {
    if d.len() != 14 {
        return d.to_owned();
    }
    format!(
        "{}.{}.{}/{}-{}",
        &d[0..2],
        &d[2..5],
        &d[5..8],
        &d[8..12],
        &d[12..14]
    )
}

#[derive(Debug, Serialize)]
pub struct PageDto {
    pub id: Uuid,
    pub slug: String,
    pub name: String,
    pub category: String,
    pub description: String,
    pub address: String,
    pub city: String,
    pub cnpj: String,
    pub verified: bool,
    pub my_role: Option<String>,
    pub following: bool,
    /// Só para quem administra (R3).
    pub follower_count: Option<i64>,
}

async fn to_dto(state: &AppState, p: Page, user: &AuthUser) -> AppResult<PageDto> {
    let my_role = role(state, p.id, user).await?;
    let following = sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM page_followers WHERE page_id = $1 AND user_id = $2) AS "e!""#,
        p.id,
        user.user_id
    )
    .fetch_one(&state.db)
    .await?;
    let follower_count = if my_role.is_some() {
        Some(
            sqlx::query_scalar!(
                r#"SELECT count(*) AS "n!" FROM page_followers WHERE page_id = $1"#,
                p.id
            )
            .fetch_one(&state.db)
            .await?,
        )
    } else {
        None
    };
    Ok(PageDto {
        id: p.id,
        slug: p.slug,
        name: p.name,
        category: p.category,
        description: p.description,
        address: p.address,
        city: p.city,
        cnpj: format_cnpj(&p.cnpj),
        verified: p.verified,
        my_role,
        following,
        follower_count,
    })
}

#[derive(Debug, Serialize)]
pub struct PageItemDto {
    pub slug: String,
    pub name: String,
    pub category: String,
    pub city: String,
    pub verified: bool,
    pub following: bool,
    pub my_role: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ListQuery {
    pub q: Option<String>,
    /// Só as que eu acompanho ou administro.
    #[serde(default)]
    pub mine: bool,
}

/// GET /v1/pages?q=&mine=true
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<ListDto<PageItemDto>>> {
    let pattern =
        q.q.as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(|s| {
                let s: String = s.chars().take(60).collect();
                format!(
                    "%{}%",
                    s.replace('\\', "\\\\")
                        .replace('%', "\\%")
                        .replace('_', "\\_")
                )
            });
    let items = sqlx::query_as!(
        PageItemDto,
        r#"
        SELECT p.slug, p.name, p.category, p.city,
               (p.verified_at IS NOT NULL) AS "verified!",
               (f.user_id IS NOT NULL) AS "following!",
               a.role AS "my_role?"
        FROM pages p
        LEFT JOIN page_followers f ON f.page_id = p.id AND f.user_id = $1
        LEFT JOIN page_admins a ON a.page_id = p.id AND a.user_id = $1
        WHERE p.deleted_at IS NULL
          AND ($2::text IS NULL OR p.name ILIKE $2 ESCAPE '\' OR p.city ILIKE $2 ESCAPE '\')
          AND (NOT $3 OR f.user_id IS NOT NULL OR a.user_id IS NOT NULL)
        ORDER BY lower(p.name), p.id
        LIMIT 100
        "#,
        user.user_id,
        pattern,
        q.mine
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto { items }))
}

#[derive(Debug, Deserialize)]
pub struct CreatePage {
    pub name: String,
    pub category: String,
    pub cnpj: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub address: String,
    #[serde(default)]
    pub city: String,
    pub slug: Option<String>,
}

fn category(raw: &str) -> AppResult<String> {
    if CATEGORIES.contains(&raw) {
        Ok(raw.to_owned())
    } else {
        Err(AppError::Validation("invalid_page_category"))
    }
}

/// POST /v1/pages — quem cria vira dono.
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreatePage>,
) -> AppResult<(StatusCode, Json<PageDto>)> {
    let name = validation::line(&req.name, 2, 80, "invalid_page_name")?;
    let category = category(&req.category)?;
    let cnpj = validation::cnpj(&req.cnpj)?;
    let description = validation::long_text(&req.description, 2000, "invalid_page_description")?;
    let address = validation::line(&req.address, 0, 200, "invalid_address")?;
    let city = validation::line(&req.city, 0, 80, "invalid_place")?;
    let slug = match req.slug.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        Some(s) => validation::community_slug(s)?,
        None => validation::community_slug(&validation::slugify(&name))
            .map_err(|_| AppError::Validation("invalid_page_name"))?,
    };

    let mut tx = state.db.begin().await?;
    sqlx::query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1::text, 9))",
        user.user_id.to_string()
    )
    .execute(&mut *tx)
    .await?;
    let owned = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM page_admins a JOIN pages p ON p.id = a.page_id
           WHERE a.user_id = $1 AND a.role = 'owner' AND p.deleted_at IS NULL"#,
        user.user_id
    )
    .fetch_one(&mut *tx)
    .await?;
    if owned >= MAX_OWNED {
        return Err(AppError::LimitReached("page_limit"));
    }
    let id = Uuid::now_v7();
    let res = sqlx::query!(
        "INSERT INTO pages (id, slug, name, category, description, address, city, cnpj, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
        id,
        slug,
        name,
        category,
        description,
        address,
        city,
        cnpj,
        user.user_id
    )
    .execute(&mut *tx)
    .await;
    if let Err(sqlx::Error::Database(db)) = &res
        && db.is_unique_violation()
    {
        return Err(match db.constraint() {
            Some("pages_cnpj_key") => AppError::Conflict("cnpj_taken"),
            _ => AppError::Conflict("slug_taken"),
        });
    }
    res?;
    sqlx::query!(
        "INSERT INTO page_admins (page_id, user_id, role) VALUES ($1, $2, 'owner')",
        id,
        user.user_id
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    let page = load(&state, &slug).await?;
    Ok((
        StatusCode::CREATED,
        Json(to_dto(&state, page, &user).await?),
    ))
}

/// GET /v1/pages/{slug}
pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<Json<PageDto>> {
    let p = load(&state, &slug).await?;
    Ok(Json(to_dto(&state, p, &user).await?))
}

#[derive(Debug, Deserialize)]
pub struct UpdatePage {
    pub name: Option<String>,
    pub category: Option<String>,
    pub description: Option<String>,
    pub address: Option<String>,
    pub city: Option<String>,
}

/// PATCH /v1/pages/{slug} — quem administra. CNPJ e endereço curto não mudam
/// pelo app (CNPJ: só a administração).
pub async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Json(req): Json<UpdatePage>,
) -> AppResult<Json<PageDto>> {
    let mut p = load(&state, &slug).await?;
    if role(&state, p.id, &user).await?.is_none() {
        return Err(AppError::Forbidden);
    }
    if let Some(v) = &req.name {
        p.name = validation::line(v, 2, 80, "invalid_page_name")?;
    }
    if let Some(v) = &req.category {
        p.category = category(v)?;
    }
    if let Some(v) = &req.description {
        p.description = validation::long_text(v, 2000, "invalid_page_description")?;
    }
    if let Some(v) = &req.address {
        p.address = validation::line(v, 0, 200, "invalid_address")?;
    }
    if let Some(v) = &req.city {
        p.city = validation::line(v, 0, 80, "invalid_place")?;
    }
    sqlx::query!(
        "UPDATE pages SET name = $2, category = $3, description = $4, address = $5, city = $6
         WHERE id = $1",
        p.id,
        p.name,
        p.category,
        p.description,
        p.address,
        p.city
    )
    .execute(&state.db)
    .await?;
    Ok(Json(to_dto(&state, p, &user).await?))
}

/// DELETE /v1/pages/{slug} — dono (ou admin da plataforma).
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<StatusCode> {
    let p = load(&state, &slug).await?;
    let r = role(&state, p.id, &user).await?;
    if !(r.as_deref() == Some("owner") || user.is_admin) {
        return Err(AppError::Forbidden);
    }
    sqlx::query!("UPDATE pages SET deleted_at = now() WHERE id = $1", p.id)
        .execute(&state.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// PUT /v1/pages/{slug}/follow — acompanhar (idempotente).
pub async fn follow(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<StatusCode> {
    let p = load(&state, &slug).await?;
    sqlx::query!(
        "INSERT INTO page_followers (page_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        p.id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/pages/{slug}/follow
pub async fn unfollow(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<StatusCode> {
    let p = load(&state, &slug).await?;
    sqlx::query!(
        "DELETE FROM page_followers WHERE page_id = $1 AND user_id = $2",
        p.id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
pub struct AddAdmin {
    pub username: String,
}

/// POST /v1/pages/{slug}/admins `{username}` — o dono adiciona administrador.
pub async fn add_admin(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Json(req): Json<AddAdmin>,
) -> AppResult<StatusCode> {
    let p = load(&state, &slug).await?;
    if role(&state, p.id, &user).await?.as_deref() != Some("owner") {
        return Err(AppError::Forbidden);
    }
    let target = user_id_by_username(&state, &req.username).await?;
    sqlx::query!(
        "INSERT INTO page_admins (page_id, user_id, role) VALUES ($1, $2, 'admin')
         ON CONFLICT DO NOTHING",
        p.id,
        target
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/pages/{slug}/admins/{username} — o dono remove (ou a pessoa sai).
pub async fn remove_admin(
    State(state): State<AppState>,
    user: AuthUser,
    Path((slug, username)): Path<(String, String)>,
) -> AppResult<StatusCode> {
    let p = load(&state, &slug).await?;
    let target = user_id_by_username(&state, &username).await?;
    let is_owner = role(&state, p.id, &user).await?.as_deref() == Some("owner");
    if !(is_owner || target == user.user_id) {
        return Err(AppError::Forbidden);
    }
    sqlx::query!(
        "DELETE FROM page_admins WHERE page_id = $1 AND user_id = $2 AND role = 'admin'",
        p.id,
        target
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// POST /v1/admin/pages/{slug}/verify — administração confere o CNPJ.
pub async fn verify(
    State(state): State<AppState>,
    AdminUser(_admin): AdminUser,
    Path(slug): Path<String>,
) -> AppResult<StatusCode> {
    let p = load(&state, &slug).await?;
    sqlx::query!(
        "UPDATE pages SET verified_at = coalesce(verified_at, now()) WHERE id = $1",
        p.id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

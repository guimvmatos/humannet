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
    pub cep: Option<String>,
    pub logo_key: Option<String>,
    pub cover_key: Option<String>,
}

pub async fn load(state: &AppState, raw: &str) -> AppResult<Page> {
    let slug = validation::community_slug(raw).map_err(|_| AppError::NotFound)?;
    sqlx::query_as!(
        Page,
        r#"SELECT p.id, p.slug, p.name, p.category, p.description, p.address, p.city, p.cnpj,
                  (p.verified_at IS NOT NULL) AS "verified!", p.cep,
                  lm.key AS "logo_key?", cm.key AS "cover_key?"
           FROM pages p
           LEFT JOIN media lm ON lm.id = p.logo_media_id
           LEFT JOIN media cm ON cm.id = p.cover_media_id
           WHERE p.slug = $1 AND p.deleted_at IS NULL"#,
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
    /// Só dígitos (8) ou nulo.
    pub cep: Option<String>,
    pub logo_url: Option<String>,
    pub cover_url: Option<String>,
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
        cep: p.cep,
        logo_url: p.logo_key.map(|k| state.media.url(&k)),
        cover_url: p.cover_key.map(|k| state.media.url(&k)),
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
    pub logo_url: Option<String>,
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
    let rows = sqlx::query!(
        r#"
        SELECT p.slug, p.name, p.category, p.city,
               (p.verified_at IS NOT NULL) AS "verified!",
               (f.user_id IS NOT NULL) AS "following!",
               a.role AS "my_role?", lm.key AS "logo_key?"
        FROM pages p
        LEFT JOIN page_followers f ON f.page_id = p.id AND f.user_id = $1
        LEFT JOIN page_admins a ON a.page_id = p.id AND a.user_id = $1
        LEFT JOIN media lm ON lm.id = p.logo_media_id
        WHERE p.deleted_at IS NULL
          AND ($2::text IS NULL OR p.name ILIKE $2 ESCAPE '\' OR p.city ILIKE $2 ESCAPE '\')
          AND (NOT $3 OR f.user_id IS NOT NULL OR a.user_id IS NOT NULL)
        ORDER BY (a.user_id IS NULL), lower(p.name), p.id
        LIMIT 100
        "#,
        user.user_id,
        pattern,
        q.mine
    )
    .fetch_all(&state.db)
    .await?;
    let items = rows
        .into_iter()
        .map(|r| PageItemDto {
            slug: r.slug,
            name: r.name,
            category: r.category,
            city: r.city,
            verified: r.verified,
            following: r.following,
            my_role: r.my_role,
            logo_url: r.logo_key.map(|k| state.media.url(&k)),
        })
        .collect();
    Ok(Json(ListDto { items }))
}

/// CEP só com dígitos (8). Vazio = sem CEP.
fn cep(raw: &str) -> AppResult<Option<String>> {
    let d: String = raw.chars().filter(char::is_ascii_digit).collect();
    let other = raw
        .chars()
        .any(|c| !c.is_ascii_digit() && c != '-' && c != '.' && c != ' ');
    match d.len() {
        0 if !other => Ok(None),
        8 if !other => Ok(Some(d)),
        _ => Err(AppError::Validation("invalid_cep")),
    }
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
    #[serde(default)]
    pub cep: String,
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
    let cep = cep(&req.cep)?;
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
        "INSERT INTO pages (id, slug, name, category, description, address, city, cnpj, created_by, cep)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
        id,
        slug,
        name,
        category,
        description,
        address,
        city,
        cnpj,
        user.user_id,
        cep
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
    pub cep: Option<String>,
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
    if let Some(v) = &req.cep {
        p.cep = cep(v)?;
    }
    sqlx::query!(
        "UPDATE pages SET name = $2, category = $3, description = $4, address = $5, city = $6,
                          cep = $7
         WHERE id = $1",
        p.id,
        p.name,
        p.category,
        p.description,
        p.address,
        p.city,
        p.cep
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
    // Passa a ver e responder as mensagens da página.
    sqlx::query!(
        "INSERT INTO conversation_members (conversation_id, user_id, role)
         SELECT id, $2, 'page' FROM conversations WHERE page_id = $1 AND customer_id <> $2
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
    sqlx::query!(
        "DELETE FROM conversation_members m USING conversations c
         WHERE m.conversation_id = c.id AND c.page_id = $1 AND m.user_id = $2 AND m.role = 'page'
           AND NOT EXISTS (SELECT 1 FROM page_admins a WHERE a.page_id = $1 AND a.user_id = $2)",
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

#[derive(Debug, Serialize)]
pub struct PageAdminDto {
    #[serde(flatten)]
    pub user: crate::routes::posts::AuthorDto,
    /// owner | admin
    pub role: String,
}

/// GET /v1/pages/{slug}/admins — quem administra (dono primeiro). Público:
/// os posts da página também mostram quem publicou (R1).
pub async fn admins(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<Json<ListDto<PageAdminDto>>> {
    let p = load(&state, &slug).await?;
    let rows = sqlx::query!(
        "SELECT u.id, u.username, u.display_name, a.role FROM page_admins a
         JOIN users u ON u.id = a.user_id WHERE a.page_id = $1
         ORDER BY a.role DESC, a.created_at",
        p.id
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<PageAdminDto> = rows
        .into_iter()
        .map(|r| PageAdminDto {
            user: crate::routes::posts::AuthorDto {
                id: r.id,
                username: r.username,
                display_name: r.display_name,
                avatar_url: None,
            },
            role: r.role,
        })
        .collect();
    crate::routes::posts::fill_avatars(&state, items.iter_mut().map(|a| &mut a.user)).await?;
    Ok(Json(ListDto { items }))
}

#[derive(Debug, Deserialize)]
pub struct SetImage {
    pub media_id: Uuid,
}

/// Troca a logo (`logo = true`, foto kind=avatar) ou a capa (kind=cover).
async fn set_image(
    state: &AppState,
    user: &AuthUser,
    slug: &str,
    media_id: Option<Uuid>,
    logo: bool,
) -> AppResult<PageDto> {
    let p = load(state, slug).await?;
    if role(state, p.id, user).await?.is_none() {
        return Err(AppError::Forbidden);
    }
    let mut tx = state.db.begin().await?;
    if let Some(m) = media_id {
        let kind = if logo {
            crate::media::Kind::Avatar
        } else {
            crate::media::Kind::Cover
        };
        crate::routes::photos::claim(&mut tx, user.user_id, kind, &[m]).await?;
    }
    let old = if logo {
        sqlx::query_scalar!(
            "UPDATE pages p SET logo_media_id = $2 FROM pages o
             WHERE p.id = $1 AND o.id = p.id RETURNING o.logo_media_id",
            p.id,
            media_id
        )
        .fetch_one(&mut *tx)
        .await?
    } else {
        sqlx::query_scalar!(
            "UPDATE pages p SET cover_media_id = $2 FROM pages o
             WHERE p.id = $1 AND o.id = p.id RETURNING o.cover_media_id",
            p.id,
            media_id
        )
        .fetch_one(&mut *tx)
        .await?
    };
    let old_keys = match old {
        Some(old) if Some(old) != media_id => {
            sqlx::query_scalar!("DELETE FROM media WHERE id = $1 RETURNING key", old)
                .fetch_all(&mut *tx)
                .await?
        }
        _ => vec![],
    };
    tx.commit().await?;
    state.media.delete_later(old_keys);
    let p = load(state, slug).await?;
    to_dto(state, p, user).await
}

/// PUT /v1/pages/{slug}/logo `{media_id}` (foto enviada com kind=avatar).
pub async fn set_logo(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Json(req): Json<SetImage>,
) -> AppResult<Json<PageDto>> {
    Ok(Json(
        set_image(&state, &user, &slug, Some(req.media_id), true).await?,
    ))
}

/// DELETE /v1/pages/{slug}/logo
pub async fn delete_logo(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<Json<PageDto>> {
    Ok(Json(set_image(&state, &user, &slug, None, true).await?))
}

/// PUT /v1/pages/{slug}/cover `{media_id}` (foto enviada com kind=cover).
pub async fn set_cover(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Json(req): Json<SetImage>,
) -> AppResult<Json<PageDto>> {
    Ok(Json(
        set_image(&state, &user, &slug, Some(req.media_id), false).await?,
    ))
}

/// DELETE /v1/pages/{slug}/cover
pub async fn delete_cover(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<Json<PageDto>> {
    Ok(Json(set_image(&state, &user, &slug, None, false).await?))
}

/// GET /v1/pages/{slug}/posts?before= — mural da página. Todos veem.
pub async fn wall(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Query(q): Query<crate::routes::pagination::PageQuery>,
) -> AppResult<Json<crate::routes::pagination::Page<crate::routes::posts::PostDto>>> {
    let p = load(&state, &slug).await?;
    Ok(Json(
        crate::routes::posts::page_wall(&state, user.user_id, p.id, &q).await?,
    ))
}

/// POST /v1/pages/{slug}/posts `{body, media_ids}` — quem administra publica
/// no mural. Aparece no feed de quem acompanha.
pub async fn post_to_wall(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Json(req): Json<crate::routes::posts::CreatePost>,
) -> AppResult<(StatusCode, Json<crate::routes::posts::PostDto>)> {
    let p = load(&state, &slug).await?;
    if !crate::routes::posts::is_page_admin(&state.db, p.id, user.user_id).await? {
        return Err(AppError::Forbidden);
    }
    let dto = crate::routes::posts::insert(&state, user.user_id, Some(p.id), req).await?;
    Ok((StatusCode::CREATED, Json(dto)))
}

//! Comunidades-fórum (SPEC 4.5): criação, busca, entrada, papéis e moderação.
//!
//! - Pública: qualquer pessoa logada lê os tópicos e entra na hora.
//! - Fechada: nome, descrição e regras são visíveis; tópicos só para membros;
//!   entrar exige aprovação de um moderador.
//! - Papéis: dono (um só), moderador, membro. Administradores da plataforma
//!   têm os poderes de moderador em qualquer comunidade.
//! - Contagem de membros só para quem modera (R3).

use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use sqlx::PgExecutor;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    routes::{friends::ListDto, posts::AuthorDto, profiles::user_id_by_username},
    validation,
};

/// Quantas comunidades uma pessoa pode ter como dona.
pub const MAX_OWNED: i64 = 10;
/// Quantas comunidades uma pessoa pode integrar (ativas + pedidos).
pub const MAX_JOINED: i64 = 300;

// ---------------------------------------------------------------- acesso

pub struct Community {
    pub id: Uuid,
    pub slug: String,
    pub name: String,
    pub description: String,
    pub rules: String,
    pub theme: String,
    pub visibility: String,
    pub created_at: OffsetDateTime,
}

/// Papel e situação de quem está pedindo, nesta comunidade.
#[derive(Debug, Clone, Default)]
pub struct Access {
    pub role: Option<String>,
    pub status: Option<String>,
    pub is_admin: bool,
    pub public: bool,
}

impl Access {
    pub fn is_member(&self) -> bool {
        self.status.as_deref() == Some("active")
    }
    pub fn is_banned(&self) -> bool {
        self.status.as_deref() == Some("banned")
    }
    pub fn is_owner(&self) -> bool {
        self.is_member() && self.role.as_deref() == Some("owner")
    }
    pub fn is_mod(&self) -> bool {
        self.is_admin
            || (self.is_member() && matches!(self.role.as_deref(), Some("owner" | "moderator")))
    }
    pub fn can_read(&self) -> bool {
        self.public || self.is_member() || self.is_admin
    }
    pub fn can_post(&self) -> bool {
        self.is_member()
    }
}

pub async fn load_by_slug(state: &AppState, raw: &str) -> AppResult<Community> {
    let slug = validation::community_slug(raw).map_err(|_| AppError::NotFound)?;
    sqlx::query_as!(
        Community,
        "SELECT id, slug, name, description, rules, theme, visibility, created_at
         FROM communities WHERE slug = $1 AND deleted_at IS NULL",
        slug
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)
}

pub async fn access<'e>(
    db: impl PgExecutor<'e>,
    community: &Community,
    user: &AuthUser,
) -> sqlx::Result<Access> {
    let row = sqlx::query!(
        "SELECT role, status FROM community_members WHERE community_id = $1 AND user_id = $2",
        community.id,
        user.user_id
    )
    .fetch_optional(db)
    .await?;
    Ok(Access {
        role: row.as_ref().map(|r| r.role.clone()),
        status: row.map(|r| r.status),
        is_admin: user.is_admin,
        public: community.visibility == "public",
    })
}

// ---------------------------------------------------------------- DTOs

#[derive(Debug, Serialize)]
pub struct CommunityDto {
    pub id: Uuid,
    pub slug: String,
    pub name: String,
    pub description: String,
    pub rules: String,
    pub theme: String,
    pub visibility: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    pub my_role: Option<String>,
    pub my_status: Option<String>,
    pub can_read: bool,
    pub can_post: bool,
    pub can_moderate: bool,
    /// Só para quem modera (R3).
    pub member_count: Option<i64>,
    pub pending_count: Option<i64>,
}

async fn to_dto(state: &AppState, c: Community, a: &Access) -> AppResult<CommunityDto> {
    let (member_count, pending_count) = if a.is_mod() {
        let r = sqlx::query!(
            r#"SELECT count(*) FILTER (WHERE status = 'active') AS "active!",
                      count(*) FILTER (WHERE status = 'pending') AS "pending!"
               FROM community_members WHERE community_id = $1"#,
            c.id
        )
        .fetch_one(&state.db)
        .await?;
        (Some(r.active), Some(r.pending))
    } else {
        (None, None)
    };
    Ok(CommunityDto {
        id: c.id,
        slug: c.slug,
        name: c.name,
        description: c.description,
        rules: c.rules,
        theme: c.theme,
        visibility: c.visibility,
        created_at: c.created_at,
        my_role: a.role.clone(),
        my_status: a.status.clone(),
        can_read: a.can_read(),
        can_post: a.can_post(),
        can_moderate: a.is_mod(),
        member_count,
        pending_count,
    })
}

#[derive(Debug, Serialize)]
pub struct CommunityItemDto {
    pub id: Uuid,
    pub slug: String,
    pub name: String,
    pub description: String,
    pub theme: String,
    pub visibility: String,
    pub my_role: Option<String>,
    pub my_status: Option<String>,
}

// ---------------------------------------------------------------- listar / criar

#[derive(Debug, Deserialize)]
pub struct ListQuery {
    /// Busca no nome e no endereço.
    pub q: Option<String>,
    pub theme: Option<String>,
    /// Só as minhas (membro ou pedido pendente).
    #[serde(default)]
    pub mine: bool,
}

/// GET /v1/communities?q=&theme=&mine=true — ordem alfabética, até 100.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<ListDto<CommunityItemDto>>> {
    let pattern =
        q.q.as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(|s| {
                let s: String = s.chars().take(60).collect();
                let escaped = s
                    .replace('\\', "\\\\")
                    .replace('%', "\\%")
                    .replace('_', "\\_");
                format!("%{escaped}%")
            });
    let theme = q.theme.filter(|t| !t.is_empty());
    let items = sqlx::query_as!(
        CommunityItemDto,
        r#"
        SELECT c.id, c.slug, c.name, c.description, c.theme, c.visibility,
               m.role AS "my_role?", m.status AS "my_status?"
        FROM communities c
        LEFT JOIN community_members m ON m.community_id = c.id AND m.user_id = $1
        WHERE c.deleted_at IS NULL
          AND ($2::text IS NULL OR c.name ILIKE $2 ESCAPE '\' OR c.slug ILIKE $2 ESCAPE '\')
          AND ($3::text IS NULL OR c.theme = $3)
          AND (NOT $4 OR m.status IN ('active', 'pending'))
        ORDER BY lower(c.name), c.id
        LIMIT 100
        "#,
        user.user_id,
        pattern,
        theme,
        q.mine,
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto { items }))
}

#[derive(Debug, Deserialize)]
pub struct CreateCommunity {
    /// Opcional: se faltar, é gerado a partir do nome.
    pub slug: Option<String>,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub rules: String,
    pub theme: String,
    pub visibility: String,
}

fn visibility(raw: &str) -> AppResult<String> {
    match raw {
        "public" | "closed" => Ok(raw.to_owned()),
        _ => Err(AppError::Validation("invalid_visibility")),
    }
}

/// POST /v1/communities — quem cria vira dono.
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreateCommunity>,
) -> AppResult<(StatusCode, Json<CommunityDto>)> {
    let name = validation::community_name(&req.name)?;
    let slug = match req.slug.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        Some(s) => validation::community_slug(s)?,
        None => validation::community_slug(&validation::slugify(&name))?,
    };
    let description = validation::community_text(&req.description)?;
    let rules = validation::community_text(&req.rules)?;
    let theme = validation::community_theme(&req.theme)?;
    let visibility = visibility(&req.visibility)?;

    let mut tx = state.db.begin().await?;
    // Serializa criações da mesma pessoa (limite sem corrida).
    sqlx::query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1::text, 7))",
        user.user_id.to_string()
    )
    .execute(&mut *tx)
    .await?;
    let owned = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM community_members m
           JOIN communities c ON c.id = m.community_id
           WHERE m.user_id = $1 AND m.role = 'owner' AND c.deleted_at IS NULL"#,
        user.user_id
    )
    .fetch_one(&mut *tx)
    .await?;
    if owned >= MAX_OWNED {
        return Err(AppError::LimitReached("community_limit"));
    }
    let id = Uuid::now_v7();
    let created_at = sqlx::query_scalar!(
        r#"
        INSERT INTO communities (id, slug, name, description, rules, theme, visibility, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (slug) DO NOTHING
        RETURNING created_at
        "#,
        id,
        slug,
        name,
        description,
        rules,
        theme,
        visibility,
        user.user_id
    )
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::Conflict("slug_taken"))?;
    sqlx::query!(
        "INSERT INTO community_members (community_id, user_id, role, status)
         VALUES ($1, $2, 'owner', 'active')",
        id,
        user.user_id
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    tracing::info!(community_id = %id, "community created");

    let c = Community {
        id,
        slug,
        name,
        description,
        rules,
        theme,
        visibility,
        created_at,
    };
    let a = Access {
        role: Some("owner".into()),
        status: Some("active".into()),
        is_admin: user.is_admin,
        public: c.visibility == "public",
    };
    Ok((StatusCode::CREATED, Json(to_dto(&state, c, &a).await?)))
}

// ---------------------------------------------------------------- ver / editar / apagar

/// GET /v1/communities/{slug}
pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<Json<CommunityDto>> {
    let c = load_by_slug(&state, &slug).await?;
    let a = access(&state.db, &c, &user).await?;
    Ok(Json(to_dto(&state, c, &a).await?))
}

#[derive(Debug, Deserialize)]
pub struct UpdateCommunity {
    pub name: Option<String>,
    pub description: Option<String>,
    pub rules: Option<String>,
    pub theme: Option<String>,
    pub visibility: Option<String>,
}

/// PATCH /v1/communities/{slug} — dono (ou admin). O endereço não muda.
pub async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Json(req): Json<UpdateCommunity>,
) -> AppResult<Json<CommunityDto>> {
    let mut c = load_by_slug(&state, &slug).await?;
    let a = access(&state.db, &c, &user).await?;
    if !(a.is_owner() || a.is_admin) {
        return Err(AppError::Forbidden);
    }
    if let Some(v) = &req.name {
        c.name = validation::community_name(v)?;
    }
    if let Some(v) = &req.description {
        c.description = validation::community_text(v)?;
    }
    if let Some(v) = &req.rules {
        c.rules = validation::community_text(v)?;
    }
    if let Some(v) = &req.theme {
        c.theme = validation::community_theme(v)?;
    }
    let opened = match &req.visibility {
        Some(v) => {
            let v = visibility(v)?;
            let opened = c.visibility == "closed" && v == "public";
            c.visibility = v;
            opened
        }
        None => false,
    };
    let mut tx = state.db.begin().await?;
    sqlx::query!(
        "UPDATE communities SET name = $2, description = $3, rules = $4, theme = $5, visibility = $6
         WHERE id = $1",
        c.id,
        c.name,
        c.description,
        c.rules,
        c.theme,
        c.visibility
    )
    .execute(&mut *tx)
    .await?;
    if opened {
        // Abriu a comunidade: quem estava esperando entra.
        sqlx::query!(
            "UPDATE community_members SET status = 'active'
             WHERE community_id = $1 AND status = 'pending'",
            c.id
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    let a = Access {
        public: c.visibility == "public",
        ..a
    };
    Ok(Json(to_dto(&state, c, &a).await?))
}

/// DELETE /v1/communities/{slug} — dono (ou admin). Some para todos.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<StatusCode> {
    let c = load_by_slug(&state, &slug).await?;
    let a = access(&state.db, &c, &user).await?;
    if !(a.is_owner() || a.is_admin) {
        return Err(AppError::Forbidden);
    }
    sqlx::query!(
        "UPDATE communities SET deleted_at = now() WHERE id = $1",
        c.id
    )
    .execute(&state.db)
    .await?;
    tracing::info!(community_id = %c.id, "community deleted");
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------- entrar / sair

#[derive(Debug, Serialize)]
pub struct MembershipDto {
    /// active | pending
    pub status: String,
}

/// PUT /v1/communities/{slug}/membership — entra (pública) ou pede para
/// entrar (fechada). Idempotente.
pub async fn join(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<Json<MembershipDto>> {
    let c = load_by_slug(&state, &slug).await?;
    let a = access(&state.db, &c, &user).await?;
    if a.is_banned() {
        return Err(AppError::Forbidden);
    }
    if let Some(status) = a.status {
        return Ok(Json(MembershipDto { status }));
    }
    let joined = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM community_members WHERE user_id = $1 AND status <> 'banned'"#,
        user.user_id
    )
    .fetch_one(&state.db)
    .await?;
    if joined >= MAX_JOINED {
        return Err(AppError::LimitReached("community_join_limit"));
    }
    let status = if c.visibility == "public" {
        "active"
    } else {
        "pending"
    };
    let status = sqlx::query_scalar!(
        r#"
        INSERT INTO community_members (community_id, user_id, role, status)
        VALUES ($1, $2, 'member', $3)
        ON CONFLICT (community_id, user_id) DO UPDATE SET status = community_members.status
        RETURNING status
        "#,
        c.id,
        user.user_id,
        status
    )
    .fetch_one(&state.db)
    .await?;
    if status == "banned" {
        return Err(AppError::Forbidden);
    }
    Ok(Json(MembershipDto { status }))
}

/// DELETE /v1/communities/{slug}/membership — sai, ou cancela o pedido.
/// O dono não sai: transfere a comunidade ou apaga.
pub async fn leave(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
) -> AppResult<StatusCode> {
    let c = load_by_slug(&state, &slug).await?;
    let a = access(&state.db, &c, &user).await?;
    if a.role.as_deref() == Some("owner") {
        return Err(AppError::Validation("owner_cannot_leave"));
    }
    sqlx::query!(
        "DELETE FROM community_members
         WHERE community_id = $1 AND user_id = $2 AND status <> 'banned'",
        c.id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------- membros

#[derive(Debug, Deserialize)]
pub struct MembersQuery {
    /// active (padrão) | pending | banned
    pub status: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct MemberDto {
    pub user: AuthorDto,
    pub role: String,
    pub status: String,
    #[serde(with = "time::serde::rfc3339")]
    pub since: OffsetDateTime,
}

/// GET /v1/communities/{slug}/members?status= — membros veem os ativos;
/// pendentes e banidos, só quem modera.
pub async fn members(
    State(state): State<AppState>,
    user: AuthUser,
    Path(slug): Path<String>,
    Query(q): Query<MembersQuery>,
) -> AppResult<Json<ListDto<MemberDto>>> {
    let c = load_by_slug(&state, &slug).await?;
    let a = access(&state.db, &c, &user).await?;
    let status = q.status.unwrap_or_else(|| "active".into());
    match status.as_str() {
        "active" if a.is_member() || a.is_mod() => {}
        "pending" | "banned" if a.is_mod() => {}
        "active" | "pending" | "banned" => return Err(AppError::Forbidden),
        _ => return Err(AppError::Validation("invalid_status")),
    }
    let rows = sqlx::query!(
        r#"
        SELECT u.id, u.username, u.display_name, m.role, m.status, m.created_at
        FROM community_members m JOIN users u ON u.id = m.user_id
        WHERE m.community_id = $1 AND m.status = $2
          AND ($4 OR NOT EXISTS (
            SELECT 1 FROM blocks b
            WHERE (b.blocker_id = $3 AND b.blocked_id = u.id)
               OR (b.blocker_id = u.id AND b.blocked_id = $3)))
        ORDER BY CASE m.role WHEN 'owner' THEN 0 WHEN 'moderator' THEN 1 ELSE 2 END,
                 lower(u.username)
        LIMIT 1000
        "#,
        c.id,
        status,
        user.user_id,
        a.is_mod()
    )
    .fetch_all(&state.db)
    .await?;
    let items = rows
        .into_iter()
        .map(|r| MemberDto {
            user: AuthorDto {
                id: r.id,
                username: r.username,
                display_name: r.display_name,
            },
            role: r.role,
            status: r.status,
            since: r.created_at,
        })
        .collect();
    Ok(Json(ListDto { items }))
}

#[derive(Debug, Deserialize)]
pub struct MemberAction {
    /// approve | reject | ban | unban | promote | demote | transfer
    pub action: String,
}

/// POST /v1/communities/{slug}/members/{username}
///
/// - moderadores: approve, reject, ban, unban (não banem o dono nem outros moderadores);
/// - dono (ou admin): promote, demote e ban de moderador;
/// - só o dono: transfer (o alvo vira dono e o dono vira moderador).
pub async fn member_action(
    State(state): State<AppState>,
    user: AuthUser,
    Path((slug, username)): Path<(String, String)>,
    Json(req): Json<MemberAction>,
) -> AppResult<StatusCode> {
    let c = load_by_slug(&state, &slug).await?;
    let target = user_id_by_username(&state, &username).await?;
    let mut tx = state.db.begin().await?;
    // Serializa mudanças de papel na mesma comunidade.
    sqlx::query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1::text, 8))",
        c.id.to_string()
    )
    .execute(&mut *tx)
    .await?;
    let a = access(&mut *tx, &c, &user).await?;
    if !a.is_mod() {
        return Err(AppError::Forbidden);
    }
    let boss = a.is_owner() || a.is_admin;
    if target == user.user_id && req.action != "transfer" {
        return Err(AppError::Validation("cannot_target_self"));
    }
    let t = sqlx::query!(
        "SELECT role, status FROM community_members WHERE community_id = $1 AND user_id = $2",
        c.id,
        target
    )
    .fetch_optional(&mut *tx)
    .await?;
    let (t_role, t_status) = match &t {
        Some(r) => (Some(r.role.as_str()), Some(r.status.as_str())),
        None => (None, None),
    };

    match req.action.as_str() {
        "approve" => {
            if t_status != Some("pending") {
                return Err(AppError::NotFound);
            }
            sqlx::query!(
                "UPDATE community_members SET status = 'active', created_at = now()
                 WHERE community_id = $1 AND user_id = $2",
                c.id,
                target
            )
            .execute(&mut *tx)
            .await?;
        }
        "reject" => {
            if t_status != Some("pending") {
                return Err(AppError::NotFound);
            }
            sqlx::query!(
                "DELETE FROM community_members WHERE community_id = $1 AND user_id = $2",
                c.id,
                target
            )
            .execute(&mut *tx)
            .await?;
        }
        "ban" => {
            match t_role {
                Some("owner") => return Err(AppError::Forbidden),
                Some("moderator") if !boss => return Err(AppError::Forbidden),
                _ => {}
            }
            // Banir funciona mesmo para quem ainda não é membro (impede entrar).
            sqlx::query!(
                r#"
                INSERT INTO community_members (community_id, user_id, role, status)
                VALUES ($1, $2, 'member', 'banned')
                ON CONFLICT (community_id, user_id)
                DO UPDATE SET role = 'member', status = 'banned', created_at = now()
                "#,
                c.id,
                target
            )
            .execute(&mut *tx)
            .await?;
        }
        "unban" => {
            if t_status != Some("banned") {
                return Err(AppError::NotFound);
            }
            sqlx::query!(
                "DELETE FROM community_members WHERE community_id = $1 AND user_id = $2",
                c.id,
                target
            )
            .execute(&mut *tx)
            .await?;
        }
        "promote" | "demote" => {
            if !boss {
                return Err(AppError::Forbidden);
            }
            let (from, to) = if req.action == "promote" {
                ("member", "moderator")
            } else {
                ("moderator", "member")
            };
            if t_status != Some("active") || t_role != Some(from) {
                return Err(AppError::Validation("invalid_member_state"));
            }
            sqlx::query!(
                "UPDATE community_members SET role = $3 WHERE community_id = $1 AND user_id = $2",
                c.id,
                target,
                to
            )
            .execute(&mut *tx)
            .await?;
        }
        "transfer" => {
            if !a.is_owner() {
                return Err(AppError::Forbidden);
            }
            if target == user.user_id {
                return Err(AppError::Validation("cannot_target_self"));
            }
            if t_status != Some("active") {
                return Err(AppError::Validation("invalid_member_state"));
            }
            sqlx::query!(
                "UPDATE community_members SET role = 'moderator' WHERE community_id = $1 AND user_id = $2",
                c.id,
                user.user_id
            )
            .execute(&mut *tx)
            .await?;
            sqlx::query!(
                "UPDATE community_members SET role = 'owner' WHERE community_id = $1 AND user_id = $2",
                c.id,
                target
            )
            .execute(&mut *tx)
            .await?;
        }
        _ => return Err(AppError::Validation("invalid_member_action")),
    }
    sqlx::query!(
        "INSERT INTO moderation_actions (id, admin_id, action, target_kind, target_id)
         VALUES ($1, $2, $3, 'community_member', $4)",
        Uuid::now_v7(),
        user.user_id,
        format!("community:{}", req.action),
        target
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Exclusão de conta: cada comunidade da pessoa passa para o moderador mais
/// antigo (ou, sem moderadores, para o membro mais antigo). Sem ninguém, a
/// comunidade é apagada. Roda dentro da transação da exclusão.
pub async fn hand_over_owned(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    user_id: Uuid,
) -> sqlx::Result<()> {
    let owned = sqlx::query_scalar!(
        "SELECT community_id FROM community_members WHERE user_id = $1 AND role = 'owner'",
        user_id
    )
    .fetch_all(&mut **tx)
    .await?;
    for community_id in owned {
        sqlx::query!(
            "UPDATE community_members SET role = 'member' WHERE community_id = $1 AND user_id = $2",
            community_id,
            user_id
        )
        .execute(&mut **tx)
        .await?;
        let heir = sqlx::query_scalar!(
            r#"
            SELECT user_id FROM community_members
            WHERE community_id = $1 AND user_id <> $2 AND status = 'active'
            ORDER BY (role = 'moderator') DESC, created_at ASC
            LIMIT 1
            "#,
            community_id,
            user_id
        )
        .fetch_optional(&mut **tx)
        .await?;
        match heir {
            Some(heir) => {
                sqlx::query!(
                    "UPDATE community_members SET role = 'owner' WHERE community_id = $1 AND user_id = $2",
                    community_id,
                    heir
                )
                .execute(&mut **tx)
                .await?;
            }
            None => {
                sqlx::query!(
                    "UPDATE communities SET deleted_at = now() WHERE id = $1 AND deleted_at IS NULL",
                    community_id
                )
                .execute(&mut **tx)
                .await?;
            }
        }
    }
    Ok(())
}

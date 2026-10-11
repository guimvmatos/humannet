//! Coletivos estudantis (república, atlética, centro acadêmico, grupo):
//! criam eventos sem CNPJ, com controle (decisão de 2026-10-10, início na
//! UFSCar).
//!
//! 1. O aluno pede para virar organizador, com e-mail institucional.
//! 2. Se o envio de e-mail estiver ligado, confirma o e-mail com um código.
//! 3. A administração aprova: nasce a página do tipo `coletivo`, com a pessoa
//!    como dona e responsável visível.
//! 4. Os 2 primeiros eventos de cada coletivo passam por revisão; no máximo
//!    3 eventos por semana.

use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

use crate::{
    AppState,
    auth::{AdminUser, AuthUser},
    crypto,
    error::{AppError, AppResult},
    routes::{friends::ListDto, posts::AuthorDto},
    validation,
};

pub const CATEGORIES: &[&str] = &["republica", "atletica", "centro_academico", "coletivo"];
/// Eventos de um coletivo que passam por revisão antes de sair direto.
pub const REVIEWED_EVENTS: i64 = 2;
/// Eventos criados por coletivo em 7 dias.
pub const MAX_EVENTS_PER_WEEK: i64 = 3;
const CODE_TTL_MINUTES: i64 = 30;

/// Domínios aceitos para o e-mail institucional (`INSTITUTION_EMAIL_DOMAINS`,
/// separados por vírgula; padrão `ufscar.br`). Vale o domínio e subdomínios
/// (ex.: `estudante.ufscar.br`).
fn institution_domains() -> Vec<String> {
    std::env::var("INSTITUTION_EMAIL_DOMAINS")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| "ufscar.br".to_owned())
        .split(',')
        .map(|d| d.trim().trim_start_matches('@').to_ascii_lowercase())
        .filter(|d| !d.is_empty())
        .collect()
}

fn institution_email(raw: &str) -> AppResult<String> {
    let email =
        validation::email(raw).map_err(|_| AppError::Validation("invalid_institution_email"))?;
    let domain = email.rsplit('@').next().unwrap_or("");
    let ok = institution_domains()
        .iter()
        .any(|d| domain == d || domain.ends_with(&format!(".{d}")));
    if ok {
        Ok(email)
    } else {
        Err(AppError::Validation("invalid_institution_email"))
    }
}

fn new_code() -> String {
    let mut b = [0u8; 4];
    rand::fill(&mut b);
    format!("{:06}", u32::from_le_bytes(b) % 1_000_000)
}

#[derive(Debug, Serialize)]
pub struct RequestDto {
    pub id: Uuid,
    pub name: String,
    pub category: String,
    pub description: String,
    pub institution_email: String,
    pub email_verified: bool,
    /// O servidor consegue mandar o código? Sem isso, a confirmação do e-mail
    /// fica com a administração.
    pub email_check: &'static str,
    /// pending | approved | rejected
    pub status: String,
    pub reason: String,
    /// Página criada na aprovação.
    pub page_slug: Option<String>,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    /// Só na lista da administração.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user: Option<AuthorDto>,
}

struct Row {
    id: Uuid,
    name: String,
    category: String,
    description: String,
    institution_email: String,
    email_verified: bool,
    status: String,
    reason: String,
    page_slug: Option<String>,
    created_at: OffsetDateTime,
    user_id: Uuid,
    username: String,
    display_name: Option<String>,
}

impl Row {
    fn dto(self, state: &AppState, with_user: bool) -> RequestDto {
        RequestDto {
            id: self.id,
            name: self.name,
            category: self.category,
            description: self.description,
            institution_email: self.institution_email,
            email_verified: self.email_verified,
            email_check: if state.mailer.enabled() {
                "code"
            } else {
                "manual"
            },
            status: self.status,
            reason: self.reason,
            page_slug: self.page_slug,
            created_at: self.created_at,
            user: with_user.then_some(AuthorDto {
                id: self.user_id,
                username: self.username,
                display_name: self.display_name,
                avatar_url: None,
            }),
        }
    }
}

async fn latest(state: &AppState, user: Uuid) -> AppResult<Option<Row>> {
    Ok(sqlx::query_as!(
        Row,
        r#"SELECT r.id, r.name, r.category, r.description, r.institution_email,
                  (r.email_verified_at IS NOT NULL) AS "email_verified!", r.status, r.reason,
                  p.slug AS "page_slug?", r.created_at, u.id AS user_id, u.username,
                  u.display_name
           FROM organizer_requests r JOIN users u ON u.id = r.user_id
           LEFT JOIN pages p ON p.id = r.page_id AND p.deleted_at IS NULL
           WHERE r.user_id = $1
           ORDER BY r.created_at DESC LIMIT 1"#,
        user
    )
    .fetch_optional(&state.db)
    .await?)
}

#[derive(Debug, Deserialize)]
pub struct NewRequest {
    pub name: String,
    pub category: String,
    #[serde(default)]
    pub description: String,
    pub institution_email: String,
}

async fn send_code(state: &AppState, id: Uuid, email: &str) -> AppResult<()> {
    if !state.mailer.enabled() {
        return Ok(());
    }
    let code = new_code();
    sqlx::query!(
        "UPDATE organizer_requests SET email_code_hash = $2, email_code_expires_at = $3
         WHERE id = $1",
        id,
        crypto::sha256(&code),
        OffsetDateTime::now_utc() + Duration::minutes(CODE_TTL_MINUTES)
    )
    .execute(&state.db)
    .await?;
    let text = format!(
        "Seu código para confirmar o e-mail na HumanNet é {code}.\n\n\
         Ele vale {CODE_TTL_MINUTES} minutos. Se não foi você, ignore este e-mail."
    );
    if let Err(e) = state
        .mailer
        .send(email, "HumanNet: código de confirmação", &text)
        .await
    {
        tracing::warn!(error = %e, "código do coletivo não enviado");
        return Err(AppError::Validation("email_send_failed"));
    }
    Ok(())
}

/// POST /v1/organizer-requests — pedir para virar organizador (coletivo).
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<NewRequest>,
) -> AppResult<(StatusCode, Json<RequestDto>)> {
    let name = validation::line(&req.name, 2, 80, "invalid_page_name")?;
    if !CATEGORIES.contains(&req.category.as_str()) {
        return Err(AppError::Validation("invalid_page_category"));
    }
    let description = validation::long_text(&req.description, 1000, "invalid_page_description")?;
    let email = institution_email(&req.institution_email)?;
    let id = Uuid::now_v7();
    sqlx::query!(
        "INSERT INTO organizer_requests (id, user_id, name, category, description, institution_email)
         VALUES ($1, $2, $3, $4, $5, $6)",
        id,
        user.user_id,
        name,
        req.category,
        description,
        email
    )
    .execute(&state.db)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(d) if d.is_unique_violation() => {
            AppError::Conflict("request_pending")
        }
        _ => AppError::from(e),
    })?;
    send_code(&state, id, &email).await?;
    let row = latest(&state, user.user_id)
        .await?
        .ok_or(AppError::NotFound)?;
    Ok((StatusCode::CREATED, Json(row.dto(&state, false))))
}

/// GET /v1/organizer-requests/mine — meu pedido mais recente (ou 404).
pub async fn mine(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<RequestDto>> {
    let row = latest(&state, user.user_id)
        .await?
        .ok_or(AppError::NotFound)?;
    Ok(Json(row.dto(&state, false)))
}

#[derive(Debug, Deserialize)]
pub struct VerifyCode {
    pub code: String,
}

/// POST /v1/organizer-requests/verify `{code}` — confirma o e-mail.
pub async fn verify(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<VerifyCode>,
) -> AppResult<Json<RequestDto>> {
    let code: String = req.code.chars().filter(char::is_ascii_digit).collect();
    let n = sqlx::query!(
        "UPDATE organizer_requests
         SET email_verified_at = now(), email_code_hash = NULL, email_code_expires_at = NULL
         WHERE user_id = $1 AND status = 'pending' AND email_code_hash = $2
           AND email_code_expires_at > now()",
        user.user_id,
        crypto::sha256(&code)
    )
    .execute(&state.db)
    .await?
    .rows_affected();
    if n == 0 {
        return Err(AppError::Validation("invalid_code"));
    }
    let row = latest(&state, user.user_id)
        .await?
        .ok_or(AppError::NotFound)?;
    Ok(Json(row.dto(&state, false)))
}

/// POST /v1/organizer-requests/resend — manda outro código.
pub async fn resend(State(state): State<AppState>, user: AuthUser) -> AppResult<StatusCode> {
    let r = sqlx::query!(
        "SELECT id, institution_email FROM organizer_requests
         WHERE user_id = $1 AND status = 'pending' AND email_verified_at IS NULL",
        user.user_id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    send_code(&state, r.id, &r.institution_email).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /v1/admin/organizer-requests — pedidos pendentes.
pub async fn admin_list(
    State(state): State<AppState>,
    _admin: AdminUser,
) -> AppResult<Json<ListDto<RequestDto>>> {
    let rows = sqlx::query_as!(
        Row,
        r#"SELECT r.id, r.name, r.category, r.description, r.institution_email,
                  (r.email_verified_at IS NOT NULL) AS "email_verified!", r.status, r.reason,
                  NULL::text AS "page_slug?", r.created_at, u.id AS user_id, u.username,
                  u.display_name
           FROM organizer_requests r JOIN users u ON u.id = r.user_id
           WHERE r.status = 'pending'
           ORDER BY r.created_at
           LIMIT 100"#
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto {
        items: rows.into_iter().map(|r| r.dto(&state, true)).collect(),
    }))
}

/// POST /v1/admin/organizer-requests/{id}/approve — cria o coletivo.
pub async fn approve(
    State(state): State<AppState>,
    admin: AdminUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<RequestDto>> {
    let r = sqlx::query!(
        "SELECT user_id, name, category, description FROM organizer_requests
         WHERE id = $1 AND status = 'pending'",
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    let base = validation::slugify(&r.name);
    let mut tx = state.db.begin().await?;
    let page_id = Uuid::now_v7();
    // Slug livre: nome, depois nome-2, nome-3...
    let mut slug = String::new();
    for i in 1..=50 {
        let candidate = if i == 1 {
            base.clone()
        } else {
            format!("{base}-{i}")
        };
        let Ok(c) = validation::community_slug(&candidate) else {
            continue;
        };
        let taken = sqlx::query_scalar!(
            r#"SELECT EXISTS (SELECT 1 FROM pages WHERE slug = $1) AS "e!""#,
            c
        )
        .fetch_one(&mut *tx)
        .await?;
        if !taken {
            slug = c;
            break;
        }
    }
    if slug.is_empty() {
        slug = format!("coletivo-{}", &page_id.simple().to_string()[..8]);
    }
    sqlx::query!(
        "INSERT INTO pages (id, slug, name, category, description, kind, created_by, verified_at)
         VALUES ($1, $2, $3, $4, $5, 'coletivo', $6, now())",
        page_id,
        slug,
        r.name,
        r.category,
        r.description,
        r.user_id
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "INSERT INTO page_admins (page_id, user_id, role) VALUES ($1, $2, 'owner')",
        page_id,
        r.user_id
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "UPDATE organizer_requests SET status = 'approved', decided_by = $2, decided_at = now(),
           page_id = $3
         WHERE id = $1",
        id,
        admin.0.user_id,
        page_id
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    let row = latest(&state, r.user_id).await?.ok_or(AppError::NotFound)?;
    Ok(Json(row.dto(&state, true)))
}

#[derive(Debug, Deserialize)]
pub struct Reject {
    #[serde(default)]
    pub reason: String,
}

/// POST /v1/admin/organizer-requests/{id}/reject `{reason}`
pub async fn reject(
    State(state): State<AppState>,
    admin: AdminUser,
    Path(id): Path<Uuid>,
    Json(req): Json<Reject>,
) -> AppResult<StatusCode> {
    let reason = validation::long_text(&req.reason, 300, "invalid_reason")?;
    let n = sqlx::query!(
        "UPDATE organizer_requests SET status = 'rejected', reason = $3, decided_by = $2,
           decided_at = now(), email_code_hash = NULL
         WHERE id = $1 AND status = 'pending'",
        id,
        admin.0.user_id,
        reason
    )
    .execute(&state.db)
    .await?
    .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound);
    }
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Serialize)]
pub struct PendingEvent {
    pub id: Uuid,
    pub title: String,
    pub description: String,
    #[serde(with = "time::serde::rfc3339")]
    pub starts_at: OffsetDateTime,
    pub location: String,
    pub page_slug: String,
    pub page_name: String,
    pub responsible: Option<String>,
}

/// GET /v1/admin/events/pending — eventos de coletivos esperando revisão.
pub async fn pending_events(
    State(state): State<AppState>,
    _admin: AdminUser,
) -> AppResult<Json<ListDto<PendingEvent>>> {
    let items = sqlx::query_as!(
        PendingEvent,
        r#"SELECT e.id, e.title, e.description, e.starts_at,
                  CASE WHEN e.location = '' THEN p.address ELSE e.location END AS "location!",
                  p.slug AS page_slug, p.name AS page_name,
                  (SELECT u.username FROM page_admins a JOIN users u ON u.id = a.user_id
                    WHERE a.page_id = p.id AND a.role = 'owner') AS responsible
           FROM events e JOIN pages p ON p.id = e.page_id AND p.deleted_at IS NULL
           WHERE e.status = 'pending_review' AND e.deleted_at IS NULL
           ORDER BY e.starts_at
           LIMIT 100"#
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto { items }))
}

#[derive(Debug, Deserialize)]
pub struct Review {
    pub approve: bool,
}

/// POST /v1/admin/events/{id}/review `{approve}`
pub async fn review_event(
    State(state): State<AppState>,
    _admin: AdminUser,
    Path(id): Path<Uuid>,
    Json(req): Json<Review>,
) -> AppResult<StatusCode> {
    let status = if req.approve { "published" } else { "rejected" };
    let n = sqlx::query!(
        "UPDATE events SET status = $2 WHERE id = $1 AND status = 'pending_review'",
        id,
        status
    )
    .execute(&state.db)
    .await?
    .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound);
    }
    Ok(StatusCode::NO_CONTENT)
}

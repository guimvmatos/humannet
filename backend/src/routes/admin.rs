//! Moderação (só administradores) e redefinição de senha assistida.

use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

use crate::{
    AppState,
    auth::AdminUser,
    crypto,
    error::{AppError, AppResult},
    routes::{friends::ListDto, profiles::user_id_by_username},
    validation,
};

/// Validade do código de redefinição de senha.
pub const RESET_TTL_HOURS: i64 = 24;
/// Tentativas erradas antes de o código ser invalidado.
pub const RESET_MAX_ATTEMPTS: i32 = 5;

/// Sincroniza os administradores com a lista da configuração (ADMIN_USERNAMES).
pub async fn sync_admins(db: &sqlx::PgPool, usernames: &[String]) -> sqlx::Result<()> {
    sqlx::query!(
        "UPDATE users SET role = CASE WHEN username = ANY($1) THEN 'admin' ELSE 'user' END
         WHERE role <> CASE WHEN username = ANY($1) THEN 'admin' ELSE 'user' END",
        usernames
    )
    .execute(db)
    .await?;
    Ok(())
}

async fn log_action(
    db: &sqlx::PgPool,
    admin: Uuid,
    action: &str,
    target_kind: &str,
    target_id: Uuid,
    report_id: Option<Uuid>,
) -> sqlx::Result<()> {
    sqlx::query!(
        "INSERT INTO moderation_actions (id, admin_id, action, target_kind, target_id, report_id)
         VALUES ($1, $2, $3, $4, $5, $6)",
        Uuid::now_v7(),
        admin,
        action,
        target_kind,
        target_id,
        report_id
    )
    .execute(db)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------- denúncias

#[derive(Debug, Deserialize)]
pub struct ReportsQuery {
    pub status: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct AdminReportDto {
    pub id: Uuid,
    pub kind: String,
    pub target_id: Uuid,
    /// Perfil denunciado, ou autor do conteúdo (dono, se for comunidade).
    pub target_username: Option<String>,
    pub target_suspended: bool,
    pub snapshot: String,
    pub reason: String,
    pub details: String,
    pub reporter_username: Option<String>,
    pub status: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
}

/// GET /v1/admin/reports?status=open
pub async fn list_reports(
    State(state): State<AppState>,
    _admin: AdminUser,
    Query(q): Query<ReportsQuery>,
) -> AppResult<Json<ListDto<AdminReportDto>>> {
    let status = q.status.unwrap_or_else(|| "open".to_owned());
    let items = sqlx::query_as!(
        AdminReportDto,
        r#"
        SELECT r.id, r.target_kind AS kind, r.target_id,
               tu.username AS "target_username?",
               (tu.suspended_at IS NOT NULL) AS "target_suspended!",
               r.snapshot, r.reason, r.details,
               ru.username AS "reporter_username?",
               r.status, r.created_at
        FROM reports r
        LEFT JOIN users tu ON tu.id = r.target_user_id
        LEFT JOIN users ru ON ru.id = r.reporter_id
        WHERE r.status = $1
        ORDER BY r.created_at ASC
        LIMIT 200
        "#,
        status
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto { items }))
}

#[derive(Debug, Deserialize)]
pub struct Resolve {
    /// dismiss | remove_content (ou remove_post) | suspend_user
    pub action: String,
}

/// POST /v1/admin/reports/{id}/resolve — aplica a ação e fecha todas as
/// denúncias abertas sobre o mesmo alvo.
pub async fn resolve_report(
    State(state): State<AppState>,
    AdminUser(admin): AdminUser,
    Path(id): Path<Uuid>,
    Json(req): Json<Resolve>,
) -> AppResult<StatusCode> {
    let report = sqlx::query!(
        "SELECT target_kind, target_id, target_user_id FROM reports WHERE id = $1",
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    let new_status = match req.action.as_str() {
        "dismiss" => "dismissed",
        "remove_content" | "remove_post" => {
            remove_content(&state.db, &report.target_kind, report.target_id).await?;
            "actioned"
        }
        "suspend_user" => {
            let user_id = report.target_user_id.ok_or(AppError::NotFound)?;
            suspend(&state.db, user_id).await?;
            "actioned"
        }
        _ => return Err(AppError::Validation("invalid_moderation_action")),
    };

    sqlx::query!(
        "UPDATE reports SET status = $1, resolved_at = now()
         WHERE status = 'open' AND target_kind = $2 AND target_id = $3",
        new_status,
        report.target_kind,
        report.target_id
    )
    .execute(&state.db)
    .await?;
    log_action(
        &state.db,
        admin.user_id,
        &req.action,
        &report.target_kind,
        report.target_id,
        Some(id),
    )
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Remove (apaga o texto de) o conteúdo denunciado. Perfil não é "removível":
/// para isso existe a suspensão.
async fn remove_content(db: &sqlx::PgPool, kind: &str, id: Uuid) -> AppResult<()> {
    const REMOVED: &str = "[removido pela moderação]";
    match kind {
        "post" => {
            sqlx::query!(
                "UPDATE posts SET deleted_at = now(), body = $2 WHERE id = $1 AND deleted_at IS NULL",
                id,
                REMOVED
            )
            .execute(db)
            .await?;
        }
        "comment" => {
            sqlx::query!(
                "UPDATE comments SET deleted_at = now(), body = $2 WHERE id = $1 AND deleted_at IS NULL",
                id,
                REMOVED
            )
            .execute(db)
            .await?;
        }
        "topic" => {
            sqlx::query!(
                "UPDATE topics SET deleted_at = now(), title = $2, body = '' WHERE id = $1 AND deleted_at IS NULL",
                id,
                REMOVED
            )
            .execute(db)
            .await?;
        }
        "reply" => {
            sqlx::query!(
                "UPDATE topic_replies SET deleted_at = now(), body = $2 WHERE id = $1 AND deleted_at IS NULL",
                id,
                REMOVED
            )
            .execute(db)
            .await?;
        }
        "community" => {
            sqlx::query!(
                "UPDATE communities SET deleted_at = now() WHERE id = $1 AND deleted_at IS NULL",
                id
            )
            .execute(db)
            .await?;
        }
        _ => return Err(AppError::Validation("invalid_moderation_action")),
    }
    Ok(())
}

async fn suspend(db: &sqlx::PgPool, user_id: Uuid) -> sqlx::Result<()> {
    let mut tx = db.begin().await?;
    sqlx::query!(
        "UPDATE users SET suspended_at = now() WHERE id = $1 AND suspended_at IS NULL AND role <> 'admin'",
        user_id
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "DELETE FROM sessions WHERE user_id = $1 AND EXISTS (SELECT 1 FROM users WHERE id = $1 AND suspended_at IS NOT NULL)",
        user_id
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await
}

/// POST /v1/admin/users/{username}/unsuspend
pub async fn unsuspend(
    State(state): State<AppState>,
    AdminUser(admin): AdminUser,
    Path(username): Path<String>,
) -> AppResult<StatusCode> {
    let id = user_id_by_username(&state, &username).await?;
    sqlx::query!("UPDATE users SET suspended_at = NULL WHERE id = $1", id)
        .execute(&state.db)
        .await?;
    log_action(&state.db, admin.user_id, "unsuspend", "user", id, None).await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------- senha

#[derive(Debug, Serialize)]
pub struct ResetCodeDto {
    pub code: String,
    #[serde(with = "time::serde::rfc3339")]
    pub expires_at: OffsetDateTime,
}

/// POST /v1/admin/users/{username}/password-reset — gera um código de uso
/// único (24 h). O admin repassa o código à pessoa por um canal confiável.
pub async fn create_reset_code(
    State(state): State<AppState>,
    AdminUser(admin): AdminUser,
    Path(username): Path<String>,
) -> AppResult<(StatusCode, Json<ResetCodeDto>)> {
    let id = user_id_by_username(&state, &username).await?;
    let code = crypto::new_human_code();
    let expires_at = OffsetDateTime::now_utc() + Duration::hours(RESET_TTL_HOURS);
    sqlx::query!(
        r#"
        INSERT INTO password_resets (user_id, code_hash, created_by, expires_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (user_id) DO UPDATE
          SET code_hash = EXCLUDED.code_hash, created_by = EXCLUDED.created_by,
              expires_at = EXCLUDED.expires_at, attempts = 0
        "#,
        id,
        crypto::sha256(&code),
        admin.user_id,
        expires_at
    )
    .execute(&state.db)
    .await?;
    log_action(
        &state.db,
        admin.user_id,
        "password_reset_code",
        "user",
        id,
        None,
    )
    .await?;
    Ok((StatusCode::CREATED, Json(ResetCodeDto { code, expires_at })))
}

#[derive(Debug, Deserialize)]
pub struct ResetPassword {
    pub username: String,
    pub code: String,
    pub new_password: String,
}

/// POST /v1/auth/reset-password — público. Troca a senha com o código e
/// encerra todas as sessões. Erros não revelam se o usuário existe.
pub async fn reset_password(
    State(state): State<AppState>,
    headers: axum::http::HeaderMap,
    Json(req): Json<ResetPassword>,
) -> AppResult<StatusCode> {
    let ip_key = format!("reset-ip:{}", crate::ratelimit::client_ip(&headers));
    if state.auth_limits.per_ip.is_blocked(&ip_key) {
        return Err(AppError::TooManyAttempts);
    }
    validation::password(&req.new_password)?;
    let invalid = AppError::Validation("invalid_reset_code");
    let Ok(username) = validation::username(&req.username) else {
        return Err(invalid);
    };
    let code = req.code.trim().to_ascii_uppercase();

    let mut tx = state.db.begin().await?;
    let row = sqlx::query!(
        r#"
        SELECT r.user_id, r.code_hash, r.attempts
        FROM password_resets r JOIN users u ON u.id = r.user_id
        WHERE u.username = $1 AND r.expires_at > now()
        FOR UPDATE OF r
        "#,
        username
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(row) = row else {
        return Err(invalid);
    };

    if row.code_hash != crypto::sha256(&code) {
        if row.attempts + 1 >= RESET_MAX_ATTEMPTS {
            sqlx::query!(
                "DELETE FROM password_resets WHERE user_id = $1",
                row.user_id
            )
            .execute(&mut *tx)
            .await?;
        } else {
            sqlx::query!(
                "UPDATE password_resets SET attempts = attempts + 1 WHERE user_id = $1",
                row.user_id
            )
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        state.auth_limits.per_ip.record_failure(&ip_key);
        return Err(invalid);
    }

    let new = req.new_password;
    let phc = tokio::task::spawn_blocking(move || crypto::hash_password(&new))
        .await
        .map_err(anyhow::Error::from)??;
    sqlx::query!(
        "UPDATE users SET password_hash = $1 WHERE id = $2",
        phc,
        row.user_id
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!("DELETE FROM sessions WHERE user_id = $1", row.user_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query!(
        "DELETE FROM password_resets WHERE user_id = $1",
        row.user_id
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    tracing::info!(user_id = %row.user_id, "password reset with admin code");
    Ok(StatusCode::NO_CONTENT)
}

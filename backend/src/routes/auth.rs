use axum::{Json, extract::State, http::StatusCode};
use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    crypto,
    error::{AppError, AppResult},
    routes::me::UserDto,
    validation,
};

#[derive(Deserialize)]
pub struct RegisterRequest {
    pub invite_code: String,
    pub username: String,
    pub email: String,
    pub password: String,
    /// Obrigatório quando o servidor exige CPF (CPF_HMAC_KEY definida).
    #[serde(default)]
    pub cpf: Option<String>,
}

#[derive(Deserialize)]
pub struct LoginRequest {
    /// Nome de usuário ou e-mail.
    pub login: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    pub token: String,
    #[serde(with = "time::serde::rfc3339")]
    pub expires_at: OffsetDateTime,
    pub user: UserDto,
}

/// POST /v1/auth/register
pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> AppResult<(StatusCode, Json<AuthResponse>)> {
    let username = validation::username(&req.username)?;
    let email = validation::email(&req.email)?;
    validation::password(&req.password)?;
    let cpf_hmac = cpf_hmac_for(&state, req.cpf.as_deref())?;
    let code = req.invite_code.trim();
    if code.is_empty() || code.len() > 64 {
        return Err(AppError::InvalidInvite);
    }

    let password = req.password;
    let password_hash = tokio::task::spawn_blocking(move || crypto::hash_password(&password))
        .await
        .map_err(anyhow::Error::from)??;

    let mut tx = state.db.begin().await?;

    // Trava o convite para que dois registros simultâneos não o usem duas vezes.
    let invite = sqlx::query!(
        r#"
        SELECT id, created_by
        FROM invites
        WHERE code_hash = $1 AND used_at IS NULL AND expires_at > now()
        FOR UPDATE
        "#,
        crypto::sha256(code)
    )
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::InvalidInvite)?;

    let user_id = Uuid::now_v7();
    // ADMIN_USERNAMES também vale para quem se cadastra com a API já no ar
    // (sync_admins só roda na inicialização).
    let role = if state.policy.admin_usernames.contains(&username) {
        "admin"
    } else {
        "user"
    };
    let created_at = sqlx::query_scalar!(
        r#"
        INSERT INTO users (id, username, email, password_hash, invited_by, role, cpf_hmac)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING created_at
        "#,
        user_id,
        username,
        email,
        password_hash,
        invite.created_by,
        role,
        cpf_hmac,
    )
    .fetch_one(&mut *tx)
    .await
    .map_err(map_unique_violation)?;

    sqlx::query!(
        "UPDATE invites SET used_by = $1, used_at = now() WHERE id = $2",
        user_id,
        invite.id
    )
    .execute(&mut *tx)
    .await?;

    let (token, expires_at) =
        create_session(&mut tx, user_id, state.policy.session_ttl_days).await?;
    tx.commit().await?;

    tracing::info!(%user_id, "user registered");

    Ok((
        StatusCode::CREATED,
        Json(AuthResponse {
            token,
            expires_at,
            user: UserDto {
                id: user_id,
                username,
                email,
                display_name: None,
                bio: String::new(),
                role: role.to_owned(),
                created_at,
                needs_cpf: false,
            },
        }),
    ))
}

/// POST /v1/auth/login
pub async fn login(
    State(state): State<AppState>,
    headers: axum::http::HeaderMap,
    Json(req): Json<LoginRequest>,
) -> AppResult<Json<AuthResponse>> {
    let login = req.login.trim().to_lowercase();
    let limits = &state.auth_limits;
    let login_key = format!("login:{login}");
    let ip_key = format!("ip:{}", crate::ratelimit::client_ip(&headers));
    if limits.per_login.is_blocked(&login_key) || limits.per_ip.is_blocked(&ip_key) {
        return Err(AppError::TooManyAttempts);
    }
    if login.is_empty() || login.len() > 254 || req.password.len() > 4 * validation::PASSWORD_MAX {
        return Err(AppError::InvalidCredentials);
    }

    let user = sqlx::query_as!(
        UserWithHash,
        r#"
        SELECT id, username, email, display_name, bio, role, suspended_at, password_hash, created_at,
               (cpf_hmac IS NULL) AS "needs_cpf!"
        FROM users
        WHERE username = $1 OR email = $1
        "#,
        login
    )
    .fetch_optional(&state.db)
    .await?;

    // Sempre executa uma verificação Argon2, exista o usuário ou não (timing).
    let phc = user.as_ref().map_or_else(
        || crypto::dummy_hash().to_owned(),
        |u| u.password_hash.clone(),
    );
    let password = req.password;
    let ok = tokio::task::spawn_blocking(move || crypto::verify_password(&password, &phc))
        .await
        .map_err(anyhow::Error::from)?;

    let user = match (ok, user) {
        (true, Some(u)) => u,
        _ => {
            limits.per_login.record_failure(&login_key);
            limits.per_ip.record_failure(&ip_key);
            return Err(AppError::InvalidCredentials);
        }
    };
    limits.per_login.clear(&login_key);
    if user.suspended_at.is_some() {
        return Err(AppError::Suspended);
    }

    let mut tx = state.db.begin().await?;
    let (token, expires_at) =
        create_session(&mut tx, user.id, state.policy.session_ttl_days).await?;
    tx.commit().await?;

    Ok(Json(AuthResponse {
        token,
        expires_at,
        user: UserDto {
            id: user.id,
            username: user.username,
            email: user.email,
            display_name: user.display_name,
            bio: user.bio,
            role: user.role,
            created_at: user.created_at,
            needs_cpf: user.needs_cpf,
        }
        .with_policy(&state),
    }))
}

/// POST /v1/auth/logout — revoga a sessão atual.
pub async fn logout(State(state): State<AppState>, user: AuthUser) -> AppResult<StatusCode> {
    sqlx::query!("DELETE FROM sessions WHERE id = $1", user.session_id)
        .execute(&state.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

struct UserWithHash {
    id: Uuid,
    username: String,
    email: String,
    display_name: Option<String>,
    bio: String,
    role: String,
    needs_cpf: bool,
    suspended_at: Option<OffsetDateTime>,
    password_hash: String,
    created_at: OffsetDateTime,
}

async fn create_session(
    tx: &mut sqlx::PgConnection,
    user_id: Uuid,
    ttl_days: i64,
) -> AppResult<(String, OffsetDateTime)> {
    let token = crypto::new_session_token();
    let expires_at = OffsetDateTime::now_utc() + Duration::days(ttl_days);
    sqlx::query!(
        "INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES ($1, $2, $3, $4)",
        Uuid::now_v7(),
        user_id,
        crypto::sha256(&token),
        expires_at,
    )
    .execute(tx)
    .await?;
    Ok((token, expires_at))
}

pub fn map_unique_violation(err: sqlx::Error) -> AppError {
    if let sqlx::Error::Database(db) = &err
        && db.is_unique_violation()
    {
        return match db.constraint() {
            Some("users_username_key") => AppError::Conflict("username_taken"),
            Some("users_email_key") => AppError::Conflict("email_taken"),
            Some("users_cpf_hmac_key") => AppError::Conflict("cpf_taken"),
            _ => AppError::Conflict("conflict"),
        };
    }
    err.into()
}

/// Com CPF obrigatório: valida e devolve o HMAC. Sem: ignora o campo.
pub fn cpf_hmac_for(state: &AppState, raw: Option<&str>) -> AppResult<Option<Vec<u8>>> {
    let Some(key) = &state.policy.cpf_key else {
        return Ok(None);
    };
    let raw = raw.ok_or(AppError::Validation("cpf_required"))?;
    let digits = validation::cpf(raw)?;
    Ok(Some(crypto::cpf_hmac(&key.0, &digits)))
}

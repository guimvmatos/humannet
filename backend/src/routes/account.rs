//! Conta: trocar senha e excluir conta (exigência da Play Store e da LGPD).

use axum::{Json, extract::State, http::StatusCode};
use serde::Deserialize;

use crate::{
    AppState,
    auth::AuthUser,
    crypto,
    error::{AppError, AppResult},
    validation,
};

/// Confere a senha atual do usuário (Argon2 fora do runtime async).
async fn check_password(state: &AppState, user: &AuthUser, password: String) -> AppResult<()> {
    if password.len() > 4 * validation::PASSWORD_MAX {
        return Err(AppError::InvalidCredentials);
    }
    let phc = sqlx::query_scalar!(
        "SELECT password_hash FROM users WHERE id = $1",
        user.user_id
    )
    .fetch_one(&state.db)
    .await?;
    let ok = tokio::task::spawn_blocking(move || crypto::verify_password(&password, &phc))
        .await
        .map_err(anyhow::Error::from)?;
    if ok {
        Ok(())
    } else {
        Err(AppError::InvalidCredentials)
    }
}

#[derive(Deserialize)]
pub struct ChangePassword {
    pub current_password: String,
    pub new_password: String,
}

/// PUT /v1/me/password — troca a senha e encerra as outras sessões.
pub async fn change_password(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<ChangePassword>,
) -> AppResult<StatusCode> {
    validation::password(&req.new_password)?;
    check_password(&state, &user, req.current_password).await?;

    let new = req.new_password;
    let phc = tokio::task::spawn_blocking(move || crypto::hash_password(&new))
        .await
        .map_err(anyhow::Error::from)??;

    let mut tx = state.db.begin().await?;
    sqlx::query!(
        "UPDATE users SET password_hash = $1 WHERE id = $2",
        phc,
        user.user_id
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "DELETE FROM sessions WHERE user_id = $1 AND id <> $2",
        user.user_id,
        user.session_id
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    tracing::info!(user_id = %user.user_id, "password changed");
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub struct DeleteAccount {
    pub password: String,
}

/// DELETE /v1/me — exclusão **definitiva**: perfil, posts, amizades, pedidos,
/// convites não usados, bloqueios e sessões. Denúncias feitas por esta pessoa
/// ficam anônimas (moderação); denúncias contra ela permanecem.
pub async fn delete_account(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<DeleteAccount>,
) -> AppResult<StatusCode> {
    check_password(&state, &user, req.password).await?;
    let mut tx = state.db.begin().await?;
    crate::routes::communities::hand_over_owned(&mut tx, user.user_id).await?;
    // Fotos: os registros caem junto com a conta; os arquivos, logo depois.
    let keys = sqlx::query_scalar!("SELECT key FROM media WHERE owner_id = $1", user.user_id)
        .fetch_all(&mut *tx)
        .await?;
    sqlx::query!("DELETE FROM users WHERE id = $1", user.user_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    state.media.delete_later(keys);
    tracing::info!(user_id = %user.user_id, "account deleted");
    Ok(StatusCode::NO_CONTENT)
}

use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::Serialize;

/// Erro de aplicação. A mensagem enviada ao cliente é sempre um código estável
/// (`error`) — nunca detalhes internos ou de banco.
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("validation failed: {0}")]
    Validation(&'static str),
    #[error("unauthorized")]
    Unauthorized,
    #[error("invalid credentials")]
    InvalidCredentials,
    #[error("invalid invite")]
    InvalidInvite,
    #[error("not found")]
    NotFound,
    #[error("forbidden")]
    Forbidden,
    #[error("conflict: {0}")]
    Conflict(&'static str),
    #[error("limit reached: {0}")]
    LimitReached(&'static str),
    #[error(transparent)]
    Internal(#[from] anyhow::Error),
}

#[derive(Serialize)]
struct ErrorBody {
    error: &'static str,
}

impl AppError {
    fn status_and_code(&self) -> (StatusCode, &'static str) {
        match self {
            Self::Validation(code) => (StatusCode::UNPROCESSABLE_ENTITY, code),
            Self::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized"),
            Self::InvalidCredentials => (StatusCode::UNAUTHORIZED, "invalid_credentials"),
            Self::InvalidInvite => (StatusCode::BAD_REQUEST, "invalid_invite"),
            Self::NotFound => (StatusCode::NOT_FOUND, "not_found"),
            Self::Forbidden => (StatusCode::FORBIDDEN, "forbidden"),
            Self::Conflict(code) => (StatusCode::CONFLICT, code),
            Self::LimitReached(code) => (StatusCode::TOO_MANY_REQUESTS, code),
            Self::Internal(_) => (StatusCode::INTERNAL_SERVER_ERROR, "internal_error"),
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        if let Self::Internal(err) = &self {
            tracing::error!(error = ?err, "internal error");
        }
        let (status, code) = self.status_and_code();
        (status, Json(ErrorBody { error: code })).into_response()
    }
}

impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        Self::Internal(err.into())
    }
}

pub type AppResult<T> = Result<T, AppError>;

pub mod auth;
pub mod config;
pub mod crypto;
pub mod error;
pub mod ratelimit;
pub mod routes;
pub mod validation;

use std::time::Duration;

use axum::{
    Router,
    http::{HeaderName, StatusCode},
    routing::{delete, get, patch, post, put},
};
use sqlx::PgPool;
use tower_http::{
    limit::RequestBodyLimitLayer,
    request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer},
    timeout::TimeoutLayer,
    trace::TraceLayer,
};

pub use config::{Config, Policy};

/// Limite de corpo para a API JSON. Upload de mídia terá rota própria.
const MAX_BODY_BYTES: usize = 64 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub policy: Policy,
    pub auth_limits: std::sync::Arc<ratelimit::AuthLimits>,
}

impl AppState {
    pub fn new(db: PgPool, policy: Policy) -> Self {
        Self {
            db,
            policy,
            auth_limits: std::sync::Arc::default(),
        }
    }
}

pub fn app(state: AppState) -> Router {
    let request_id = HeaderName::from_static("x-request-id");

    let v1 = Router::new()
        .route("/auth/register", post(routes::auth::register))
        .route("/auth/login", post(routes::auth::login))
        .route("/auth/logout", post(routes::auth::logout))
        .route("/auth/reset-password", post(routes::admin::reset_password))
        .route("/admin/reports", get(routes::admin::list_reports))
        .route(
            "/admin/reports/{id}/resolve",
            post(routes::admin::resolve_report),
        )
        .route(
            "/admin/users/{username}/unsuspend",
            post(routes::admin::unsuspend),
        )
        .route(
            "/admin/users/{username}/password-reset",
            post(routes::admin::create_reset_code),
        )
        .route(
            "/me",
            get(routes::me::get).delete(routes::account::delete_account),
        )
        .route("/me/password", put(routes::account::change_password))
        .route("/me/profile", patch(routes::profiles::update))
        .route("/invites", post(routes::invites::create))
        .route("/users/{username}", get(routes::profiles::get))
        .route(
            "/users/{username}/friend",
            put(routes::friends::request_or_accept).delete(routes::friends::remove),
        )
        .route(
            "/users/{username}/block",
            put(routes::safety::block).delete(routes::safety::unblock),
        )
        .route("/blocks", get(routes::safety::list_blocks))
        .route("/reports", post(routes::safety::report))
        .route("/friends", get(routes::friends::list))
        .route("/friend-requests", get(routes::friends::incoming))
        .route("/users/{username}/posts", get(routes::posts::list_by_user))
        .route("/posts", post(routes::posts::create))
        .route(
            "/posts/{id}",
            get(routes::posts::get).delete(routes::posts::delete),
        )
        .route(
            "/posts/{id}/like",
            put(routes::posts::like).delete(routes::posts::unlike),
        )
        .route(
            "/posts/{id}/comments",
            get(routes::comments::list).post(routes::comments::create),
        )
        .route("/comments/{id}", delete(routes::comments::delete))
        .route("/feed", get(routes::posts::feed))
        .route(
            "/communities",
            get(routes::communities::list).post(routes::communities::create),
        )
        .route(
            "/communities/{slug}",
            get(routes::communities::get)
                .patch(routes::communities::update)
                .delete(routes::communities::delete),
        )
        .route(
            "/communities/{slug}/membership",
            put(routes::communities::join).delete(routes::communities::leave),
        )
        .route(
            "/communities/{slug}/members",
            get(routes::communities::members),
        )
        .route(
            "/communities/{slug}/members/{username}",
            post(routes::communities::member_action),
        )
        .route(
            "/communities/{slug}/topics",
            get(routes::topics::list).post(routes::topics::create),
        )
        .route(
            "/topics/{id}",
            get(routes::topics::get)
                .patch(routes::topics::update)
                .delete(routes::topics::delete),
        )
        .route(
            "/topics/{id}/replies",
            get(routes::topics::replies).post(routes::topics::reply),
        )
        .route("/replies/{id}", delete(routes::topics::delete_reply));

    Router::new()
        .route("/health", get(routes::health::health))
        .nest("/v1", v1)
        .with_state(state)
        // Camadas: a última adicionada é a mais externa.
        .layer(RequestBodyLimitLayer::new(MAX_BODY_BYTES))
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            REQUEST_TIMEOUT,
        ))
        .layer(PropagateRequestIdLayer::new(request_id.clone()))
        .layer(TraceLayer::new_for_http())
        .layer(SetRequestIdLayer::new(request_id, MakeRequestUuid))
}

/// Migrações embutidas no binário.
pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

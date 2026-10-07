//! Helpers compartilhados pelos testes de integração.
#![allow(dead_code)]

pub use axum::{
    Router,
    body::Body,
    http::{Method, Request, StatusCode, header},
};
use http_body_util::BodyExt;
pub use humannet_api::{AppState, Policy, app, routes::invites::create_invite};
pub use serde_json::{Value, json};
pub use sqlx::PgPool;
use tower::ServiceExt;

pub const PASSWORD: &str = "senha-bem-longa-123";

pub fn test_app(db: PgPool) -> Router {
    app(AppState::new(db, Policy::default()))
}

pub async fn call(
    app: &Router,
    method: Method,
    uri: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut req = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        req = req.header(header::AUTHORIZATION, format!("Bearer {t}"));
    }
    let req = match body {
        Some(b) => req
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(b.to_string())),
        None => req.body(Body::empty()),
    }
    .unwrap();

    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(Value::Null)
    };
    (status, json)
}

pub async fn admin_invite(db: &PgPool) -> String {
    create_invite(db, None, 14).await.unwrap().code
}

pub async fn register(
    app: &Router,
    invite: &str,
    username: &str,
    email: &str,
) -> (StatusCode, Value) {
    call(
        app,
        Method::POST,
        "/v1/auth/register",
        None,
        Some(json!({
            "invite_code": invite,
            "username": username,
            "email": email,
            "password": PASSWORD,
        })),
    )
    .await
}

/// Registra um usuário e devolve o token.
pub async fn signup(app: &Router, db: &PgPool, username: &str) -> String {
    let invite = admin_invite(db).await;
    let (status, body) = register(app, &invite, username, &format!("{username}@example.com")).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    body["token"].as_str().unwrap().to_owned()
}

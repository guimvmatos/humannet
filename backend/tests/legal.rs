//! Termos de Uso e Política de Privacidade: textos públicos e aceite.

mod common;

use common::*;
use tower::ServiceExt;

#[sqlx::test]
async fn terms_are_public_and_required(db: PgPool) {
    let app = test_app(db.clone());

    for path in ["/legal/termos", "/legal/privacidade"] {
        let res = app
            .clone()
            .oneshot(Request::get(path).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK, "{path}");
        let bytes = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let text = String::from_utf8(bytes.to_vec()).unwrap();
        assert!(text.contains("18 anos"), "{path}");
    }

    // Cadastro sem aceite (ou com versão velha) é recusado.
    let invite = admin_invite(&db).await;
    for accept in [json!(null), json!(0)] {
        let (s, b) = call(
            &app,
            Method::POST,
            "/v1/auth/register",
            None,
            Some(json!({
                "invite_code": invite, "username": "alice",
                "email": "alice@example.com", "password": PASSWORD,
                "accept_terms": accept,
            })),
        )
        .await;
        assert_eq!(
            (s, b["error"].as_str()),
            (StatusCode::UNPROCESSABLE_ENTITY, Some("terms_required"))
        );
    }

    let alice = signup(&app, &db, "alice").await;
    let (_, me) = call(&app, Method::GET, "/v1/me", Some(&alice), None).await;
    assert_eq!(me["needs_terms"], false);
    assert!(me.get("terms_version").is_none());

    // Conta antiga (antes dos termos): o app pede o aceite.
    sqlx::query("UPDATE users SET terms_version = 0, terms_accepted_at = NULL")
        .execute(&db)
        .await
        .unwrap();
    let (_, me) = call(&app, Method::GET, "/v1/me", Some(&alice), None).await;
    assert_eq!(me["needs_terms"], true);
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/terms",
        Some(&alice),
        Some(json!({"version": 99})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/terms",
        Some(&alice),
        Some(json!({"version": 1})),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, me) = call(&app, Method::GET, "/v1/me", Some(&alice), None).await;
    assert_eq!(me["needs_terms"], false);
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/terms",
        None,
        Some(json!({"version": 1})),
    )
    .await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
}

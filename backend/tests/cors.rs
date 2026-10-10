//! CORS para a versão web do app (GitHub Pages).

mod common;

use common::*;
use tower::ServiceExt;

#[sqlx::test]
async fn web_origin_allowed_others_not(db: PgPool) {
    let app = test_app(db);
    let preflight = |origin: &'static str| {
        Request::builder()
            .method(Method::OPTIONS)
            .uri("/v1/me")
            .header(header::ORIGIN, origin)
            .header(header::ACCESS_CONTROL_REQUEST_METHOD, "GET")
            .header(header::ACCESS_CONTROL_REQUEST_HEADERS, "authorization")
            .body(Body::empty())
            .unwrap()
    };
    let res = app
        .clone()
        .oneshot(preflight("https://guimvmatos.github.io"))
        .await
        .unwrap();
    assert!(res.status().is_success());
    assert_eq!(
        res.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN],
        "https://guimvmatos.github.io"
    );
    let res = app
        .oneshot(preflight("https://evil.example"))
        .await
        .unwrap();
    assert!(
        res.headers()
            .get(header::ACCESS_CONTROL_ALLOW_ORIGIN)
            .is_none()
    );
}

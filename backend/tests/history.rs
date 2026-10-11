//! Minha atividade (listar e apagar em lote) e Baixar meus dados.

mod common;

use common::*;
use tower::ServiceExt;

async fn post(app: &Router, token: &str, body: &str) -> String {
    let (s, p) = call(
        app,
        Method::POST,
        "/v1/posts",
        Some(token),
        Some(json!({ "body": body })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    p["id"].as_str().unwrap().to_owned()
}

async fn history(app: &Router, token: &str, kind: &str) -> Value {
    let (s, v) = call(
        app,
        Method::GET,
        &format!("/v1/me/history?kind={kind}&limit=2"),
        Some(token),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{v}");
    v
}

fn bodies(v: &Value) -> Vec<String> {
    v["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["body"].as_str().unwrap().to_owned())
        .collect()
}

#[sqlx::test]
async fn history_list_delete_and_export(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    call(
        &app,
        Method::PUT,
        "/v1/users/bob/friend",
        Some(&alice),
        None,
    )
    .await;
    call(
        &app,
        Method::PUT,
        "/v1/users/alice/friend",
        Some(&bob),
        None,
    )
    .await;

    let p1 = post(&app, &alice, "primeiro").await;
    let p2 = post(&app, &alice, "segundo").await;
    let p3 = post(&app, &alice, "terceiro").await;
    let bp = post(&app, &bob, "post do bob").await;
    let (_, c) = call(
        &app,
        Method::POST,
        &format!("/v1/posts/{bp}/comments"),
        Some(&alice),
        Some(json!({"body": "boa!"})),
    )
    .await;
    call(
        &app,
        Method::PUT,
        &format!("/v1/posts/{bp}/like"),
        Some(&alice),
        None,
    )
    .await;
    call(
        &app,
        Method::POST,
        "/v1/users/bob/scraps",
        Some(&alice),
        Some(json!({"body": "oi bob"})),
    )
    .await;

    // Paginado: 2 por vez, mais recente primeiro.
    let h = history(&app, &alice, "posts").await;
    assert_eq!(bodies(&h), ["terceiro", "segundo"]);
    let cursor = h["next_cursor"].as_str().unwrap().to_owned();
    let (_, h2) = call(
        &app,
        Method::GET,
        &format!(
            "/v1/me/history?kind=posts&limit=2&before={}",
            cursor.replace('+', "%2B")
        ),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(bodies(&h2), ["primeiro"]);
    assert!(h2["next_cursor"].is_null());

    let h = history(&app, &alice, "comments").await;
    assert_eq!(bodies(&h), ["boa!"]);
    assert_eq!(h["items"][0]["other_username"], "bob");
    assert_eq!(h["items"][0]["post_id"], bp.as_str());
    let h = history(&app, &alice, "likes").await;
    assert_eq!(h["items"][0]["id"], bp.as_str());
    let h = history(&app, &alice, "scraps").await;
    assert_eq!(bodies(&h), ["oi bob"]);

    // Exporta antes de apagar.
    let (s, link) = call(&app, Method::POST, "/v1/me/export", Some(&alice), None).await;
    assert_eq!(s, StatusCode::CREATED, "{link}");
    let url = link["url"].as_str().unwrap().to_owned();
    let get = |u: String| {
        app.clone()
            .oneshot(Request::get(u).body(Body::empty()).unwrap())
    };
    let res = get(url.clone()).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    assert!(
        res.headers()[header::CONTENT_DISPOSITION]
            .to_str()
            .unwrap()
            .contains("humannet-alice-")
    );
    let bytes = axum::body::to_bytes(res.into_body(), 1 << 20)
        .await
        .unwrap();
    let data: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(data["conta"]["usuario"], "alice");
    assert_eq!(data["posts"].as_array().unwrap().len(), 3);
    assert_eq!(data["comentarios"][0]["texto"], "boa!");
    assert_eq!(data["amigos"][0]["usuario"], "bob");
    assert_eq!(data["recados_escritos"][0]["para"], "bob");
    assert!(data["conta"].get("cpf").is_none());
    // Uso único.
    assert_eq!(get(url).await.unwrap().status(), StatusCode::NOT_FOUND);

    // Apagar em lote: ids de outra pessoa são ignorados.
    let (s, r) = call(
        &app,
        Method::POST,
        "/v1/me/history/delete",
        Some(&alice),
        Some(json!({"kind": "posts", "ids": [p1, p2, bp]})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    assert_eq!(r["deleted"], 2);
    assert_eq!(bodies(&history(&app, &alice, "posts").await), ["terceiro"]);
    let (s, _) = call(
        &app,
        Method::GET,
        &format!("/v1/posts/{bp}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "post do bob continua");

    for (kind, id) in [
        ("comments", c["id"].as_str().unwrap().to_owned()),
        ("likes", bp.clone()),
    ] {
        let (_, r) = call(
            &app,
            Method::POST,
            "/v1/me/history/delete",
            Some(&alice),
            Some(json!({"kind": kind, "ids": [id]})),
        )
        .await;
        assert_eq!(r["deleted"], 1, "{kind}");
        assert!(bodies(&history(&app, &alice, kind).await).is_empty());
    }
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/me/history/delete",
        Some(&alice),
        Some(json!({"kind": "posts", "ids": []})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = call(&app, Method::GET, "/v1/me/history?kind=posts", None, None).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    let _ = p3;
}

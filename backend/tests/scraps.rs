//! Beta lote 10: recados, status/subnick e foto de perfil nas listas.

mod common;

use common::*;

async fn befriend(app: &Router, a: &str, b_name: &str, b: &str, a_name: &str) {
    call(
        app,
        Method::PUT,
        &format!("/v1/users/{b_name}/friend"),
        Some(a),
        None,
    )
    .await;
    call(
        app,
        Method::PUT,
        &format!("/v1/users/{a_name}/friend"),
        Some(b),
        None,
    )
    .await;
}

#[sqlx::test]
async fn scraps_flow(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;

    let body = json!({"body": "Saudades!"});
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/users/alice/scraps",
        Some(&bob),
        Some(body.clone()),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN, "só amigos");
    befriend(&app, &alice, "bob", &bob, "alice").await;
    let (s, sc) = call(
        &app,
        Method::POST,
        "/v1/users/alice/scraps",
        Some(&bob),
        Some(body),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{sc}");
    let id = sc["id"].as_str().unwrap().to_owned();
    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/users/alice/scraps",
        Some(&alice),
        Some(json!({"body": "eu"})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("cannot_scrap_self"))
    );

    let (_, list) = call(
        &app,
        Method::GET,
        "/v1/users/alice/scraps",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(list["items"][0]["body"], "Saudades!");
    assert_eq!(list["items"][0]["can_delete"], true);
    let (s, _) = call(
        &app,
        Method::GET,
        "/v1/users/alice/scraps",
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN, "quem não é amigo não lê");

    // Vira novidade para a dona.
    let (_, c) = call(&app, Method::GET, "/v1/me/counts", Some(&alice), None).await;
    assert_eq!(c["unread_activity"], 1);
    let (_, a) = call(&app, Method::GET, "/v1/me/activity", Some(&alice), None).await;
    assert_eq!(a["items"][0]["kind"], "scrap");

    // Denúncia e exclusão pela dona.
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&alice),
        Some(json!({"kind": "scrap", "scrap_id": id, "reason": "spam"})),
    )
    .await;
    assert_eq!(s, StatusCode::ACCEPTED);
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/scraps/{id}"),
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/scraps/{id}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
}

#[sqlx::test]
async fn status_with_expiry(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    befriend(&app, &alice, "bob", &bob, "alice").await;

    let (s, st) = call(
        &app,
        Method::PUT,
        "/v1/me/status",
        Some(&alice),
        Some(json!({"text": "  de   férias  ", "hours": 72})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{st}");
    assert_eq!(st["text"], "de férias");
    let (_, p) = call(&app, Method::GET, "/v1/users/alice", Some(&bob), None).await;
    assert_eq!(p["status"], "de férias");
    let (_, p) = call(&app, Method::GET, "/v1/users/alice", Some(&carol), None).await;
    assert_eq!(p["status"], Value::Null);
    let (_, f) = call(&app, Method::GET, "/v1/friends", Some(&bob), None).await;
    assert_eq!(f["items"][0]["status"], "de férias");
    assert_eq!(f["items"][0]["username"], "alice");

    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/status",
        Some(&alice),
        Some(json!({"text": "x", "hours": 5})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // Expirou → some.
    sqlx::query("UPDATE users SET status_expires_at = now() - interval '1 minute'")
        .execute(&db)
        .await
        .unwrap();
    let (_, p) = call(&app, Method::GET, "/v1/users/alice", Some(&bob), None).await;
    assert_eq!(p["status"], Value::Null);
}

#[sqlx::test]
async fn avatar_shows_in_lists(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    befriend(&app, &alice, "bob", &bob, "alice").await;
    // Avatar de alice direto no banco (o upload é testado em photos.rs).
    sqlx::query(
        "WITH m AS (INSERT INTO media (id, owner_id, kind, key, width, height, bytes, attached_at)
                    SELECT gen_random_uuid(), id, 'avatar', 'media/a.jpg', 512, 512, 10, now()
                    FROM users WHERE username = 'alice' RETURNING id, owner_id)
         UPDATE users SET avatar_media_id = m.id FROM m WHERE users.id = m.owner_id",
    )
    .execute(&db)
    .await
    .unwrap();
    call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&alice),
        Some(json!({"body": "oi"})),
    )
    .await;
    let (_, feed) = call(&app, Method::GET, "/v1/feed", Some(&bob), None).await;
    assert_eq!(
        feed["items"][0]["author"]["avatar_url"],
        "memory://media/a.jpg"
    );
    let (_, f) = call(&app, Method::GET, "/v1/friends", Some(&bob), None).await;
    assert_eq!(f["items"][0]["avatar_url"], "memory://media/a.jpg");
    let (_, f) = call(&app, Method::GET, "/v1/friends", Some(&alice), None).await;
    assert_eq!(f["items"][0]["avatar_url"], Value::Null);
}

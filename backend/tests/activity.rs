//! Beta lote 6: contadores e novidades.

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

async fn counts(app: &Router, token: &str) -> Value {
    let (s, b) = call(app, Method::GET, "/v1/me/counts", Some(token), None).await;
    assert_eq!(s, StatusCode::OK, "{b}");
    b
}

#[sqlx::test]
async fn counts_and_activity(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;

    // Pedido de amizade.
    call(
        &app,
        Method::PUT,
        "/v1/users/alice/friend",
        Some(&carol),
        None,
    )
    .await;
    let c = counts(&app, &alice).await;
    assert_eq!(c["friend_requests"], 1);
    assert_eq!(c["unread_activity"], 0);

    // Comentário de bob no post de alice.
    befriend(&app, &alice, "bob", &bob, "alice").await;
    let (_, p) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&alice),
        Some(json!({"body": "oi"})),
    )
    .await;
    let post = p["id"].as_str().unwrap();
    call(
        &app,
        Method::POST,
        &format!("/v1/posts/{post}/comments"),
        Some(&bob),
        Some(json!({"body": "olá!"})),
    )
    .await;
    // O próprio comentário não conta.
    call(
        &app,
        Method::POST,
        &format!("/v1/posts/{post}/comments"),
        Some(&alice),
        Some(json!({"body": "valeu"})),
    )
    .await;

    // Depoimento pendente.
    call(
        &app,
        Method::PUT,
        "/v1/users/alice/testimonial",
        Some(&bob),
        Some(json!({"body": "Gente boa"})),
    )
    .await;

    // Comunidade fechada de alice com pedido de carol; tópico com resposta.
    call(
        &app,
        Method::POST,
        "/v1/communities",
        Some(&alice),
        Some(json!({"name": "Clube", "theme": "outros", "visibility": "closed"})),
    )
    .await;
    call(
        &app,
        Method::PUT,
        "/v1/communities/clube/membership",
        Some(&carol),
        None,
    )
    .await;
    call(
        &app,
        Method::PUT,
        "/v1/communities/clube/membership",
        Some(&bob),
        None,
    )
    .await;
    call(
        &app,
        Method::POST,
        "/v1/communities/clube/members/bob",
        Some(&alice),
        Some(json!({"action": "approve"})),
    )
    .await;
    let (_, t) = call(
        &app,
        Method::POST,
        "/v1/communities/clube/topics",
        Some(&alice),
        Some(json!({"title": "Encontro"})),
    )
    .await;
    let topic = t["id"].as_str().unwrap();
    call(
        &app,
        Method::POST,
        &format!("/v1/topics/{topic}/replies"),
        Some(&bob),
        Some(json!({"body": "Eu vou"})),
    )
    .await;

    let c = counts(&app, &alice).await;
    assert_eq!(c["pending_testimonials"], 1);
    assert_eq!(c["community_requests"], 1);
    assert_eq!(c["unread_activity"], 2);

    let (_, a) = call(&app, Method::GET, "/v1/me/activity", Some(&alice), None).await;
    let items = a["items"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0]["kind"], "reply");
    assert_eq!(items[0]["target_title"], "Encontro");
    assert_eq!(items[0]["unread"], true);
    assert_eq!(items[1]["kind"], "comment");
    assert_eq!(items[1]["actor"]["username"], "bob");

    // Bob respondeu no tópico: uma resposta de alice depois é novidade para ele.
    call(
        &app,
        Method::POST,
        &format!("/v1/topics/{topic}/replies"),
        Some(&alice),
        Some(json!({"body": "Combinado"})),
    )
    .await;
    assert_eq!(counts(&app, &bob).await["unread_activity"], 1);

    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/me/activity/seen",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    assert_eq!(counts(&app, &alice).await["unread_activity"], 0);
    let (_, a) = call(&app, Method::GET, "/v1/me/activity", Some(&alice), None).await;
    assert_eq!(a["items"][0]["unread"], false);

    // Bloqueio esconde as novidades de quem foi bloqueado.
    call(&app, Method::PUT, "/v1/users/bob/block", Some(&alice), None).await;
    let (_, a) = call(&app, Method::GET, "/v1/me/activity", Some(&alice), None).await;
    assert_eq!(a["items"].as_array().unwrap().len(), 0);
}

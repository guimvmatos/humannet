//! Beta lote 13: mensagens diretas.

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

async fn send(app: &Router, token: &str, conv: &str, body: &str) -> (StatusCode, Value) {
    call(
        app,
        Method::POST,
        &format!("/v1/conversations/{conv}/messages"),
        Some(token),
        Some(json!({ "body": body })),
    )
    .await
}

#[sqlx::test]
async fn direct_conversation(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;

    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/conversations/direct",
        Some(&alice),
        Some(json!({"username": "bob"})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN, "só amigos");
    befriend(&app, &alice, "bob", &bob, "alice").await;
    let (s, c) = call(
        &app,
        Method::POST,
        "/v1/conversations/direct",
        Some(&alice),
        Some(json!({"username": "bob"})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{c}");
    assert_eq!(c["title"], "@bob");
    let id = c["id"].as_str().unwrap().to_owned();
    // Mesma conversa pelos dois lados.
    let (_, c2) = call(
        &app,
        Method::POST,
        "/v1/conversations/direct",
        Some(&bob),
        Some(json!({"username": "alice"})),
    )
    .await;
    assert_eq!(c2["id"], id.as_str());

    let (s, m) = send(&app, &alice, &id, "Oi Bob!").await;
    assert_eq!(s, StatusCode::CREATED, "{m}");
    send(&app, &alice, &id, "Tudo bem?").await;

    // Bolinha e lista do bob.
    let (_, counts) = call(&app, Method::GET, "/v1/me/counts", Some(&bob), None).await;
    assert_eq!(counts["unread_messages"], 1);
    let (_, l) = call(&app, Method::GET, "/v1/conversations", Some(&bob), None).await;
    assert_eq!(l["items"][0]["unread"], 2);
    assert_eq!(l["items"][0]["last_message"], "Tudo bem?");

    // Mensagens em ordem cronológica; buscar só as novas.
    let (_, msgs) = call(
        &app,
        Method::GET,
        &format!("/v1/conversations/{id}/messages"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(msgs["items"][0]["body"], "Oi Bob!");
    assert_eq!(msgs["items"][1]["mine"], false);
    let last = msgs["items"][1]["id"].as_str().unwrap().to_owned();
    send(&app, &bob, &id, "Tudo ótimo").await;
    let (_, new) = call(
        &app,
        Method::GET,
        &format!("/v1/conversations/{id}/messages?after={last}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(new["items"].as_array().unwrap().len(), 1);
    assert_eq!(new["items"][0]["body"], "Tudo ótimo");

    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/conversations/{id}/read"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, counts) = call(&app, Method::GET, "/v1/me/counts", Some(&bob), None).await;
    assert_eq!(counts["unread_messages"], 0);

    // Quem não é membro não lê.
    let (s, _) = call(
        &app,
        Method::GET,
        &format!("/v1/conversations/{id}/messages"),
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    // Apagar a própria mensagem.
    let mid = m["id"].as_str().unwrap();
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/messages/{mid}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/messages/{mid}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, msgs) = call(
        &app,
        Method::GET,
        &format!("/v1/conversations/{id}/messages"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(msgs["items"][0]["deleted"], true);
    assert_eq!(msgs["items"][0]["body"], "");

    // Bloqueio impede enviar.
    call(&app, Method::PUT, "/v1/users/alice/block", Some(&bob), None).await;
    let (s, _) = send(&app, &alice, &id, "?").await;
    assert_eq!(s, StatusCode::FORBIDDEN);
}

#[sqlx::test]
async fn group_conversation(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    let dave = signup(&app, &db, "dave").await;
    befriend(&app, &alice, "bob", &bob, "alice").await;
    befriend(&app, &alice, "carol", &carol, "alice").await;

    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/conversations",
        Some(&alice),
        Some(json!({"title": "Família", "usernames": ["bob", "dave"]})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("not_friends"))
    );
    let (s, g) = call(
        &app,
        Method::POST,
        "/v1/conversations",
        Some(&alice),
        Some(json!({"title": "Família", "usernames": ["bob"]})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{g}");
    assert_eq!(g["member_count"], 2);
    let id = g["id"].as_str().unwrap().to_owned();

    // Só quem criou adiciona.
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/conversations/{id}/members"),
        Some(&bob),
        Some(json!({"usernames": ["carol"]})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, g) = call(
        &app,
        Method::POST,
        &format!("/v1/conversations/{id}/members"),
        Some(&alice),
        Some(json!({"usernames": ["carol"]})),
    )
    .await;
    assert_eq!((s, g["member_count"].as_i64()), (StatusCode::OK, Some(3)));

    send(&app, &carol, &id, "Oi gente").await;
    let (_, l) = call(&app, Method::GET, "/v1/conversations", Some(&bob), None).await;
    assert_eq!(l["items"][0]["title"], "Família");
    assert_eq!(l["items"][0]["unread"], 1);
    let (s, _) = send(&app, &dave, &id, "intruso").await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    // Denúncia de mensagem por membro.
    let (_, msgs) = call(
        &app,
        Method::GET,
        &format!("/v1/conversations/{id}/messages"),
        Some(&bob),
        None,
    )
    .await;
    let mid = msgs["items"][0]["id"].as_str().unwrap();
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&bob),
        Some(json!({"kind": "message", "message_id": mid, "reason": "spam"})),
    )
    .await;
    assert_eq!(s, StatusCode::ACCEPTED);

    // Dona sai: outro membro passa a administrar.
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/conversations/{id}/members/me"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, l) = call(&app, Method::GET, "/v1/conversations", Some(&bob), None).await;
    assert_eq!(l["items"][0]["is_owner"], true);
    let (_, ms) = call(
        &app,
        Method::GET,
        &format!("/v1/conversations/{id}/members"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(ms["items"].as_array().unwrap().len(), 2);
}

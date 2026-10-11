//! Marcações: @menções (com política de quem pode) e "com fulano" com
//! aprovação.

mod common;

use common::*;

async fn befriend(app: &Router, a: &str, an: &str, b: &str, bn: &str) {
    call(
        app,
        Method::PUT,
        &format!("/v1/users/{bn}/friend"),
        Some(a),
        None,
    )
    .await;
    call(
        app,
        Method::PUT,
        &format!("/v1/users/{an}/friend"),
        Some(b),
        None,
    )
    .await;
}

async fn activity_kinds(app: &Router, token: &str) -> Vec<String> {
    let (_, a) = call(app, Method::GET, "/v1/me/activity", Some(token), None).await;
    a["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["kind"].as_str().unwrap().to_owned())
        .collect()
}

#[test]
fn parses_mentions() {
    use humannet_api::routes::tags::mentioned_usernames;
    assert_eq!(
        mentioned_usernames("oi @Bob e @carol_1, @bob de novo; mail a@b.com @xy"),
        ["bob", "carol_1"]
    );
}

#[sqlx::test]
async fn mentions_respect_policy_and_blocks(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    let dave = signup(&app, &db, "dave").await;

    // Padrão: todos podem mencionar.
    let (_, p) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&alice),
        Some(json!({"body": "valeu @bob e @carol e @ninguem"})),
    )
    .await;
    let post = p["id"].as_str().unwrap().to_owned();
    assert_eq!(activity_kinds(&app, &bob).await, ["mention"]);
    assert_eq!(activity_kinds(&app, &carol).await, ["mention"]);

    // Carol só aceita de amigos; dave não é amigo dela.
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/mentions",
        Some(&carol),
        Some(json!({"policy": "friends"})),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (_, pol) = call(&app, Method::GET, "/v1/me/mentions", Some(&carol), None).await;
    assert_eq!(pol["policy"], "friends");
    call(
        &app,
        Method::POST,
        &format!("/v1/posts/{post}/comments"),
        Some(&dave),
        Some(json!({"body": "@carol @bob olha isso"})),
    )
    .await;
    assert_eq!(activity_kinds(&app, &carol).await, ["mention"]);
    assert_eq!(activity_kinds(&app, &bob).await, ["mention", "mention"]);

    // Bloqueio impede.
    call(&app, Method::PUT, "/v1/users/dave/block", Some(&bob), None).await;
    call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&dave),
        Some(json!({"body": "@bob ei"})),
    )
    .await;
    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM mentions m JOIN users u ON u.id = m.user_id WHERE u.username = 'bob'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 2);

    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/mentions",
        Some(&carol),
        Some(json!({"policy": "talvez"})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // Sugestões: amigos primeiro; quem não aceita de todos não aparece.
    befriend(&app, &alice, "alice", &dave, "dave").await;
    let (_, sug) = call(
        &app,
        Method::GET,
        "/v1/mentions/suggest?q=",
        Some(&alice),
        None,
    )
    .await;
    let names: Vec<&str> = sug["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|u| u["username"].as_str().unwrap())
        .collect();
    assert_eq!(
        names,
        ["dave", "bob"],
        "carol só amigos; dave amigo primeiro"
    );
}

#[sqlx::test]
async fn tags_need_approval(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;

    // Só amigos podem ser marcados.
    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&alice),
        Some(json!({"body": "rolê", "tags": ["bob", "carol"]})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("tag_not_friend"))
    );
    let (s, p) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&alice),
        Some(json!({"body": "rolê", "tags": ["@Bob"]})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    let post = p["id"].as_str().unwrap().to_owned();
    assert_eq!(p["tagged"][0]["username"], "bob");
    assert_eq!(p["tagged"][0]["pending"], true);

    // Pendente: carol não vê; bob vê na lista de pendentes e nas bolinhas.
    let (_, seen) = call(
        &app,
        Method::GET,
        &format!("/v1/posts/{post}"),
        Some(&carol),
        None,
    )
    .await;
    assert!(seen["tagged"].as_array().unwrap().is_empty());
    let (_, c) = call(&app, Method::GET, "/v1/me/counts", Some(&bob), None).await;
    assert_eq!(c["pending_tags"], 1);
    let (_, pend) = call(&app, Method::GET, "/v1/me/tags/pending", Some(&bob), None).await;
    assert_eq!(pend["items"][0]["post_id"], post.as_str());
    assert!(activity_kinds(&app, &bob).await.contains(&"tag".to_owned()));
    let (_, tagged) = call(
        &app,
        Method::GET,
        "/v1/users/bob/tagged",
        Some(&carol),
        None,
    )
    .await;
    assert!(tagged["items"].as_array().unwrap().is_empty());

    // Aprova: aparece para todos e no "Marcado" do perfil.
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/posts/{post}/tag/approve"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, seen) = call(
        &app,
        Method::GET,
        &format!("/v1/posts/{post}"),
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(seen["tagged"][0]["pending"], false);
    let (_, tagged) = call(
        &app,
        Method::GET,
        "/v1/users/bob/tagged",
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(tagged["items"][0]["id"], post.as_str());
    let (_, c) = call(&app, Method::GET, "/v1/me/counts", Some(&bob), None).await;
    assert_eq!(c["pending_tags"], 0);

    // Carol não tira a marcação de ninguém; bob tira a dele.
    let uri = format!("/v1/posts/{post}/tags/bob");
    let (s, _) = call(&app, Method::DELETE, &uri, Some(&carol), None).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(&app, Method::DELETE, &uri, Some(&bob), None).await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, seen) = call(
        &app,
        Method::GET,
        &format!("/v1/posts/{post}"),
        Some(&alice),
        None,
    )
    .await;
    assert!(seen["tagged"].as_array().unwrap().is_empty());
}

//! Beta lote 1: curtidas e comentários.

mod common;

use common::*;

async fn befriend(app: &Router, a: &str, a_name: &str, b: &str, b_name: &str) {
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

async fn post(app: &Router, token: &str, body: &str) -> String {
    let (_, p) = call(
        app,
        Method::POST,
        "/v1/posts",
        Some(token),
        Some(json!({ "body": body })),
    )
    .await;
    p["id"].as_str().unwrap().to_owned()
}

async fn get_post(app: &Router, token: &str, id: &str) -> (StatusCode, Value) {
    call(
        app,
        Method::GET,
        &format!("/v1/posts/{id}"),
        Some(token),
        None,
    )
    .await
}

#[sqlx::test]
async fn likes_are_private_to_author(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;
    let id = post(&app, &alice, "oi").await;

    for _ in 0..2 {
        let (s, _) = call(
            &app,
            Method::PUT,
            &format!("/v1/posts/{id}/like"),
            Some(&bob),
            None,
        )
        .await;
        assert_eq!(s, StatusCode::NO_CONTENT);
    }

    // Bob sabe que curtiu, mas não vê o número.
    let (_, p) = get_post(&app, &bob, &id).await;
    assert_eq!(p["liked_by_me"], true);
    assert!(
        p.get("like_count").is_none(),
        "R3: número de curtidas é do autor"
    );

    // Alice (autora) vê o número.
    let (_, p) = get_post(&app, &alice, &id).await;
    assert_eq!(p["like_count"], 1);
    assert_eq!(p["liked_by_me"], false);

    // No feed também.
    let (_, feed) = call(&app, Method::GET, "/v1/feed", Some(&alice), None).await;
    assert_eq!(feed["items"][0]["like_count"], 1);
    let (_, feed) = call(&app, Method::GET, "/v1/feed", Some(&bob), None).await;
    assert!(feed["items"][0].get("like_count").is_none());
    assert_eq!(feed["items"][0]["liked_by_me"], true);

    // Descurtir.
    call(
        &app,
        Method::DELETE,
        &format!("/v1/posts/{id}/like"),
        Some(&bob),
        None,
    )
    .await;
    let (_, p) = get_post(&app, &alice, &id).await;
    assert_eq!(p["like_count"], 0);
}

#[sqlx::test]
async fn blocked_cannot_like_or_comment(db: PgPool) {
    // Posts são globais (ADR-0008); o bloqueio é o que corta o acesso.
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let carol = signup(&app, &db, "carol").await;
    let id = post(&app, &alice, "post da alice").await;
    call(
        &app,
        Method::PUT,
        "/v1/users/carol/block",
        Some(&alice),
        None,
    )
    .await;

    let (s, _) = call(
        &app,
        Method::PUT,
        &format!("/v1/posts/{id}/like"),
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/posts/{id}/comments"),
        Some(&carol),
        Some(json!({ "body": "intrometida" })),
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(
        &app,
        Method::GET,
        &format!("/v1/posts/{id}/comments"),
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn comment_flow_and_permissions(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;
    befriend(&app, &alice, "alice", &carol, "carol").await;
    let id = post(&app, &alice, "post da alice").await;
    let uri = format!("/v1/posts/{id}/comments");

    let (s, c1) = call(
        &app,
        Method::POST,
        &uri,
        Some(&bob),
        Some(json!({ "body": " primeiro! " })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(c1["body"], "primeiro!");
    let (_, c2) = call(
        &app,
        Method::POST,
        &uri,
        Some(&carol),
        Some(json!({ "body": "segundo" })),
    )
    .await;

    // Validação.
    let (s, err) = call(
        &app,
        Method::POST,
        &uri,
        Some(&bob),
        Some(json!({ "body": "  " })),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(err["error"], "invalid_comment_body");

    // Ordem cronológica e contagem no post.
    let (_, list) = call(&app, Method::GET, &uri, Some(&carol), None).await;
    let bodies: Vec<&str> = list["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["body"].as_str().unwrap())
        .collect();
    assert_eq!(bodies, ["primeiro!", "segundo"]);
    // Carol só pode apagar o próprio comentário.
    assert_eq!(list["items"][0]["can_delete"], false);
    assert_eq!(list["items"][1]["can_delete"], true);
    let (_, p) = get_post(&app, &bob, &id).await;
    assert_eq!(p["comment_count"], 2);

    // Bob não apaga comentário da Carol; Alice (dona do post) apaga.
    let c2_id = c2["id"].as_str().unwrap();
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/comments/{c2_id}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/comments/{c2_id}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, list) = call(&app, Method::GET, &uri, Some(&bob), None).await;
    assert_eq!(list["items"].as_array().unwrap().len(), 1);

    // Texto apagado não fica no banco.
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM comments WHERE body = 'segundo'")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 0);
}

#[sqlx::test]
async fn comments_from_blocked_people_are_hidden(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;
    befriend(&app, &alice, "alice", &carol, "carol").await;
    let id = post(&app, &alice, "post").await;
    let uri = format!("/v1/posts/{id}/comments");
    call(
        &app,
        Method::POST,
        &uri,
        Some(&carol),
        Some(json!({ "body": "da carol" })),
    )
    .await;

    // Bob bloqueia Carol: não vê o comentário dela.
    call(&app, Method::PUT, "/v1/users/carol/block", Some(&bob), None).await;
    let (_, list) = call(&app, Method::GET, &uri, Some(&bob), None).await;
    assert!(list["items"].as_array().unwrap().is_empty());
    // Alice ainda vê.
    let (_, list) = call(&app, Method::GET, &uri, Some(&alice), None).await;
    assert_eq!(list["items"].as_array().unwrap().len(), 1);
}

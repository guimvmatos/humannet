//! Fase 1a: perfis, seguir, posts e feed cronológico.

mod common;

use common::*;

async fn post(app: &Router, token: &str, body: &str) -> Value {
    let (status, res) = call(
        app,
        Method::POST,
        "/v1/posts",
        Some(token),
        Some(json!({ "body": body })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{res}");
    res
}

/// `a` pede amizade a `b_name` e `b` aceita.
async fn befriend(app: &Router, a: &str, a_name: &str, b: &str, b_name: &str) {
    let (s, r) = call(
        app,
        Method::PUT,
        &format!("/v1/users/{b_name}/friend"),
        Some(a),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(r["relation"], "request_sent");
    let (s, r) = call(
        app,
        Method::PUT,
        &format!("/v1/users/{a_name}/friend"),
        Some(b),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(r["relation"], "friends");
}

fn bodies(page: &Value) -> Vec<&str> {
    page["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["body"].as_str().unwrap())
        .collect()
}

// ---------------------------------------------------------------- perfil

#[sqlx::test]
async fn profile_counts_are_private(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    befriend(&app, &bob, "bob", &alice, "alice").await;

    // Alice vê as próprias contagens.
    let (s, me) = call(&app, Method::GET, "/v1/users/alice", Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(me["is_self"], true);
    assert_eq!(me["relation"], "self");
    assert_eq!(me["stats"]["friends"], 1);

    // Bob vê o perfil da Alice sem contagens e sem e-mail (R3).
    let (_, other) = call(&app, Method::GET, "/v1/users/ALICE", Some(&bob), None).await;
    assert_eq!(other["username"], "alice");
    assert_eq!(other["is_self"], false);
    assert_eq!(other["relation"], "friends");
    assert!(other.get("stats").is_none());
    assert!(other.get("email").is_none());
}

#[sqlx::test]
async fn profile_not_found_and_auth(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let (s, _) = call(&app, Method::GET, "/v1/users/ninguem", Some(&alice), None).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(&app, Method::GET, "/v1/users/a.b", Some(&alice), None).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(&app, Method::GET, "/v1/users/alice", None, None).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
}

#[sqlx::test]
async fn update_profile_partial(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;

    let (s, me) = call(
        &app,
        Method::PATCH,
        "/v1/me/profile",
        Some(&alice),
        Some(json!({ "display_name": "  Alice A. ", "bio": "Leitora\r\nCiclista" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{me}");
    assert_eq!(me["display_name"], "Alice A.");
    assert_eq!(me["bio"], "Leitora\nCiclista");

    // Só a bio muda; display_name preservado.
    let (_, me) = call(
        &app,
        Method::PATCH,
        "/v1/me/profile",
        Some(&alice),
        Some(json!({ "bio": "" })),
    )
    .await;
    assert_eq!(me["display_name"], "Alice A.");
    assert_eq!(me["bio"], "");

    // "" remove o display_name.
    let (_, me) = call(
        &app,
        Method::PATCH,
        "/v1/me/profile",
        Some(&alice),
        Some(json!({ "display_name": "" })),
    )
    .await;
    assert!(me["display_name"].is_null());

    let (s, err) = call(
        &app,
        Method::PATCH,
        "/v1/me/profile",
        Some(&alice),
        Some(json!({ "display_name": "x".repeat(51) })),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(err["error"], "invalid_display_name");
}

// ---------------------------------------------------------------- posts

#[sqlx::test]
async fn create_get_and_validate_post(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;

    let p = post(&app, &alice, "  Olá, HumanNet!  ").await;
    assert_eq!(p["body"], "Olá, HumanNet!");
    assert_eq!(p["author"]["username"], "alice");
    assert!(p["edited_at"].is_null());
    assert!(p.get("likes").is_none(), "sem contagens públicas");

    let id = p["id"].as_str().unwrap();
    let (s, got) = call(
        &app,
        Method::GET,
        &format!("/v1/posts/{id}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(got["id"], p["id"]);

    for bad in ["", "   ", &"x".repeat(5001)] {
        let (s, err) = call(
            &app,
            Method::POST,
            "/v1/posts",
            Some(&alice),
            Some(json!({ "body": bad })),
        )
        .await;
        assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(err["error"], "invalid_post_body");
    }
}

#[sqlx::test]
async fn only_author_can_delete_and_content_is_erased(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let id = post(&app, &alice, "texto sensível").await["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let uri = format!("/v1/posts/{id}");

    let (s, _) = call(&app, Method::DELETE, &uri, Some(&bob), None).await;
    assert_eq!(s, StatusCode::FORBIDDEN);

    let (s, _) = call(&app, Method::DELETE, &uri, Some(&alice), None).await;
    assert_eq!(s, StatusCode::NO_CONTENT);

    let (s, _) = call(&app, Method::GET, &uri, Some(&alice), None).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(&app, Method::DELETE, &uri, Some(&alice), None).await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    let (stored,): (String,) = sqlx::query_as("SELECT body FROM posts")
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(
        !stored.contains("sensível"),
        "texto apagado não pode ficar no banco"
    );
}

#[sqlx::test]
async fn invalid_post_id_is_rejected(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let (s, _) = call(
        &app,
        Method::GET,
        "/v1/posts/nao-e-uuid",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
}

// ---------------------------------------------------------------- feed

#[sqlx::test]
async fn feed_is_chronological_from_friends_and_self(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;

    post(&app, &bob, "bob 1").await;
    post(&app, &carol, "carol 1").await; // Carol só tem pedido pendente
    post(&app, &alice, "alice 1").await;
    post(&app, &bob, "bob 2").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;
    call(
        &app,
        Method::PUT,
        "/v1/users/carol/friend",
        Some(&alice),
        None,
    )
    .await;

    let (s, feed) = call(&app, Method::GET, "/v1/feed", Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(bodies(&feed), ["bob 2", "alice 1", "bob 1"]);
    assert!(feed["next_cursor"].is_null());
}

#[sqlx::test]
async fn feed_pagination_has_explicit_end(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    for i in 1..=5 {
        post(&app, &alice, &format!("p{i}")).await;
    }

    let (_, p1) = call(&app, Method::GET, "/v1/feed?limit=2", Some(&alice), None).await;
    assert_eq!(bodies(&p1), ["p5", "p4"]);
    let c1 = p1["next_cursor"].as_str().unwrap();

    let (_, p2) = call(
        &app,
        Method::GET,
        &format!("/v1/feed?limit=2&before={c1}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(bodies(&p2), ["p3", "p2"]);
    let c2 = p2["next_cursor"].as_str().unwrap();

    let (_, p3) = call(
        &app,
        Method::GET,
        &format!("/v1/feed?limit=2&before={c2}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(bodies(&p3), ["p1"]);
    assert!(p3["next_cursor"].is_null(), "fim explícito do feed");
}

#[sqlx::test]
async fn feed_excludes_deleted_and_unfriended(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;
    let p = post(&app, &bob, "vai sumir").await;
    post(&app, &bob, "fica").await;

    let id = p["id"].as_str().unwrap();
    call(
        &app,
        Method::DELETE,
        &format!("/v1/posts/{id}"),
        Some(&bob),
        None,
    )
    .await;
    let (_, feed) = call(&app, Method::GET, "/v1/feed", Some(&alice), None).await;
    assert_eq!(bodies(&feed), ["fica"]);

    call(
        &app,
        Method::DELETE,
        "/v1/users/bob/friend",
        Some(&alice),
        None,
    )
    .await;
    let (_, feed) = call(&app, Method::GET, "/v1/feed", Some(&alice), None).await;
    assert!(bodies(&feed).is_empty());
}

#[sqlx::test]
async fn user_posts_listing(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    post(&app, &bob, "b1").await;
    post(&app, &bob, "b2").await;
    post(&app, &alice, "a1").await;

    // Sem amizade: posts do perfil são privados.
    let (s, _) = call(&app, Method::GET, "/v1/users/bob/posts", Some(&alice), None).await;
    assert_eq!(s, StatusCode::FORBIDDEN);

    // O próprio sempre vê.
    let (s, page) = call(&app, Method::GET, "/v1/users/bob/posts", Some(&bob), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(bodies(&page), ["b2", "b1"]);

    befriend(&app, &alice, "alice", &bob, "bob").await;
    let (s, page) = call(&app, Method::GET, "/v1/users/bob/posts", Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(bodies(&page), ["b2", "b1"]);
}

#[sqlx::test]
async fn single_post_hidden_when_blocked(db: PgPool) {
    // Posts são globais (ADR-0008): não-amigo vê; bloqueio esconde.
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let id = post(&app, &bob, "só amigos").await["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let uri = format!("/v1/posts/{id}");

    let (s, _) = call(&app, Method::GET, &uri, Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK);

    // 404, não 403: não revela que o post existe.
    call(&app, Method::PUT, "/v1/users/alice/block", Some(&bob), None).await;
    let (s, _) = call(&app, Method::GET, &uri, Some(&alice), None).await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    call(
        &app,
        Method::DELETE,
        "/v1/users/alice/block",
        Some(&bob),
        None,
    )
    .await;
    let (s, _) = call(&app, Method::GET, &uri, Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK);
}

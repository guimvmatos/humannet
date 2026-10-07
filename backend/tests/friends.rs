//! ADR-0006: amizade mútua.

mod common;

use common::*;

async fn put_friend(app: &Router, token: &str, username: &str) -> (StatusCode, Value) {
    call(
        app,
        Method::PUT,
        &format!("/v1/users/{username}/friend"),
        Some(token),
        None,
    )
    .await
}

async fn del_friend(app: &Router, token: &str, username: &str) -> StatusCode {
    call(
        app,
        Method::DELETE,
        &format!("/v1/users/{username}/friend"),
        Some(token),
        None,
    )
    .await
    .0
}

async fn relation(app: &Router, token: &str, username: &str) -> String {
    let (_, p) = call(
        app,
        Method::GET,
        &format!("/v1/users/{username}"),
        Some(token),
        None,
    )
    .await;
    p["relation"].as_str().unwrap().to_owned()
}

async fn friendship_rows(db: &PgPool) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM friendships")
        .fetch_one(db)
        .await
        .unwrap()
}

async fn request_rows(db: &PgPool) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM friend_requests")
        .fetch_one(db)
        .await
        .unwrap()
}

#[sqlx::test]
async fn request_then_accept(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;

    let (s, r) = put_friend(&app, &alice, "bob").await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(r["relation"], "request_sent");
    assert_eq!(relation(&app, &alice, "bob").await, "request_sent");
    assert_eq!(relation(&app, &bob, "alice").await, "request_received");

    // Repetir o pedido é idempotente.
    let (_, r) = put_friend(&app, &alice, "bob").await;
    assert_eq!(r["relation"], "request_sent");
    assert_eq!(request_rows(&db).await, 1);

    // Bob vê o pedido na lista de recebidos.
    let (_, reqs) = call(&app, Method::GET, "/v1/friend-requests", Some(&bob), None).await;
    assert_eq!(reqs["items"][0]["user"]["username"], "alice");
    let (_, p) = call(&app, Method::GET, "/v1/users/bob", Some(&bob), None).await;
    assert_eq!(p["stats"]["pending_requests"], 1);

    // Aceitar.
    let (_, r) = put_friend(&app, &bob, "alice").await;
    assert_eq!(r["relation"], "friends");
    assert_eq!(relation(&app, &alice, "bob").await, "friends");
    assert_eq!(relation(&app, &bob, "alice").await, "friends");

    // Invariantes: uma linha de amizade, nenhum pedido pendente.
    assert_eq!(friendship_rows(&db).await, 1);
    assert_eq!(request_rows(&db).await, 0);

    // Ambos se veem na lista de amigos.
    for (tok, other) in [(&alice, "bob"), (&bob, "alice")] {
        let (_, list) = call(&app, Method::GET, "/v1/friends", Some(tok), None).await;
        assert_eq!(list["items"][0]["username"], other);
        assert!(list["items"][0].get("email").is_none());
    }
}

#[sqlx::test]
async fn decline_cancel_and_unfriend_remove_everything(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;

    // Recusar.
    put_friend(&app, &alice, "bob").await;
    assert_eq!(
        del_friend(&app, &bob, "alice").await,
        StatusCode::NO_CONTENT
    );
    assert_eq!(relation(&app, &alice, "bob").await, "none");

    // Cancelar o próprio pedido.
    put_friend(&app, &alice, "bob").await;
    assert_eq!(
        del_friend(&app, &alice, "bob").await,
        StatusCode::NO_CONTENT
    );
    assert_eq!(relation(&app, &bob, "alice").await, "none");

    // Desfazer amizade (qualquer lado), idempotente.
    put_friend(&app, &alice, "bob").await;
    put_friend(&app, &bob, "alice").await;
    for _ in 0..2 {
        assert_eq!(
            del_friend(&app, &bob, "alice").await,
            StatusCode::NO_CONTENT
        );
    }
    assert_eq!(relation(&app, &alice, "bob").await, "none");
    assert_eq!(friendship_rows(&db).await, 0);
    assert_eq!(request_rows(&db).await, 0);
}

#[sqlx::test]
async fn simultaneous_requests_become_friends(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;

    // Disparos concorrentes nos dois sentidos, várias vezes.
    let mut tasks = Vec::new();
    for i in 0..10 {
        let app = app.clone();
        let (tok, other) = if i % 2 == 0 {
            (alice.clone(), "bob")
        } else {
            (bob.clone(), "alice")
        };
        tasks.push(tokio::spawn(
            async move { put_friend(&app, &tok, other).await },
        ));
    }
    for t in tasks {
        let (s, _) = t.await.unwrap();
        assert_eq!(s, StatusCode::OK);
    }

    assert_eq!(relation(&app, &alice, "bob").await, "friends");
    assert_eq!(friendship_rows(&db).await, 1);
    assert_eq!(
        request_rows(&db).await,
        0,
        "nunca há pedido pendente entre amigos"
    );
}

#[sqlx::test]
async fn cannot_befriend_self_or_unknown(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let (s, err) = put_friend(&app, &alice, "alice").await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(err["error"], "cannot_befriend_self");
    let (s, _) = put_friend(&app, &alice, "ninguem").await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = put_friend(&app, "", "alice").await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
}

#[sqlx::test]
async fn pending_requests_are_limited(db: PgPool) {
    use humannet_api::routes::friends::MAX_PENDING_SENT;
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;

    // Cria usuários direto no banco (mais rápido que registrar 50 contas).
    let n = MAX_PENDING_SENT + 1;
    for i in 0..n {
        sqlx::query(
            "INSERT INTO users (id, username, email, password_hash) VALUES ($1, $2, $3, 'x')",
        )
        .bind(uuid::Uuid::now_v7())
        .bind(format!("user_{i}"))
        .bind(format!("u{i}@example.com"))
        .execute(&db)
        .await
        .unwrap();
    }
    for i in 0..MAX_PENDING_SENT {
        let (s, _) = put_friend(&app, &alice, &format!("user_{i}")).await;
        assert_eq!(s, StatusCode::OK);
    }
    let (s, err) = put_friend(&app, &alice, &format!("user_{MAX_PENDING_SENT}")).await;
    assert_eq!(s, StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(err["error"], "friend_request_limit");
}

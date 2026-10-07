//! Fase 1b: bloqueio, denúncia, trocar senha, excluir conta.

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
    let (_, r) = call(
        app,
        Method::PUT,
        &format!("/v1/users/{a_name}/friend"),
        Some(b),
        None,
    )
    .await;
    assert_eq!(r["relation"], "friends");
}

async fn post(app: &Router, token: &str, body: &str) -> String {
    let (s, p) = call(
        app,
        Method::POST,
        "/v1/posts",
        Some(token),
        Some(json!({ "body": body })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    p["id"].as_str().unwrap().to_owned()
}

async fn login(app: &Router, username: &str, password: &str) -> StatusCode {
    call(
        app,
        Method::POST,
        "/v1/auth/login",
        None,
        Some(json!({ "login": username, "password": password })),
    )
    .await
    .0
}

// ---------------------------------------------------------------- bloqueio

#[sqlx::test]
async fn block_removes_friendship_and_hides_both_ways(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;
    post(&app, &bob, "post do bob").await;

    let (s, _) = call(&app, Method::PUT, "/v1/users/bob/block", Some(&alice), None).await;
    assert_eq!(s, StatusCode::NO_CONTENT);

    // Amizade desfeita: o post do Bob some do feed da Alice.
    let (_, feed) = call(&app, Method::GET, "/v1/feed", Some(&alice), None).await;
    assert!(feed["items"].as_array().unwrap().is_empty());

    // Nenhum dos dois encontra o outro, e o bloqueio não é revelado (404).
    for (tok, other) in [(&alice, "bob"), (&bob, "alice")] {
        let (s, _) = call(
            &app,
            Method::GET,
            &format!("/v1/users/{other}"),
            Some(tok),
            None,
        )
        .await;
        assert_eq!(s, StatusCode::NOT_FOUND, "{other}");
        let (s, _) = call(
            &app,
            Method::PUT,
            &format!("/v1/users/{other}/friend"),
            Some(tok),
            None,
        )
        .await;
        assert_eq!(s, StatusCode::NOT_FOUND, "pedido de amizade para {other}");
        let (s, _) = call(
            &app,
            Method::GET,
            &format!("/v1/users/{other}/posts"),
            Some(tok),
            None,
        )
        .await;
        assert_eq!(s, StatusCode::NOT_FOUND);
    }
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM friend_requests")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 0);

    // Alice vê o Bob na sua lista de bloqueados; Bob não vê nada.
    let (_, list) = call(&app, Method::GET, "/v1/blocks", Some(&alice), None).await;
    assert_eq!(list["items"][0]["username"], "bob");
    let (_, list) = call(&app, Method::GET, "/v1/blocks", Some(&bob), None).await;
    assert!(list["items"].as_array().unwrap().is_empty());

    // Desbloquear devolve a visibilidade, mas não a amizade.
    let (s, _) = call(
        &app,
        Method::DELETE,
        "/v1/users/bob/block",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (s, p) = call(&app, Method::GET, "/v1/users/bob", Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(p["relation"], "none");
}

#[sqlx::test]
async fn block_is_idempotent_and_not_self(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    signup(&app, &db, "bob").await;
    for _ in 0..2 {
        let (s, _) = call(&app, Method::PUT, "/v1/users/bob/block", Some(&alice), None).await;
        assert_eq!(s, StatusCode::NO_CONTENT);
    }
    let (s, err) = call(
        &app,
        Method::PUT,
        "/v1/users/alice/block",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(err["error"], "cannot_block_self");
}

// ---------------------------------------------------------------- denúncia

#[sqlx::test]
async fn report_post_keeps_evidence_after_deletion(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;
    let id = post(&app, &bob, "conteúdo ofensivo").await;

    let body =
        json!({ "kind": "post", "post_id": id, "reason": "harassment", "details": "me ofendeu" });
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&alice),
        Some(body.clone()),
    )
    .await;
    assert_eq!(s, StatusCode::ACCEPTED);
    // Repetir não duplica.
    let (s, _) = call(&app, Method::POST, "/v1/reports", Some(&alice), Some(body)).await;
    assert_eq!(s, StatusCode::ACCEPTED);

    // O autor apaga o post; a evidência fica na denúncia.
    call(
        &app,
        Method::DELETE,
        &format!("/v1/posts/{id}"),
        Some(&bob),
        None,
    )
    .await;
    let rows: Vec<(String, String, String)> =
        sqlx::query_as("SELECT target_kind, snapshot, status FROM reports")
            .fetch_all(&db)
            .await
            .unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(
        rows[0],
        ("post".into(), "conteúdo ofensivo".into(), "open".into())
    );
}

#[sqlx::test]
async fn report_validation(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let bob_post = post(&app, &bob, "privado").await;
    let own = post(&app, &alice, "meu").await;

    let cases = [
        (
            json!({ "kind": "user", "username": "bob", "reason": "nao-existe" }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
        (
            json!({ "kind": "user", "username": "alice", "reason": "spam" }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
        (
            json!({ "kind": "post", "post_id": own, "reason": "spam" }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
        // Post de não-amigo: não pode ver, não pode denunciar (e não revela).
        (
            json!({ "kind": "post", "post_id": bob_post, "reason": "spam" }),
            StatusCode::NOT_FOUND,
        ),
        (
            json!({ "kind": "user", "username": "ninguem", "reason": "spam" }),
            StatusCode::NOT_FOUND,
        ),
        (
            json!({ "kind": "user", "username": "bob", "reason": "spam", "details": "x".repeat(1001) }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
    ];
    for (body, expected) in cases {
        let (s, _) = call(
            &app,
            Method::POST,
            "/v1/reports",
            Some(&alice),
            Some(body.clone()),
        )
        .await;
        assert_eq!(s, expected, "{body}");
    }

    // Denunciar perfil funciona sem amizade.
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&alice),
        Some(json!({ "kind": "user", "username": "bob", "reason": "impersonation" })),
    )
    .await;
    assert_eq!(s, StatusCode::ACCEPTED);
}

// ---------------------------------------------------------------- conta

#[sqlx::test]
async fn change_password_requires_current_and_revokes_other_sessions(db: PgPool) {
    let app = test_app(db.clone());
    let t1 = signup(&app, &db, "alice").await;
    let (_, l) = call(
        &app,
        Method::POST,
        "/v1/auth/login",
        None,
        Some(json!({ "login": "alice", "password": PASSWORD })),
    )
    .await;
    let t2 = l["token"].as_str().unwrap().to_owned();

    let (s, err) = call(
        &app,
        Method::PUT,
        "/v1/me/password",
        Some(&t1),
        Some(json!({ "current_password": "senha-errada-123", "new_password": "nova-senha-segura-1" })),
    )
    .await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    assert_eq!(err["error"], "invalid_credentials");

    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/password",
        Some(&t1),
        Some(json!({ "current_password": PASSWORD, "new_password": "curta" })),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/password",
        Some(&t1),
        Some(json!({ "current_password": PASSWORD, "new_password": "nova-senha-segura-1" })),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);

    // Sessão atual continua; a outra foi encerrada.
    assert_eq!(
        call(&app, Method::GET, "/v1/me", Some(&t1), None).await.0,
        StatusCode::OK
    );
    assert_eq!(
        call(&app, Method::GET, "/v1/me", Some(&t2), None).await.0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        login(&app, "alice", PASSWORD).await,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        login(&app, "alice", "nova-senha-segura-1").await,
        StatusCode::OK
    );
}

#[sqlx::test]
async fn delete_account_erases_everything(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;
    post(&app, &alice, "texto da alice").await;
    call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&alice),
        Some(json!({ "kind": "user", "username": "bob", "reason": "spam" })),
    )
    .await;

    // Senha errada não apaga.
    let (s, _) = call(
        &app,
        Method::DELETE,
        "/v1/me",
        Some(&alice),
        Some(json!({ "password": "senha-errada-123" })),
    )
    .await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);

    let (s, _) = call(
        &app,
        Method::DELETE,
        "/v1/me",
        Some(&alice),
        Some(json!({ "password": PASSWORD })),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);

    // Sessão morta, login impossível, perfil inexistente.
    assert_eq!(
        call(&app, Method::GET, "/v1/me", Some(&alice), None)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        login(&app, "alice", PASSWORD).await,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        call(&app, Method::GET, "/v1/users/alice", Some(&bob), None)
            .await
            .0,
        StatusCode::NOT_FOUND
    );

    // Nada da Alice no banco além da denúncia, que fica anônima.
    let posts: i64 = sqlx::query_scalar("SELECT count(*) FROM posts")
        .fetch_one(&db)
        .await
        .unwrap();
    let friendships: i64 = sqlx::query_scalar("SELECT count(*) FROM friendships")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!((posts, friendships), (0, 0));
    let posts_text: i64 =
        sqlx::query_scalar("SELECT count(*) FROM posts WHERE body LIKE '%alice%'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(posts_text, 0);
    let reporter: Option<uuid::Uuid> = sqlx::query_scalar("SELECT reporter_id FROM reports")
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(reporter.is_none(), "denúncia fica anônima");

    // O nome de usuário fica livre de novo.
    let invite = admin_invite(&db).await;
    let (s, _) = register(&app, &invite, "alice", "alice@example.com").await;
    assert_eq!(s, StatusCode::CREATED);
}

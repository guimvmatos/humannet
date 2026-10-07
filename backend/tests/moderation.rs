//! Beta lote 2: moderação, suspensão e redefinição de senha assistida.

mod common;

use common::*;
use humannet_api::routes::admin::sync_admins;

async fn make_admin(db: &PgPool, username: &str) {
    sync_admins(db, &[username.to_owned()]).await.unwrap();
}

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

async fn login(app: &Router, username: &str, password: &str) -> (StatusCode, Value) {
    call(
        app,
        Method::POST,
        "/v1/auth/login",
        None,
        Some(json!({ "login": username, "password": password })),
    )
    .await
}

#[sqlx::test]
async fn admin_routes_require_admin_role(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let (s, _) = call(&app, Method::GET, "/v1/admin/reports", Some(&alice), None).await;
    assert_eq!(s, StatusCode::FORBIDDEN);

    make_admin(&db, "alice").await;
    let (s, _) = call(&app, Method::GET, "/v1/admin/reports", Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK);
    let (_, me) = call(&app, Method::GET, "/v1/me", Some(&alice), None).await;
    assert_eq!(me["role"], "admin");

    // Sair da lista remove o papel.
    sync_admins(&db, &[]).await.unwrap();
    let (s, _) = call(&app, Method::GET, "/v1/admin/reports", Some(&alice), None).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
}

/// ADMIN_USERNAMES vale também para quem se cadastra com a API já no ar.
#[sqlx::test]
async fn admin_username_is_admin_from_registration(db: PgPool) {
    let policy = Policy {
        admin_usernames: vec!["boss".to_owned()],
        ..Policy::default()
    };
    let app = humannet_api::app(AppState::new(db.clone(), policy));
    let invite = admin_invite(&db).await;
    let (s, body) = register(&app, &invite, "Boss", "boss@example.com").await;
    assert_eq!(s, StatusCode::CREATED, "{body}");
    assert_eq!(body["user"]["role"], "admin");
    let boss = body["token"].as_str().unwrap();
    let (s, _) = call(&app, Method::GET, "/v1/admin/reports", Some(boss), None).await;
    assert_eq!(s, StatusCode::OK);

    let alice = signup(&app, &db, "alice").await;
    let (_, me) = call(&app, Method::GET, "/v1/me", Some(&alice), None).await;
    assert_eq!(me["role"], "user");
}

#[sqlx::test]
async fn remove_reported_post(db: PgPool) {
    let app = test_app(db.clone());
    let admin = signup(&app, &db, "admin").await;
    make_admin(&db, "admin").await;
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    befriend(&app, &alice, "alice", &bob, "bob").await;
    befriend(&app, &carol, "carol", &bob, "bob").await;
    let (_, p) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&bob),
        Some(json!({ "body": "ofensa" })),
    )
    .await;
    let post_id = p["id"].as_str().unwrap().to_owned();

    // Duas pessoas denunciam o mesmo post.
    for tok in [&alice, &carol] {
        call(
            &app,
            Method::POST,
            "/v1/reports",
            Some(tok),
            Some(json!({ "kind": "post", "post_id": post_id, "reason": "harassment" })),
        )
        .await;
    }

    let (_, list) = call(&app, Method::GET, "/v1/admin/reports", Some(&admin), None).await;
    let items = list["items"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0]["target_username"], "bob");
    assert_eq!(items[0]["snapshot"], "ofensa");
    let report_id = items[0]["id"].as_str().unwrap();

    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/admin/reports/{report_id}/resolve"),
        Some(&admin),
        Some(json!({ "action": "remove_post" })),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);

    // Post sumiu; as duas denúncias foram fechadas; ação registrada.
    let (s, _) = call(
        &app,
        Method::GET,
        &format!("/v1/posts/{post_id}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (_, list) = call(&app, Method::GET, "/v1/admin/reports", Some(&admin), None).await;
    assert!(list["items"].as_array().unwrap().is_empty());
    let (_, done) = call(
        &app,
        Method::GET,
        "/v1/admin/reports?status=actioned",
        Some(&admin),
        None,
    )
    .await;
    assert_eq!(done["items"].as_array().unwrap().len(), 2);
    let logged: i64 =
        sqlx::query_scalar("SELECT count(*) FROM moderation_actions WHERE action = 'remove_post'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(logged, 1);
}

#[sqlx::test]
async fn suspend_and_unsuspend(db: PgPool) {
    let app = test_app(db.clone());
    let admin = signup(&app, &db, "admin").await;
    make_admin(&db, "admin").await;
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;

    call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&alice),
        Some(json!({ "kind": "user", "username": "bob", "reason": "spam" })),
    )
    .await;
    let (_, list) = call(&app, Method::GET, "/v1/admin/reports", Some(&admin), None).await;
    let id = list["items"][0]["id"].as_str().unwrap().to_owned();
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/admin/reports/{id}/resolve"),
        Some(&admin),
        Some(json!({ "action": "suspend_user" })),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);

    // Sessões encerradas; login recusado com motivo claro.
    let (s, _) = call(&app, Method::GET, "/v1/me", Some(&bob), None).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    let (s, err) = login(&app, "bob", PASSWORD).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    assert_eq!(err["error"], "account_suspended");
    // Senha errada continua genérica (não revela a suspensão).
    let (s, _) = login(&app, "bob", "senha-errada-123").await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);

    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/admin/users/bob/unsuspend",
        Some(&admin),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (s, _) = login(&app, "bob", PASSWORD).await;
    assert_eq!(s, StatusCode::OK);
}

#[sqlx::test]
async fn admins_cannot_be_suspended(db: PgPool) {
    let app = test_app(db.clone());
    let admin = signup(&app, &db, "admin").await;
    make_admin(&db, "admin").await;
    let alice = signup(&app, &db, "alice").await;
    call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&alice),
        Some(json!({ "kind": "user", "username": "admin", "reason": "spam" })),
    )
    .await;
    let (_, list) = call(&app, Method::GET, "/v1/admin/reports", Some(&admin), None).await;
    let id = list["items"][0]["id"].as_str().unwrap().to_owned();
    call(
        &app,
        Method::POST,
        &format!("/v1/admin/reports/{id}/resolve"),
        Some(&admin),
        Some(json!({ "action": "suspend_user" })),
    )
    .await;
    let (s, _) = call(&app, Method::GET, "/v1/me", Some(&admin), None).await;
    assert_eq!(s, StatusCode::OK);
}

#[sqlx::test]
async fn admin_assisted_password_reset(db: PgPool) {
    let app = test_app(db.clone());
    let admin = signup(&app, &db, "admin").await;
    make_admin(&db, "admin").await;
    let bob = signup(&app, &db, "bob").await;

    // Só admin gera código.
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/admin/users/admin/password-reset",
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);

    let (s, c) = call(
        &app,
        Method::POST,
        "/v1/admin/users/bob/password-reset",
        Some(&admin),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    let code = c["code"].as_str().unwrap().to_owned();
    assert_eq!(code.len(), 10);

    let reset = |code: String, pw: &'static str, user: &'static str| {
        let app = app.clone();
        async move {
            call(
                &app,
                Method::POST,
                "/v1/auth/reset-password",
                None,
                Some(json!({ "username": user, "code": code, "new_password": pw })),
            )
            .await
        }
    };

    // Código errado, usuário inexistente: mesma resposta.
    let (s, e) = reset("ERRADO1234".into(), "nova-senha-segura-1", "bob").await;
    assert_eq!(
        (s, e["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_reset_code"))
    );
    let (s2, e2) = reset(code.clone(), "nova-senha-segura-1", "ninguem").await;
    assert_eq!(
        (s2, e2["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_reset_code"))
    );

    // Código certo (minúsculas aceitas): troca a senha e derruba as sessões.
    let (s, _) = reset(code.to_lowercase(), "nova-senha-segura-1", "bob").await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    assert_eq!(
        call(&app, Method::GET, "/v1/me", Some(&bob), None).await.0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        login(&app, "bob", "nova-senha-segura-1").await.0,
        StatusCode::OK
    );

    // Uso único.
    let (s, _) = reset(code, "outra-senha-segura-2", "bob").await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test]
async fn reset_code_dies_after_too_many_attempts(db: PgPool) {
    use humannet_api::routes::admin::RESET_MAX_ATTEMPTS;
    let app = test_app(db.clone());
    let admin = signup(&app, &db, "admin").await;
    make_admin(&db, "admin").await;
    signup(&app, &db, "bob").await;
    let (_, c) = call(
        &app,
        Method::POST,
        "/v1/admin/users/bob/password-reset",
        Some(&admin),
        None,
    )
    .await;
    let code = c["code"].as_str().unwrap().to_owned();

    for _ in 0..RESET_MAX_ATTEMPTS {
        call(
            &app,
            Method::POST,
            "/v1/auth/reset-password",
            None,
            Some(json!({ "username": "bob", "code": "ERRADO1234", "new_password": "nova-senha-segura-1" })),
        )
        .await;
    }
    // Mesmo o código certo não serve mais.
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/auth/reset-password",
        None,
        Some(json!({ "username": "bob", "code": code, "new_password": "nova-senha-segura-1" })),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
}

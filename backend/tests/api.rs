//! Testes de integração da API. Cada `#[sqlx::test]` recebe um banco novo com
//! as migrações aplicadas. Requer DATABASE_URL apontando para um Postgres.

mod common;

use common::*;

// ---------------------------------------------------------------- health

#[sqlx::test]
async fn health_ok(db: PgPool) {
    let app = test_app(db);
    let (status, body) = call(&app, Method::GET, "/health", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "ok");
}

// ---------------------------------------------------------------- registro

#[sqlx::test]
async fn register_happy_path_returns_token_that_works(db: PgPool) {
    let app = test_app(db.clone());
    let invite = admin_invite(&db).await;

    let (status, body) = register(&app, &invite, "Gui_Matos", "Gui@Example.com").await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(
        body["user"]["username"], "gui_matos",
        "username normalizado"
    );
    assert_eq!(
        body["user"]["email"], "gui@example.com",
        "email normalizado"
    );
    assert!(body.get("password_hash").is_none());

    let token = body["token"].as_str().unwrap();
    let (status, me) = call(&app, Method::GET, "/v1/me", Some(token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(me["username"], "gui_matos");
}

#[sqlx::test]
async fn register_stores_only_hashes(db: PgPool) {
    let app = test_app(db.clone());
    let token = signup(&app, &db, "alice").await;

    let (pw_hash,): (String,) = sqlx::query_as("SELECT password_hash FROM users")
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(pw_hash.starts_with("$argon2id$"));
    assert!(!pw_hash.contains(PASSWORD));

    let (stored,): (Vec<u8>,) = sqlx::query_as("SELECT token_hash FROM sessions")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_ne!(
        stored,
        token.as_bytes(),
        "token não pode ser guardado em claro"
    );
    assert_eq!(stored.len(), 32);
}

#[sqlx::test]
async fn invite_is_single_use(db: PgPool) {
    let app = test_app(db.clone());
    let invite = admin_invite(&db).await;

    let (s1, _) = register(&app, &invite, "alice", "alice@example.com").await;
    let (s2, body) = register(&app, &invite, "bob", "bob@example.com").await;
    assert_eq!(s1, StatusCode::CREATED);
    assert_eq!(s2, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"], "invalid_invite");
}

#[sqlx::test]
async fn unknown_or_expired_invite_is_rejected(db: PgPool) {
    let app = test_app(db.clone());

    let (status, body) = register(&app, "nao-existe", "alice", "alice@example.com").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"], "invalid_invite");

    let invite = admin_invite(&db).await;
    sqlx::query("UPDATE invites SET expires_at = now() - interval '1 minute'")
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = register(&app, &invite, "alice", "alice@example.com").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[sqlx::test]
async fn failed_registration_does_not_consume_invite(db: PgPool) {
    let app = test_app(db.clone());
    signup(&app, &db, "alice").await;

    let invite = admin_invite(&db).await;
    let (status, body) = register(&app, &invite, "alice", "outra@example.com").await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["error"], "username_taken");

    // O mesmo convite continua válido para outro nome.
    let (status, _) = register(&app, &invite, "bob", "bob@example.com").await;
    assert_eq!(status, StatusCode::CREATED);
}

#[sqlx::test]
async fn duplicate_email_is_conflict(db: PgPool) {
    let app = test_app(db.clone());
    signup(&app, &db, "alice").await;
    let invite = admin_invite(&db).await;
    let (status, body) = register(&app, &invite, "bob", "ALICE@example.com").await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["error"], "email_taken");
}

#[sqlx::test]
async fn register_validates_input(db: PgPool) {
    let app = test_app(db.clone());
    let invite = admin_invite(&db).await;

    let cases = [
        (
            json!({"username": "a b", "email": "a@example.com", "password": PASSWORD}),
            "invalid_username",
        ),
        (
            json!({"username": "alice", "email": "nope", "password": PASSWORD}),
            "invalid_email",
        ),
        (
            json!({"username": "alice", "email": "a@example.com", "password": "curta"}),
            "invalid_password",
        ),
    ];
    for (mut body, expected) in cases {
        body["invite_code"] = json!(invite);
        let (status, res) = call(&app, Method::POST, "/v1/auth/register", None, Some(body)).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(res["error"], expected);
    }
}

#[sqlx::test]
async fn oversized_body_is_rejected(db: PgPool) {
    let app = test_app(db);
    let huge = "x".repeat(100 * 1024);
    let (status, _) = call(
        &app,
        Method::POST,
        "/v1/auth/login",
        None,
        Some(json!({"login": "a", "password": huge})),
    )
    .await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
}

// ---------------------------------------------------------------- login / logout

#[sqlx::test]
async fn login_with_username_or_email(db: PgPool) {
    let app = test_app(db.clone());
    signup(&app, &db, "alice").await;

    for login in ["alice", "ALICE", "alice@example.com"] {
        let (status, body) = call(
            &app,
            Method::POST,
            "/v1/auth/login",
            None,
            Some(json!({"login": login, "password": PASSWORD})),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "login={login}");
        assert_eq!(body["user"]["username"], "alice");
    }
}

#[sqlx::test]
async fn login_errors_are_indistinguishable(db: PgPool) {
    let app = test_app(db.clone());
    signup(&app, &db, "alice").await;

    let (s1, b1) = call(
        &app,
        Method::POST,
        "/v1/auth/login",
        None,
        Some(json!({"login": "alice", "password": "senha-errada-123"})),
    )
    .await;
    let (s2, b2) = call(
        &app,
        Method::POST,
        "/v1/auth/login",
        None,
        Some(json!({"login": "ninguem", "password": "senha-errada-123"})),
    )
    .await;
    assert_eq!(s1, StatusCode::UNAUTHORIZED);
    assert_eq!(
        (s1, &b1),
        (s2, &b2),
        "senha errada e usuário inexistente devem parecer iguais"
    );
    assert_eq!(b1["error"], "invalid_credentials");
}

#[sqlx::test]
async fn logout_revokes_only_current_session(db: PgPool) {
    let app = test_app(db.clone());
    let t1 = signup(&app, &db, "alice").await;
    let (_, body) = call(
        &app,
        Method::POST,
        "/v1/auth/login",
        None,
        Some(json!({"login": "alice", "password": PASSWORD})),
    )
    .await;
    let t2 = body["token"].as_str().unwrap().to_owned();

    let (status, _) = call(&app, Method::POST, "/v1/auth/logout", Some(&t1), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (s1, _) = call(&app, Method::GET, "/v1/me", Some(&t1), None).await;
    let (s2, _) = call(&app, Method::GET, "/v1/me", Some(&t2), None).await;
    assert_eq!(s1, StatusCode::UNAUTHORIZED);
    assert_eq!(s2, StatusCode::OK);
}

#[sqlx::test]
async fn expired_session_is_rejected(db: PgPool) {
    let app = test_app(db.clone());
    let token = signup(&app, &db, "alice").await;
    sqlx::query("UPDATE sessions SET expires_at = now() - interval '1 second'")
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = call(&app, Method::GET, "/v1/me", Some(&token), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test]
async fn me_requires_valid_bearer(db: PgPool) {
    let app = test_app(db);
    let (s, _) = call(&app, Method::GET, "/v1/me", None, None).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    let (s, _) = call(&app, Method::GET, "/v1/me", Some("lixo"), None).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    let fake = "A".repeat(43);
    let (s, _) = call(&app, Method::GET, "/v1/me", Some(&fake), None).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
}

// ---------------------------------------------------------------- convites

#[sqlx::test]
async fn user_invite_records_inviter(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;

    let (status, inv) = call(&app, Method::POST, "/v1/invites", Some(&alice), None).await;
    assert_eq!(status, StatusCode::CREATED);
    let code = inv["code"].as_str().unwrap();

    let (status, _) = register(&app, code, "bob", "bob@example.com").await;
    assert_eq!(status, StatusCode::CREATED);

    let (inviter,): (String,) = sqlx::query_as(
        "SELECT i.username FROM users u JOIN users i ON i.id = u.invited_by WHERE u.username = 'bob'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(inviter, "alice");
}

#[sqlx::test]
async fn invite_limit_is_enforced(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let limit = Policy::default().max_active_invites;

    for _ in 0..limit {
        let (s, _) = call(&app, Method::POST, "/v1/invites", Some(&alice), None).await;
        assert_eq!(s, StatusCode::CREATED);
    }
    let (s, body) = call(&app, Method::POST, "/v1/invites", Some(&alice), None).await;
    assert_eq!(s, StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(body["error"], "invite_limit");
}

#[sqlx::test]
async fn invites_require_auth(db: PgPool) {
    let app = test_app(db);
    let (s, _) = call(&app, Method::POST, "/v1/invites", None, None).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
}

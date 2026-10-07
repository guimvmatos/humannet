//! Beta lote 11: uma conta por CPF (sem guardar o número).

mod common;

use common::*;
use humannet_api::config::SecretKey;
use humannet_api::routes::admin::sync_admins;

fn app_with_cpf(db: &PgPool) -> Router {
    let policy = Policy {
        cpf_key: Some(SecretKey(b"chave-de-teste-com-32-bytes-ok!!".to_vec())),
        ..Policy::default()
    };
    app(AppState::new(db.clone(), policy))
}

async fn register_cpf(
    app: &Router,
    db: &PgPool,
    user: &str,
    cpf: Option<&str>,
) -> (StatusCode, Value) {
    let invite = admin_invite(db).await;
    let mut body = json!({
        "invite_code": invite,
        "username": user,
        "email": format!("{user}@example.com"),
        "password": PASSWORD,
    });
    if let Some(c) = cpf {
        body["cpf"] = json!(c);
    }
    call(app, Method::POST, "/v1/auth/register", None, Some(body)).await
}

#[sqlx::test]
async fn one_account_per_cpf(db: PgPool) {
    let app = app_with_cpf(&db);
    let (s, b) = register_cpf(&app, &db, "alice", None).await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("cpf_required"))
    );
    let (s, b) = register_cpf(&app, &db, "alice", Some("529.982.247-24")).await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_cpf"))
    );
    let (s, b) = register_cpf(&app, &db, "alice", Some("529.982.247-25")).await;
    assert_eq!(s, StatusCode::CREATED, "{b}");
    assert_eq!(b["user"]["needs_cpf"], false);

    // Mesmo CPF, com ou sem pontuação: recusado.
    let (s, b) = register_cpf(&app, &db, "bob", Some("52998224725")).await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::CONFLICT, Some("cpf_taken"))
    );

    // O número não fica no banco.
    let raw: Vec<u8> = sqlx::query_scalar("SELECT cpf_hmac FROM users WHERE username = 'alice'")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(raw.len(), 32);
    assert!(!String::from_utf8_lossy(&raw).contains("52998224725"));
}

#[sqlx::test]
async fn old_accounts_add_cpf_and_admin_releases(db: PgPool) {
    // Contas criadas antes da exigência.
    let old = test_app(db.clone());
    let alice = signup(&old, &db, "alice").await;
    let admin = signup(&old, &db, "admin").await;
    sync_admins(&db, &["admin".to_owned()]).await.unwrap();

    let app = app_with_cpf(&db);
    let (_, me) = call(&app, Method::GET, "/v1/me", Some(&alice), None).await;
    assert_eq!(me["needs_cpf"], true);
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/cpf",
        Some(&alice),
        Some(json!({"cpf": "529.982.247-25"})),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, me) = call(&app, Method::GET, "/v1/me", Some(&alice), None).await;
    assert_eq!(me["needs_cpf"], false);
    let (s, b) = call(
        &app,
        Method::PUT,
        "/v1/me/cpf",
        Some(&alice),
        Some(json!({"cpf": "111.444.777-35"})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::CONFLICT, Some("cpf_already_set"))
    );

    // Outra conta tentando o mesmo CPF; admin libera o da alice.
    let (s, b) = call(
        &app,
        Method::PUT,
        "/v1/me/cpf",
        Some(&admin),
        Some(json!({"cpf": "52998224725"})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::CONFLICT, Some("cpf_taken"))
    );
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/admin/users/alice/release-cpf",
        Some(&admin),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/cpf",
        Some(&admin),
        Some(json!({"cpf": "52998224725"})),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);

    // Sem a chave no servidor, ninguém precisa de CPF.
    let (_, me) = call(&old, Method::GET, "/v1/me", Some(&alice), None).await;
    assert_eq!(me["needs_cpf"], false);
}

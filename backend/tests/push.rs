//! Beta lote 14: notificações push (registro de aparelho e eventos).

mod common;

use common::*;
use humannet_api::push::{Fcm, Kind, Push};
use uuid::Uuid;

fn app_with_push(db: PgPool) -> (Router, Push) {
    let state = AppState::new(db, Policy::default());
    let push = state.push.clone();
    (app(state), push)
}

async fn id_of(app: &Router, token: &str) -> Uuid {
    let (_, me) = call(app, Method::GET, "/v1/me", Some(token), None).await;
    me["id"].as_str().unwrap().parse().unwrap()
}

async fn friend(app: &Router, token: &str, other: &str) -> StatusCode {
    call(
        app,
        Method::PUT,
        &format!("/v1/users/{other}/friend"),
        Some(token),
        None,
    )
    .await
    .0
}

#[sqlx::test]
async fn device_registration(db: PgPool) {
    let (app, _) = app_with_push(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let tok = "fcm-Token_123:abc";

    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/devices",
        None,
        Some(json!({"token": tok})),
    )
    .await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/devices",
        Some(&alice),
        Some(json!({"token": "tem espaço"})),
    )
    .await;
    assert!(s.is_client_error(), "token inválido: {s}");

    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/devices",
        Some(&alice),
        Some(json!({"token": tok})),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    // Idempotente.
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/devices",
        Some(&alice),
        Some(json!({"token": tok})),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let alice_id = id_of(&app, &alice).await;
    let owner: Uuid = sqlx::query_scalar("SELECT user_id FROM push_devices WHERE token = $1")
        .bind(tok)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(owner, alice_id);

    // Outra conta no mesmo aparelho: o token muda de dono.
    call(
        &app,
        Method::PUT,
        "/v1/me/devices",
        Some(&bob),
        Some(json!({"token": tok})),
    )
    .await;
    let owner: Uuid = sqlx::query_scalar("SELECT user_id FROM push_devices WHERE token = $1")
        .bind(tok)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(owner, id_of(&app, &bob).await);

    // Alice não remove o aparelho do bob.
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/me/devices/{tok}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM push_devices")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 1);
    call(
        &app,
        Method::DELETE,
        &format!("/v1/me/devices/{tok}"),
        Some(&bob),
        None,
    )
    .await;
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM push_devices")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 0);

    // No máximo 10 aparelhos por conta.
    for i in 0..12 {
        call(
            &app,
            Method::PUT,
            "/v1/me/devices",
            Some(&alice),
            Some(json!({"token": format!("tok-{i}")})),
        )
        .await;
    }
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM push_devices WHERE user_id = $1")
        .bind(alice_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 10);
}

#[sqlx::test]
async fn events_are_pushed(db: PgPool) {
    let (app, push) = app_with_push(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let a = id_of(&app, &alice).await;
    let b = id_of(&app, &bob).await;

    friend(&app, &alice, "bob").await;
    friend(&app, &bob, "alice").await;
    let sent = push.sent();
    assert_eq!(sent.len(), 2, "{sent:?}");
    assert_eq!(
        (sent[0].actor, &sent[0].to, &sent[0].kind),
        (a, &vec![b], &Kind::FriendRequest)
    );
    assert_eq!(
        (sent[1].actor, &sent[1].to, &sent[1].kind),
        (b, &vec![a], &Kind::FriendAccepted)
    );
    // Repetir o pedido (já amigos) não avisa de novo.
    friend(&app, &alice, "bob").await;
    assert_eq!(push.sent().len(), 2);

    // Mensagem direta.
    let (_, c) = call(
        &app,
        Method::POST,
        "/v1/conversations/direct",
        Some(&alice),
        Some(json!({"username": "bob"})),
    )
    .await;
    let conv: Uuid = c["id"].as_str().unwrap().parse().unwrap();
    call(
        &app,
        Method::POST,
        &format!("/v1/conversations/{conv}/messages"),
        Some(&alice),
        Some(json!({"body": "segredo"})),
    )
    .await;
    let last = push.sent().pop().unwrap();
    assert_eq!(last.to, vec![b]);
    assert_eq!(
        last.kind,
        Kind::Message {
            conversation: conv,
            group: None
        }
    );

    // Recado e depoimento.
    call(
        &app,
        Method::POST,
        "/v1/users/bob/scraps",
        Some(&alice),
        Some(json!({"body": "oi!"})),
    )
    .await;
    assert_eq!(push.sent().pop().unwrap().kind, Kind::Scrap);
    let (s, t) = call(
        &app,
        Method::PUT,
        "/v1/users/bob/testimonial",
        Some(&alice),
        Some(json!({"body": "Pessoa incrível, amigo de verdade."})),
    )
    .await;
    assert!(s.is_success(), "{t}");
    assert_eq!(push.sent().pop().unwrap().kind, Kind::Testimonial);

    // Comentário: avisa o autor do post, nunca quem comenta no próprio post.
    let (s, p) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&bob),
        Some(json!({"body": "Post do bob"})),
    )
    .await;
    assert!(s.is_success(), "{p}");
    let post: Uuid = p["id"].as_str().unwrap().parse().unwrap();
    let before = push.sent().len();
    call(
        &app,
        Method::POST,
        &format!("/v1/posts/{post}/comments"),
        Some(&bob),
        Some(json!({"body": "eu mesmo"})),
    )
    .await;
    assert_eq!(push.sent().len(), before, "comentário no próprio post");
    call(
        &app,
        Method::POST,
        &format!("/v1/posts/{post}/comments"),
        Some(&alice),
        Some(json!({"body": "legal"})),
    )
    .await;
    let last = push.sent().pop().unwrap();
    assert_eq!(
        (last.actor, last.to, last.kind),
        (a, vec![b], Kind::Comment { post })
    );
}

#[test]
fn bad_service_account_is_rejected() {
    assert!(Fcm::from_service_account("{}").is_err());
    assert!(Fcm::from_service_account("não é json").is_err());
    let fake = json!({
        "project_id": "x",
        "client_email": "x@x.iam.gserviceaccount.com",
        "private_key": "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n",
    });
    assert!(Fcm::from_service_account(&fake.to_string()).is_err());
}

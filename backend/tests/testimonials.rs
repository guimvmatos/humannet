//! Beta lote 5: depoimentos.

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

async fn write(app: &Router, token: &str, about: &str, body: &str) -> (StatusCode, Value) {
    call(
        app,
        Method::PUT,
        &format!("/v1/users/{about}/testimonial"),
        Some(token),
        Some(json!({ "body": body })),
    )
    .await
}

async fn list(app: &Router, token: &str, of: &str) -> Vec<Value> {
    let (s, b) = call(
        app,
        Method::GET,
        &format!("/v1/users/{of}/testimonials"),
        Some(token),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{b}");
    b["items"].as_array().unwrap().clone()
}

#[sqlx::test]
async fn write_approve_and_show(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;

    // Só amigos escrevem.
    let (s, _) = write(&app, &bob, "alice", "Pessoa incrível").await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    befriend(&app, &alice, "bob", &bob, "alice").await;
    befriend(&app, &alice, "carol", &carol, "alice").await;
    let (s, b) = write(&app, &alice, "alice", "Eu sou ótima").await;
    assert_eq!(
        (s, b["error"].as_str()),
        (
            StatusCode::UNPROCESSABLE_ENTITY,
            Some("cannot_testify_self")
        )
    );
    let (s, _) = write(&app, &bob, "alice", "   ").await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    let (s, t) = write(&app, &bob, "alice", "Pessoa incrível").await;
    assert_eq!(s, StatusCode::OK, "{t}");
    assert_eq!(t["status"], "pending");
    let id = t["id"].as_str().unwrap().to_owned();

    // Pendente: autor vê o próprio; amigos não; dona vê na fila.
    assert_eq!(list(&app, &bob, "alice").await.len(), 1);
    assert_eq!(list(&app, &carol, "alice").await.len(), 0);
    let (_, p) = call(&app, Method::GET, "/v1/users/alice", Some(&alice), None).await;
    assert_eq!(p["stats"]["pending_testimonials"], 1);
    let (_, pend) = call(
        &app,
        Method::GET,
        "/v1/me/testimonials/pending",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(pend["items"][0]["author"]["username"], "bob");

    // Só a dona aprova.
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/testimonials/{id}/approve"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/testimonials/{id}/approve"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let items = list(&app, &carol, "alice").await;
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["body"], "Pessoa incrível");
    assert_eq!(items[0]["can_delete"], false);

    // Quem não é amigo da dona não vê.
    let dave = signup(&app, &db, "dave").await;
    assert_eq!(list(&app, &dave, "alice").await.len(), 0);

    // Reescrever volta para pendente.
    write(&app, &bob, "alice", "Pessoa incrível e generosa").await;
    assert_eq!(list(&app, &carol, "alice").await.len(), 0);
    let (_, pend) = call(
        &app,
        Method::GET,
        "/v1/me/testimonials/pending",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(pend["items"].as_array().unwrap().len(), 1);

    // A dona remove.
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/testimonials/{id}"),
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/testimonials/{id}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    assert_eq!(list(&app, &bob, "alice").await.len(), 0);
}

#[sqlx::test]
async fn block_removes_testimonials(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    befriend(&app, &alice, "bob", &bob, "alice").await;
    let (_, t) = write(&app, &bob, "alice", "Amiga demais").await;
    let id = t["id"].as_str().unwrap();
    call(
        &app,
        Method::POST,
        &format!("/v1/testimonials/{id}/approve"),
        Some(&alice),
        None,
    )
    .await;
    call(&app, Method::PUT, "/v1/users/bob/block", Some(&alice), None).await;
    call(
        &app,
        Method::DELETE,
        "/v1/users/bob/block",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(list(&app, &alice, "alice").await.len(), 0);
}

#[sqlx::test]
async fn report_testimonial(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    befriend(&app, &alice, "bob", &bob, "alice").await;
    let (_, t) = write(&app, &bob, "alice", "texto estranho").await;
    let id = t["id"].as_str().unwrap();
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&alice),
        Some(json!({"kind": "testimonial", "testimonial_id": id, "reason": "harassment"})),
    )
    .await;
    assert_eq!(s, StatusCode::ACCEPTED);
}

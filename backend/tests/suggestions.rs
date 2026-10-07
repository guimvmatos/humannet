//! Beta lote 8: sugestão de amigos.

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

async fn suggestions(app: &Router, token: &str) -> Vec<Value> {
    let (s, b) = call(app, Method::GET, "/v1/me/suggestions", Some(token), None).await;
    assert_eq!(s, StatusCode::OK, "{b}");
    b["items"].as_array().unwrap().clone()
}

#[sqlx::test]
async fn mutual_friends_and_places(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    let dave = signup(&app, &db, "dave").await;
    let erin = signup(&app, &db, "erin").await;
    assert!(suggestions(&app, &alice).await.is_empty());

    // alice-bob, bob-carol, bob-dave, carol-dave: carol e dave têm bob em comum com alice.
    befriend(&app, &alice, "bob", &bob, "alice").await;
    befriend(&app, &bob, "carol", &carol, "bob").await;
    befriend(&app, &bob, "dave", &dave, "bob").await;

    // erin e alice: mesma escola e cidade natal (sem diferenciar maiúsculas).
    let (s, _) = call(
        &app,
        Method::PATCH,
        "/v1/me/profile",
        Some(&alice),
        Some(json!({"hometown": "Recife", "school": "UFPE", "city": "São Paulo"})),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    call(
        &app,
        Method::PATCH,
        "/v1/me/profile",
        Some(&erin),
        Some(json!({"hometown": "recife", "school": "  UFPE "})),
    )
    .await;
    let (_, p) = call(&app, Method::GET, "/v1/users/erin", Some(&alice), None).await;
    assert_eq!(p["school"], "UFPE");

    let s = suggestions(&app, &alice).await;
    let names: Vec<&str> = s
        .iter()
        .map(|x| x["user"]["username"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["erin", "carol", "dave"]);
    assert_eq!(s[0]["reasons"][0], "Também estudou em UFPE");
    assert_eq!(s[0]["reasons"][1], "Também é de recife");
    assert_eq!(s[1]["reasons"][0], "1 amigo em comum");
    assert_eq!(s[1]["mutual_friends"], 1);

    // Pedido pendente tira da lista; dispensar também.
    call(
        &app,
        Method::PUT,
        "/v1/users/carol/friend",
        Some(&alice),
        None,
    )
    .await;
    let (st, _) = call(
        &app,
        Method::POST,
        "/v1/me/suggestions/dave/dismiss",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::NO_CONTENT);
    let names: Vec<String> = suggestions(&app, &alice)
        .await
        .iter()
        .map(|x| x["user"]["username"].as_str().unwrap().to_owned())
        .collect();
    assert_eq!(names, ["erin"]);

    // Bloqueio tira da lista.
    call(&app, Method::PUT, "/v1/users/erin/block", Some(&erin), None).await;
    call(
        &app,
        Method::PUT,
        "/v1/users/alice/block",
        Some(&erin),
        None,
    )
    .await;
    assert!(suggestions(&app, &alice).await.is_empty());

    // Campo longo demais.
    let (s, _) = call(
        &app,
        Method::PATCH,
        "/v1/me/profile",
        Some(&alice),
        Some(json!({"city": "x".repeat(81)})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
}

//! Beta lote 19: temas e hashtags dos posts; candidatos do "Para você".

mod common;

use common::*;

#[sqlx::test]
async fn topics_hashtags_and_candidates(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    call(
        &app,
        Method::PUT,
        "/v1/users/bob/friend",
        Some(&alice),
        None,
    )
    .await;
    call(
        &app,
        Method::PUT,
        "/v1/users/alice/friend",
        Some(&bob),
        None,
    )
    .await;

    let (s, t) = call(&app, Method::GET, "/v1/topics", Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(t[0]["id"], "politica");
    assert_eq!(t[0]["sub"][3][0], "eleicoes");

    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&bob),
        Some(json!({"body": "x", "topics": ["politica.esquerda"]})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_topic"))
    );
    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&bob),
        Some(json!({"body": "x", "topics": ["humor", "games", "musica", "arte"]})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("too_many_topics"))
    );

    let (s, p) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&bob),
        Some(json!({"body": "Rua alagada! #Alagamento #Itavuvu", "topics": ["cidade.clima", "cidade.clima"]})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    assert_eq!(p["topics"], json!(["cidade.clima"]));
    assert_eq!(p["hashtags"], json!(["alagamento", "itavuvu"]));
    call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&carol),
        Some(json!({"body": "não sou amiga"})),
    )
    .await;

    // Candidatos: mesma fonte do cronológico (sem a carol), com temas.
    let (s, c) = call(
        &app,
        Method::GET,
        "/v1/feed/candidates?days=7",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{c}");
    let items = c["items"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["topics"][0], "cidade.clima");
    assert!(c["next_cursor"].is_null());
    let (_, f) = call(&app, Method::GET, "/v1/feed", Some(&alice), None).await;
    assert_eq!(f["items"][0]["hashtags"][0], "alagamento");
}

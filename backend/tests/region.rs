//! Feed regional (C1/C2) com posts globais (ADR-0008): todo post pessoal
//! com posição entra, guardado com desvio de até ~1,5 km.

mod common;

use common::*;

// Centro de Sorocaba e pontos a ~2 km e ~30 km.
const HERE: (f64, f64) = (-23.5015, -47.4526);
const NEAR: (f64, f64) = (-23.5195, -47.4526);
const FAR: (f64, f64) = (-23.2300, -47.4526);

async fn post_region(app: &Router, token: &str, body: &str, at: (f64, f64)) -> (StatusCode, Value) {
    call(
        app,
        Method::POST,
        "/v1/posts",
        Some(token),
        Some(json!({"body": body, "lat": at.0, "lng": at.1,
                    "topics": ["cidade.clima"]})),
    )
    .await
}

fn feed_url(at: (f64, f64), km: f64) -> String {
    format!("/v1/feed/region?lat={}&lng={}&radius_km={km}", at.0, at.1)
}

fn bodies(v: &Value) -> Vec<String> {
    v["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["body"].as_str().unwrap().to_owned())
        .collect()
}

#[sqlx::test]
async fn region_posts_and_feed(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;

    let (s, p) = post_region(&app, &bob, "Rua XV alagada", HERE).await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    assert!(
        p.get("lat").is_none() && p.get("cell_lat").is_none(),
        "posição não sai no post"
    );
    post_region(&app, &carol, "Trânsito parado na Itavuvu", NEAR).await;
    post_region(&app, &carol, "Chuva em Itu", FAR).await;
    // Sem posição (aparelho negou): post vale, mas não entra no regional.
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&bob),
        Some(json!({"body": "sem posição"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);

    // Guardado com desvio (até 1,5 km) e arredondado para a célula de ~500 m.
    let cell: (f64, f64) =
        sqlx::query_as("SELECT cell_lat, cell_lng FROM posts WHERE body = 'Rua XV alagada'")
            .fetch_one(&db)
            .await
            .unwrap();
    let km = |a: (f64, f64), b: (f64, f64)| {
        let dy = (a.0 - b.0) * 111.0;
        let dx = (a.1 - b.1) * 111.0 * a.0.to_radians().cos();
        (dx * dx + dy * dy).sqrt()
    };
    assert!(km(cell, HERE) <= 1.5 + 0.4, "desvio limitado: {cell:?}");
    let snapped = |v: f64| ((v / 0.005).round() * 0.005 - v).abs() < 1e-6;
    assert!(snapped(cell.0) && snapped(cell.1), "na grade: {cell:?}");
    let (s, _) = call(&app, Method::GET, &feed_url(HERE, 1.0), Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK, "raio mínimo 1 km vale");

    let (s, f) = call(&app, Method::GET, &feed_url(HERE, 10.0), Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK, "{f}");
    assert_eq!(
        bodies(&f),
        vec!["Trânsito parado na Itavuvu", "Rua XV alagada"]
    );
    let (_, f) = call(&app, Method::GET, &feed_url(HERE, 50.0), Some(&alice), None).await;
    assert_eq!(bodies(&f).len(), 3);
    assert!(f["items"][0].get("distance").is_none());

    let (s, _) = call(&app, Method::GET, &feed_url(HERE, 0.5), Some(&alice), None).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "raio mínimo 1 km");
    let (s, _) = call(&app, Method::GET, &feed_url(HERE, 80.0), Some(&alice), None).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "raio máximo 50 km");

    // Post é global: qualquer pessoa abre e comenta (não precisa ser amigo).
    let id = f["items"][2]["id"].as_str().unwrap().to_owned();
    let (s, _) = call(
        &app,
        Method::GET,
        &format!("/v1/posts/{id}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/posts/{id}/comments"),
        Some(&alice),
        Some(json!({"body": "Cuidado aí!"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);

    // Bloqueio esconde nos dois sentidos.
    call(
        &app,
        Method::PUT,
        "/v1/users/carol/block",
        Some(&alice),
        None,
    )
    .await;
    let (_, f) = call(&app, Method::GET, &feed_url(HERE, 10.0), Some(&alice), None).await;
    assert_eq!(bodies(&f), vec!["Rua XV alagada"]);

    // C2: candidatos para ordenar no aparelho.
    let (s, c) = call(
        &app,
        Method::GET,
        &format!(
            "/v1/feed/region/candidates?lat={}&lng={}&radius_km=50&days=7",
            HERE.0, HERE.1
        ),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{c}");
    assert_eq!(c["items"].as_array().unwrap().len(), 3);
    assert_eq!(c["items"][0]["topics"][0], "cidade.clima");
}

#[sqlx::test]
async fn for_you_candidates_include_strangers_with_topics(db: PgPool) {
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

    for (token, body, topics) in [
        (&bob, "Amigo sem tema", json!([])),
        (&carol, "Golaço #brasileirao", json!(["esportes.futebol"])),
        (&carol, "Estranha sem tema", json!([])),
    ] {
        let (s, _) = call(
            &app,
            Method::POST,
            "/v1/posts",
            Some(token),
            Some(json!({"body": body, "topics": topics})),
        )
        .await;
        assert_eq!(s, StatusCode::CREATED);
    }
    let (s, c) = call(&app, Method::GET, "/v1/feed/candidates", Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK, "{c}");
    let got: Vec<(String, bool)> = c["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| {
            (
                p["body"].as_str().unwrap().to_owned(),
                p["in_network"].as_bool().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        got,
        vec![
            ("Amigo sem tema".to_owned(), true),
            ("Golaço #brasileirao".to_owned(), false),
        ],
        "estranho só entra com tema/hashtag"
    );

    // Cronológico continua só da rede.
    let (_, f) = call(&app, Method::GET, "/v1/feed", Some(&alice), None).await;
    assert_eq!(bodies(&f), vec!["Amigo sem tema"]);
    assert!(f["items"][0].get("in_network").is_none());

    // Bloqueio tira o estranho dos candidatos.
    call(
        &app,
        Method::PUT,
        "/v1/users/carol/block",
        Some(&alice),
        None,
    )
    .await;
    let (_, c) = call(&app, Method::GET, "/v1/feed/candidates", Some(&alice), None).await;
    assert_eq!(bodies(&c), vec!["Amigo sem tema"]);
}

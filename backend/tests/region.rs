//! Beta lote 20: posts para a região e feed regional (C1/C2).

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
        Some(
            json!({"body": body, "audience": "region", "lat": at.0, "lng": at.1,
                    "topics": ["cidade.clima"]}),
        ),
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

    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&bob),
        Some(json!({"body": "x", "audience": "region"})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_location"))
    );

    let (s, p) = post_region(&app, &bob, "Rua XV alagada", HERE).await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    assert_eq!(p["audience"], "region");
    assert!(
        p.get("lat").is_none() && p.get("cell_lat").is_none(),
        "posição não sai no post"
    );
    post_region(&app, &carol, "Trânsito parado na Itavuvu", NEAR).await;
    post_region(&app, &carol, "Chuva em Itu", FAR).await;
    // Post só para amigos não entra no regional.
    call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&bob),
        Some(json!({"body": "só amigos"})),
    )
    .await;

    // Guardado arredondado para a célula de ~500 m.
    let cell: (f64, f64) =
        sqlx::query_as("SELECT cell_lat, cell_lng FROM posts WHERE body = 'Rua XV alagada'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(cell, (-23.5, -47.455));

    let (s, f) = call(&app, Method::GET, &feed_url(HERE, 1.0), Some(&alice), None).await;
    assert_eq!(s, StatusCode::OK, "{f}");
    assert_eq!(bodies(&f), vec!["Rua XV alagada"]);
    let (_, f) = call(&app, Method::GET, &feed_url(HERE, 5.0), Some(&alice), None).await;
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

    // Post regional: qualquer pessoa abre e comenta (não precisa ser amigo).
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
    let (_, f) = call(&app, Method::GET, &feed_url(HERE, 5.0), Some(&alice), None).await;
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

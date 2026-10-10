//! Beta lote 18: "Minha história" e sugestões de reencontro.

mod common;

use common::*;

const SOROCABA: i32 = 3552205;

async fn org(app: &Router, token: &str, kind: &str, name: &str) -> String {
    let (s, o) = call(
        app,
        Method::POST,
        "/v1/orgs",
        Some(token),
        Some(json!({"kind": kind, "name": name, "municipality_code": SOROCABA})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{o}");
    o["id"].as_str().unwrap().to_owned()
}

async fn add(app: &Router, token: &str, body: Value) -> (StatusCode, Value) {
    call(
        app,
        Method::POST,
        "/v1/me/timeline",
        Some(token),
        Some(body),
    )
    .await
}

#[sqlx::test]
async fn catalogs_dedupe_and_search(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;

    let (_, m) = call(
        &app,
        Method::GET,
        "/v1/geo/municipalities?q=soroc",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(m["items"][0]["name"], "Sorocaba");
    assert_eq!(m["items"][0]["uf"], "SP");
    assert_eq!(m["items"][0]["code"], SOROCABA);
    let (_, m) = call(
        &app,
        Method::GET,
        "/v1/geo/municipalities?q=sao%20jose%20dos%20c",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(m["items"][0]["name"], "São José dos Campos");

    // Mesmo nome normalizado na mesma cidade = mesma instituição.
    let a = org(&app, &alice, "escola", "E.E. Prof. Júlio Bierrenbach").await;
    let b = org(
        &app,
        &alice,
        "escola",
        "Escola Estadual Prof Julio Bierrenbach",
    )
    .await;
    assert_eq!(a, b);
    let (_, l) = call(
        &app,
        Method::GET,
        "/v1/orgs?kind=escola&q=julio",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(l["items"].as_array().unwrap().len(), 1);
    assert_eq!(l["items"][0]["municipality"]["name"], "Sorocaba");

    let (_, c) = call(
        &app,
        Method::GET,
        "/v1/courses?q=computa",
        Some(&alice),
        None,
    )
    .await;
    let names: Vec<&str> = c["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|x| x["name"].as_str().unwrap())
        .collect();
    assert!(names.contains(&"Ciência da Computação"), "{names:?}");
    let (_, c1) = call(
        &app,
        Method::POST,
        "/v1/courses",
        Some(&alice),
        Some(json!({"name": "Bioinformática"})),
    )
    .await;
    let (_, c2) = call(
        &app,
        Method::POST,
        "/v1/courses",
        Some(&alice),
        Some(json!({"name": "bioinformatica"})),
    )
    .await;
    assert_eq!(c1["id"], c2["id"]);
}

#[sqlx::test]
async fn timeline_privacy_and_reunions(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    let dave = signup(&app, &db, "dave").await;

    let school = org(&app, &alice, "escola", "E.E. Dom Pedro").await;
    let ufscar = org(&app, &alice, "faculdade", "UFSCar Sorocaba").await;
    let (_, cc) = call(
        &app,
        Method::GET,
        "/v1/courses?q=ciencia%20da%20comp",
        Some(&alice),
        None,
    )
    .await;
    let cc = cc["items"][0]["id"].as_i64().unwrap();

    // Validações.
    let (s, b) = add(&app, &alice, json!({"kind": "escola", "org_id": ufscar})).await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_org"))
    );
    let (_, b) = add(
        &app,
        &alice,
        json!({"kind": "morou", "municipality_code": 1}),
    )
    .await;
    assert_eq!(b["error"], "invalid_municipality");
    let (_, b) = add(
        &app,
        &alice,
        json!({"kind": "faculdade", "org_id": ufscar, "start_year": 2020, "end_year": 2010}),
    )
    .await;
    assert_eq!(b["error"], "invalid_year");

    // Alice: escola 2005–2010, Computação na UFSCar 2011–2015, nasceu em 1993.
    let (s, e) = add(&app, &alice, json!({"kind": "escola", "org_id": school, "level": "medio", "start_year": 2005, "end_year": 2010})).await;
    assert_eq!(s, StatusCode::CREATED, "{e}");
    assert_eq!(e["visibility"], "suggestions", "escola: oculta por padrão");
    add(&app, &alice, json!({"kind": "faculdade", "org_id": ufscar, "course_id": cc, "level": "graduacao", "start_year": 2011, "end_year": 2015})).await;
    let (_, e) = add(
        &app,
        &alice,
        json!({"kind": "nasceu", "municipality_code": SOROCABA, "start_year": 1993}),
    )
    .await;
    assert_eq!(e["end_year"], Value::Null);
    let (s, _) = add(
        &app,
        &alice,
        json!({"kind": "nasceu", "municipality_code": SOROCABA}),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT, "só um 'nasci em'");

    // Bob: mesma escola, mesma época (com folga de 2 anos).
    add(
        &app,
        &bob,
        json!({"kind": "escola", "org_id": school, "start_year": 2011, "end_year": 2013}),
    )
    .await;
    // Carol: mesmo curso e faculdade, mesma época.
    add(&app, &carol, json!({"kind": "faculdade", "org_id": ufscar, "course_id": cc, "start_year": 2013, "end_year": 2017})).await;
    // Dave: mesma escola, outra época, e não quer ser encontrado pela faculdade.
    add(
        &app,
        &dave,
        json!({"kind": "escola", "org_id": school, "start_year": 1980, "end_year": 1985}),
    )
    .await;
    add(
        &app,
        &dave,
        json!({"kind": "faculdade", "org_id": ufscar, "start_year": 2012, "discoverable": false}),
    )
    .await;

    let (_, s) = call(&app, Method::GET, "/v1/me/suggestions", Some(&alice), None).await;
    let items = s["items"].as_array().unwrap();
    let names: Vec<&str> = items
        .iter()
        .map(|i| i["user"]["username"].as_str().unwrap())
        .collect();
    assert_eq!(
        names,
        vec!["carol", "bob"],
        "carol (curso) antes de bob; dave fora"
    );
    assert_eq!(
        items[0]["reasons"][0],
        "Ciência da Computação na UFSCar Sorocaba, mesma época"
    );
    assert_eq!(
        items[1]["reasons"][0],
        "Estudou na E.E. Dom Pedro na mesma época"
    );

    // Visibilidade: amigos veem só itens "amigos"; outros, nada.
    let (s, _) = call(
        &app,
        Method::GET,
        "/v1/users/alice/timeline",
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    call(
        &app,
        Method::PUT,
        "/v1/users/alice/friend",
        Some(&bob),
        None,
    )
    .await;
    call(
        &app,
        Method::PUT,
        "/v1/users/bob/friend",
        Some(&alice),
        None,
    )
    .await;
    let (_, t) = call(
        &app,
        Method::GET,
        "/v1/users/alice/timeline",
        Some(&bob),
        None,
    )
    .await;
    let kinds: Vec<&str> = t["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["kind"].as_str().unwrap())
        .collect();
    assert_eq!(
        kinds,
        vec!["faculdade"],
        "escola e nascimento ficam só para sugestões"
    );
    assert!(
        t["items"][0]["visibility"].is_null(),
        "configuração só para o dono"
    );
    let (_, mine) = call(&app, Method::GET, "/v1/me/timeline", Some(&alice), None).await;
    assert_eq!(mine["items"].as_array().unwrap().len(), 3);

    // Editar e apagar.
    let id = mine["items"][0]["id"].as_str().unwrap().to_owned();
    let (s, e) = call(
        &app,
        Method::PUT,
        &format!("/v1/me/timeline/{id}"),
        Some(&alice),
        Some(json!({"kind": "nasceu", "municipality_code": SOROCABA, "start_year": 1994, "visibility": "private"})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{e}");
    assert_eq!(e["visibility"], "private");
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/me/timeline/{id}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, mine) = call(&app, Method::GET, "/v1/me/timeline", Some(&alice), None).await;
    assert_eq!(
        mine["items"].as_array().unwrap().len(),
        3,
        "bob não apaga item da alice"
    );
    call(
        &app,
        Method::DELETE,
        &format!("/v1/me/timeline/{id}"),
        Some(&alice),
        None,
    )
    .await;
    let (_, mine) = call(&app, Method::GET, "/v1/me/timeline", Some(&alice), None).await;
    assert_eq!(mine["items"].as_array().unwrap().len(), 2);
}

//! Beta lote 16: coordenadas das páginas e mapa de eventos.

mod common;

use common::*;

fn in_days(d: i64) -> String {
    (time::OffsetDateTime::now_utc() + time::Duration::days(d))
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap()
}

const AREA: &str = "south=-24&west=-48&north=-23&east=-47";

#[sqlx::test]
async fn pin_and_map(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;

    let (s, p) = call(
        &app,
        Method::POST,
        "/v1/pages",
        Some(&alice),
        Some(json!({
            "name": "Bar do Zé", "category": "bar", "cnpj": "11.222.333/0001-81",
            "address": "Rua XV de Novembro, 10 - Centro", "city": "Sorocaba - SP"
        })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    // Teste: o geocodificador devolve o centro de Sorocaba.
    assert_eq!(p["lat"], -23.5015);
    assert_eq!(p["pin_manual"], false);

    call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/events",
        Some(&alice),
        Some(json!({"title": "Samba de sexta", "starts_at": in_days(2)})),
    )
    .await;
    call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/events",
        Some(&alice),
        Some(json!({"title": "Festa do mês que vem", "starts_at": in_days(30)})),
    )
    .await;

    // Qualquer pessoa vê o mapa (eventos são públicos).
    let (s, m) = call(
        &app,
        Method::GET,
        &format!("/v1/events/map?{AREA}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{m}");
    let items = m["items"].as_array().unwrap();
    assert_eq!(items.len(), 1, "padrão: próximos 14 dias");
    assert_eq!(items[0]["title"], "Samba de sexta");
    assert_eq!(items[0]["page_slug"], "bar-do-ze");
    let (_, m) = call(
        &app,
        Method::GET,
        &format!("/v1/events/map?{AREA}&days=60"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(m["items"].as_array().unwrap().len(), 2);
    let (_, m) = call(
        &app,
        Method::GET,
        &format!("/v1/events/map?{AREA}&days=1"),
        Some(&bob),
        None,
    )
    .await;
    assert!(m["items"].as_array().unwrap().is_empty());
    let (_, m) = call(
        &app,
        Method::GET,
        "/v1/events/map?south=-10&west=-40&north=-9&east=-39",
        Some(&bob),
        None,
    )
    .await;
    assert!(m["items"].as_array().unwrap().is_empty(), "fora da área");
    let (s, _) = call(
        &app,
        Method::GET,
        "/v1/events/map?south=-34&west=-74&north=5&east=-34",
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "área grande demais");
    let (s, _) = call(
        &app,
        Method::GET,
        &format!("/v1/events/map?{AREA}"),
        None,
        None,
    )
    .await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);

    // Ajuste manual do ponto: só quem administra; endereço novo não apaga.
    let (s, _) = call(
        &app,
        Method::PATCH,
        "/v1/pages/bar-do-ze",
        Some(&bob),
        Some(json!({"lat": -23.6, "lng": -47.5})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, b) = call(
        &app,
        Method::PATCH,
        "/v1/pages/bar-do-ze",
        Some(&alice),
        Some(json!({"lat": -23.6})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_location"))
    );
    let (_, p) = call(
        &app,
        Method::PATCH,
        "/v1/pages/bar-do-ze",
        Some(&alice),
        Some(json!({"lat": -23.6, "lng": -47.5})),
    )
    .await;
    assert_eq!(
        (p["lat"].as_f64(), p["pin_manual"].as_bool()),
        (Some(-23.6), Some(true))
    );
    let (_, p) = call(
        &app,
        Method::PATCH,
        "/v1/pages/bar-do-ze",
        Some(&alice),
        Some(json!({"address": "Av. Itavuvu, 500"})),
    )
    .await;
    assert_eq!(p["lat"], -23.6, "ponto manual fica");
    let (_, p) = call(
        &app,
        Method::PATCH,
        "/v1/pages/bar-do-ze",
        Some(&alice),
        Some(json!({"reset_pin": true})),
    )
    .await;
    assert_eq!(
        (p["lat"].as_f64(), p["pin_manual"].as_bool()),
        (Some(-23.5015), Some(false))
    );
}

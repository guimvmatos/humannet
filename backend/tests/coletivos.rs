//! Coletivos estudantis: pedido com e-mail institucional, aprovação, eventos
//! com revisão, limite semanal e endereço só para quem vai.

mod common;

use common::*;
use humannet_api::routes::admin::sync_admins;

fn soon(days: i64) -> String {
    (time::OffsetDateTime::now_utc() + time::Duration::days(days))
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap()
}

#[sqlx::test]
async fn organizer_request_flow(db: PgPool) {
    let state = AppState::new(db.clone(), Policy::default());
    let mailer = state.mailer.clone();
    let app = app(state);
    let alice = signup(&app, &db, "alice").await;
    let admin = signup(&app, &db, "boss").await;
    sync_admins(&db, &["boss".to_owned()]).await.unwrap();
    let bob = signup(&app, &db, "bob").await;

    // E-mail precisa ser da instituição.
    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/organizer-requests",
        Some(&alice),
        Some(json!({"name": "República Toca", "category": "republica",
                    "institution_email": "alice@gmail.com"})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (
            StatusCode::UNPROCESSABLE_ENTITY,
            Some("invalid_institution_email")
        )
    );
    let (s, r) = call(
        &app,
        Method::POST,
        "/v1/organizer-requests",
        Some(&alice),
        Some(json!({"name": "República Toca", "category": "republica",
                    "description": "Festas da Toca",
                    "institution_email": "Alice@Estudante.UFSCar.br"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{r}");
    assert_eq!(r["status"], "pending");
    assert_eq!(r["email_check"], "code");
    assert_eq!(r["email_verified"], false);
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/organizer-requests",
        Some(&alice),
        Some(json!({"name": "Outra", "category": "coletivo",
                    "institution_email": "alice@ufscar.br"})),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT, "um pedido aberto por vez");

    // Código por e-mail.
    let sent = mailer.sent();
    assert_eq!(sent[0].0, "alice@estudante.ufscar.br");
    let code: String = sent[0]
        .2
        .chars()
        .filter(char::is_ascii_digit)
        .take(6)
        .collect();
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/organizer-requests/verify",
        Some(&alice),
        Some(json!({"code": "000000"})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, r) = call(
        &app,
        Method::POST,
        "/v1/organizer-requests/verify",
        Some(&alice),
        Some(json!({"code": code})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    assert_eq!(r["email_verified"], true);

    // Só a administração aprova.
    let (s, _) = call(
        &app,
        Method::GET,
        "/v1/admin/organizer-requests",
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (_, list) = call(
        &app,
        Method::GET,
        "/v1/admin/organizer-requests",
        Some(&admin),
        None,
    )
    .await;
    let id = list["items"][0]["id"].as_str().unwrap().to_owned();
    assert_eq!(list["items"][0]["user"]["username"], "alice");
    let (s, r) = call(
        &app,
        Method::POST,
        &format!("/v1/admin/organizer-requests/{id}/approve"),
        Some(&admin),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    let slug = r["page_slug"].as_str().unwrap().to_owned();
    assert_eq!(slug, "republica-toca");
    let (_, page) = call(
        &app,
        Method::GET,
        &format!("/v1/pages/{slug}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(page["kind"], "coletivo");
    assert_eq!(page["cnpj"], "");
    assert_eq!(page["responsible"], "alice");
    let (_, mine) = call(
        &app,
        Method::GET,
        "/v1/organizer-requests/mine",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(mine["status"], "approved");

    // Eventos: os 2 primeiros esperam revisão; o público não vê.
    let ev = |title: &str, hidden: bool| {
        json!({"title": title, "starts_at": soon(2), "location": "Rua das Flores, 10",
               "address_hidden": hidden})
    };
    let (s, e1) = call(
        &app,
        Method::POST,
        &format!("/v1/pages/{slug}/events"),
        Some(&alice),
        Some(ev("Festa 1", true)),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{e1}");
    assert_eq!(e1["status"], "pending_review");
    let e1 = e1["id"].as_str().unwrap().to_owned();
    let (s, _) = call(
        &app,
        Method::GET,
        &format!("/v1/events/{e1}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (_, pend) = call(
        &app,
        Method::GET,
        "/v1/admin/events/pending",
        Some(&admin),
        None,
    )
    .await;
    assert_eq!(pend["items"][0]["responsible"], "alice");
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/admin/events/{e1}/review"),
        Some(&admin),
        Some(json!({"approve": true})),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);

    // Endereço escondido: bob não vê até marcar "vou"; no mapa, só a região.
    let (_, e) = call(
        &app,
        Method::GET,
        &format!("/v1/events/{e1}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(e["location"], "");
    assert_eq!(e["address_hidden"], true);
    assert_eq!(e["responsible"], "alice");
    let (_, e) = call(
        &app,
        Method::GET,
        &format!("/v1/events/{e1}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(e["location"], "Rua das Flores, 10");
    let (_, e) = call(
        &app,
        Method::PUT,
        &format!("/v1/events/{e1}/interest"),
        Some(&bob),
        Some(json!({"status": "going"})),
    )
    .await;
    assert_eq!(e["location"], "Rua das Flores, 10");

    // Limite: 3 por semana.
    for t in ["Festa 2", "Festa 3"] {
        let (s, _) = call(
            &app,
            Method::POST,
            &format!("/v1/pages/{slug}/events"),
            Some(&alice),
            Some(ev(t, false)),
        )
        .await;
        assert_eq!(s, StatusCode::CREATED);
    }
    let (s, b) = call(
        &app,
        Method::POST,
        &format!("/v1/pages/{slug}/events"),
        Some(&alice),
        Some(ev("Festa 4", false)),
    )
    .await;
    assert_eq!(b["error"], "event_week_limit", "{s}");
}

#[sqlx::test]
async fn reject_and_manual_mode(db: PgPool) {
    let state = AppState::new(db.clone(), Policy::default())
        .with_mailer(humannet_api::mail::Mailer::Disabled);
    let app = app(state);
    let alice = signup(&app, &db, "alice").await;
    let admin = signup(&app, &db, "boss").await;
    sync_admins(&db, &["boss".to_owned()]).await.unwrap();

    let (s, r) = call(
        &app,
        Method::POST,
        "/v1/organizer-requests",
        Some(&alice),
        Some(json!({"name": "Atlética X", "category": "atletica",
                    "institution_email": "alice@ufscar.br"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{r}");
    assert_eq!(r["email_check"], "manual");
    let id = r["id"].as_str().unwrap().to_owned();
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/admin/organizer-requests/{id}/reject"),
        Some(&admin),
        Some(json!({"reason": "Não achamos a atlética"})),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, mine) = call(
        &app,
        Method::GET,
        "/v1/organizer-requests/mine",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(mine["status"], "rejected");
    assert_eq!(mine["reason"], "Não achamos a atlética");
    // Recusado: pode pedir de novo.
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/organizer-requests",
        Some(&alice),
        Some(json!({"name": "Atlética X", "category": "atletica",
                    "institution_email": "alice@ufscar.br"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
}

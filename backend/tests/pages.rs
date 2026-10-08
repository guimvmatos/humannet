//! Beta lote 12: páginas de lugares e eventos.

mod common;

use common::*;
use humannet_api::routes::admin::sync_admins;

const CNPJ: &str = "11.222.333/0001-81";

async fn create_page(app: &Router, token: &str, name: &str, cnpj: &str) -> (StatusCode, Value) {
    call(
        app,
        Method::POST,
        "/v1/pages",
        Some(token),
        Some(json!({
            "name": name, "category": "bar", "cnpj": cnpj,
            "address": "Rua Augusta, 100", "city": "São Paulo",
            "description": "Música ao vivo."
        })),
    )
    .await
}

fn in_days(d: i64) -> String {
    (time::OffsetDateTime::now_utc() + time::Duration::days(d))
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap()
}

#[sqlx::test]
async fn page_lifecycle(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;

    let (s, b) = create_page(&app, &alice, "Bar do Zé", "11.222.333/0001-82").await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_cnpj"))
    );
    let (s, p) = create_page(&app, &alice, "Bar do Zé", CNPJ).await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    assert_eq!(p["slug"], "bar-do-ze");
    assert_eq!(p["cnpj"], "11.222.333/0001-81");
    assert_eq!(p["my_role"], "owner");
    assert_eq!(p["verified"], false);
    assert_eq!(p["follower_count"], 0);

    // Mesmo CNPJ não cria outra página.
    let (s, b) = create_page(&app, &bob, "Outro Bar", "11222333000181").await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::CONFLICT, Some("cnpj_taken"))
    );

    // Acompanhar; contagem só para quem administra.
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/pages/bar-do-ze/follow",
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, p) = call(&app, Method::GET, "/v1/pages/bar-do-ze", Some(&bob), None).await;
    assert_eq!(p["following"], true);
    assert_eq!(p["follower_count"], Value::Null);
    let (_, p) = call(&app, Method::GET, "/v1/pages/bar-do-ze", Some(&alice), None).await;
    assert_eq!(p["follower_count"], 1);
    let (_, l) = call(&app, Method::GET, "/v1/pages?mine=true", Some(&bob), None).await;
    assert_eq!(l["items"][0]["slug"], "bar-do-ze");

    // Só quem administra edita; dono adiciona admin.
    let (s, _) = call(
        &app,
        Method::PATCH,
        "/v1/pages/bar-do-ze",
        Some(&bob),
        Some(json!({"name": "X"})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/admins",
        Some(&alice),
        Some(json!({"username": "bob"})),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (s, p) = call(
        &app,
        Method::PATCH,
        "/v1/pages/bar-do-ze",
        Some(&bob),
        Some(json!({"city": "Santos"})),
    )
    .await;
    assert_eq!((s, p["city"].as_str()), (StatusCode::OK, Some("Santos")));

    // Admin da plataforma verifica.
    let admin = signup(&app, &db, "admin").await;
    sync_admins(&db, &["admin".to_owned()]).await.unwrap();
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/admin/pages/bar-do-ze/verify",
        Some(&admin),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, p) = call(&app, Method::GET, "/v1/pages/bar-do-ze", Some(&bob), None).await;
    assert_eq!(p["verified"], true);

    // Dono exclui a conta: bob (admin) herda.
    call(
        &app,
        Method::DELETE,
        "/v1/me",
        Some(&alice),
        Some(json!({"password": PASSWORD})),
    )
    .await;
    let (_, p) = call(&app, Method::GET, "/v1/pages/bar-do-ze", Some(&bob), None).await;
    assert_eq!(p["my_role"], "owner");
}

#[sqlx::test]
async fn events_and_interest(db: PgPool) {
    let app = test_app(db.clone());
    let owner = signup(&app, &db, "owner").await;
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    create_page(&app, &owner, "Bar do Zé", CNPJ).await;
    // alice e bob amigos.
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

    let ev =
        json!({"title": "Samba de sexta", "starts_at": in_days(2), "description": "Roda de samba"});
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/events",
        Some(&alice),
        Some(ev.clone()),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, e) = call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/events",
        Some(&owner),
        Some(ev),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{e}");
    assert_eq!(e["location"], "Rua Augusta, 100");
    let id = e["id"].as_str().unwrap().to_owned();
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/events",
        Some(&owner),
        Some(json!({"title": "Passado", "starts_at": in_days(-3)})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // Interesse: bob vai; alice vê que o amigo bob vai, sem números.
    let (s, e) = call(
        &app,
        Method::PUT,
        &format!("/v1/events/{id}/interest"),
        Some(&bob),
        Some(json!({"status": "going"})),
    )
    .await;
    assert_eq!(
        (s, e["my_interest"].as_str()),
        (StatusCode::OK, Some("going"))
    );
    call(
        &app,
        Method::PUT,
        &format!("/v1/events/{id}/interest"),
        Some(&carol),
        Some(json!({"status": "interested"})),
    )
    .await;
    let (_, e) = call(
        &app,
        Method::GET,
        &format!("/v1/events/{id}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(e["friends"][0]["username"], "bob");
    assert_eq!(e["friends_count"], 1);
    assert_eq!(e["going_count"], Value::Null);
    let (_, e) = call(
        &app,
        Method::GET,
        &format!("/v1/events/{id}"),
        Some(&owner),
        None,
    )
    .await;
    assert_eq!(
        (e["going_count"].as_i64(), e["interested_count"].as_i64()),
        (Some(1), Some(1))
    );

    // Agenda: bob (marcou) vê; alice só depois de acompanhar.
    let (_, a) = call(&app, Method::GET, "/v1/events", Some(&bob), None).await;
    assert_eq!(a["items"].as_array().unwrap().len(), 1);
    let (_, a) = call(&app, Method::GET, "/v1/events", Some(&alice), None).await;
    assert_eq!(a["items"].as_array().unwrap().len(), 0);
    call(
        &app,
        Method::PUT,
        "/v1/pages/bar-do-ze/follow",
        Some(&alice),
        None,
    )
    .await;
    let (_, a) = call(&app, Method::GET, "/v1/events", Some(&alice), None).await;
    assert_eq!(a["items"][0]["title"], "Samba de sexta");

    // Cancelar: não aceita mais interesse.
    let (s, e) = call(
        &app,
        Method::PATCH,
        &format!("/v1/events/{id}"),
        Some(&owner),
        Some(json!({"cancelled": true})),
    )
    .await;
    assert_eq!((s, e["cancelled"].as_bool()), (StatusCode::OK, Some(true)));
    let (s, b) = call(
        &app,
        Method::PUT,
        &format!("/v1/events/{id}/interest"),
        Some(&alice),
        Some(json!({"status": "going"})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("event_cancelled"))
    );

    // Denúncia de evento e de página.
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&alice),
        Some(json!({"kind": "event", "event_id": id, "reason": "spam"})),
    )
    .await;
    assert_eq!(s, StatusCode::ACCEPTED);
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/reports",
        Some(&alice),
        Some(json!({"kind": "page", "slug": "bar-do-ze", "reason": "other"})),
    )
    .await;
    assert_eq!(s, StatusCode::ACCEPTED);

    let (_, l) = call(
        &app,
        Method::GET,
        "/v1/pages/bar-do-ze/events",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(l["items"].as_array().unwrap().len(), 1);
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/events/{id}"),
        Some(&owner),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, l) = call(
        &app,
        Method::GET,
        "/v1/pages/bar-do-ze/events",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(l["items"].as_array().unwrap().len(), 0);
}

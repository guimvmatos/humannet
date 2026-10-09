//! Beta lote 15: páginas 2.0 (logo, capa, CEP, mural, mensagens).

mod common;

use std::io::Cursor;

use common::*;
use http_body_util::BodyExt;
use tower::ServiceExt;

fn png(w: u32, h: u32) -> Vec<u8> {
    let img = image::RgbImage::from_pixel(w, h, image::Rgb([200, 80, 10]));
    let mut out = Vec::new();
    image::DynamicImage::ImageRgb8(img)
        .write_to(&mut Cursor::new(&mut out), image::ImageFormat::Png)
        .unwrap();
    out
}

async fn upload(app: &Router, token: &str, kind: &str, bytes: Vec<u8>) -> Value {
    let req = Request::builder()
        .method(Method::POST)
        .uri(format!("/v1/media?kind={kind}"))
        .header(header::AUTHORIZATION, format!("Bearer {token}"))
        .header(header::CONTENT_TYPE, "image/png")
        .body(Body::from(bytes))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    assert!(res.status().is_success(), "{}", res.status());
    let body = res.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&body).unwrap()
}

async fn new_page(app: &Router, token: &str, cep: &str) -> (StatusCode, Value) {
    call(
        app,
        Method::POST,
        "/v1/pages",
        Some(token),
        Some(json!({
            "name": "Bar do Zé", "category": "bar", "cnpj": "11.222.333/0001-81",
            "address": "Rua XV de Novembro, 10", "city": "Sorocaba", "cep": cep
        })),
    )
    .await
}

async fn follow(app: &Router, token: &str) {
    let (s, _) = call(
        app,
        Method::PUT,
        "/v1/pages/bar-do-ze/follow",
        Some(token),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
}

#[sqlx::test]
async fn cep_logo_cover_and_admins(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;

    let (s, b) = new_page(&app, &alice, "123").await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_cep"))
    );
    let (s, p) = new_page(&app, &alice, "18035-000").await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    assert_eq!(p["cep"], "18035000");
    assert!(p["logo_url"].is_null());

    // Logo (kind=avatar, quadrada) e capa (kind=cover, 3:1).
    let logo = upload(&app, &alice, "avatar", png(300, 200)).await;
    let cover = upload(&app, &alice, "cover", png(1200, 900)).await;
    assert_eq!(
        (cover["width"].as_i64(), cover["height"].as_i64()),
        (Some(1200), Some(400))
    );
    let (s, p) = call(
        &app,
        Method::PUT,
        "/v1/pages/bar-do-ze/logo",
        Some(&alice),
        Some(json!({"media_id": logo["id"]})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{p}");
    assert!(p["logo_url"].is_string());
    let (_, p) = call(
        &app,
        Method::PUT,
        "/v1/pages/bar-do-ze/cover",
        Some(&alice),
        Some(json!({"media_id": cover["id"]})),
    )
    .await;
    assert!(p["cover_url"].is_string());
    // Quem não administra não troca.
    let other = upload(&app, &bob, "avatar", png(100, 100)).await;
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/pages/bar-do-ze/logo",
        Some(&bob),
        Some(json!({"media_id": other["id"]})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    // Lista mostra a logo e as que eu administro primeiro.
    let (_, l) = call(&app, Method::GET, "/v1/pages?mine=true", Some(&alice), None).await;
    assert_eq!(l["items"][0]["my_role"], "owner");
    assert!(l["items"][0]["logo_url"].is_string());
    let (_, p) = call(
        &app,
        Method::DELETE,
        "/v1/pages/bar-do-ze/cover",
        Some(&alice),
        None,
    )
    .await;
    assert!(p["cover_url"].is_null());

    // Quem administra: público, dono primeiro.
    call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/admins",
        Some(&alice),
        Some(json!({"username": "bob"})),
    )
    .await;
    let (s, a) = call(
        &app,
        Method::GET,
        "/v1/pages/bar-do-ze/admins",
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(a["items"][0]["username"], "alice");
    assert_eq!(a["items"][0]["role"], "owner");
    assert_eq!(a["items"][1]["role"], "admin");
}

#[sqlx::test]
async fn wall_and_feed(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    new_page(&app, &alice, "").await;
    // bob é amigo da alice mas não acompanha; carol acompanha.
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
    follow(&app, &carol).await;

    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/posts",
        Some(&carol),
        Some(json!({"body": "invasão"})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, post) = call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/posts",
        Some(&alice),
        Some(json!({"body": "Samba hoje às 20h!"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{post}");
    assert_eq!(post["page"]["slug"], "bar-do-ze");
    assert_eq!(post["author"]["username"], "alice");
    let post_id = post["id"].as_str().unwrap().to_owned();

    // Mural: todos veem.
    let (_, w) = call(
        &app,
        Method::GET,
        "/v1/pages/bar-do-ze/posts",
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(w["items"][0]["body"], "Samba hoje às 20h!");
    // Feed: só quem acompanha.
    let (_, f) = call(&app, Method::GET, "/v1/feed", Some(&carol), None).await;
    assert_eq!(f["items"][0]["id"], post_id.as_str());
    let (_, f) = call(&app, Method::GET, "/v1/feed", Some(&bob), None).await;
    assert!(
        f["items"]
            .as_array()
            .unwrap()
            .iter()
            .all(|p| p["id"] != post_id.as_str())
    );
    // Não aparece no perfil pessoal da alice.
    let (_, mine) = call(&app, Method::GET, "/v1/users/alice/posts", Some(&bob), None).await;
    assert!(mine["items"].as_array().unwrap().is_empty());

    // Qualquer um comenta; quem administra apaga comentário de outro.
    let (s, c) = call(
        &app,
        Method::POST,
        &format!("/v1/posts/{post_id}/comments"),
        Some(&carol),
        Some(json!({"body": "Vou!"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{c}");
    call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/admins",
        Some(&alice),
        Some(json!({"username": "bob"})),
    )
    .await;
    let (_, list) = call(
        &app,
        Method::GET,
        &format!("/v1/posts/{post_id}/comments"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(list["items"][0]["can_delete"], true);
    let cid = c["id"].as_str().unwrap();
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/comments/{cid}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    // E apaga o post da página.
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/posts/{post_id}"),
        Some(&bob),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
}

#[sqlx::test]
async fn messages_to_page(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;
    new_page(&app, &alice, "").await;

    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/conversation",
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(b["error"], "follow_page_first", "{s}");
    let (_, b) = call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/conversation",
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(b["error"], "cannot_message_own_page");

    follow(&app, &carol).await;
    let (s, c) = call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/conversation",
        Some(&carol),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{c}");
    assert_eq!(c["title"], "Bar do Zé");
    assert_eq!(c["page_slug"], "bar-do-ze");
    assert_eq!(c["as_page"], false);
    let conv = c["id"].as_str().unwrap().to_owned();
    let (s, _) = call(
        &app,
        Method::POST,
        &format!("/v1/conversations/{conv}/messages"),
        Some(&carol),
        Some(json!({"body": "Tem mesa para 6?"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);

    // Quem administra vê e responde como a página.
    let (_, l) = call(&app, Method::GET, "/v1/conversations", Some(&alice), None).await;
    assert_eq!(l["items"][0]["title"], "Bar do Zé · @carol");
    assert_eq!(l["items"][0]["as_page"], true);
    assert_eq!(l["items"][0]["unread"], 1);
    let (_, m) = call(
        &app,
        Method::POST,
        &format!("/v1/conversations/{conv}/messages"),
        Some(&alice),
        Some(json!({"body": "Tem sim!"})),
    )
    .await;
    assert_eq!(m["as_page"], true);

    // Novo administrador passa a ver; a resposta de outro admin não conta
    // como "não lida" para ele.
    call(
        &app,
        Method::POST,
        "/v1/pages/bar-do-ze/admins",
        Some(&alice),
        Some(json!({"username": "bob"})),
    )
    .await;
    call(
        &app,
        Method::POST,
        &format!("/v1/conversations/{conv}/messages"),
        Some(&carol),
        Some(json!({"body": "Às 21h, pode ser?"})),
    )
    .await;
    call(
        &app,
        Method::POST,
        &format!("/v1/conversations/{conv}/messages"),
        Some(&alice),
        Some(json!({"body": "Pode!"})),
    )
    .await;
    let (_, l) = call(&app, Method::GET, "/v1/conversations", Some(&bob), None).await;
    assert_eq!(l["items"][0]["id"], conv.as_str());
    assert_eq!(
        l["items"][0]["unread"], 1,
        "só a da carol; a da alice é da página"
    );
    // Removido, deixa de ver.
    call(
        &app,
        Method::DELETE,
        "/v1/pages/bar-do-ze/admins/bob",
        Some(&alice),
        None,
    )
    .await;
    let (_, l) = call(&app, Method::GET, "/v1/conversations", Some(&bob), None).await;
    assert!(l["items"].as_array().unwrap().is_empty());

    // Carol deixa de acompanhar: não envia mais.
    call(
        &app,
        Method::DELETE,
        "/v1/pages/bar-do-ze/follow",
        Some(&carol),
        None,
    )
    .await;
    let (_, b) = call(
        &app,
        Method::POST,
        &format!("/v1/conversations/{conv}/messages"),
        Some(&carol),
        Some(json!({"body": "oi?"})),
    )
    .await;
    assert_eq!(b["error"], "follow_page_first");
}

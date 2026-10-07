//! Beta lote 9: fotos.

mod common;

use std::io::Cursor;

use common::*;
use http_body_util::BodyExt;
use humannet_api::media::MediaStore;
use tower::ServiceExt;

fn png(w: u32, h: u32) -> Vec<u8> {
    let img = image::RgbImage::from_pixel(w, h, image::Rgb([10, 120, 200]));
    let mut out = Vec::new();
    image::DynamicImage::ImageRgb8(img)
        .write_to(&mut Cursor::new(&mut out), image::ImageFormat::Png)
        .unwrap();
    out
}

async fn upload(app: &Router, token: &str, kind: &str, bytes: Vec<u8>) -> (StatusCode, Value) {
    let req = Request::builder()
        .method(Method::POST)
        .uri(format!("/v1/media?kind={kind}"))
        .header(header::AUTHORIZATION, format!("Bearer {token}"))
        .header(header::CONTENT_TYPE, "image/png")
        .body(Body::from(bytes))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let body = res.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&body).unwrap_or(Value::Null))
}

fn setup(db: &PgPool) -> (Router, MediaStore) {
    let state = AppState::new(db.clone(), Policy::default());
    let store = state.media.clone();
    (app(state), store)
}

fn key_of(url: &Value) -> String {
    url.as_str()
        .unwrap()
        .trim_start_matches("memory://")
        .to_owned()
}

#[sqlx::test]
async fn post_with_images(db: PgPool) {
    let (app, store) = setup(&db);
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;

    let (s, m) = upload(&app, &alice, "post", png(2400, 1200)).await;
    assert_eq!(s, StatusCode::CREATED, "{m}");
    assert_eq!(
        (m["width"].as_i64(), m["height"].as_i64()),
        (Some(1600), Some(800))
    );
    let key = key_of(&m["url"]);
    assert!(store.contains(&key));
    let id = m["id"].as_str().unwrap().to_owned();

    // Lixo e tipo errado são recusados.
    let (s, b) = upload(&app, &alice, "post", b"isto nao e imagem".to_vec()).await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_image"))
    );
    let (s, _) = upload(&app, &alice, "video", png(10, 10)).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // Foto de outra pessoa não pode ser usada.
    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&bob),
        Some(json!({"body": "", "media_ids": [id]})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("invalid_media"))
    );

    // Post só com foto.
    let (s, p) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&alice),
        Some(json!({"media_ids": [id]})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    assert_eq!(p["body"], "");
    assert_eq!(p["images"][0]["id"], id.as_str());
    let post = p["id"].as_str().unwrap().to_owned();

    // Não dá para reusar a mesma foto; nem post vazio.
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&alice),
        Some(json!({"media_ids": [id]})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&alice),
        Some(json!({"body": "  "})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // Mais de 4.
    let mut ids = vec![];
    for _ in 0..5 {
        let (_, m) = upload(&app, &alice, "post", png(20, 20)).await;
        ids.push(m["id"].as_str().unwrap().to_owned());
    }
    let (s, b) = call(
        &app,
        Method::POST,
        "/v1/posts",
        Some(&alice),
        Some(json!({"body": "x", "media_ids": ids})),
    )
    .await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::UNPROCESSABLE_ENTITY, Some("too_many_images"))
    );

    // Feed traz as fotos.
    let (_, feed) = call(&app, Method::GET, "/v1/feed", Some(&alice), None).await;
    assert_eq!(feed["items"][0]["images"].as_array().unwrap().len(), 1);

    // Apagar o post apaga o arquivo.
    let (s, _) = call(
        &app,
        Method::DELETE,
        &format!("/v1/posts/{post}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    assert!(!store.contains(&key));
}

#[sqlx::test]
async fn avatar_and_daily_photo(db: PgPool) {
    let (app, store) = setup(&db);
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

    let (_, a1) = upload(&app, &alice, "avatar", png(900, 600)).await;
    assert_eq!(a1["width"], 512);
    // Foto de post não serve como avatar.
    let (_, p) = upload(&app, &alice, "post", png(50, 50)).await;
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/avatar",
        Some(&alice),
        Some(json!({"media_id": p["id"]})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = call(
        &app,
        Method::PUT,
        "/v1/me/avatar",
        Some(&alice),
        Some(json!({"media_id": a1["id"]})),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (_, prof) = call(&app, Method::GET, "/v1/users/alice", Some(&carol), None).await;
    assert_eq!(prof["avatar_url"], a1["url"]);

    // Trocar o avatar apaga o antigo.
    let (_, a2) = upload(&app, &alice, "avatar", png(300, 300)).await;
    call(
        &app,
        Method::PUT,
        "/v1/me/avatar",
        Some(&alice),
        Some(json!({"media_id": a2["id"]})),
    )
    .await;
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    assert!(!store.contains(&key_of(&a1["url"])));

    // Foto do dia: amigos veem; outros não.
    let (_, d) = upload(&app, &alice, "daily", png(1000, 1000)).await;
    let (s, dp) = call(
        &app,
        Method::PUT,
        "/v1/me/daily-photo",
        Some(&alice),
        Some(json!({"media_id": d["id"], "caption": "Pôr do sol   na praia"})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{dp}");
    assert_eq!(dp["caption"], "Pôr do sol na praia");
    let (_, prof) = call(&app, Method::GET, "/v1/users/alice", Some(&bob), None).await;
    assert_eq!(prof["daily_photo"]["caption"], "Pôr do sol na praia");
    let (_, prof) = call(&app, Method::GET, "/v1/users/alice", Some(&carol), None).await;
    assert_eq!(prof["daily_photo"], Value::Null);

    // Excluir a conta apaga os arquivos.
    call(
        &app,
        Method::DELETE,
        "/v1/me",
        Some(&alice),
        Some(json!({"password": PASSWORD})),
    )
    .await;
    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    assert!(!store.contains(&key_of(&a2["url"])));
    assert!(!store.contains(&key_of(&d["url"])));
}

#[sqlx::test]
async fn upload_requires_storage(db: PgPool) {
    let state = AppState::new(db.clone(), Policy::default()).with_media(MediaStore::Disabled);
    let app = app(state);
    let alice = signup(&app, &db, "alice").await;
    let (s, b) = upload(&app, &alice, "post", png(10, 10)).await;
    assert_eq!(
        (s, b["error"].as_str()),
        (StatusCode::SERVICE_UNAVAILABLE, Some("media_unavailable"))
    );
}

#[sqlx::test]
async fn cleanup_removes_unused_uploads(db: PgPool) {
    let (app, store) = setup(&db);
    let alice = signup(&app, &db, "alice").await;
    let (_, m) = upload(&app, &alice, "post", png(10, 10)).await;
    sqlx::query("UPDATE media SET created_at = now() - interval '2 days'")
        .execute(&db)
        .await
        .unwrap();
    let n = humannet_api::routes::photos::cleanup_orphans(&db, &store)
        .await
        .unwrap();
    assert_eq!(n, 1);
    assert!(!store.contains(&key_of(&m["url"])));
}

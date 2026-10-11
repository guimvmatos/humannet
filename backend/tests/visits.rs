//! "Quem visitou meu perfil": recíproco, ligado por padrão, só o dia.

mod common;

use common::*;

async fn visits(app: &Router, token: &str) -> Value {
    let (s, v) = call(app, Method::GET, "/v1/me/visits", Some(token), None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    v
}

fn names(v: &Value) -> Vec<String> {
    v["visitors"]
        .as_array()
        .unwrap()
        .iter()
        .map(|x| x["username"].as_str().unwrap().to_owned())
        .collect()
}

async fn open(app: &Router, token: &str, who: &str) {
    let (s, _) = call(
        app,
        Method::GET,
        &format!("/v1/users/{who}"),
        Some(token),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
}

#[sqlx::test]
async fn visits_are_reciprocal(db: PgPool) {
    let app = test_app(db.clone());
    let alice = signup(&app, &db, "alice").await;
    let bob = signup(&app, &db, "bob").await;
    let carol = signup(&app, &db, "carol").await;

    open(&app, &bob, "alice").await;
    open(&app, &carol, "alice").await;
    open(&app, &alice, "alice").await; // a própria pessoa não conta
    open(&app, &bob, "alice").await; // repetir só atualiza

    let v = visits(&app, &alice).await;
    assert_eq!(v["enabled"], true);
    assert_eq!(names(&v), ["bob", "carol"]);
    let day = v["visitors"][0]["day"].as_str().unwrap();
    assert_eq!(day.len(), 10, "só o dia: {day}");
    assert!(v["visitors"][0].get("visited_at").is_none());

    // Carol desliga: some da lista de alice e não vê mais as dela.
    let (s, v) = call(
        &app,
        Method::PUT,
        "/v1/me/visits",
        Some(&carol),
        Some(json!({"enabled": false})),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(v["enabled"], false);
    assert_eq!(names(&visits(&app, &alice).await), ["bob"]);
    open(&app, &alice, "carol").await;
    let v = visits(&app, &carol).await;
    assert!(names(&v).is_empty());
    // Desligada, também não deixa rastro ao visitar.
    open(&app, &carol, "bob").await;
    assert!(names(&visits(&app, &bob).await).is_empty());

    // Religar não traz de volta o que foi apagado.
    call(
        &app,
        Method::PUT,
        "/v1/me/visits",
        Some(&carol),
        Some(json!({"enabled": true})),
    )
    .await;
    assert!(names(&visits(&app, &carol).await).is_empty());

    // Bloqueio esconde.
    call(&app, Method::PUT, "/v1/users/bob/block", Some(&alice), None).await;
    assert!(names(&visits(&app, &alice).await).is_empty());

    // Mais de 30 dias: apagado.
    open(&app, &carol, "alice").await;
    sqlx::query("UPDATE profile_visits SET visited_at = now() - interval '31 days'")
        .execute(&db)
        .await
        .unwrap();
    assert!(names(&visits(&app, &alice).await).is_empty());
    let left: i64 = sqlx::query_scalar("SELECT count(*) FROM profile_visits")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(left, 0);
}

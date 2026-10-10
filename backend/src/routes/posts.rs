use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    media::Kind,
    routes::{
        friends,
        pagination::{Page, PageQuery},
        photos::{self, MediaDto},
        profiles::visible_user_id,
    },
    validation,
};

#[derive(Debug, Serialize)]
pub struct AuthorDto {
    pub id: Uuid,
    pub username: String,
    pub display_name: Option<String>,
    /// Foto de perfil (link assinado). Preenchida por `fill_avatars`.
    pub avatar_url: Option<String>,
}

/// Preenche `avatar_url` de vários autores numa consulta só.
pub async fn fill_avatars<'a>(
    state: &AppState,
    authors: impl IntoIterator<Item = &'a mut AuthorDto>,
) -> sqlx::Result<()> {
    let mut authors: Vec<&mut AuthorDto> = authors.into_iter().collect();
    if authors.is_empty() {
        return Ok(());
    }
    let mut ids: Vec<Uuid> = authors.iter().map(|a| a.id).collect();
    ids.sort();
    ids.dedup();
    let rows = sqlx::query!(
        "SELECT u.id, m.key FROM users u JOIN media m ON m.id = u.avatar_media_id
         WHERE u.id = ANY($1)",
        &ids
    )
    .fetch_all(&state.db)
    .await?;
    let keys: std::collections::HashMap<Uuid, String> =
        rows.into_iter().map(|r| (r.id, r.key)).collect();
    for a in &mut authors {
        a.avatar_url = keys.get(&a.id).map(|k| state.media.url(k));
    }
    Ok(())
}

/// Post como o app o recebe.
/// Curtidas: só o autor vê o número (R3). Os outros sabem só se curtiram.
#[derive(Debug, Serialize)]
pub struct PostDto {
    pub id: Uuid,
    pub author: AuthorDto,
    pub body: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    #[serde(with = "time::serde::rfc3339::option")]
    pub edited_at: Option<OffsetDateTime>,
    pub comment_count: i64,
    pub liked_by_me: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub like_count: Option<i64>,
    /// Até 4 fotos, na ordem.
    pub images: Vec<MediaDto>,
    /// Temas marcados pelo autor (lista fixa) e hashtags do texto.
    pub topics: Vec<String>,
    pub hashtags: Vec<String>,
    /// friends (padrão) | region (qualquer pessoa perto vê; sem distância).
    pub audience: String,
    /// Post do mural de uma página (o autor é quem administra e publicou).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub page: Option<PageRef>,
}

#[derive(Debug, Serialize)]
pub struct PageRef {
    pub slug: String,
    pub name: String,
    pub logo_url: Option<String>,
}

/// Linha "achatada" vinda do banco.
struct PostRow {
    id: Uuid,
    body: String,
    created_at: OffsetDateTime,
    edited_at: Option<OffsetDateTime>,
    author_id: Uuid,
    author_username: String,
    author_display_name: Option<String>,
    page_slug: Option<String>,
    page_name: Option<String>,
    page_logo_key: Option<String>,
    topics: Vec<String>,
    hashtags: Vec<String>,
    audience: String,
}

impl From<PostRow> for PostDto {
    fn from(r: PostRow) -> Self {
        Self {
            id: r.id,
            author: AuthorDto {
                id: r.author_id,
                username: r.author_username,
                display_name: r.author_display_name,
                avatar_url: None,
            },
            body: r.body,
            created_at: r.created_at,
            edited_at: r.edited_at,
            comment_count: 0,
            liked_by_me: false,
            like_count: None,
            images: Vec::new(),
            topics: r.topics,
            hashtags: r.hashtags,
            audience: r.audience,
            page: match (r.page_slug, r.page_name) {
                (Some(slug), Some(name)) => Some(PageRef {
                    slug,
                    name,
                    // Chave do bucket; vira link assinado em `enrich`.
                    logo_url: r.page_logo_key,
                }),
                _ => None,
            },
        }
    }
}

/// Preenche comentários/curtidas de vários posts numa única consulta.
async fn enrich(state: &AppState, viewer: Uuid, posts: &mut [PostDto]) -> sqlx::Result<()> {
    let db = &state.db;
    if posts.is_empty() {
        return Ok(());
    }
    let ids: Vec<Uuid> = posts.iter().map(|p| p.id).collect();
    let rows = sqlx::query!(
        r#"
        SELECT p.id AS "id!",
               (SELECT count(*) FROM comments c
                 WHERE c.post_id = p.id AND c.deleted_at IS NULL) AS "comment_count!",
               EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.user_id = $2) AS "liked!",
               CASE WHEN p.author_id = $2
                    THEN (SELECT count(*) FROM likes l WHERE l.post_id = p.id) END AS like_count
        FROM posts p
        WHERE p.id = ANY($1)
        "#,
        &ids,
        viewer
    )
    .fetch_all(db)
    .await?;
    for r in rows {
        if let Some(p) = posts.iter_mut().find(|p| p.id == r.id) {
            p.comment_count = r.comment_count;
            p.liked_by_me = r.liked;
            p.like_count = r.like_count;
        }
    }
    fill_avatars(state, posts.iter_mut().map(|p| &mut p.author)).await?;
    for p in posts.iter_mut() {
        if let Some(pg) = p.page.as_mut() {
            pg.logo_url = pg.logo_url.take().map(|k| state.media.url(&k));
        }
    }
    let mut images = photos::for_posts(db, &state.media, &ids).await?;
    for p in posts.iter_mut() {
        p.images = images.remove(&p.id).unwrap_or_default();
    }
    Ok(())
}

async fn page(
    state: &AppState,
    viewer: Uuid,
    rows: Vec<PostRow>,
    limit: i64,
) -> sqlx::Result<Page<PostDto>> {
    let mut items: Vec<PostDto> = rows.into_iter().map(PostDto::from).collect();
    enrich(state, viewer, &mut items).await?;
    Ok(Page::from_overfetch(items, limit, |p| p.id))
}

/// Quem administra a página (dono ou admin).
pub(crate) async fn is_page_admin(
    db: &sqlx::PgPool,
    page_id: Uuid,
    user_id: Uuid,
) -> sqlx::Result<bool> {
    sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM page_admins WHERE page_id = $1 AND user_id = $2) AS "e!""#,
        page_id,
        user_id
    )
    .fetch_one(db)
    .await
}

/// Post visível para `viewer`: de página (ativa) para todos; os demais, só
/// autor e amigos. 404 caso contrário. Devolve (autor, página).
pub(crate) async fn visible_post(
    state: &AppState,
    viewer: Uuid,
    post_id: Uuid,
) -> AppResult<(Uuid, Option<Uuid>)> {
    let r = sqlx::query!(
        r#"SELECT p.author_id, p.page_id, (pg.deleted_at IS NULL) AS "page_alive?",
                  (p.audience = 'region') AS "region!"
           FROM posts p LEFT JOIN pages pg ON pg.id = p.page_id
           WHERE p.id = $1 AND p.deleted_at IS NULL"#,
        post_id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    let ok = match r.page_id {
        Some(_) => r.page_alive == Some(true),
        // Post para a região: qualquer pessoa vê, menos quem tem bloqueio.
        None if r.region => {
            r.author_id == viewer
                || !crate::routes::safety::is_blocked_either_way(&state.db, viewer, r.author_id)
                    .await?
        }
        None => friends::can_see_content(&state.db, viewer, r.author_id).await?,
    };
    if !ok {
        return Err(AppError::NotFound);
    }
    Ok((r.author_id, r.page_id))
}

/// Post visível para `viewer`. 404 caso contrário. Devolve o autor.
pub(crate) async fn visible_post_author(
    state: &AppState,
    viewer: Uuid,
    post_id: Uuid,
) -> AppResult<Uuid> {
    Ok(visible_post(state, viewer, post_id).await?.0)
}

#[derive(Debug, Deserialize)]
pub struct CreatePost {
    #[serde(default)]
    pub body: String,
    /// Fotos enviadas antes em POST /v1/media?kind=post (até 4).
    #[serde(default)]
    pub media_ids: Vec<Uuid>,
    /// Até 3 temas da lista (`GET /v1/topics`), ex.: "cidade.transito".
    #[serde(default)]
    pub topics: Vec<String>,
    /// "friends" (padrão) ou "region" (com `lat`/`lng` do aparelho, que o
    /// servidor arredonda para uma célula de ~500 m antes de guardar).
    pub audience: Option<String>,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
}

/// Fotos por post.
pub const MAX_IMAGES: usize = 4;

/// POST /v1/posts
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreatePost>,
) -> AppResult<(StatusCode, Json<PostDto>)> {
    let dto = insert(&state, user.user_id, None, req).await?;
    Ok((StatusCode::CREATED, Json(dto)))
}

/// Cria um post (pessoal ou, com `page_id`, no mural da página).
pub(crate) async fn insert(
    state: &AppState,
    author: Uuid,
    page_id: Option<Uuid>,
    req: CreatePost,
) -> AppResult<PostDto> {
    if req.media_ids.len() > MAX_IMAGES {
        return Err(AppError::Validation("too_many_images"));
    }
    // Só foto é um post válido; só texto também. Vazio, não.
    let body = if req.media_ids.is_empty() || !req.body.trim().is_empty() {
        validation::post_body(&req.body)?
    } else {
        String::new()
    };
    let mut topics: Vec<String> = Vec::new();
    for t in &req.topics {
        if !crate::topics::valid(t) {
            return Err(AppError::Validation("invalid_topic"));
        }
        if !topics.contains(t) {
            topics.push(t.clone());
        }
    }
    if topics.len() > 3 {
        return Err(AppError::Validation("too_many_topics"));
    }
    let hashtags = crate::topics::hashtags(&body);
    let (audience, cell) = match req.audience.as_deref() {
        None | Some("friends") => ("friends", None),
        Some("region") if page_id.is_none() => match (req.lat, req.lng) {
            (Some(lat), Some(lng)) => ("region", Some(region::cell(lat, lng)?)),
            _ => return Err(AppError::Validation("invalid_location")),
        },
        _ => return Err(AppError::Validation("invalid_audience")),
    };
    let mut tx = state.db.begin().await?;
    let id = Uuid::now_v7();
    sqlx::query!(
        "INSERT INTO posts (id, author_id, body, page_id, topics, hashtags, audience,
                            cell_lat, cell_lng)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
        id,
        author,
        body,
        page_id,
        &topics,
        &hashtags,
        audience,
        cell.map(|c| c.0),
        cell.map(|c| c.1)
    )
    .execute(&mut *tx)
    .await?;
    if !req.media_ids.is_empty() {
        photos::claim(&mut tx, author, Kind::Post, &req.media_ids).await?;
        for (i, m) in req.media_ids.iter().enumerate() {
            sqlx::query!(
                "INSERT INTO post_media (post_id, media_id, position) VALUES ($1, $2, $3)",
                id,
                m,
                i16::try_from(i).unwrap_or(0)
            )
            .execute(&mut *tx)
            .await?;
        }
    }
    tx.commit().await?;
    let row = fetch_row(state, id).await?.ok_or(AppError::NotFound)?;
    let mut items = [PostDto::from(row)];
    enrich(state, author, &mut items).await?;
    let [dto] = items;
    Ok(dto)
}

async fn fetch_row(state: &AppState, id: Uuid) -> sqlx::Result<Option<PostRow>> {
    sqlx::query_as!(
        PostRow,
        r#"
        SELECT p.id, p.body, p.created_at, p.edited_at,
               u.id AS author_id, u.username AS author_username,
               u.display_name AS author_display_name, p.topics, p.hashtags, p.audience,
               pg.slug AS "page_slug?", pg.name AS "page_name?", lm.key AS "page_logo_key?"
        FROM posts p JOIN users u ON u.id = p.author_id
        LEFT JOIN pages pg ON pg.id = p.page_id
        LEFT JOIN media lm ON lm.id = pg.logo_media_id
        WHERE p.id = $1 AND p.deleted_at IS NULL
        "#,
        id
    )
    .fetch_optional(&state.db)
    .await
}

/// GET /v1/posts/{id} — post pessoal: só o autor e os amigos dele (para os
/// demais, 404: não revela que existe). Post de página: todos.
pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<PostDto>> {
    visible_post(&state, user.user_id, id).await?;
    let row = fetch_row(&state, id).await?.ok_or(AppError::NotFound)?;
    let mut items = [PostDto::from(row)];
    enrich(&state, user.user_id, &mut items).await?;
    let [dto] = items;
    Ok(Json(dto))
}

/// DELETE /v1/posts/{id} — o autor (ou quem administra a página, se for do
/// mural). Exclusão lógica.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let r = sqlx::query!(
        "SELECT author_id, page_id FROM posts WHERE id = $1 AND deleted_at IS NULL",
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    let page_admin = match r.page_id {
        Some(pg) => is_page_admin(&state.db, pg, user.user_id).await?,
        None => false,
    };
    if r.author_id != user.user_id && !page_admin {
        return Err(AppError::Forbidden);
    }

    // Apaga também o conteúdo: exclusão lógica não deve reter o texto nem as fotos.
    sqlx::query!(
        "UPDATE posts SET deleted_at = now(), body = '[removido]' WHERE id = $1",
        id
    )
    .execute(&state.db)
    .await?;
    photos::delete_post_media(&state, id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /v1/users/{username}/posts — só para o próprio e amigos (ADR-0006).
pub async fn list_by_user(
    State(state): State<AppState>,
    viewer: AuthUser,
    Path(username): Path<String>,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Page<PostDto>>> {
    let author = visible_user_id(&state, viewer.user_id, &username).await?;
    if !friends::can_see_content(&state.db, viewer.user_id, author).await? {
        return Err(AppError::Forbidden);
    }
    let limit = q.limit();
    let rows = sqlx::query_as!(
        PostRow,
        r#"
        SELECT p.id, p.body, p.created_at, p.edited_at,
               u.id AS author_id, u.username AS author_username,
               u.display_name AS author_display_name, p.topics, p.hashtags, p.audience,
               NULL::text AS "page_slug?", NULL::text AS "page_name?",
               NULL::text AS "page_logo_key?"
        FROM posts p JOIN users u ON u.id = p.author_id
        WHERE p.author_id = $1
          AND p.page_id IS NULL
          AND p.deleted_at IS NULL
          AND ($2::uuid IS NULL OR p.id < $2)
        ORDER BY p.id DESC
        LIMIT $3
        "#,
        author,
        q.before,
        limit + 1
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(page(&state, viewer.user_id, rows, limit).await?))
}

/// GET /v1/feed — modo cronológico (padrão, R2): meus amigos, eu e as
/// páginas que acompanho. Sem ranking. A ordem é a de publicação.
pub async fn feed(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Page<PostDto>>> {
    let limit = q.limit();
    let rows = sqlx::query_as!(
        PostRow,
        r#"
        SELECT p.id, p.body, p.created_at, p.edited_at,
               u.id AS author_id, u.username AS author_username,
               u.display_name AS author_display_name, p.topics, p.hashtags, p.audience,
               pg.slug AS "page_slug?", pg.name AS "page_name?", lm.key AS "page_logo_key?"
        FROM posts p JOIN users u ON u.id = p.author_id
        LEFT JOIN pages pg ON pg.id = p.page_id
        LEFT JOIN media lm ON lm.id = pg.logo_media_id
        WHERE p.deleted_at IS NULL
          AND ((p.page_id IS NULL
                AND (p.author_id = $1
                     OR p.author_id IN (SELECT friend_id FROM friends WHERE user_id = $1)))
               OR (pg.deleted_at IS NULL
                   AND p.page_id IN (SELECT page_id FROM page_followers WHERE user_id = $1)))
          AND ($2::uuid IS NULL OR p.id < $2)
        ORDER BY p.id DESC
        LIMIT $3
        "#,
        user.user_id,
        q.before,
        limit + 1
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(page(&state, user.user_id, rows, limit).await?))
}

/// PUT /v1/posts/{id}/like — idempotente.
pub async fn like(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    visible_post_author(&state, user.user_id, id).await?;
    sqlx::query!(
        "INSERT INTO likes (post_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/posts/{id}/like — idempotente.
pub async fn unlike(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    sqlx::query!(
        "DELETE FROM likes WHERE post_id = $1 AND user_id = $2",
        id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Mural de uma página (mais novos primeiro). Todos veem.
pub(crate) async fn page_wall(
    state: &AppState,
    viewer: Uuid,
    page_id: Uuid,
    q: &PageQuery,
) -> AppResult<Page<PostDto>> {
    let limit = q.limit();
    let rows = sqlx::query_as!(
        PostRow,
        r#"
        SELECT p.id, p.body, p.created_at, p.edited_at,
               u.id AS author_id, u.username AS author_username,
               u.display_name AS author_display_name, p.topics, p.hashtags, p.audience,
               pg.slug AS "page_slug?", pg.name AS "page_name?", lm.key AS "page_logo_key?"
        FROM posts p JOIN users u ON u.id = p.author_id
        JOIN pages pg ON pg.id = p.page_id
        LEFT JOIN media lm ON lm.id = pg.logo_media_id
        WHERE p.page_id = $1 AND p.deleted_at IS NULL
          AND ($2::uuid IS NULL OR p.id < $2)
        ORDER BY p.id DESC
        LIMIT $3
        "#,
        page_id,
        q.before,
        limit + 1
    )
    .fetch_all(&state.db)
    .await?;
    Ok(page(state, viewer, rows, limit).await?)
}

/// GET /v1/topics — a lista fixa de temas e subtemas.
pub async fn topics(_user: AuthUser) -> Json<&'static [crate::topics::Topic]> {
    Json(crate::topics::TOPICS)
}

#[derive(Debug, Deserialize)]
pub struct CandidatesQuery {
    pub days: Option<i64>,
}

/// GET /v1/feed/candidates?days=7 — posts recentes da mesma fonte do feed
/// cronológico (amigos, eu, páginas que acompanho), para o app ordenar no
/// aparelho pelo perfil de interesses (ADR-0004). O servidor não ordena nem
/// guarda nada sobre interesses.
pub async fn candidates(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<CandidatesQuery>,
) -> AppResult<Json<Page<PostDto>>> {
    let days = q.days.unwrap_or(7).clamp(1, 30);
    let rows = sqlx::query_as!(
        PostRow,
        r#"
        SELECT p.id, p.body, p.created_at, p.edited_at,
               u.id AS author_id, u.username AS author_username,
               u.display_name AS author_display_name, p.topics, p.hashtags, p.audience,
               pg.slug AS "page_slug?", pg.name AS "page_name?", lm.key AS "page_logo_key?"
        FROM posts p JOIN users u ON u.id = p.author_id
        LEFT JOIN pages pg ON pg.id = p.page_id
        LEFT JOIN media lm ON lm.id = pg.logo_media_id
        WHERE p.deleted_at IS NULL
          AND p.created_at > now() - make_interval(days => $2::int)
          AND ((p.page_id IS NULL
                AND (p.author_id = $1
                     OR p.author_id IN (SELECT friend_id FROM friends WHERE user_id = $1)))
               OR (pg.deleted_at IS NULL
                   AND p.page_id IN (SELECT page_id FROM page_followers WHERE user_id = $1)))
        ORDER BY p.id DESC
        LIMIT 300
        "#,
        user.user_id,
        i32::try_from(days).unwrap_or(7)
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<PostDto> = rows.into_iter().map(PostDto::from).collect();
    enrich(&state, user.user_id, &mut items).await?;
    Ok(Json(Page {
        items,
        next_cursor: None,
    }))
}

pub mod region {
    //! Feed regional (C1 cronológico, C2 ordenado no aparelho). A posição de
    //! quem lê chega só na consulta, já arredondada para a célula, e não é
    //! guardada nem registrada. Distâncias nunca são devolvidas.

    use super::*;

    /// Grade de ~500 m (0,005° de latitude ≈ 555 m).
    const STEP: f64 = 0.005;

    pub fn cell(lat: f64, lng: f64) -> AppResult<(f64, f64)> {
        if !(lat.is_finite() && lng.is_finite() && lat.abs() <= 90.0 && lng.abs() <= 180.0) {
            return Err(AppError::Validation("invalid_location"));
        }
        let snap = |v: f64| ((v / STEP).round() * STEP * 1e6).round() / 1e6;
        Ok((snap(lat), snap(lng)))
    }

    #[derive(Debug, Deserialize)]
    pub struct RegionQuery {
        pub lat: f64,
        pub lng: f64,
        /// 1 a 50 km.
        pub radius_km: f64,
        pub before: Option<Uuid>,
        pub limit: Option<i64>,
        /// Só para `/candidates`: últimos N dias (1 a 30).
        pub days: Option<i64>,
    }

    async fn rows(
        state: &AppState,
        viewer: Uuid,
        q: &RegionQuery,
        before: Option<Uuid>,
        days: i32,
        limit: i64,
    ) -> AppResult<Vec<PostRow>> {
        if !(1.0..=50.0).contains(&q.radius_km) {
            return Err(AppError::Validation("invalid_radius"));
        }
        let (lat, lng) = cell(q.lat, q.lng)?;
        // Folga de meia célula: quem está na borda não perde post vizinho.
        let r = q.radius_km + 0.4;
        let dlat = r / 111.0;
        let dlng = r / (111.0 * lat.to_radians().cos().max(0.05));
        let rows = sqlx::query_as!(
            PostRow,
            r#"
            SELECT p.id, p.body, p.created_at, p.edited_at,
                   u.id AS author_id, u.username AS author_username,
                   u.display_name AS author_display_name, p.topics, p.hashtags, p.audience,
                   NULL::text AS "page_slug?", NULL::text AS "page_name?",
                   NULL::text AS "page_logo_key?"
            FROM posts p JOIN users u ON u.id = p.author_id
            WHERE p.audience = 'region' AND p.deleted_at IS NULL AND u.suspended_at IS NULL
              AND p.cell_lat BETWEEN $1::float8 - $3::float8 AND $1::float8 + $3::float8
              AND p.cell_lng BETWEEN $2::float8 - $4::float8 AND $2::float8 + $4::float8
              AND 6371 * 2 * asin(sqrt(
                    power(sin(radians(p.cell_lat - $1::float8) / 2), 2)
                    + cos(radians($1::float8)) * cos(radians(p.cell_lat))
                      * power(sin(radians(p.cell_lng - $2::float8) / 2), 2))) <= $5::float8
              AND p.created_at > now() - make_interval(days => $6::int)
              AND ($7::uuid IS NULL OR p.id < $7)
              AND NOT EXISTS (SELECT 1 FROM blocks b
                WHERE (b.blocker_id = $8 AND b.blocked_id = p.author_id)
                   OR (b.blocker_id = p.author_id AND b.blocked_id = $8))
            ORDER BY p.id DESC
            LIMIT $9
            "#,
            lat,
            lng,
            dlat,
            dlng,
            r,
            days,
            before,
            viewer,
            limit
        )
        .fetch_all(&state.db)
        .await?;
        Ok(rows)
    }

    /// GET /v1/feed/region?lat=&lng=&radius_km=&before= — C1: cronológico.
    pub async fn feed(
        State(state): State<AppState>,
        user: AuthUser,
        Query(q): Query<RegionQuery>,
    ) -> AppResult<Json<Page<PostDto>>> {
        let limit = PageQuery {
            before: None,
            limit: q.limit,
        }
        .limit();
        let rows = rows(&state, user.user_id, &q, q.before, 30, limit + 1).await?;
        Ok(Json(page(&state, user.user_id, rows, limit).await?))
    }

    /// GET /v1/feed/region/candidates?lat=&lng=&radius_km=&days=7 — C2: o app
    /// ordena pelo perfil de interesses (no aparelho).
    pub async fn candidates(
        State(state): State<AppState>,
        user: AuthUser,
        Query(q): Query<RegionQuery>,
    ) -> AppResult<Json<Page<PostDto>>> {
        let days = i32::try_from(q.days.unwrap_or(7).clamp(1, 30)).unwrap_or(7);
        let rows = rows(&state, user.user_id, &q, None, days, 300).await?;
        let mut items: Vec<PostDto> = rows.into_iter().map(PostDto::from).collect();
        enrich(&state, user.user_id, &mut items).await?;
        Ok(Json(Page {
            items,
            next_cursor: None,
        }))
    }
}

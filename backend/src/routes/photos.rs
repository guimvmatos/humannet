//! Fotos (lote 9): upload, foto de perfil e Foto do dia. Fotos de post são
//! anexadas em POST /v1/posts (`media_ids`).
//!
//! Fluxo: o app envia a imagem (já reduzida) em POST /v1/media?kind=…; o
//! servidor recodifica sem metadados, guarda no bucket e devolve um id. Esse
//! id é usado depois no post, no avatar ou na Foto do dia. Fotos enviadas e
//! não usadas em 24 h são apagadas.

use std::collections::HashMap;

use axum::{
    Json,
    body::Bytes,
    extract::{Query, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use time::{Date, OffsetDateTime, UtcOffset};
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    media::{self, Kind, MediaStore},
};

/// Uploads por pessoa por hora.
const MAX_UPLOADS_PER_HOUR: i64 = 60;
/// Legenda da Foto do dia.
const CAPTION_MAX: usize = 200;

#[derive(Debug, Clone, Serialize)]
pub struct MediaDto {
    pub id: Uuid,
    pub url: String,
    pub width: i32,
    pub height: i32,
}

#[derive(Debug, Deserialize)]
pub struct UploadQuery {
    /// post | avatar | daily
    pub kind: String,
}

/// POST /v1/media?kind=post — corpo = bytes da imagem (JPEG, PNG ou WebP).
pub async fn upload(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<UploadQuery>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<MediaDto>)> {
    let kind = Kind::parse(&q.kind).ok_or(AppError::Validation("invalid_media_kind"))?;
    if !state.media.enabled() {
        return Err(AppError::Unavailable("media_unavailable"));
    }
    if body.is_empty() {
        return Err(AppError::Validation("invalid_image"));
    }
    let recent = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM media
           WHERE owner_id = $1 AND created_at > now() - interval '1 hour'"#,
        user.user_id
    )
    .fetch_one(&state.db)
    .await?;
    if recent >= MAX_UPLOADS_PER_HOUR {
        return Err(AppError::LimitReached("upload_limit"));
    }

    let processed = tokio::task::spawn_blocking(move || media::process(&body, kind))
        .await
        .map_err(anyhow::Error::from)?
        .map_err(|e| {
            tracing::info!(error = %e, "imagem recusada");
            AppError::Validation("invalid_image")
        })?;

    let id = Uuid::now_v7();
    let key = format!("media/{}/{id}.jpg", user.user_id);
    let size = i32::try_from(processed.jpeg.len()).unwrap_or(i32::MAX);
    let (w, h) = (
        i32::try_from(processed.width).unwrap_or(i32::MAX),
        i32::try_from(processed.height).unwrap_or(i32::MAX),
    );
    state.media.put(&key, processed.jpeg).await?;
    sqlx::query!(
        "INSERT INTO media (id, owner_id, kind, key, width, height, bytes)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
        id,
        user.user_id,
        kind.as_str(),
        key,
        w,
        h,
        size
    )
    .execute(&state.db)
    .await?;
    Ok((
        StatusCode::CREATED,
        Json(MediaDto {
            id,
            url: state.media.url(&key),
            width: w,
            height: h,
        }),
    ))
}

/// Confere que as fotos são minhas, do tipo certo e ainda não usadas, e as
/// marca como usadas. Devolve na ordem pedida.
pub async fn claim(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    owner: Uuid,
    kind: Kind,
    ids: &[Uuid],
) -> AppResult<()> {
    let mut unique = ids.to_vec();
    unique.sort();
    unique.dedup();
    if unique.len() != ids.len() {
        return Err(AppError::Validation("invalid_media"));
    }
    let n = sqlx::query!(
        "UPDATE media SET attached_at = now()
         WHERE id = ANY($1) AND owner_id = $2 AND kind = $3 AND attached_at IS NULL",
        ids,
        owner,
        kind.as_str()
    )
    .execute(&mut **tx)
    .await?
    .rows_affected();
    if n != ids.len() as u64 {
        return Err(AppError::Validation("invalid_media"));
    }
    Ok(())
}

/// Fotos de vários posts, em ordem.
pub async fn for_posts(
    db: &sqlx::PgPool,
    store: &MediaStore,
    post_ids: &[Uuid],
) -> sqlx::Result<HashMap<Uuid, Vec<MediaDto>>> {
    let rows = sqlx::query!(
        "SELECT pm.post_id, m.id, m.key, m.width, m.height
         FROM post_media pm JOIN media m ON m.id = pm.media_id
         WHERE pm.post_id = ANY($1)
         ORDER BY pm.post_id, pm.position",
        post_ids
    )
    .fetch_all(db)
    .await?;
    let mut out: HashMap<Uuid, Vec<MediaDto>> = HashMap::new();
    for r in rows {
        out.entry(r.post_id).or_default().push(MediaDto {
            id: r.id,
            url: store.url(&r.key),
            width: r.width,
            height: r.height,
        });
    }
    Ok(out)
}

/// Apaga as fotos de um post (registros + arquivos). Usado ao apagar o post.
pub async fn delete_post_media(state: &AppState, post_id: Uuid) -> sqlx::Result<()> {
    let keys = sqlx::query_scalar!(
        "DELETE FROM media WHERE id IN (SELECT media_id FROM post_media WHERE post_id = $1)
         RETURNING key",
        post_id
    )
    .fetch_all(&state.db)
    .await?;
    state.media.delete_later(keys);
    Ok(())
}

// ---------------------------------------------------------------- avatar

#[derive(Debug, Deserialize)]
pub struct SetMedia {
    pub media_id: Uuid,
    #[serde(default)]
    pub caption: String,
}

/// PUT /v1/me/avatar `{media_id}` — foto enviada com kind=avatar.
pub async fn set_avatar(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<SetMedia>,
) -> AppResult<Json<MediaDto>> {
    let mut tx = state.db.begin().await?;
    claim(&mut tx, user.user_id, Kind::Avatar, &[req.media_id]).await?;
    let old = sqlx::query_scalar!(
        "SELECT avatar_media_id FROM users WHERE id = $1 FOR UPDATE",
        user.user_id
    )
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query!(
        "UPDATE users SET avatar_media_id = $2 WHERE id = $1",
        user.user_id,
        req.media_id
    )
    .execute(&mut *tx)
    .await?;
    let old_keys = match old {
        Some(old) => {
            sqlx::query_scalar!("DELETE FROM media WHERE id = $1 RETURNING key", old)
                .fetch_all(&mut *tx)
                .await?
        }
        None => vec![],
    };
    let m = sqlx::query!(
        "SELECT key, width, height FROM media WHERE id = $1",
        req.media_id
    )
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    state.media.delete_later(old_keys);
    Ok(Json(MediaDto {
        id: req.media_id,
        url: state.media.url(&m.key),
        width: m.width,
        height: m.height,
    }))
}

/// DELETE /v1/me/avatar
pub async fn delete_avatar(State(state): State<AppState>, user: AuthUser) -> AppResult<StatusCode> {
    let keys = sqlx::query_scalar!(
        "DELETE FROM media WHERE id = (SELECT avatar_media_id FROM users WHERE id = $1)
         RETURNING key",
        user.user_id
    )
    .fetch_all(&state.db)
    .await?;
    state.media.delete_later(keys);
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------- Foto do dia

/// "Hoje" no horário de Brasília (UTC−3, sem horário de verão).
pub fn today() -> Date {
    let brt = UtcOffset::from_hms(-3, 0, 0).unwrap_or(UtcOffset::UTC);
    OffsetDateTime::now_utc().to_offset(brt).date()
}

#[derive(Debug, Serialize)]
pub struct DailyPhotoDto {
    pub photo: MediaDto,
    pub caption: String,
    /// AAAA-MM-DD
    pub day: String,
}

/// PUT /v1/me/daily-photo `{media_id, caption?}` — a de hoje (substitui).
pub async fn set_daily(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<SetMedia>,
) -> AppResult<Json<DailyPhotoDto>> {
    let caption = req.caption.split_whitespace().collect::<Vec<_>>().join(" ");
    if caption.chars().count() > CAPTION_MAX {
        return Err(AppError::Validation("invalid_caption"));
    }
    let day = today();
    let mut tx = state.db.begin().await?;
    claim(&mut tx, user.user_id, Kind::Daily, &[req.media_id]).await?;
    let old_keys = sqlx::query_scalar!(
        "DELETE FROM media WHERE id = (SELECT media_id FROM daily_photos WHERE user_id = $1 AND day = $2)
         RETURNING key",
        user.user_id,
        day
    )
    .fetch_all(&mut *tx)
    .await?;
    sqlx::query!(
        "INSERT INTO daily_photos (user_id, day, media_id, caption) VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, day) DO UPDATE SET media_id = EXCLUDED.media_id,
           caption = EXCLUDED.caption, created_at = now()",
        user.user_id,
        day,
        req.media_id,
        caption
    )
    .execute(&mut *tx)
    .await?;
    let m = sqlx::query!(
        "SELECT key, width, height FROM media WHERE id = $1",
        req.media_id
    )
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    state.media.delete_later(old_keys);
    Ok(Json(DailyPhotoDto {
        photo: MediaDto {
            id: req.media_id,
            url: state.media.url(&m.key),
            width: m.width,
            height: m.height,
        },
        caption,
        day: day.to_string(),
    }))
}

/// DELETE /v1/me/daily-photo — apaga a de hoje.
pub async fn delete_daily(State(state): State<AppState>, user: AuthUser) -> AppResult<StatusCode> {
    let keys = sqlx::query_scalar!(
        "DELETE FROM media WHERE id = (SELECT media_id FROM daily_photos WHERE user_id = $1 AND day = $2)
         RETURNING key",
        user.user_id,
        today()
    )
    .fetch_all(&state.db)
    .await?;
    state.media.delete_later(keys);
    Ok(StatusCode::NO_CONTENT)
}

/// A Foto do dia mais recente (até 7 dias), para o perfil.
pub async fn latest_daily(state: &AppState, user_id: Uuid) -> sqlx::Result<Option<DailyPhotoDto>> {
    let row = sqlx::query!(
        "SELECT d.day, d.caption, m.id, m.key, m.width, m.height
         FROM daily_photos d JOIN media m ON m.id = d.media_id
         WHERE d.user_id = $1 AND d.day > $2
         ORDER BY d.day DESC LIMIT 1",
        user_id,
        today() - time::Duration::days(7)
    )
    .fetch_optional(&state.db)
    .await?;
    Ok(row.map(|r| DailyPhotoDto {
        photo: MediaDto {
            id: r.id,
            url: state.media.url(&r.key),
            width: r.width,
            height: r.height,
        },
        caption: r.caption,
        day: r.day.to_string(),
    }))
}

/// Link da foto de perfil.
pub async fn avatar_url(state: &AppState, user_id: Uuid) -> sqlx::Result<Option<String>> {
    let key = sqlx::query_scalar!(
        "SELECT m.key FROM users u JOIN media m ON m.id = u.avatar_media_id WHERE u.id = $1",
        user_id
    )
    .fetch_optional(&state.db)
    .await?;
    Ok(key.map(|k| state.media.url(&k)))
}

/// Apaga fotos enviadas e não usadas há mais de 24 h. Roda de hora em hora.
pub async fn cleanup_orphans(db: &sqlx::PgPool, store: &MediaStore) -> sqlx::Result<usize> {
    let keys = sqlx::query_scalar!(
        "DELETE FROM media WHERE attached_at IS NULL AND created_at < now() - interval '24 hours'
         RETURNING key"
    )
    .fetch_all(db)
    .await?;
    let n = keys.len();
    for k in keys {
        store.delete(&k).await;
    }
    Ok(n)
}

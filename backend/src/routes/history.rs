//! "Minha atividade": tudo o que eu escrevi ou curti, com opção de apagar, e
//! "Baixar meus dados" (portabilidade, LGPD art. 18, V).

use axum::{
    Json,
    extract::{Path, Query, State},
    http::{StatusCode, header},
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    crypto,
    error::{AppError, AppResult},
    routes::photos,
};

const MAX_LIMIT: i64 = 50;
/// Apagar em lote: até 100 itens por pedido.
const MAX_DELETE: usize = 100;
/// O link de download vale 10 minutos e uma vez só.
const EXPORT_TTL_MINUTES: i64 = 10;

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Posts,
    Comments,
    Likes,
    Scraps,
    Testimonials,
}

#[derive(Debug, Deserialize)]
pub struct HistoryQuery {
    pub kind: Kind,
    /// Cursor: data do último item recebido (RFC 3339).
    #[serde(default, with = "time::serde::rfc3339::option")]
    pub before: Option<OffsetDateTime>,
    pub limit: Option<i64>,
}

/// Um item da minha atividade.
#[derive(Debug, Serialize)]
pub struct HistoryItem {
    /// O que apagar: post, comentário, recado, depoimento; em curtidas, o post.
    pub id: Uuid,
    /// Post para abrir (posts, comentários e curtidas).
    pub post_id: Option<Uuid>,
    /// A outra pessoa: autor do post comentado/curtido, ou destinatário.
    pub other_username: Option<String>,
    /// Texto (até 280 caracteres).
    pub body: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Serialize)]
pub struct HistoryPage {
    pub items: Vec<HistoryItem>,
    #[serde(with = "time::serde::rfc3339::option")]
    pub next_cursor: Option<OffsetDateTime>,
}

struct Row {
    id: Uuid,
    post_id: Option<Uuid>,
    other_username: Option<String>,
    body: String,
    created_at: OffsetDateTime,
}

fn excerpt(s: &str) -> String {
    const MAX: usize = 280;
    if s.chars().count() <= MAX {
        return s.to_owned();
    }
    let mut out: String = s.chars().take(MAX).collect();
    out.push('…');
    out
}

/// GET /v1/me/history?kind=posts|comments|likes|scraps|testimonials&before=
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<HistoryQuery>,
) -> AppResult<Json<HistoryPage>> {
    let limit = q.limit.unwrap_or(30).clamp(1, MAX_LIMIT);
    let me = user.user_id;
    let before = q.before;
    let n = limit + 1;
    let rows: Vec<Row> = match q.kind {
        Kind::Posts => {
            sqlx::query_as!(
                Row,
                r#"SELECT p.id, p.id AS "post_id?", pg.name AS "other_username?", p.body,
                          p.created_at
                   FROM posts p LEFT JOIN pages pg ON pg.id = p.page_id
                   WHERE p.author_id = $1 AND p.deleted_at IS NULL
                     AND ($2::timestamptz IS NULL OR p.created_at < $2)
                   ORDER BY p.created_at DESC LIMIT $3"#,
                me,
                before,
                n
            )
            .fetch_all(&state.db)
            .await?
        }
        Kind::Comments => {
            sqlx::query_as!(
                Row,
                r#"SELECT c.id, c.post_id AS "post_id?", u.username AS "other_username?",
                          c.body, c.created_at
                   FROM comments c JOIN posts p ON p.id = c.post_id
                   JOIN users u ON u.id = p.author_id
                   WHERE c.author_id = $1 AND c.deleted_at IS NULL AND p.deleted_at IS NULL
                     AND ($2::timestamptz IS NULL OR c.created_at < $2)
                   ORDER BY c.created_at DESC LIMIT $3"#,
                me,
                before,
                n
            )
            .fetch_all(&state.db)
            .await?
        }
        Kind::Likes => {
            sqlx::query_as!(
                Row,
                r#"SELECT l.post_id AS id, l.post_id AS "post_id?",
                          u.username AS "other_username?", p.body, l.created_at
                   FROM likes l JOIN posts p ON p.id = l.post_id
                   JOIN users u ON u.id = p.author_id
                   WHERE l.user_id = $1 AND p.deleted_at IS NULL
                     AND ($2::timestamptz IS NULL OR l.created_at < $2)
                   ORDER BY l.created_at DESC LIMIT $3"#,
                me,
                before,
                n
            )
            .fetch_all(&state.db)
            .await?
        }
        Kind::Scraps => {
            sqlx::query_as!(
                Row,
                r#"SELECT s.id, NULL::uuid AS "post_id?", u.username AS "other_username?",
                          s.body, s.created_at
                   FROM scraps s JOIN users u ON u.id = s.recipient_id
                   WHERE s.author_id = $1
                     AND ($2::timestamptz IS NULL OR s.created_at < $2)
                   ORDER BY s.created_at DESC LIMIT $3"#,
                me,
                before,
                n
            )
            .fetch_all(&state.db)
            .await?
        }
        Kind::Testimonials => {
            sqlx::query_as!(
                Row,
                r#"SELECT t.id, NULL::uuid AS "post_id?", u.username AS "other_username?",
                          t.body, t.created_at
                   FROM testimonials t JOIN users u ON u.id = t.recipient_id
                   WHERE t.author_id = $1
                     AND ($2::timestamptz IS NULL OR t.created_at < $2)
                   ORDER BY t.created_at DESC LIMIT $3"#,
                me,
                before,
                n
            )
            .fetch_all(&state.db)
            .await?
        }
    };
    let more = rows.len() as i64 > limit;
    let mut items: Vec<HistoryItem> = rows
        .into_iter()
        .take(usize::try_from(limit).unwrap_or(30))
        .map(|r| HistoryItem {
            id: r.id,
            post_id: r.post_id,
            other_username: r.other_username,
            body: excerpt(&r.body),
            created_at: r.created_at,
        })
        .collect();
    items.shrink_to_fit();
    let next_cursor = if more {
        items.last().map(|i| i.created_at)
    } else {
        None
    };
    Ok(Json(HistoryPage { items, next_cursor }))
}

#[derive(Debug, Deserialize)]
pub struct DeleteRequest {
    pub kind: Kind,
    pub ids: Vec<Uuid>,
}

#[derive(Debug, Serialize)]
pub struct DeleteResult {
    pub deleted: u64,
}

/// POST /v1/me/history/delete `{kind, ids}` — apaga (ou descurte) itens meus.
/// Ids que não são meus são ignorados.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<DeleteRequest>,
) -> AppResult<Json<DeleteResult>> {
    if req.ids.is_empty() || req.ids.len() > MAX_DELETE {
        return Err(AppError::Validation("invalid_ids"));
    }
    let me = user.user_id;
    let ids = &req.ids;
    let deleted = match req.kind {
        Kind::Posts => {
            // Mesmo efeito de apagar um por um: some o texto e as fotos.
            let gone = sqlx::query_scalar!(
                "UPDATE posts SET deleted_at = now(), body = '[removido]'
                 WHERE id = ANY($2) AND author_id = $1 AND deleted_at IS NULL
                 RETURNING id",
                me,
                ids
            )
            .fetch_all(&state.db)
            .await?;
            for id in &gone {
                photos::delete_post_media(&state, *id).await?;
            }
            gone.len() as u64
        }
        Kind::Comments => sqlx::query!(
            "UPDATE comments SET deleted_at = now(), body = '[removido]'
             WHERE id = ANY($2) AND author_id = $1 AND deleted_at IS NULL",
            me,
            ids
        )
        .execute(&state.db)
        .await?
        .rows_affected(),
        Kind::Likes => sqlx::query!(
            "DELETE FROM likes WHERE user_id = $1 AND post_id = ANY($2)",
            me,
            ids
        )
        .execute(&state.db)
        .await?
        .rows_affected(),
        Kind::Scraps => sqlx::query!(
            "DELETE FROM scraps WHERE author_id = $1 AND id = ANY($2)",
            me,
            ids
        )
        .execute(&state.db)
        .await?
        .rows_affected(),
        Kind::Testimonials => sqlx::query!(
            "DELETE FROM testimonials WHERE author_id = $1 AND id = ANY($2)",
            me,
            ids
        )
        .execute(&state.db)
        .await?
        .rows_affected(),
    };
    Ok(Json(DeleteResult { deleted }))
}

#[derive(Debug, Serialize)]
pub struct ExportLink {
    /// Caminho relativo à API, ex.: `/export/abc…`. Vale 10 min, uma vez.
    pub url: String,
    #[serde(with = "time::serde::rfc3339")]
    pub expires_at: OffsetDateTime,
}

/// POST /v1/me/export — cria um link de download dos meus dados. O link não
/// leva o token de sessão (abre no navegador do aparelho).
pub async fn create_export(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<(StatusCode, Json<ExportLink>)> {
    let token = crypto::new_session_token();
    let expires_at = OffsetDateTime::now_utc() + Duration::minutes(EXPORT_TTL_MINUTES);
    sqlx::query!(
        "DELETE FROM data_exports WHERE user_id = $1 OR expires_at < now()",
        user.user_id
    )
    .execute(&state.db)
    .await?;
    sqlx::query!(
        "INSERT INTO data_exports (token_hash, user_id, expires_at) VALUES ($1, $2, $3)",
        crypto::sha256(&token),
        user.user_id,
        expires_at
    )
    .execute(&state.db)
    .await?;
    Ok((
        StatusCode::CREATED,
        Json(ExportLink {
            url: format!("/export/{token}"),
            expires_at,
        }),
    ))
}

/// GET /export/{token} — o arquivo JSON com os meus dados (uso único).
pub async fn download_export(
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> AppResult<impl IntoResponse> {
    if token.len() > 128 {
        return Err(AppError::NotFound);
    }
    let user_id = sqlx::query_scalar!(
        "DELETE FROM data_exports WHERE token_hash = $1 AND expires_at > now()
         RETURNING user_id",
        crypto::sha256(&token)
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    let (username, json) = export_json(&state, user_id).await?;
    let date = OffsetDateTime::now_utc().date();
    let disposition = format!("attachment; filename=\"humannet-{username}-{date}.json\"");
    Ok((
        [
            (
                header::CONTENT_TYPE,
                "application/json; charset=utf-8".to_owned(),
            ),
            (header::CONTENT_DISPOSITION, disposition),
            (header::CACHE_CONTROL, "no-store".to_owned()),
        ],
        json,
    ))
}

/// Monta o JSON no próprio Postgres. CPF não entra (só guardamos um código
/// irreversível); senha e sessões também não.
async fn export_json(state: &AppState, user_id: Uuid) -> AppResult<(String, String)> {
    let r = sqlx::query!(
        r#"
        SELECT u.username,
        json_build_object(
          'formato', 'HumanNet — exportação de dados (LGPD art. 18)',
          'gerado_em', now(),
          'conta', json_build_object(
            'usuario', u.username, 'email', u.email, 'nome', u.display_name,
            'bio', u.bio, 'cidade_natal', u.hometown, 'cidade', u.city,
            'escola', u.school, 'criada_em', u.created_at,
            'termos_aceitos_versao', u.terms_version,
            'termos_aceitos_em', u.terms_accepted_at),
          'posts', (SELECT coalesce(json_agg(json_build_object(
              'id', p.id, 'texto', p.body, 'temas', p.topics, 'hashtags', p.hashtags,
              'fotos', (SELECT count(*) FROM post_media pm WHERE pm.post_id = p.id),
              'tem_area_aproximada', p.cell_lat IS NOT NULL,
              'criado_em', p.created_at, 'editado_em', p.edited_at)
              ORDER BY p.created_at), '[]')
            FROM posts p WHERE p.author_id = u.id AND p.deleted_at IS NULL),
          'comentarios', (SELECT coalesce(json_agg(json_build_object(
              'id', c.id, 'post', c.post_id, 'texto', c.body, 'criado_em', c.created_at)
              ORDER BY c.created_at), '[]')
            FROM comments c WHERE c.author_id = u.id AND c.deleted_at IS NULL),
          'curtidas', (SELECT coalesce(json_agg(json_build_object(
              'post', l.post_id, 'em', l.created_at) ORDER BY l.created_at), '[]')
            FROM likes l WHERE l.user_id = u.id),
          'amigos', (SELECT coalesce(json_agg(json_build_object(
              'usuario', f2.username, 'desde', f.created_at) ORDER BY f.created_at), '[]')
            FROM friends f JOIN users f2 ON f2.id = f.friend_id WHERE f.user_id = u.id),
          'recados_escritos', (SELECT coalesce(json_agg(json_build_object(
              'para', r2.username, 'texto', s.body, 'em', s.created_at)
              ORDER BY s.created_at), '[]')
            FROM scraps s JOIN users r2 ON r2.id = s.recipient_id WHERE s.author_id = u.id),
          'recados_recebidos', (SELECT coalesce(json_agg(json_build_object(
              'de', a2.username, 'texto', s.body, 'em', s.created_at)
              ORDER BY s.created_at), '[]')
            FROM scraps s JOIN users a2 ON a2.id = s.author_id WHERE s.recipient_id = u.id),
          'depoimentos_escritos', (SELECT coalesce(json_agg(json_build_object(
              'para', r2.username, 'texto', t.body, 'situacao', t.status, 'em', t.created_at)
              ORDER BY t.created_at), '[]')
            FROM testimonials t JOIN users r2 ON r2.id = t.recipient_id
            WHERE t.author_id = u.id),
          'depoimentos_recebidos', (SELECT coalesce(json_agg(json_build_object(
              'de', a2.username, 'texto', t.body, 'situacao', t.status, 'em', t.created_at)
              ORDER BY t.created_at), '[]')
            FROM testimonials t JOIN users a2 ON a2.id = t.author_id
            WHERE t.recipient_id = u.id),
          'mensagens_enviadas', (SELECT coalesce(json_agg(json_build_object(
              'conversa', m.conversation_id, 'texto', m.body, 'em', m.created_at)
              ORDER BY m.created_at), '[]')
            FROM messages m WHERE m.author_id = u.id AND m.deleted_at IS NULL),
          'linha_do_tempo', (SELECT coalesce(json_agg(json_build_object(
              'tipo', e.kind, 'nivel', e.level, 'inicio', e.start_year, 'fim', e.end_year,
              'visibilidade', e.visibility) ORDER BY e.start_year), '[]')
            FROM life_entries e WHERE e.user_id = u.id)
        )::text AS "json!"
        FROM users u WHERE u.id = $1
        "#,
        user_id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    Ok((r.username, r.json))
}

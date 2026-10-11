//! Marcações.
//!
//! - **@menção** no texto de posts e comentários. Cada pessoa escolhe quem pode
//!   mencioná-la (`everyone` por padrão, `friends` ou `nobody`). Bloqueio
//!   impede nos dois sentidos. Quem é mencionado recebe aviso.
//! - **"Com fulano"**: o autor marca amigos no post. A marcação fica pendente
//!   e só aparece depois que a pessoa aprova; ela pode tirar quando quiser.

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
    push::Kind,
    routes::{
        friends::ListDto,
        posts::{AuthorDto, fill_avatars},
        safety::is_blocked_either_way,
    },
};

/// Máximo de pessoas mencionadas ou marcadas por post/comentário.
pub const MAX_PER_ITEM: usize = 10;

/// `@nome` no texto: 3 a 30 de [a-z0-9_], com algo que não seja letra/número
/// antes (evita e-mails). Sem repetidos, até `MAX_PER_ITEM`.
pub fn mentioned_usernames(text: &str) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    let mut out: Vec<String> = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let prev_ok = i == 0 || !(chars[i - 1].is_alphanumeric() || chars[i - 1] == '_');
        if chars[i] == '@' && prev_ok {
            let mut j = i + 1;
            let mut name = String::new();
            while j < chars.len()
                && (chars[j].is_ascii_alphanumeric() || chars[j] == '_')
                && name.len() < 31
            {
                name.push(chars[j].to_ascii_lowercase());
                j += 1;
            }
            if (3..=30).contains(&name.len()) && !out.contains(&name) {
                out.push(name);
                if out.len() == MAX_PER_ITEM {
                    break;
                }
            }
            i = j;
        } else {
            i += 1;
        }
    }
    out
}

/// Grava as menções válidas de um post ou comentário e avisa as pessoas.
/// Menção inválida (não existe, não aceita, bloqueio) é ignorada em silêncio:
/// o texto continua igual.
pub async fn record_mentions(
    state: &AppState,
    actor: Uuid,
    post_id: Uuid,
    comment_id: Option<Uuid>,
    text: &str,
) -> AppResult<()> {
    let names = mentioned_usernames(text);
    if names.is_empty() {
        return Ok(());
    }
    let rows = sqlx::query!(
        r#"
        SELECT u.id, u.mention_policy,
               EXISTS (SELECT 1 FROM friends f WHERE f.user_id = u.id AND f.friend_id = $2)
                 AS "friend!"
        FROM users u
        WHERE u.username = ANY($1) AND u.id <> $2 AND u.suspended_at IS NULL
        "#,
        &names,
        actor
    )
    .fetch_all(&state.db)
    .await?;
    let mut notified = Vec::new();
    for r in rows {
        let allowed = match r.mention_policy.as_str() {
            "everyone" => true,
            "friends" => r.friend,
            _ => false,
        };
        if !allowed || is_blocked_either_way(&state.db, actor, r.id).await? {
            continue;
        }
        sqlx::query!(
            "INSERT INTO mentions (id, user_id, actor_id, post_id, comment_id)
             VALUES ($1, $2, $3, $4, $5)",
            Uuid::now_v7(),
            r.id,
            actor,
            post_id,
            comment_id
        )
        .execute(&state.db)
        .await?;
        notified.push(r.id);
    }
    state
        .push
        .notify(&state.db, actor, notified, Kind::Mention { post: post_id });
    Ok(())
}

/// Confere a lista "com fulano" antes de criar o post: só amigos, sem
/// bloqueio, até `MAX_PER_ITEM`. Devolve os ids.
pub async fn check_tags(
    state: &AppState,
    author: Uuid,
    usernames: &[String],
) -> AppResult<Vec<Uuid>> {
    let mut names: Vec<String> = Vec::new();
    for u in usernames {
        let u = u.trim().trim_start_matches('@').to_ascii_lowercase();
        if !u.is_empty() && !names.contains(&u) {
            names.push(u);
        }
    }
    if names.len() > MAX_PER_ITEM {
        return Err(AppError::Validation("too_many_tags"));
    }
    if names.is_empty() {
        return Ok(Vec::new());
    }
    let ids = sqlx::query_scalar!(
        r#"SELECT u.id FROM users u
           JOIN friends f ON f.friend_id = u.id AND f.user_id = $2
           WHERE u.username = ANY($1) AND u.suspended_at IS NULL"#,
        &names,
        author
    )
    .fetch_all(&state.db)
    .await?;
    if ids.len() != names.len() {
        return Err(AppError::Validation("tag_not_friend"));
    }
    Ok(ids)
}

/// Grava as marcações (pendentes) e avisa quem foi marcado.
pub async fn add_tags(
    state: &AppState,
    author: Uuid,
    post_id: Uuid,
    ids: &[Uuid],
) -> AppResult<()> {
    if ids.is_empty() {
        return Ok(());
    }
    sqlx::query!(
        "INSERT INTO post_tags (post_id, user_id)
         SELECT $1, unnest($2::uuid[]) ON CONFLICT DO NOTHING",
        post_id,
        ids
    )
    .execute(&state.db)
    .await?;
    state
        .push
        .notify(&state.db, author, ids.to_vec(), Kind::Tag { post: post_id });
    Ok(())
}

/// Marcação mostrada no post.
#[derive(Debug, Clone, Serialize)]
pub struct TagDto {
    pub username: String,
    pub display_name: Option<String>,
    /// Ainda não aprovada (só o autor do post e a própria pessoa veem).
    pub pending: bool,
}

/// Marcações de vários posts, como `viewer` pode vê-las.
pub async fn for_posts(
    state: &AppState,
    viewer: Uuid,
    ids: &[Uuid],
) -> sqlx::Result<Vec<(Uuid, TagDto)>> {
    let rows = sqlx::query!(
        r#"
        SELECT t.post_id, u.username, u.display_name, (t.status = 'pending') AS "pending!"
        FROM post_tags t JOIN users u ON u.id = t.user_id
        JOIN posts p ON p.id = t.post_id
        WHERE t.post_id = ANY($1)
          AND (t.status = 'approved' OR p.author_id = $2 OR t.user_id = $2)
          AND NOT EXISTS (SELECT 1 FROM blocks b
                WHERE (b.blocker_id = $2 AND b.blocked_id = u.id)
                   OR (b.blocker_id = u.id AND b.blocked_id = $2))
        ORDER BY t.created_at
        "#,
        ids,
        viewer
    )
    .fetch_all(&state.db)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| {
            (
                r.post_id,
                TagDto {
                    username: r.username,
                    display_name: r.display_name,
                    pending: r.pending,
                },
            )
        })
        .collect())
}

#[derive(Debug, Serialize)]
pub struct PendingTag {
    pub post_id: Uuid,
    pub author: AuthorDto,
    pub excerpt: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
}

/// GET /v1/me/tags/pending — marcações esperando minha aprovação.
pub async fn pending(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<PendingTag>>> {
    let rows = sqlx::query!(
        r#"
        SELECT t.post_id, t.created_at, p.body, u.id, u.username, u.display_name
        FROM post_tags t JOIN posts p ON p.id = t.post_id AND p.deleted_at IS NULL
        JOIN users u ON u.id = p.author_id
        WHERE t.user_id = $1 AND t.status = 'pending'
          AND NOT EXISTS (SELECT 1 FROM blocks b
                WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
                   OR (b.blocker_id = u.id AND b.blocked_id = $1))
        ORDER BY t.created_at DESC
        LIMIT 100
        "#,
        user.user_id
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<PendingTag> = rows
        .into_iter()
        .map(|r| PendingTag {
            post_id: r.post_id,
            author: AuthorDto {
                id: r.id,
                username: r.username,
                display_name: r.display_name,
                avatar_url: None,
            },
            excerpt: r.body.chars().take(140).collect(),
            created_at: r.created_at,
        })
        .collect();
    fill_avatars(&state, items.iter_mut().map(|t| &mut t.author)).await?;
    Ok(Json(ListDto { items }))
}

/// POST /v1/posts/{id}/tag/approve — aceito aparecer neste post.
pub async fn approve(
    State(state): State<AppState>,
    user: AuthUser,
    Path(post_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let n = sqlx::query!(
        "UPDATE post_tags SET status = 'approved', approved_at = now()
         WHERE post_id = $1 AND user_id = $2 AND status = 'pending'",
        post_id,
        user.user_id
    )
    .execute(&state.db)
    .await?
    .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound);
    }
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/posts/{id}/tags/{username} — a própria pessoa sai da marcação
/// (recusar ou tirar depois) ou o autor do post a retira.
pub async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path((post_id, username)): Path<(Uuid, String)>,
) -> AppResult<StatusCode> {
    let n = sqlx::query!(
        r#"
        DELETE FROM post_tags t USING users u, posts p
        WHERE t.post_id = $1 AND u.username = $2 AND t.user_id = u.id AND p.id = t.post_id
          AND (t.user_id = $3 OR p.author_id = $3)
        "#,
        post_id,
        username.trim().to_ascii_lowercase(),
        user.user_id
    )
    .execute(&state.db)
    .await?
    .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound);
    }
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MentionPolicy {
    /// everyone | friends | nobody
    pub policy: String,
}

/// GET /v1/me/mentions — quem pode me mencionar.
pub async fn get_policy(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<MentionPolicy>> {
    let policy = sqlx::query_scalar!(
        "SELECT mention_policy FROM users WHERE id = $1",
        user.user_id
    )
    .fetch_one(&state.db)
    .await?;
    Ok(Json(MentionPolicy { policy }))
}

/// PUT /v1/me/mentions `{policy}`.
pub async fn set_policy(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<MentionPolicy>,
) -> AppResult<Json<MentionPolicy>> {
    if !matches!(req.policy.as_str(), "everyone" | "friends" | "nobody") {
        return Err(AppError::Validation("invalid_mention_policy"));
    }
    sqlx::query!(
        "UPDATE users SET mention_policy = $2 WHERE id = $1",
        user.user_id,
        req.policy
    )
    .execute(&state.db)
    .await?;
    Ok(Json(req))
}

#[derive(Debug, Deserialize)]
pub struct SuggestQuery {
    pub q: String,
    /// `true`: só amigos (para "com fulano").
    #[serde(default)]
    pub friends_only: bool,
}

/// GET /v1/mentions/suggest?q=gui — até 8 nomes que começam com `q`:
/// amigos primeiro, depois quem aceita menção de todos. Sem bloqueados.
pub async fn suggest(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<SuggestQuery>,
) -> AppResult<Json<ListDto<AuthorDto>>> {
    let prefix: String =
        q.q.trim()
            .trim_start_matches('@')
            .to_ascii_lowercase()
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '_')
            .take(30)
            .collect();
    let rows = sqlx::query!(
        r#"
        SELECT u.id, u.username, u.display_name,
               EXISTS (SELECT 1 FROM friends f WHERE f.user_id = $1 AND f.friend_id = u.id)
                 AS "friend!"
        FROM users u
        WHERE u.id <> $1 AND u.suspended_at IS NULL
          AND (u.username LIKE $2 || '%' OR lower(coalesce(u.display_name, '')) LIKE $2 || '%')
          AND (EXISTS (SELECT 1 FROM friends f WHERE f.user_id = $1 AND f.friend_id = u.id)
               OR (NOT $3 AND u.mention_policy = 'everyone'))
          AND NOT EXISTS (SELECT 1 FROM blocks b
                WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
                   OR (b.blocker_id = u.id AND b.blocked_id = $1))
        ORDER BY 4 DESC, u.username
        LIMIT 8
        "#,
        user.user_id,
        prefix,
        q.friends_only
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<AuthorDto> = rows
        .into_iter()
        .map(|r| AuthorDto {
            id: r.id,
            username: r.username,
            display_name: r.display_name,
            avatar_url: None,
        })
        .collect();
    fill_avatars(&state, items.iter_mut()).await?;
    Ok(Json(ListDto { items }))
}

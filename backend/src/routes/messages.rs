//! Mensagens diretas: conversa 1:1 e em grupo, só entre amigos (R9).
//!
//! - 1:1: só com amigos; uma conversa por par. Bloqueio impede enviar.
//! - Grupo: quem cria adiciona amigos seus (até 50 pessoas). Qualquer um sai.
//! - Sem "visto por último" nem confirmação de leitura para os outros: só o
//!   próprio "lido até" (para as bolinhas), anti-cobrança.
//! - Mensagem de quem tem bloqueio com quem lê não aparece.

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
    routes::{
        friends::{self, ListDto},
        pagination::{Page, PageQuery},
        posts::{AuthorDto, fill_avatars},
        profiles::{user_id_by_username, visible_user_id},
        safety::is_blocked_either_way,
    },
    validation,
};

const MAX_GROUP: usize = 50;
const MESSAGE_MAX: usize = 4000;
const MESSAGES_PER_MINUTE: i64 = 30;

#[derive(Debug, Serialize)]
pub struct ConversationDto {
    pub id: Uuid,
    /// direct | group
    pub kind: String,
    /// Grupo: nome. 1:1: nome da outra pessoa.
    pub title: String,
    /// 1:1: a outra pessoa.
    pub other: Option<AuthorDto>,
    pub member_count: i64,
    pub last_message: Option<String>,
    #[serde(with = "time::serde::rfc3339")]
    pub last_message_at: OffsetDateTime,
    pub unread: i64,
    pub is_owner: bool,
}

#[derive(Debug, Serialize)]
pub struct MessageDto {
    pub id: Uuid,
    pub author: Option<AuthorDto>,
    pub body: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    pub mine: bool,
    pub deleted: bool,
}

/// Confere que sou membro. NotFound se não (não revela que existe).
async fn membership(state: &AppState, conv: Uuid, me: Uuid) -> AppResult<(String, String)> {
    let r = sqlx::query!(
        "SELECT c.kind, m.role FROM conversations c
         JOIN conversation_members m ON m.conversation_id = c.id AND m.user_id = $2
         WHERE c.id = $1",
        conv,
        me
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    Ok((r.kind, r.role))
}

async fn conversations_for(
    state: &AppState,
    me: Uuid,
    only: Option<Uuid>,
) -> AppResult<Vec<ConversationDto>> {
    let rows = sqlx::query!(
        r#"
        SELECT c.id, c.kind, c.title, c.last_message_at, m.role,
               (SELECT count(*) FROM conversation_members x WHERE x.conversation_id = c.id) AS "member_count!",
               (SELECT count(*) FROM messages g
                 WHERE g.conversation_id = c.id AND g.created_at > m.last_read_at
                   AND g.author_id IS DISTINCT FROM $1 AND g.deleted_at IS NULL
                   AND NOT EXISTS (SELECT 1 FROM blocks b
                     WHERE (b.blocker_id = $1 AND b.blocked_id = g.author_id)
                        OR (b.blocker_id = g.author_id AND b.blocked_id = $1))) AS "unread!",
               (SELECT g.body FROM messages g
                 WHERE g.conversation_id = c.id AND g.deleted_at IS NULL
                   AND NOT EXISTS (SELECT 1 FROM blocks b
                     WHERE (b.blocker_id = $1 AND b.blocked_id = g.author_id)
                        OR (b.blocker_id = g.author_id AND b.blocked_id = $1))
                 ORDER BY g.id DESC LIMIT 1) AS last_body,
               o.id AS "other_id?", o.username AS "other_username?",
               o.display_name AS other_display_name
        FROM conversations c
        JOIN conversation_members m ON m.conversation_id = c.id AND m.user_id = $1
        LEFT JOIN LATERAL (
          SELECT u.id, u.username, u.display_name FROM conversation_members om
          JOIN users u ON u.id = om.user_id
          WHERE c.kind = 'direct' AND om.conversation_id = c.id AND om.user_id <> $1
          LIMIT 1
        ) o ON true
        WHERE ($2::uuid IS NULL OR c.id = $2)
        ORDER BY c.last_message_at DESC
        LIMIT 200
        "#,
        me,
        only
    )
    .fetch_all(&state.db)
    .await?;
    let mut out: Vec<ConversationDto> = rows
        .into_iter()
        .map(|r| {
            let other = match (r.other_id, r.other_username) {
                (Some(id), Some(username)) => Some(AuthorDto {
                    id,
                    username,
                    display_name: r.other_display_name,
                    avatar_url: None,
                }),
                _ => None,
            };
            let title = match (&other, r.kind.as_str()) {
                (Some(o), "direct") => o.display_name.clone().unwrap_or(format!("@{}", o.username)),
                (None, "direct") => "Conversa".to_owned(),
                _ => r.title,
            };
            ConversationDto {
                id: r.id,
                kind: r.kind,
                title,
                other,
                member_count: r.member_count,
                last_message: r.last_body.map(|b| b.chars().take(120).collect()),
                last_message_at: r.last_message_at,
                unread: r.unread,
                is_owner: r.role == "owner",
            }
        })
        .collect();
    fill_avatars(state, out.iter_mut().filter_map(|c| c.other.as_mut())).await?;
    Ok(out)
}

/// GET /v1/conversations — mais recentes primeiro.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<ConversationDto>>> {
    Ok(Json(ListDto {
        items: conversations_for(&state, user.user_id, None).await?,
    }))
}

async fn one(state: &AppState, me: Uuid, id: Uuid) -> AppResult<ConversationDto> {
    conversations_for(state, me, Some(id))
        .await?
        .pop()
        .ok_or(AppError::NotFound)
}

/// GET /v1/conversations/{id}
pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ConversationDto>> {
    Ok(Json(one(&state, user.user_id, id).await?))
}

#[derive(Debug, Deserialize)]
pub struct DirectReq {
    pub username: String,
}

/// POST /v1/conversations/direct `{username}` — abre (ou cria) a conversa 1:1.
pub async fn direct(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<DirectReq>,
) -> AppResult<Json<ConversationDto>> {
    let me = user.user_id;
    let other = visible_user_id(&state, me, &req.username).await?;
    if other == me {
        return Err(AppError::Validation("cannot_message_self"));
    }
    if !friends::can_see_content(&state.db, me, other).await? {
        return Err(AppError::Forbidden);
    }
    let (a, b) = if me < other { (me, other) } else { (other, me) };
    let key = format!("{a}:{b}");
    let mut tx = state.db.begin().await?;
    let id = sqlx::query_scalar!(
        r#"
        INSERT INTO conversations (id, kind, direct_key, created_by)
        VALUES ($1, 'direct', $2, $3)
        ON CONFLICT (direct_key) DO UPDATE SET direct_key = EXCLUDED.direct_key
        RETURNING id
        "#,
        Uuid::now_v7(),
        key,
        me
    )
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query!(
        "INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)
         ON CONFLICT DO NOTHING",
        id,
        me,
        other
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(one(&state, me, id).await?))
}

#[derive(Debug, Deserialize)]
pub struct GroupReq {
    pub title: String,
    pub usernames: Vec<String>,
}

/// Ids de amigos meus, a partir dos @. Erro se algum não for amigo.
async fn friend_ids(state: &AppState, me: Uuid, usernames: &[String]) -> AppResult<Vec<Uuid>> {
    let mut ids = Vec::new();
    for u in usernames {
        let id = user_id_by_username(state, u).await?;
        if id == me {
            continue;
        }
        if !friends::can_see_content(&state.db, me, id).await? {
            return Err(AppError::Validation("not_friends"));
        }
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    Ok(ids)
}

/// POST /v1/conversations `{title, usernames}` — grupo com amigos.
pub async fn create_group(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<GroupReq>,
) -> AppResult<(StatusCode, Json<ConversationDto>)> {
    let me = user.user_id;
    let title = validation::line(&req.title, 1, 60, "invalid_group_title")?;
    let ids = friend_ids(&state, me, &req.usernames).await?;
    if ids.is_empty() {
        return Err(AppError::Validation("group_needs_members"));
    }
    if ids.len() + 1 > MAX_GROUP {
        return Err(AppError::Validation("group_too_big"));
    }
    let id = Uuid::now_v7();
    let mut tx = state.db.begin().await?;
    sqlx::query!(
        "INSERT INTO conversations (id, kind, title, created_by) VALUES ($1, 'group', $2, $3)",
        id,
        title,
        me
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, 'owner')",
        id,
        me
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "INSERT INTO conversation_members (conversation_id, user_id)
         SELECT $1, unnest($2::uuid[])",
        id,
        &ids
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(one(&state, me, id).await?)))
}

#[derive(Debug, Deserialize)]
pub struct AddMembers {
    pub usernames: Vec<String>,
}

/// POST /v1/conversations/{id}/members `{usernames}` — quem criou o grupo
/// adiciona amigos seus.
pub async fn add_members(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<AddMembers>,
) -> AppResult<Json<ConversationDto>> {
    let me = user.user_id;
    let (kind, role) = membership(&state, id, me).await?;
    if kind != "group" || role != "owner" {
        return Err(AppError::Forbidden);
    }
    let ids = friend_ids(&state, me, &req.usernames).await?;
    let current = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM conversation_members WHERE conversation_id = $1"#,
        id
    )
    .fetch_one(&state.db)
    .await?;
    if usize::try_from(current).unwrap_or(0) + ids.len() > MAX_GROUP {
        return Err(AppError::Validation("group_too_big"));
    }
    sqlx::query!(
        "INSERT INTO conversation_members (conversation_id, user_id)
         SELECT $1, unnest($2::uuid[]) ON CONFLICT DO NOTHING",
        id,
        &ids
    )
    .execute(&state.db)
    .await?;
    Ok(Json(one(&state, me, id).await?))
}

#[derive(Debug, Serialize)]
pub struct MemberItem {
    #[serde(flatten)]
    pub user: AuthorDto,
    pub is_owner: bool,
}

/// GET /v1/conversations/{id}/members
pub async fn members(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ListDto<MemberItem>>> {
    membership(&state, id, user.user_id).await?;
    let rows = sqlx::query!(
        "SELECT u.id, u.username, u.display_name, m.role FROM conversation_members m
         JOIN users u ON u.id = m.user_id WHERE m.conversation_id = $1
         ORDER BY m.role DESC, lower(u.username)",
        id
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<MemberItem> = rows
        .into_iter()
        .map(|r| MemberItem {
            user: AuthorDto {
                id: r.id,
                username: r.username,
                display_name: r.display_name,
                avatar_url: None,
            },
            is_owner: r.role == "owner",
        })
        .collect();
    fill_avatars(&state, items.iter_mut().map(|m| &mut m.user)).await?;
    Ok(Json(ListDto { items }))
}

/// DELETE /v1/conversations/{id}/members/me — sair do grupo. Se quem criou
/// sai, o membro mais antigo passa a administrar.
pub async fn leave(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let me = user.user_id;
    let (kind, role) = membership(&state, id, me).await?;
    if kind != "group" {
        return Err(AppError::Validation("cannot_leave_direct"));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query!(
        "DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        id,
        me
    )
    .execute(&mut *tx)
    .await?;
    if role == "owner" {
        sqlx::query!(
            "UPDATE conversation_members SET role = 'owner'
             WHERE conversation_id = $1 AND user_id = (
               SELECT user_id FROM conversation_members WHERE conversation_id = $1
               ORDER BY joined_at LIMIT 1)",
            id
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
pub struct MessagesQuery {
    /// Mais antigas que este id (rolar para cima).
    pub before: Option<Uuid>,
    /// Mais novas que este id (buscar novidades).
    pub after: Option<Uuid>,
    pub limit: Option<i64>,
}

/// GET /v1/conversations/{id}/messages?before=|after= — devolve em ordem
/// cronológica. `next_cursor` = id da mais antiga, se houver mais para trás.
pub async fn messages(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Query(q): Query<MessagesQuery>,
) -> AppResult<Json<Page<MessageDto>>> {
    let me = user.user_id;
    membership(&state, id, me).await?;
    let limit = PageQuery {
        before: None,
        limit: q.limit,
    }
    .limit();
    let rows = sqlx::query!(
        r#"
        SELECT g.id, g.body, g.created_at, g.deleted_at,
               u.id AS "author_id?", u.username AS "username?", u.display_name
        FROM messages g LEFT JOIN users u ON u.id = g.author_id
        WHERE g.conversation_id = $1
          AND ($2::uuid IS NULL OR g.id < $2)
          AND ($3::uuid IS NULL OR g.id > $3)
          AND NOT EXISTS (SELECT 1 FROM blocks b
            WHERE (b.blocker_id = $4 AND b.blocked_id = g.author_id)
               OR (b.blocker_id = g.author_id AND b.blocked_id = $4))
        ORDER BY CASE WHEN $3::uuid IS NULL THEN g.id END DESC,
                 CASE WHEN $3::uuid IS NOT NULL THEN g.id END ASC
        LIMIT $5
        "#,
        id,
        q.before,
        q.after,
        me,
        limit + 1
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<MessageDto> = rows
        .into_iter()
        .map(|r| MessageDto {
            id: r.id,
            mine: r.author_id == Some(me),
            deleted: r.deleted_at.is_some(),
            author: match (r.author_id, r.username) {
                (Some(id), Some(username)) => Some(AuthorDto {
                    id,
                    username,
                    display_name: r.display_name,
                    avatar_url: None,
                }),
                _ => None,
            },
            body: if r.deleted_at.is_some() {
                String::new()
            } else {
                r.body
            },
            created_at: r.created_at,
        })
        .collect();
    let has_more = items.len() > usize::try_from(limit).unwrap_or(0);
    items.truncate(usize::try_from(limit).unwrap_or(0));
    if q.after.is_none() {
        items.reverse();
    }
    fill_avatars(&state, items.iter_mut().filter_map(|m| m.author.as_mut())).await?;
    let next_cursor = if has_more && q.after.is_none() {
        items.first().map(|m| m.id)
    } else {
        None
    };
    Ok(Json(Page { items, next_cursor }))
}

#[derive(Debug, Deserialize)]
pub struct SendReq {
    pub body: String,
}

/// POST /v1/conversations/{id}/messages `{body}`
pub async fn send(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<SendReq>,
) -> AppResult<(StatusCode, Json<MessageDto>)> {
    let me = user.user_id;
    let (kind, _) = membership(&state, id, me).await?;
    let body = validation::long_text(&req.body, MESSAGE_MAX, "invalid_message")?;
    if body.is_empty() {
        return Err(AppError::Validation("invalid_message"));
    }
    if kind == "direct" {
        let other = sqlx::query_scalar!(
            "SELECT user_id FROM conversation_members WHERE conversation_id = $1 AND user_id <> $2",
            id,
            me
        )
        .fetch_optional(&state.db)
        .await?;
        if let Some(other) = other
            && (is_blocked_either_way(&state.db, me, other).await?
                || !friends::can_see_content(&state.db, me, other).await?)
        {
            return Err(AppError::Forbidden);
        }
    }
    let recent = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM messages
           WHERE author_id = $1 AND created_at > now() - interval '1 minute'"#,
        me
    )
    .fetch_one(&state.db)
    .await?;
    if recent >= MESSAGES_PER_MINUTE {
        return Err(AppError::LimitReached("message_limit"));
    }
    let mut tx = state.db.begin().await?;
    let r = sqlx::query!(
        r#"
        WITH g AS (
          INSERT INTO messages (id, conversation_id, author_id, body) VALUES ($1, $2, $3, $4)
          RETURNING id, body, created_at
        )
        SELECT g.id, g.body, g.created_at, u.username, u.display_name
        FROM g JOIN users u ON u.id = $3
        "#,
        Uuid::now_v7(),
        id,
        me,
        body
    )
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query!(
        "UPDATE conversations SET last_message_at = $2 WHERE id = $1",
        id,
        r.created_at
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "UPDATE conversation_members SET last_read_at = $3
         WHERE conversation_id = $1 AND user_id = $2",
        id,
        me,
        r.created_at
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    let mut dto = MessageDto {
        id: r.id,
        author: Some(AuthorDto {
            id: me,
            username: r.username,
            display_name: r.display_name,
            avatar_url: None,
        }),
        body: r.body,
        created_at: r.created_at,
        mine: true,
        deleted: false,
    };
    fill_avatars(&state, dto.author.as_mut()).await?;
    Ok((StatusCode::CREATED, Json(dto)))
}

/// POST /v1/conversations/{id}/read — marca tudo como lido (só para mim).
pub async fn mark_read(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    membership(&state, id, user.user_id).await?;
    sqlx::query!(
        "UPDATE conversation_members SET last_read_at = now()
         WHERE conversation_id = $1 AND user_id = $2",
        id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /v1/messages/{id} — quem escreveu apaga (o texto some para todos).
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let n = sqlx::query!(
        "UPDATE messages SET deleted_at = now(), body = ''
         WHERE id = $1 AND author_id = $2 AND deleted_at IS NULL",
        id,
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

/// Conversas com mensagem nova (para a bolinha).
pub async fn unread_conversations(state: &AppState, me: Uuid) -> sqlx::Result<i64> {
    sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!" FROM conversation_members m
        WHERE m.user_id = $1 AND EXISTS (
          SELECT 1 FROM messages g
          WHERE g.conversation_id = m.conversation_id AND g.created_at > m.last_read_at
            AND g.author_id IS DISTINCT FROM $1 AND g.deleted_at IS NULL
            AND NOT EXISTS (SELECT 1 FROM blocks b
              WHERE (b.blocker_id = $1 AND b.blocked_id = g.author_id)
                 OR (b.blocker_id = g.author_id AND b.blocked_id = $1)))
        "#,
        me
    )
    .fetch_one(&state.db)
    .await
}

//! Amizade mútua (ADR-0006): pedir, aceitar, recusar, cancelar, desfazer.
//!
//! Invariantes:
//! - amizade é simétrica (uma linha por par, `user_a < user_b`);
//! - nunca há pedido pendente entre amigos;
//! - pedidos cruzados (A→B e B→A) viram amizade.

use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use serde::Serialize;
use sqlx::{PgConnection, PgExecutor};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    routes::{
        posts::AuthorDto,
        profiles::{user_id_by_username, visible_user_id},
    },
};

/// Máximo de pedidos enviados ainda pendentes (anti-spam).
pub const MAX_PENDING_SENT: i64 = 50;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Relation {
    #[serde(rename = "self")]
    Myself,
    None,
    Friends,
    RequestSent,
    RequestReceived,
}

fn ordered(a: Uuid, b: Uuid) -> (Uuid, Uuid) {
    if a < b { (a, b) } else { (b, a) }
}

/// Relação de `viewer` com `other`.
pub async fn relation<'e>(
    db: impl PgExecutor<'e>,
    viewer: Uuid,
    other: Uuid,
) -> sqlx::Result<Relation> {
    if viewer == other {
        return Ok(Relation::Myself);
    }
    let (a, b) = ordered(viewer, other);
    let row = sqlx::query!(
        r#"
        SELECT
          EXISTS (SELECT 1 FROM friendships WHERE user_a = $1 AND user_b = $2) AS "friends!",
          EXISTS (SELECT 1 FROM friend_requests WHERE from_id = $3 AND to_id = $4) AS "sent!",
          EXISTS (SELECT 1 FROM friend_requests WHERE from_id = $4 AND to_id = $3) AS "received!"
        "#,
        a,
        b,
        viewer,
        other
    )
    .fetch_one(db)
    .await?;
    Ok(if row.friends {
        Relation::Friends
    } else if row.sent {
        Relation::RequestSent
    } else if row.received {
        Relation::RequestReceived
    } else {
        Relation::None
    })
}

/// `true` se `viewer` pode ver o conteúdo de `owner` (é o próprio ou amigo).
pub async fn can_see_content<'e>(
    db: impl PgExecutor<'e>,
    viewer: Uuid,
    owner: Uuid,
) -> sqlx::Result<bool> {
    if viewer == owner {
        return Ok(true);
    }
    let (a, b) = ordered(viewer, owner);
    sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM friendships WHERE user_a = $1 AND user_b = $2) AS "e!""#,
        a,
        b
    )
    .fetch_one(db)
    .await
}

/// Serializa operações sobre o mesmo par (evita corrida em pedidos cruzados).
pub(crate) async fn lock_pair(conn: &mut PgConnection, x: Uuid, y: Uuid) -> sqlx::Result<()> {
    let (a, b) = ordered(x, y);
    sqlx::query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1::text || $2::text, 0))",
        a.to_string(),
        b.to_string()
    )
    .execute(conn)
    .await?;
    Ok(())
}

#[derive(Debug, Serialize)]
pub struct RelationDto {
    pub relation: Relation,
}

/// PUT /v1/users/{username}/friend — pede amizade, ou aceita se o outro já pediu.
/// Idempotente.
pub async fn request_or_accept(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
) -> AppResult<Json<RelationDto>> {
    let me = user.user_id;
    let other = visible_user_id(&state, me, &username).await?;
    if other == me {
        return Err(AppError::Validation("cannot_befriend_self"));
    }

    let mut tx = state.db.begin().await?;
    lock_pair(&mut tx, me, other).await?;

    let current = relation(&mut *tx, me, other).await?;
    let result = match current {
        Relation::Friends | Relation::RequestSent => current,
        Relation::RequestReceived => {
            sqlx::query!(
                "DELETE FROM friend_requests WHERE from_id = $1 AND to_id = $2",
                other,
                me
            )
            .execute(&mut *tx)
            .await?;
            let (a, b) = ordered(me, other);
            sqlx::query!(
                "INSERT INTO friendships (user_a, user_b) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                a,
                b
            )
            .execute(&mut *tx)
            .await?;
            Relation::Friends
        }
        Relation::None => {
            let pending = sqlx::query_scalar!(
                r#"SELECT count(*) AS "n!" FROM friend_requests WHERE from_id = $1"#,
                me
            )
            .fetch_one(&mut *tx)
            .await?;
            if pending >= MAX_PENDING_SENT {
                return Err(AppError::LimitReached("friend_request_limit"));
            }
            sqlx::query!(
                "INSERT INTO friend_requests (from_id, to_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                me,
                other
            )
            .execute(&mut *tx)
            .await?;
            Relation::RequestSent
        }
        Relation::Myself => unreachable!("tratado acima"),
    };
    tx.commit().await?;
    let push = match (current, result) {
        (Relation::RequestReceived, Relation::Friends) => Some(crate::push::Kind::FriendAccepted),
        (Relation::None, Relation::RequestSent) => Some(crate::push::Kind::FriendRequest),
        _ => None,
    };
    if let Some(kind) = push {
        state.push.notify(&state.db, me, vec![other], kind);
    }
    Ok(Json(RelationDto { relation: result }))
}

/// DELETE /v1/users/{username}/friend — desfaz amizade, cancela o pedido enviado
/// ou recusa o recebido. Remove tudo entre o par, sem avisar o outro. Idempotente.
pub async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
) -> AppResult<StatusCode> {
    let me = user.user_id;
    let other = user_id_by_username(&state, &username).await?;
    let mut tx = state.db.begin().await?;
    lock_pair(&mut tx, me, other).await?;
    let (a, b) = ordered(me, other);
    sqlx::query!(
        "DELETE FROM friendships WHERE user_a = $1 AND user_b = $2",
        a,
        b
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "DELETE FROM friend_requests WHERE (from_id = $1 AND to_id = $2) OR (from_id = $2 AND to_id = $1)",
        me,
        other
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Serialize)]
pub struct FriendRequestDto {
    pub user: AuthorDto,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Serialize)]
pub struct ListDto<T> {
    pub items: Vec<T>,
}

/// GET /v1/friend-requests — pedidos recebidos, mais recentes primeiro.
pub async fn incoming(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<FriendRequestDto>>> {
    let rows = sqlx::query!(
        r#"
        SELECT u.id, u.username, u.display_name, r.created_at
        FROM friend_requests r JOIN users u ON u.id = r.from_id
        WHERE r.to_id = $1
        ORDER BY r.created_at DESC
        LIMIT 200
        "#,
        user.user_id
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<FriendRequestDto> = rows
        .into_iter()
        .map(|r| FriendRequestDto {
            user: AuthorDto {
                id: r.id,
                username: r.username,
                display_name: r.display_name,
                avatar_url: None,
            },
            created_at: r.created_at,
        })
        .collect();
    crate::routes::posts::fill_avatars(&state, items.iter_mut().map(|r| &mut r.user)).await?;
    Ok(Json(ListDto { items }))
}

/// Amigo na lista, com o status/subnick vigente.
#[derive(Debug, Serialize)]
pub struct FriendDto {
    #[serde(flatten)]
    pub user: AuthorDto,
    pub status: Option<String>,
}

/// GET /v1/friends — meus amigos, em ordem alfabética.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<FriendDto>>> {
    let rows = sqlx::query!(
        r#"
        SELECT u.id AS "id!", u.username AS "username!", u.display_name,
               u.status_text AS "status_text!", u.status_expires_at
        FROM friends f JOIN users u ON u.id = f.friend_id
        WHERE f.user_id = $1
        ORDER BY lower(coalesce(u.display_name, u.username))
        LIMIT 1000
        "#,
        user.user_id
    )
    .fetch_all(&state.db)
    .await?;
    let mut items: Vec<FriendDto> = rows
        .into_iter()
        .map(|r| FriendDto {
            user: AuthorDto {
                id: r.id,
                username: r.username,
                display_name: r.display_name,
                avatar_url: None,
            },
            status: crate::routes::scraps::current_status(r.status_text, r.status_expires_at),
        })
        .collect();
    crate::routes::posts::fill_avatars(&state, items.iter_mut().map(|f| &mut f.user)).await?;
    Ok(Json(ListDto { items }))
}

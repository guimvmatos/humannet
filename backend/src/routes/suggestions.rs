//! "Pessoas que você talvez conheça" (lote 8).
//!
//! Sem caixa-preta (R2): cada sugestão diz por quê. Sinais usados, todos
//! declarados pelas próprias pessoas: amigos em comum, mesma cidade natal,
//! mesma cidade atual, mesma escola. Nada de contatos do celular nem de
//! localização (R5, R7).

use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use serde::Serialize;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    routes::{friends::ListDto, posts::AuthorDto, profiles::visible_user_id},
};

const LIMIT: i64 = 20;

#[derive(Debug, Serialize)]
pub struct SuggestionDto {
    pub user: AuthorDto,
    pub mutual_friends: i64,
    /// Frases prontas para mostrar ("3 amigos em comum", "Também é de Recife").
    pub reasons: Vec<String>,
}

/// GET /v1/me/suggestions
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<SuggestionDto>>> {
    let rows = sqlx::query!(
        r#"
        WITH me AS (
          SELECT lower(hometown) AS hometown, lower(city) AS city, lower(school) AS school
          FROM users WHERE id = $1
        ),
        mutual AS (
          SELECT f2.friend_id AS id, count(*) AS n
          FROM friends f1 JOIN friends f2 ON f2.user_id = f1.friend_id
          WHERE f1.user_id = $1 AND f2.friend_id <> $1
          GROUP BY f2.friend_id
        ),
        cand AS (
          SELECT u.id, u.username, u.display_name, u.hometown, u.city, u.school,
                 coalesce(m.n, 0) AS mutual,
                 (u.hometown <> '' AND lower(u.hometown) = (SELECT hometown FROM me)) AS same_hometown,
                 (u.city <> '' AND lower(u.city) = (SELECT city FROM me)) AS same_city,
                 (u.school <> '' AND lower(u.school) = (SELECT school FROM me)) AS same_school
          FROM users u LEFT JOIN mutual m ON m.id = u.id
          WHERE u.id <> $1 AND u.suspended_at IS NULL
        )
        SELECT c.id, c.username, c.display_name, c.hometown, c.city, c.school,
               c.mutual AS "mutual!", c.same_hometown AS "same_hometown!",
               c.same_city AS "same_city!", c.same_school AS "same_school!"
        FROM cand c
        WHERE (c.mutual > 0 OR c.same_hometown OR c.same_city OR c.same_school)
          AND NOT EXISTS (SELECT 1 FROM friends f WHERE f.user_id = $1 AND f.friend_id = c.id)
          AND NOT EXISTS (SELECT 1 FROM friend_requests r
                WHERE (r.from_id = $1 AND r.to_id = c.id) OR (r.from_id = c.id AND r.to_id = $1))
          AND NOT EXISTS (SELECT 1 FROM blocks b
                WHERE (b.blocker_id = $1 AND b.blocked_id = c.id)
                   OR (b.blocker_id = c.id AND b.blocked_id = $1))
          AND NOT EXISTS (SELECT 1 FROM suggestion_dismissals d
                WHERE d.user_id = $1 AND d.dismissed_id = c.id)
        ORDER BY (c.mutual * 3 + c.same_school::int * 2 + c.same_hometown::int * 2
                  + c.same_city::int) DESC,
                 c.mutual DESC, lower(c.username)
        LIMIT $2
        "#,
        user.user_id,
        LIMIT
    )
    .fetch_all(&state.db)
    .await?;

    let mut items: Vec<SuggestionDto> = rows
        .into_iter()
        .map(|r| {
            let mut reasons = Vec::new();
            match r.mutual {
                0 => {}
                1 => reasons.push("1 amigo em comum".to_owned()),
                n => reasons.push(format!("{n} amigos em comum")),
            }
            if r.same_school {
                reasons.push(format!("Também estudou em {}", r.school));
            }
            if r.same_hometown {
                reasons.push(format!("Também é de {}", r.hometown));
            }
            if r.same_city {
                reasons.push(format!("Também mora em {}", r.city));
            }
            SuggestionDto {
                user: AuthorDto {
                    id: r.id,
                    username: r.username,
                    display_name: r.display_name,
                    avatar_url: None,
                },
                mutual_friends: r.mutual,
                reasons,
            }
        })
        .collect();
    crate::routes::posts::fill_avatars(&state, items.iter_mut().map(|s| &mut s.user)).await?;
    Ok(Json(ListDto { items }))
}

/// POST /v1/me/suggestions/{username}/dismiss — não sugerir mais essa pessoa.
pub async fn dismiss(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
) -> AppResult<StatusCode> {
    let other = visible_user_id(&state, user.user_id, &username).await?;
    if other == user.user_id {
        return Err(AppError::NotFound);
    }
    sqlx::query!(
        "INSERT INTO suggestion_dismissals (user_id, dismissed_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING",
        user.user_id,
        other
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

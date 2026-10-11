//! "Quem visitou meu perfil". Recíproco: quem desliga não vê e não aparece.
//! Só conta abrir o perfil. Guarda a última visita de cada pessoa por 30
//! dias e mostra só o dia. Sem notificação nem contador (R6).

use axum::{Json, extract::State};
use serde::{Deserialize, Serialize};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{AppState, auth::AuthUser, error::AppResult};

/// Quanto tempo uma visita fica guardada.
pub const RETENTION_DAYS: i32 = 30;

/// Registra a visita de `visitor` ao perfil de `profile`, se os dois
/// participam. Bloqueios já foram tratados por quem chama (perfil visível).
pub async fn record(state: &AppState, visitor: Uuid, profile: Uuid) -> sqlx::Result<()> {
    if visitor == profile {
        return Ok(());
    }
    sqlx::query!(
        r#"
        INSERT INTO profile_visits (profile_id, visitor_id)
        SELECT $1, $2
        WHERE (SELECT visits_enabled FROM users WHERE id = $1)
          AND (SELECT visits_enabled FROM users WHERE id = $2)
        ON CONFLICT (profile_id, visitor_id) DO UPDATE SET visited_at = now()
        "#,
        profile,
        visitor
    )
    .execute(&state.db)
    .await?;
    Ok(())
}

#[derive(Debug, Serialize)]
pub struct Visitor {
    pub username: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    /// Só o dia (sem hora), `AAAA-MM-DD` no horário de Brasília.
    pub day: String,
}

#[derive(Debug, Serialize)]
pub struct VisitsDto {
    pub enabled: bool,
    pub visitors: Vec<Visitor>,
}

/// GET /v1/me/visits — quem visitou meu perfil nos últimos 30 dias.
pub async fn list(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<VisitsDto>> {
    let me = user.user_id;
    sqlx::query!(
        "DELETE FROM profile_visits
         WHERE visited_at < now() - make_interval(days => $1)",
        RETENTION_DAYS
    )
    .execute(&state.db)
    .await?;
    let enabled = sqlx::query_scalar!("SELECT visits_enabled FROM users WHERE id = $1", me)
        .fetch_one(&state.db)
        .await?;
    if !enabled {
        return Ok(Json(VisitsDto {
            enabled,
            visitors: Vec::new(),
        }));
    }
    let rows = sqlx::query!(
        r#"
        SELECT u.id, u.username, u.display_name, v.visited_at
        FROM profile_visits v JOIN users u ON u.id = v.visitor_id
        WHERE v.profile_id = $1 AND u.visits_enabled AND u.suspended_at IS NULL
          AND NOT EXISTS (SELECT 1 FROM blocks b
                WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
                   OR (b.blocker_id = u.id AND b.blocked_id = $1))
        ORDER BY v.visited_at DESC
        LIMIT 100
        "#,
        me
    )
    .fetch_all(&state.db)
    .await?;
    let mut visitors = Vec::with_capacity(rows.len());
    for r in rows {
        visitors.push(Visitor {
            avatar_url: crate::routes::photos::avatar_url(&state, r.id).await?,
            username: r.username,
            display_name: r.display_name,
            day: day_in_brazil(r.visited_at),
        });
    }
    Ok(Json(VisitsDto { enabled, visitors }))
}

/// Dia da visita no horário de Brasília (o app mostra "hoje", "ontem"...).
fn day_in_brazil(t: OffsetDateTime) -> String {
    let d = t.to_offset(time::macros::offset!(-3)).date();
    format!("{:04}-{:02}-{:02}", d.year(), u8::from(d.month()), d.day())
}

#[derive(Debug, Deserialize)]
pub struct SetVisits {
    pub enabled: bool,
}

/// PUT /v1/me/visits `{enabled}`. Desligar apaga as visitas guardadas, as que
/// eu fiz e as que recebi.
pub async fn set(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<SetVisits>,
) -> AppResult<Json<VisitsDto>> {
    let me = user.user_id;
    sqlx::query!(
        "UPDATE users SET visits_enabled = $2 WHERE id = $1",
        me,
        req.enabled
    )
    .execute(&state.db)
    .await?;
    if !req.enabled {
        sqlx::query!(
            "DELETE FROM profile_visits WHERE profile_id = $1 OR visitor_id = $1",
            me
        )
        .execute(&state.db)
        .await?;
    }
    list(State(state), user).await
}

//! Depoimentos (SPEC 4.2), no estilo do Orkut.
//!
//! - Só amigos escrevem (R9). Um depoimento por autor e destinatário;
//!   reescrever volta para "pendente".
//! - O dono do perfil aprova antes de aparecer, e pode remover quando quiser.
//! - Quem vê: quem pode ver o conteúdo do perfil (o dono e os amigos) e o autor.

use axum::{
    Json,
    extract::{Path, State},
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
        posts::AuthorDto,
        profiles::visible_user_id,
    },
    validation,
};

#[derive(Debug, Serialize)]
pub struct TestimonialDto {
    pub id: Uuid,
    pub author: AuthorDto,
    pub recipient: AuthorDto,
    pub body: String,
    /// pending | approved
    pub status: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    /// Dono do perfil ou autor.
    pub can_delete: bool,
}

struct Row {
    id: Uuid,
    body: String,
    status: String,
    created_at: OffsetDateTime,
    author_id: Uuid,
    author_username: String,
    author_display_name: Option<String>,
    recipient_id: Uuid,
    recipient_username: String,
    recipient_display_name: Option<String>,
}

impl Row {
    fn into_dto(self, viewer: Uuid) -> TestimonialDto {
        TestimonialDto {
            id: self.id,
            can_delete: viewer == self.author_id || viewer == self.recipient_id,
            author: AuthorDto {
                id: self.author_id,
                username: self.author_username,
                display_name: self.author_display_name,
            },
            recipient: AuthorDto {
                id: self.recipient_id,
                username: self.recipient_username,
                display_name: self.recipient_display_name,
            },
            body: self.body,
            status: self.status,
            created_at: self.created_at,
        }
    }
}

/// GET /v1/users/{username}/testimonials — aprovados (mais recentes primeiro),
/// mais o meu sobre essa pessoa, mesmo pendente.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
) -> AppResult<Json<ListDto<TestimonialDto>>> {
    let me = user.user_id;
    let owner = visible_user_id(&state, me, &username).await?;
    let can_see = friends::can_see_content(&state.db, me, owner).await?;
    let rows = sqlx::query_as!(
        Row,
        r#"
        SELECT t.id, t.body, t.status, t.created_at,
               a.id AS author_id, a.username AS author_username,
               a.display_name AS author_display_name,
               r.id AS recipient_id, r.username AS recipient_username,
               r.display_name AS recipient_display_name
        FROM testimonials t
        JOIN users a ON a.id = t.author_id
        JOIN users r ON r.id = t.recipient_id
        WHERE t.recipient_id = $1
          AND ((t.status = 'approved' AND $3) OR t.author_id = $2)
          AND NOT EXISTS (
            SELECT 1 FROM blocks b
            WHERE (b.blocker_id = $2 AND b.blocked_id = t.author_id)
               OR (b.blocker_id = t.author_id AND b.blocked_id = $2))
        ORDER BY coalesce(t.approved_at, t.created_at) DESC
        LIMIT 200
        "#,
        owner,
        me,
        can_see
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto {
        items: rows.into_iter().map(|r| r.into_dto(me)).collect(),
    }))
}

/// GET /v1/me/testimonials/pending — escritos sobre mim, esperando aprovação.
pub async fn pending(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<TestimonialDto>>> {
    let me = user.user_id;
    let rows = sqlx::query_as!(
        Row,
        r#"
        SELECT t.id, t.body, t.status, t.created_at,
               a.id AS author_id, a.username AS author_username,
               a.display_name AS author_display_name,
               r.id AS recipient_id, r.username AS recipient_username,
               r.display_name AS recipient_display_name
        FROM testimonials t
        JOIN users a ON a.id = t.author_id
        JOIN users r ON r.id = t.recipient_id
        WHERE t.recipient_id = $1 AND t.status = 'pending'
        ORDER BY t.created_at ASC
        "#,
        me
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto {
        items: rows.into_iter().map(|r| r.into_dto(me)).collect(),
    }))
}

#[derive(Debug, Deserialize)]
pub struct WriteTestimonial {
    pub body: String,
}

/// PUT /v1/users/{username}/testimonial — escreve (ou reescreve) o meu
/// depoimento sobre um amigo. Fica pendente até o dono aprovar.
pub async fn write(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
    Json(req): Json<WriteTestimonial>,
) -> AppResult<(StatusCode, Json<TestimonialDto>)> {
    let me = user.user_id;
    let body = validation::testimonial_body(&req.body)?;
    let recipient = visible_user_id(&state, me, &username).await?;
    if recipient == me {
        return Err(AppError::Validation("cannot_testify_self"));
    }
    if !friends::can_see_content(&state.db, me, recipient).await? {
        return Err(AppError::Forbidden);
    }
    let id = sqlx::query_scalar!(
        r#"
        INSERT INTO testimonials (id, author_id, recipient_id, body)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (author_id, recipient_id) DO UPDATE
          SET body = EXCLUDED.body, status = 'pending', created_at = now(), approved_at = NULL
        RETURNING id
        "#,
        Uuid::now_v7(),
        me,
        recipient,
        body
    )
    .fetch_one(&state.db)
    .await?;
    let row = fetch(&state, id).await?.ok_or(AppError::NotFound)?;
    Ok((StatusCode::OK, Json(row.into_dto(me))))
}

async fn fetch(state: &AppState, id: Uuid) -> sqlx::Result<Option<Row>> {
    sqlx::query_as!(
        Row,
        r#"
        SELECT t.id, t.body, t.status, t.created_at,
               a.id AS author_id, a.username AS author_username,
               a.display_name AS author_display_name,
               r.id AS recipient_id, r.username AS recipient_username,
               r.display_name AS recipient_display_name
        FROM testimonials t
        JOIN users a ON a.id = t.author_id
        JOIN users r ON r.id = t.recipient_id
        WHERE t.id = $1
        "#,
        id
    )
    .fetch_optional(&state.db)
    .await
}

/// POST /v1/testimonials/{id}/approve — só o dono do perfil.
pub async fn approve(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let n = sqlx::query!(
        "UPDATE testimonials SET status = 'approved', approved_at = now()
         WHERE id = $1 AND recipient_id = $2 AND status = 'pending'",
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

/// DELETE /v1/testimonials/{id} — o dono do perfil recusa/remove; o autor apaga.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let n = sqlx::query!(
        "DELETE FROM testimonials WHERE id = $1 AND (recipient_id = $2 OR author_id = $2)",
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

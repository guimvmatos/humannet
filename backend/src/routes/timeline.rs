//! "Minha história": onde a pessoa nasceu, morou, estudou e trabalhou, com
//! o período em anos. Alimenta as sugestões de reencontro (escola, faculdade,
//! trabalho, mesma época).
//!
//! - Dados estruturados: municípios do IBGE; escolas, faculdades e empresas
//!   num catálogo comum sem duplicatas; cursos numa lista comum.
//! - Cada item tem visibilidade (amigos / só para sugestões / só eu) e a
//!   opção "quero ser encontrado por este item".
//! - "Onde nasci" e escola ficam, por padrão, só para sugestões: são
//!   perguntas de segurança de banco e não devem ficar à mostra.

use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    routes::{
        friends::{self, ListDto},
        profiles::visible_user_id,
    },
    text::normalize,
};

const MAX_ENTRIES: i64 = 40;
const ORGS_PER_DAY: i64 = 20;
const LOOKUP_LIMIT: i64 = 20;

// ------------------------------------------------------------ catálogos

#[derive(Debug, Serialize, Clone)]
pub struct MunicipalityDto {
    pub code: i32,
    pub name: String,
    pub uf: String,
}

#[derive(Debug, Deserialize)]
pub struct LookupQuery {
    #[serde(default)]
    pub q: String,
    pub kind: Option<String>,
    /// Município (código IBGE) para filtrar instituições.
    pub city: Option<i32>,
}

/// GET /v1/geo/municipalities?q= — busca por nome (começo das palavras).
pub async fn municipalities(
    State(state): State<AppState>,
    _user: AuthUser,
    Query(q): Query<LookupQuery>,
) -> AppResult<Json<ListDto<MunicipalityDto>>> {
    let term = normalize(&q.q);
    if term.chars().count() < 2 {
        return Ok(Json(ListDto { items: vec![] }));
    }
    let items = sqlx::query_as!(
        MunicipalityDto,
        r#"SELECT code, name, uf FROM municipalities
           WHERE search LIKE $1 || '%' OR search LIKE '% ' || $1 || '%'
           ORDER BY (search LIKE $1 || '%') DESC, char_length(name), name
           LIMIT $2"#,
        term,
        LOOKUP_LIMIT
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto { items }))
}

#[derive(Debug, Serialize, Clone)]
pub struct OrgDto {
    pub id: Uuid,
    /// escola | faculdade | empresa
    pub kind: String,
    pub name: String,
    pub municipality: Option<MunicipalityDto>,
}

fn org_kind(raw: &str) -> AppResult<&'static str> {
    match raw {
        "escola" => Ok("escola"),
        "faculdade" => Ok("faculdade"),
        "empresa" => Ok("empresa"),
        _ => Err(AppError::Validation("invalid_org_kind")),
    }
}

/// GET /v1/orgs?kind=&q=&city= — escolas, faculdades ou empresas.
pub async fn orgs(
    State(state): State<AppState>,
    _user: AuthUser,
    Query(q): Query<LookupQuery>,
) -> AppResult<Json<ListDto<OrgDto>>> {
    let kind = org_kind(q.kind.as_deref().unwrap_or(""))?;
    let term = normalize(&q.q);
    if term.chars().count() < 2 {
        return Ok(Json(ListDto { items: vec![] }));
    }
    let rows = sqlx::query!(
        r#"SELECT o.id, o.kind, o.name, m.code AS "code?", m.name AS "mname?", m.uf AS "uf?"
           FROM orgs o LEFT JOIN municipalities m ON m.code = o.municipality_code
           WHERE o.kind = $1
             AND (o.search LIKE $2 || '%' OR o.search LIKE '% ' || $2 || '%')
             AND ($3::int IS NULL OR o.municipality_code = $3)
           ORDER BY (o.search LIKE $2 || '%') DESC, char_length(o.name), o.name
           LIMIT $4"#,
        kind,
        term,
        q.city,
        LOOKUP_LIMIT
    )
    .fetch_all(&state.db)
    .await?;
    let items = rows
        .into_iter()
        .map(|r| OrgDto {
            id: r.id,
            kind: r.kind,
            name: r.name,
            municipality: match (r.code, r.mname, r.uf) {
                (Some(code), Some(name), Some(uf)) => Some(MunicipalityDto { code, name, uf }),
                _ => None,
            },
        })
        .collect();
    Ok(Json(ListDto { items }))
}

#[derive(Debug, Deserialize)]
pub struct NewOrg {
    pub kind: String,
    pub name: String,
    pub municipality_code: Option<i32>,
}

/// POST /v1/orgs `{kind, name, municipality_code?}` — acha ou cria (o mesmo
/// nome normalizado na mesma cidade é a mesma instituição).
pub async fn create_org(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<NewOrg>,
) -> AppResult<Json<OrgDto>> {
    let kind = org_kind(&req.kind)?;
    let name = crate::validation::line(&req.name, 2, 120, "invalid_org_name")?;
    let search = normalize(&name);
    if search.chars().count() < 2 {
        return Err(AppError::Validation("invalid_org_name"));
    }
    if let Some(code) = req.municipality_code {
        municipality(&state, code).await?;
    }
    let existing = sqlx::query_scalar!(
        "SELECT id FROM orgs WHERE kind = $1 AND search = $2
           AND municipality_code IS NOT DISTINCT FROM $3",
        kind,
        search,
        req.municipality_code
    )
    .fetch_optional(&state.db)
    .await?;
    let id = match existing {
        Some(id) => id,
        None => {
            let today = sqlx::query_scalar!(
                r#"SELECT count(*) AS "n!" FROM orgs
                   WHERE created_by = $1 AND created_at > now() - interval '24 hours'"#,
                user.user_id
            )
            .fetch_one(&state.db)
            .await?;
            if today >= ORGS_PER_DAY {
                return Err(AppError::LimitReached("org_limit"));
            }
            sqlx::query_scalar!(
                "INSERT INTO orgs (id, kind, name, search, municipality_code, created_by)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 ON CONFLICT ON CONSTRAINT orgs_unique DO UPDATE SET kind = EXCLUDED.kind
                 RETURNING id",
                Uuid::now_v7(),
                kind,
                name,
                search,
                req.municipality_code,
                user.user_id
            )
            .fetch_one(&state.db)
            .await?
        }
    };
    Ok(Json(org(&state, id).await?))
}

async fn municipality(state: &AppState, code: i32) -> AppResult<MunicipalityDto> {
    sqlx::query_as!(
        MunicipalityDto,
        "SELECT code, name, uf FROM municipalities WHERE code = $1",
        code
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::Validation("invalid_municipality"))
}

async fn org(state: &AppState, id: Uuid) -> AppResult<OrgDto> {
    let r = sqlx::query!(
        r#"SELECT o.id, o.kind, o.name, m.code AS "code?", m.name AS "mname?", m.uf AS "uf?"
           FROM orgs o LEFT JOIN municipalities m ON m.code = o.municipality_code
           WHERE o.id = $1"#,
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::Validation("invalid_org"))?;
    Ok(OrgDto {
        id: r.id,
        kind: r.kind,
        name: r.name,
        municipality: match (r.code, r.mname, r.uf) {
            (Some(code), Some(name), Some(uf)) => Some(MunicipalityDto { code, name, uf }),
            _ => None,
        },
    })
}

#[derive(Debug, Serialize)]
pub struct CourseDto {
    pub id: i32,
    pub name: String,
}

/// GET /v1/courses?q=
pub async fn courses(
    State(state): State<AppState>,
    _user: AuthUser,
    Query(q): Query<LookupQuery>,
) -> AppResult<Json<ListDto<CourseDto>>> {
    let term = normalize(&q.q);
    if term.chars().count() < 2 {
        return Ok(Json(ListDto { items: vec![] }));
    }
    let items = sqlx::query_as!(
        CourseDto,
        r#"SELECT id, name FROM courses
           WHERE search LIKE $1 || '%' OR search LIKE '% ' || $1 || '%'
           ORDER BY (search LIKE $1 || '%') DESC, char_length(name), name
           LIMIT $2"#,
        term,
        LOOKUP_LIMIT
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ListDto { items }))
}

#[derive(Debug, Deserialize)]
pub struct NewCourse {
    pub name: String,
}

/// POST /v1/courses `{name}` — acha ou cria.
pub async fn create_course(
    State(state): State<AppState>,
    _user: AuthUser,
    Json(req): Json<NewCourse>,
) -> AppResult<Json<CourseDto>> {
    let name = crate::validation::line(&req.name, 2, 100, "invalid_course")?;
    let search = normalize(&name);
    if search.chars().count() < 2 {
        return Err(AppError::Validation("invalid_course"));
    }
    let c = sqlx::query_as!(
        CourseDto,
        "INSERT INTO courses (name, search) VALUES ($1, $2)
         ON CONFLICT (search) DO UPDATE SET search = EXCLUDED.search
         RETURNING id, name",
        name,
        search
    )
    .fetch_one(&state.db)
    .await?;
    Ok(Json(c))
}

// ------------------------------------------------------------ história

#[derive(Debug, Serialize)]
pub struct LifeEntryDto {
    pub id: Uuid,
    /// nasceu | morou | escola | faculdade | trabalho
    pub kind: String,
    pub municipality: Option<MunicipalityDto>,
    pub org: Option<OrgDto>,
    pub course: Option<CourseDto>,
    pub level: Option<String>,
    pub start_year: Option<i16>,
    pub end_year: Option<i16>,
    /// friends | suggestions | private (só para o dono).
    pub visibility: Option<String>,
    pub discoverable: Option<bool>,
}

async fn entries_of(
    state: &AppState,
    owner: Uuid,
    only_friends_visible: bool,
    with_settings: bool,
    only: Option<Uuid>,
) -> AppResult<Vec<LifeEntryDto>> {
    let rows = sqlx::query!(
        r#"
        SELECT e.id, e.kind, e.level, e.start_year, e.end_year, e.visibility, e.discoverable,
               m.code AS "m_code?", m.name AS "m_name?", m.uf AS "m_uf?",
               o.id AS "o_id?", o.kind AS "o_kind?", o.name AS "o_name?",
               om.code AS "om_code?", om.name AS "om_name?", om.uf AS "om_uf?",
               c.id AS "c_id?", c.name AS "c_name?"
        FROM life_entries e
        LEFT JOIN municipalities m ON m.code = e.municipality_code
        LEFT JOIN orgs o ON o.id = e.org_id
        LEFT JOIN municipalities om ON om.code = o.municipality_code
        LEFT JOIN courses c ON c.id = e.course_id
        WHERE e.user_id = $1
          AND (NOT $2 OR e.visibility = 'friends')
          AND ($3::uuid IS NULL OR e.id = $3)
        ORDER BY coalesce(e.start_year, 0), e.created_at
        "#,
        owner,
        only_friends_visible,
        only
    )
    .fetch_all(&state.db)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| {
            let mun = |code: Option<i32>, name: Option<String>, uf: Option<String>| match (
                code, name, uf,
            ) {
                (Some(code), Some(name), Some(uf)) => Some(MunicipalityDto { code, name, uf }),
                _ => None,
            };
            LifeEntryDto {
                id: r.id,
                kind: r.kind,
                municipality: mun(r.m_code, r.m_name, r.m_uf),
                org: match (r.o_id, r.o_kind, r.o_name) {
                    (Some(id), Some(kind), Some(name)) => Some(OrgDto {
                        id,
                        kind,
                        name,
                        municipality: mun(r.om_code, r.om_name, r.om_uf),
                    }),
                    _ => None,
                },
                course: match (r.c_id, r.c_name) {
                    (Some(id), Some(name)) => Some(CourseDto { id, name }),
                    _ => None,
                },
                level: r.level,
                start_year: r.start_year,
                end_year: r.end_year,
                visibility: with_settings.then_some(r.visibility),
                discoverable: with_settings.then_some(r.discoverable),
            }
        })
        .collect())
}

/// GET /v1/me/timeline — a minha história completa.
pub async fn mine(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ListDto<LifeEntryDto>>> {
    Ok(Json(ListDto {
        items: entries_of(&state, user.user_id, false, true, None).await?,
    }))
}

/// GET /v1/users/{username}/timeline — itens "amigos" de um amigo.
pub async fn of_user(
    State(state): State<AppState>,
    user: AuthUser,
    Path(username): Path<String>,
) -> AppResult<Json<ListDto<LifeEntryDto>>> {
    let owner = visible_user_id(&state, user.user_id, &username).await?;
    if owner == user.user_id {
        return mine(State(state), user).await;
    }
    if !friends::can_see_content(&state.db, user.user_id, owner).await? {
        return Err(AppError::Forbidden);
    }
    Ok(Json(ListDto {
        items: entries_of(&state, owner, true, false, None).await?,
    }))
}

#[derive(Debug, Deserialize)]
pub struct EntryReq {
    pub kind: String,
    pub municipality_code: Option<i32>,
    pub org_id: Option<Uuid>,
    pub course_id: Option<i32>,
    pub level: Option<String>,
    pub start_year: Option<i16>,
    pub end_year: Option<i16>,
    pub visibility: Option<String>,
    pub discoverable: Option<bool>,
}

struct Valid {
    kind: &'static str,
    municipality_code: Option<i32>,
    org_id: Option<Uuid>,
    course_id: Option<i32>,
    level: Option<&'static str>,
    start_year: Option<i16>,
    end_year: Option<i16>,
    visibility: &'static str,
    discoverable: bool,
}

async fn validate(state: &AppState, req: &EntryReq) -> AppResult<Valid> {
    let kind = match req.kind.as_str() {
        "nasceu" => "nasceu",
        "morou" => "morou",
        "escola" => "escola",
        "faculdade" => "faculdade",
        "trabalho" => "trabalho",
        _ => return Err(AppError::Validation("invalid_entry_kind")),
    };
    let this_year = i16::try_from(time::OffsetDateTime::now_utc().year()).unwrap_or(2100);
    for y in [req.start_year, req.end_year].into_iter().flatten() {
        if !(1920..=this_year + 10).contains(&y) {
            return Err(AppError::Validation("invalid_year"));
        }
    }
    if let (Some(a), Some(b)) = (req.start_year, req.end_year)
        && b < a
    {
        return Err(AppError::Validation("invalid_year"));
    }
    let (municipality_code, org_id, course_id, level) = match kind {
        "nasceu" | "morou" => {
            let code = req
                .municipality_code
                .ok_or(AppError::Validation("invalid_municipality"))?;
            municipality(state, code).await?;
            (Some(code), None, None, None)
        }
        _ => {
            let id = req.org_id.ok_or(AppError::Validation("invalid_org"))?;
            let o = org(state, id).await?;
            let expected = match kind {
                "escola" => "escola",
                "faculdade" => "faculdade",
                _ => "empresa",
            };
            if o.kind != expected {
                return Err(AppError::Validation("invalid_org"));
            }
            let level = match (kind, req.level.as_deref()) {
                (_, None) => None,
                ("escola", Some("fundamental")) => Some("fundamental"),
                ("escola", Some("medio")) => Some("medio"),
                ("escola", Some("tecnico")) => Some("tecnico"),
                ("faculdade", Some("graduacao")) => Some("graduacao"),
                ("faculdade", Some("pos")) => Some("pos"),
                _ => return Err(AppError::Validation("invalid_level")),
            };
            let course_id = if kind == "faculdade" {
                if let Some(c) = req.course_id {
                    let ok = sqlx::query_scalar!(
                        r#"SELECT EXISTS (SELECT 1 FROM courses WHERE id = $1) AS "e!""#,
                        c
                    )
                    .fetch_one(&state.db)
                    .await?;
                    if !ok {
                        return Err(AppError::Validation("invalid_course"));
                    }
                }
                req.course_id
            } else {
                None
            };
            (None, Some(id), course_id, level)
        }
    };
    // Onde nasci e escola: por padrão, só para sugestões (perguntas de
    // segurança de banco não ficam à mostra).
    let visibility = match req.visibility.as_deref() {
        None if matches!(kind, "nasceu" | "escola") => "suggestions",
        None | Some("friends") => "friends",
        Some("suggestions") => "suggestions",
        Some("private") => "private",
        _ => return Err(AppError::Validation("invalid_visibility")),
    };
    Ok(Valid {
        kind,
        municipality_code,
        org_id,
        course_id,
        level,
        // "Nasci em" guarda só o ano de nascimento.
        start_year: req.start_year,
        end_year: if kind == "nasceu" { None } else { req.end_year },
        visibility,
        discoverable: req.discoverable.unwrap_or(true),
    })
}

/// POST /v1/me/timeline
pub async fn add(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<EntryReq>,
) -> AppResult<(StatusCode, Json<LifeEntryDto>)> {
    let v = validate(&state, &req).await?;
    let (count, has_birth) = {
        let r = sqlx::query!(
            r#"SELECT count(*) AS "n!", bool_or(kind = 'nasceu') AS "birth!"
               FROM (SELECT kind FROM life_entries WHERE user_id = $1
                     UNION ALL SELECT 'x') t"#,
            user.user_id
        )
        .fetch_one(&state.db)
        .await?;
        (r.n - 1, r.birth)
    };
    if count >= MAX_ENTRIES {
        return Err(AppError::LimitReached("timeline_limit"));
    }
    if v.kind == "nasceu" && has_birth {
        return Err(AppError::Conflict("birth_exists"));
    }
    let id = Uuid::now_v7();
    sqlx::query!(
        "INSERT INTO life_entries (id, user_id, kind, municipality_code, org_id, course_id, level,
                                   start_year, end_year, visibility, discoverable)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        id,
        user.user_id,
        v.kind,
        v.municipality_code,
        v.org_id,
        v.course_id,
        v.level,
        v.start_year,
        v.end_year,
        v.visibility,
        v.discoverable
    )
    .execute(&state.db)
    .await?;
    let mut items = entries_of(&state, user.user_id, false, true, Some(id)).await?;
    Ok((
        StatusCode::CREATED,
        Json(items.pop().ok_or(AppError::NotFound)?),
    ))
}

/// PUT /v1/me/timeline/{id} — substitui o item.
pub async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<EntryReq>,
) -> AppResult<Json<LifeEntryDto>> {
    let v = validate(&state, &req).await?;
    let current = sqlx::query_scalar!(
        "SELECT kind FROM life_entries WHERE id = $1 AND user_id = $2",
        id,
        user.user_id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    if current != v.kind {
        return Err(AppError::Validation("invalid_entry_kind"));
    }
    sqlx::query!(
        "UPDATE life_entries SET municipality_code = $3, org_id = $4, course_id = $5, level = $6,
                start_year = $7, end_year = $8, visibility = $9, discoverable = $10
         WHERE id = $1 AND user_id = $2",
        id,
        user.user_id,
        v.municipality_code,
        v.org_id,
        v.course_id,
        v.level,
        v.start_year,
        v.end_year,
        v.visibility,
        v.discoverable
    )
    .execute(&state.db)
    .await?;
    let mut items = entries_of(&state, user.user_id, false, true, Some(id)).await?;
    Ok(Json(items.pop().ok_or(AppError::NotFound)?))
}

/// DELETE /v1/me/timeline/{id}
pub async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    sqlx::query!(
        "DELETE FROM life_entries WHERE id = $1 AND user_id = $2",
        id,
        user.user_id
    )
    .execute(&state.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

// ------------------------------------------------------------ reencontros

/// Um item em comum com outra pessoa (para as sugestões).
pub struct Match {
    pub user_id: Uuid,
    pub score: i64,
    pub reason: String,
}

/// Itens da minha história que batem com itens "encontráveis" de outras
/// pessoas. Escola, faculdade e trabalho: mesma instituição (melhor ainda na
/// mesma época). Cidade natal: mesma geração (±2 anos). Cidade onde morou:
/// mesma época.
pub async fn matches(state: &AppState, me: Uuid) -> sqlx::Result<Vec<Match>> {
    let year = time::OffsetDateTime::now_utc().year();
    let rows = sqlx::query!(
        r#"
        SELECT o.user_id, me.kind,
               org.name AS "org_name?", mun.name AS "mun_name?", crs.name AS "course_name?",
               (me.course_id IS NOT NULL AND me.course_id = o.course_id) AS "same_course!",
               (me.start_year IS NOT NULL AND o.start_year IS NOT NULL) AS "dated!",
               CASE
                 WHEN me.kind = 'nasceu' THEN abs(me.start_year - o.start_year) <= 2
                 ELSE me.start_year - (CASE me.kind WHEN 'escola' THEN 2 ELSE 1 END)
                        <= coalesce(o.end_year, $2::int)
                      AND o.start_year - (CASE me.kind WHEN 'escola' THEN 2 ELSE 1 END)
                        <= coalesce(me.end_year, $2::int)
               END AS "overlap?"
        FROM life_entries me
        JOIN life_entries o
          ON o.user_id <> me.user_id AND o.kind = me.kind
         AND o.discoverable AND o.visibility <> 'private'
         AND ((me.org_id IS NOT NULL AND o.org_id = me.org_id)
              OR (me.org_id IS NULL AND o.municipality_code = me.municipality_code))
        LEFT JOIN orgs org ON org.id = me.org_id
        LEFT JOIN municipalities mun ON mun.code = me.municipality_code
        LEFT JOIN courses crs ON crs.id = me.course_id
        WHERE me.user_id = $1
        LIMIT 3000
        "#,
        me,
        year
    )
    .fetch_all(&state.db)
    .await?;
    let mut out = Vec::new();
    for r in rows {
        let same_time = r.dated && r.overlap == Some(true);
        let org = r.org_name.unwrap_or_default();
        let city = r.mun_name.unwrap_or_default();
        let (score, reason) = match (r.kind.as_str(), same_time) {
            ("escola", true) => (8, format!("Estudou na {org} na mesma época")),
            ("escola", false) if !r.dated => (3, format!("Também estudou na {org}")),
            ("faculdade", true) if r.same_course => (
                12,
                format!(
                    "{} na {org}, mesma época",
                    r.course_name.unwrap_or_default()
                ),
            ),
            ("faculdade", true) => (8, format!("Estudou na {org} na mesma época")),
            ("faculdade", false) if !r.dated => (3, format!("Também estudou na {org}")),
            ("trabalho", true) => (6, format!("Trabalhou na {org} na mesma época")),
            ("trabalho", false) if !r.dated => (2, format!("Também trabalhou na {org}")),
            ("nasceu", true) => (3, format!("Também nasceu em {city}, mesma geração")),
            ("morou", true) => (1, format!("Morou em {city} na mesma época")),
            _ => continue,
        };
        out.push(Match {
            user_id: r.user_id,
            score,
            reason,
        });
    }
    Ok(out)
}

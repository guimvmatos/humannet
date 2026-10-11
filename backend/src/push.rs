//! Notificações push (Firebase Cloud Messaging, API HTTP v1).
//!
//! - O texto NUNCA leva o conteúdo (mensagem, comentário, depoimento): só quem
//!   fez e o quê. O conteúdo passa pelo Google e fica na tela de bloqueio.
//! - Respeita bloqueio (nos dois sentidos) e conta suspensa.
//! - Envio em segundo plano: a resposta da API não espera o Google.
//! - Tokens que o FCM diz não existirem mais são apagados.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use anyhow::{Context, anyhow};
use base64::{
    Engine,
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
};
use ring::{
    rand::SystemRandom,
    signature::{RSA_PKCS1_SHA256, RsaKeyPair},
};
use serde::Deserialize;
use sqlx::PgPool;
use uuid::Uuid;

/// Mesma conversa para a mesma pessoa: no máximo um aviso a cada 20 s.
const MESSAGE_COOLDOWN: Duration = Duration::from_secs(20);
const SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Kind {
    FriendRequest,
    FriendAccepted,
    Testimonial,
    Scrap,
    Comment {
        post: Uuid,
    },
    Mention {
        post: Uuid,
    },
    Tag {
        post: Uuid,
    },
    Message {
        conversation: Uuid,
        group: Option<String>,
    },
}

impl Kind {
    fn code(&self) -> &'static str {
        match self {
            Self::FriendRequest => "friend_request",
            Self::FriendAccepted => "friend_accepted",
            Self::Testimonial => "testimonial",
            Self::Scrap => "scrap",
            Self::Comment { .. } => "comment",
            Self::Mention { .. } => "mention",
            Self::Tag { .. } => "tag",
            Self::Message { .. } => "message",
        }
    }

    /// (título, texto). `name` = nome de exibição ou @usuário de quem fez.
    fn text(&self, name: &str) -> (String, String) {
        match self {
            Self::FriendRequest => (
                "Pedido de amizade".into(),
                format!("{name} enviou um pedido de amizade"),
            ),
            Self::FriendAccepted => (
                "Nova amizade".into(),
                format!("{name} aceitou seu pedido de amizade"),
            ),
            Self::Testimonial => (
                "Novo depoimento".into(),
                format!("{name} escreveu um depoimento para você"),
            ),
            Self::Scrap => (
                "Novo recado".into(),
                format!("{name} deixou um recado no seu perfil"),
            ),
            Self::Comment { .. } => (
                "Novo comentário".into(),
                format!("{name} comentou no seu post"),
            ),
            Self::Mention { .. } => (
                "Você foi mencionado".into(),
                format!("{name} mencionou você"),
            ),
            Self::Tag { .. } => (
                "Nova marcação".into(),
                format!("{name} marcou você num post (aprove ou recuse)"),
            ),
            Self::Message { group: None, .. } => (name.to_owned(), "Nova mensagem".into()),
            Self::Message {
                group: Some(title), ..
            } => (title.clone(), format!("{name} mandou uma mensagem")),
        }
    }

    /// Id que o app usa para abrir a tela certa.
    fn target(&self) -> String {
        match self {
            Self::Comment { post } | Self::Mention { post } | Self::Tag { post } => {
                post.to_string()
            }
            Self::Message { conversation, .. } => conversation.to_string(),
            _ => String::new(),
        }
    }

    /// Avisos com a mesma etiqueta se substituem na bandeja do Android.
    fn tag(&self) -> String {
        match self {
            Self::Message { conversation, .. } => format!("conv-{conversation}"),
            Self::Comment { post } => format!("post-{post}"),
            Self::Mention { post } => format!("mention-{post}"),
            Self::Tag { post } => format!("tag-{post}"),
            other => other.code().to_owned(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Event {
    pub actor: Uuid,
    pub to: Vec<Uuid>,
    pub kind: Kind,
}

#[derive(Clone, Default)]
pub enum Push {
    #[default]
    Disabled,
    Fcm(Arc<Fcm>),
    /// Para testes: guarda os eventos em vez de enviar.
    Memory(Arc<Mutex<Vec<Event>>>),
}

impl Push {
    pub fn memory() -> Self {
        Self::Memory(Arc::default())
    }

    pub fn sent(&self) -> Vec<Event> {
        match self {
            Self::Memory(m) => m.lock().expect("lock").clone(),
            _ => Vec::new(),
        }
    }

    /// Dispara o aviso em segundo plano. Nunca falha para quem chamou.
    pub fn notify(&self, db: &PgPool, actor: Uuid, to: Vec<Uuid>, kind: Kind) {
        let to: Vec<Uuid> = to.into_iter().filter(|u| *u != actor).collect();
        if to.is_empty() {
            return;
        }
        let event = Event { actor, to, kind };
        match self {
            Self::Disabled => {}
            Self::Memory(m) => m.lock().expect("lock").push(event),
            Self::Fcm(fcm) => {
                let fcm = fcm.clone();
                let db = db.clone();
                tokio::spawn(async move {
                    if let Err(e) = fcm.deliver(&db, event).await {
                        tracing::warn!(error = %e, "push falhou");
                    }
                });
            }
        }
    }
}

/// Conta de serviço do Firebase (o JSON baixado no console).
#[derive(Deserialize)]
struct ServiceAccount {
    project_id: String,
    client_email: String,
    private_key: String,
    #[serde(default = "default_token_uri")]
    token_uri: String,
}

fn default_token_uri() -> String {
    "https://oauth2.googleapis.com/token".into()
}

pub struct Fcm {
    project_id: String,
    client_email: String,
    token_uri: String,
    key: RsaKeyPair,
    http: reqwest::Client,
    token: tokio::sync::Mutex<Option<(String, Instant)>>,
    recent: Mutex<HashMap<(Uuid, String), Instant>>,
}

impl std::fmt::Debug for Fcm {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Nunca imprime a chave privada.
        f.debug_struct("Fcm")
            .field("project_id", &self.project_id)
            .finish_non_exhaustive()
    }
}

impl Fcm {
    /// `json` = conteúdo inteiro do arquivo da conta de serviço.
    pub fn from_service_account(json: &str) -> anyhow::Result<Self> {
        let sa: ServiceAccount =
            serde_json::from_str(json).context("FCM_SERVICE_ACCOUNT_JSON inválido")?;
        let pem: String = sa
            .private_key
            .lines()
            .filter(|l| !l.starts_with("-----"))
            .collect();
        let der = STANDARD
            .decode(pem.trim())
            .context("chave privada da conta de serviço")?;
        let key = RsaKeyPair::from_pkcs8(&der).map_err(|e| anyhow!("chave privada: {e}"))?;
        let _ = rustls::crypto::ring::default_provider().install_default();
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .context("cliente http")?;
        Ok(Self {
            project_id: sa.project_id,
            client_email: sa.client_email,
            token_uri: sa.token_uri,
            key,
            http,
            token: tokio::sync::Mutex::new(None),
            recent: Mutex::default(),
        })
    }

    fn sign_jwt(&self) -> anyhow::Result<String> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs();
        let header = URL_SAFE_NO_PAD.encode(br#"{"alg":"RS256","typ":"JWT"}"#);
        let claims = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&serde_json::json!({
            "iss": self.client_email,
            "scope": SCOPE,
            "aud": self.token_uri,
            "iat": now,
            "exp": now + 3600,
        }))?);
        let input = format!("{header}.{claims}");
        let mut sig = vec![0; self.key.public().modulus_len()];
        self.key
            .sign(
                &RSA_PKCS1_SHA256,
                &SystemRandom::new(),
                input.as_bytes(),
                &mut sig,
            )
            .map_err(|_| anyhow!("assinatura do JWT"))?;
        Ok(format!("{input}.{}", URL_SAFE_NO_PAD.encode(sig)))
    }

    /// Token OAuth de acesso, renovado 5 min antes de vencer.
    async fn access_token(&self) -> anyhow::Result<String> {
        let mut cached = self.token.lock().await;
        if let Some((tok, until)) = cached.as_ref()
            && Instant::now() < *until
        {
            return Ok(tok.clone());
        }
        let form = url::form_urlencoded::Serializer::new(String::new())
            .append_pair("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
            .append_pair("assertion", &self.sign_jwt()?)
            .finish();
        let res = self
            .http
            .post(&self.token_uri)
            .header("content-type", "application/x-www-form-urlencoded")
            .body(form)
            .send()
            .await?;
        let status = res.status();
        let bytes = res.bytes().await?;
        if !status.is_success() {
            anyhow::bail!("token OAuth: HTTP {status}");
        }
        #[derive(Deserialize)]
        struct Tok {
            access_token: String,
            expires_in: u64,
        }
        let t: Tok = serde_json::from_slice(&bytes)?;
        let ttl = Duration::from_secs(t.expires_in.saturating_sub(300).max(60));
        *cached = Some((t.access_token.clone(), Instant::now() + ttl));
        Ok(t.access_token)
    }

    /// Para mensagens: pula quem já foi avisado desta conversa há pouco.
    fn cooled(&self, user: Uuid, kind: &Kind) -> bool {
        if !matches!(kind, Kind::Message { .. }) {
            return true;
        }
        let mut recent = self.recent.lock().expect("lock");
        let now = Instant::now();
        recent.retain(|_, t| now.duration_since(*t) < MESSAGE_COOLDOWN);
        let key = (user, kind.tag());
        if recent.contains_key(&key) {
            return false;
        }
        recent.insert(key, now);
        true
    }

    async fn deliver(&self, db: &PgPool, event: Event) -> anyhow::Result<()> {
        let to: Vec<Uuid> = event
            .to
            .iter()
            .copied()
            .filter(|u| self.cooled(*u, &event.kind))
            .collect();
        if to.is_empty() {
            return Ok(());
        }
        let actor = sqlx::query!(
            "SELECT username, display_name FROM users WHERE id = $1",
            event.actor
        )
        .fetch_optional(db)
        .await?;
        let Some(actor) = actor else { return Ok(()) };
        let name = actor
            .display_name
            .filter(|n| !n.trim().is_empty())
            .unwrap_or_else(|| format!("@{}", actor.username));
        let devices = sqlx::query_scalar!(
            r#"
            SELECT d.token FROM push_devices d JOIN users u ON u.id = d.user_id
            WHERE d.user_id = ANY($1) AND u.suspended_at IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM blocks b
                WHERE (b.blocker_id = d.user_id AND b.blocked_id = $2)
                   OR (b.blocker_id = $2 AND b.blocked_id = d.user_id))
            "#,
            &to,
            event.actor
        )
        .fetch_all(db)
        .await?;
        if devices.is_empty() {
            return Ok(());
        }
        let (title, body) = event.kind.text(&name);
        let token = self.access_token().await?;
        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            self.project_id
        );
        for device in devices {
            let msg = serde_json::json!({ "message": {
                "token": device,
                "notification": { "title": title, "body": body },
                "data": {
                    "kind": event.kind.code(),
                    "id": event.kind.target(),
                    "actor": actor.username,
                },
                "android": {
                    "priority": "high",
                    "collapse_key": event.kind.tag(),
                    "notification": { "tag": event.kind.tag() },
                },
            }});
            let res = self
                .http
                .post(&url)
                .bearer_auth(&token)
                .header("content-type", "application/json")
                .body(serde_json::to_vec(&msg)?)
                .send()
                .await?;
            let status = res.status();
            if status.is_success() {
                continue;
            }
            let text = res.text().await.unwrap_or_default();
            if status == reqwest::StatusCode::NOT_FOUND || text.contains("UNREGISTERED") {
                // Aparelho desinstalou o app ou o token venceu.
                sqlx::query!("DELETE FROM push_devices WHERE token = $1", device)
                    .execute(db)
                    .await?;
            } else {
                tracing::warn!(%status, "FCM recusou o envio");
            }
        }
        Ok(())
    }
}

//! Envio de e-mail (códigos de confirmação). Usa a API da Resend quando
//! `RESEND_API_KEY` e `MAIL_FROM` estão definidas; sem elas, fica desligado e
//! quem depende disso cai na aprovação manual.

use std::{
    sync::{Arc, Mutex},
    time::Duration,
};

use anyhow::{Context, bail};

#[derive(Clone, Default)]
pub enum Mailer {
    #[default]
    Disabled,
    Resend {
        http: reqwest::Client,
        key: Arc<str>,
        from: Arc<str>,
    },
    /// Para testes: guarda (para, assunto, texto).
    Memory(Arc<Mutex<Vec<(String, String, String)>>>),
}

impl Mailer {
    pub fn memory() -> Self {
        Self::Memory(Arc::default())
    }

    pub fn resend(key: &str, from: &str) -> anyhow::Result<Self> {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .context("cliente http")?;
        Ok(Self::Resend {
            http,
            key: key.into(),
            from: from.into(),
        })
    }

    pub fn enabled(&self) -> bool {
        !matches!(self, Self::Disabled)
    }

    pub fn sent(&self) -> Vec<(String, String, String)> {
        match self {
            Self::Memory(m) => m.lock().expect("lock").clone(),
            _ => Vec::new(),
        }
    }

    pub async fn send(&self, to: &str, subject: &str, text: &str) -> anyhow::Result<()> {
        match self {
            Self::Disabled => bail!("e-mail desligado"),
            Self::Memory(m) => {
                m.lock()
                    .expect("lock")
                    .push((to.to_owned(), subject.to_owned(), text.to_owned()));
                Ok(())
            }
            Self::Resend { http, key, from } => {
                let body = serde_json::to_vec(&serde_json::json!({
                    "from": &**from,
                    "to": [to],
                    "subject": subject,
                    "text": text,
                }))?;
                let res = http
                    .post("https://api.resend.com/emails")
                    .header("Authorization", format!("Bearer {key}"))
                    .header("Content-Type", "application/json")
                    .body(body)
                    .send()
                    .await
                    .context("envio de e-mail")?;
                if !res.status().is_success() {
                    bail!("envio de e-mail: status {}", res.status());
                }
                Ok(())
            }
        }
    }
}

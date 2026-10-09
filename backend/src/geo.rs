//! Coordenadas das páginas de lugar, a partir do endereço (OpenStreetMap
//! Nominatim). Uso leve e educado: no máximo 1 consulta por segundo,
//! identificando o app, como pede a política do Nominatim.
//!
//! Só o endereço do LUGAR é consultado. Nada de quem usa o app.

use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use anyhow::Context;
use serde::Deserialize;
use sqlx::PgPool;
use uuid::Uuid;

const NOMINATIM: &str = "https://nominatim.openstreetmap.org/search";
const USER_AGENT: &str = "HumanNet/0.2 (rede social; contato: guimvmatos@gmail.com)";

/// O que se sabe do endereço da página.
#[derive(Clone, Debug, Default)]
pub struct Address {
    pub address: String,
    pub city: String,
    pub cep: Option<String>,
}

impl Address {
    /// Consultas da mais precisa para a mais genérica.
    fn queries(&self) -> Vec<Vec<(&'static str, String)>> {
        // "Rua X, 10 - Centro" → "Rua X, 10" (o bairro atrapalha a busca).
        let street = self
            .address
            .split(" - ")
            .next()
            .unwrap_or("")
            .trim()
            .trim_end_matches(',')
            .to_owned();
        // "Sorocaba - SP" → "Sorocaba, SP".
        let city = self.city.replace(" - ", ", ").trim().to_owned();
        let mut out = Vec::new();
        if !street.is_empty() && !city.is_empty() {
            out.push(vec![("q", format!("{street}, {city}, Brasil"))]);
        }
        if let Some(cep) = &self.cep {
            out.push(vec![
                ("postalcode", format!("{}-{}", &cep[..5], &cep[5..])),
                ("countrycodes", "br".to_owned()),
            ]);
        }
        if !city.is_empty() {
            out.push(vec![("q", format!("{city}, Brasil"))]);
        }
        out
    }
}

#[derive(Clone, Default)]
pub enum Geocoder {
    #[default]
    Disabled,
    Nominatim(Arc<Nominatim>),
    /// Para testes: sempre a mesma coordenada, na hora.
    Fixed(f64, f64),
}

pub struct Nominatim {
    http: reqwest::Client,
    last: tokio::sync::Mutex<Option<Instant>>,
}

impl Geocoder {
    pub fn nominatim() -> anyhow::Result<Self> {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent(USER_AGENT)
            .build()
            .context("cliente http")?;
        Ok(Self::Nominatim(Arc::new(Nominatim {
            http,
            last: tokio::sync::Mutex::new(None),
        })))
    }

    /// Acha a coordenada e grava na página (em segundo plano, exceto `Fixed`).
    /// Nunca sobrescreve um ponto marcado à mão.
    pub async fn locate(&self, db: &PgPool, page_id: Uuid, addr: Address) {
        match self {
            Self::Disabled => {}
            Self::Fixed(lat, lng) => {
                if let Err(e) = save(db, page_id, *lat, *lng).await {
                    tracing::warn!(error = %e, "geo: falha ao gravar");
                }
            }
            Self::Nominatim(n) => {
                let n = n.clone();
                let db = db.clone();
                tokio::spawn(async move {
                    match n.search(&addr).await {
                        Ok(Some((lat, lng))) => {
                            if let Err(e) = save(&db, page_id, lat, lng).await {
                                tracing::warn!(error = %e, "geo: falha ao gravar");
                            }
                        }
                        Ok(None) => tracing::info!("geo: endereço não encontrado"),
                        Err(e) => tracing::warn!(error = %e, "geo: consulta falhou"),
                    }
                });
            }
        }
    }
}

async fn save(db: &PgPool, page_id: Uuid, lat: f64, lng: f64) -> sqlx::Result<()> {
    sqlx::query!(
        "UPDATE pages SET lat = $2, lng = $3, geo_source = 'auto'
         WHERE id = $1 AND geo_source IS DISTINCT FROM 'manual'",
        page_id,
        lat,
        lng
    )
    .execute(db)
    .await?;
    Ok(())
}

#[derive(Deserialize)]
struct Hit {
    lat: String,
    lon: String,
}

impl Nominatim {
    async fn search(&self, addr: &Address) -> anyhow::Result<Option<(f64, f64)>> {
        for params in addr.queries() {
            // No máximo 1 consulta por segundo (política do Nominatim).
            {
                let mut last = self.last.lock().await;
                if let Some(t) = *last {
                    let wait = Duration::from_millis(1100).saturating_sub(t.elapsed());
                    tokio::time::sleep(wait).await;
                }
                *last = Some(Instant::now());
            }
            let mut url = url::Url::parse(NOMINATIM)?;
            {
                let mut q = url.query_pairs_mut();
                q.append_pair("format", "jsonv2");
                q.append_pair("limit", "1");
                for (k, v) in &params {
                    q.append_pair(k, v);
                }
            }
            let res = self.http.get(url).send().await?;
            if !res.status().is_success() {
                anyhow::bail!("nominatim: HTTP {}", res.status());
            }
            let hits: Vec<Hit> = serde_json::from_slice(&res.bytes().await?)?;
            if let Some(h) = hits.first() {
                let (lat, lng) = (h.lat.parse::<f64>()?, h.lon.parse::<f64>()?);
                if (-90.0..=90.0).contains(&lat) && (-180.0..=180.0).contains(&lng) {
                    return Ok(Some((lat, lng)));
                }
            }
        }
        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn queries_go_from_precise_to_generic() {
        let a = Address {
            address: "Rua XV de Novembro, 10 - Centro".into(),
            city: "Sorocaba - SP".into(),
            cep: Some("18035000".into()),
        };
        let q = a.queries();
        assert_eq!(q[0][0].1, "Rua XV de Novembro, 10, Sorocaba, SP, Brasil");
        assert_eq!(q[1][0].1, "18035-000");
        assert_eq!(q[2][0].1, "Sorocaba, SP, Brasil");
        assert!(Address::default().queries().is_empty());
    }
}

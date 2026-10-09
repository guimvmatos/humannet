//! Fotos: processamento (sem metadados) e armazenamento de objetos (S3).
//!
//! - Toda foto é decodificada e **recodificada** em JPEG no servidor. Isso
//!   remove EXIF (inclusive GPS, R7), aplica a rotação da câmera e limita o
//!   tamanho. Nunca guardamos o arquivo original.
//! - Os arquivos ficam num bucket privado. O app recebe links assinados que
//!   valem por algumas horas; o link é o mesmo dentro de cada hora, para o
//!   cache do celular funcionar.

use std::{
    collections::HashMap,
    io::Cursor,
    sync::{Arc, Mutex},
    time::Duration,
};

use anyhow::{Context, anyhow};
use image::{
    DynamicImage, ImageDecoder, ImageReader, Limits, codecs::jpeg::JpegEncoder,
    imageops::FilterType,
};
use rusty_s3::{Bucket, Credentials, S3Action, UrlStyle};

/// Tamanho máximo aceito no upload (o app já reduz antes de enviar).
pub const MAX_UPLOAD_BYTES: usize = 10 * 1024 * 1024;
const JPEG_QUALITY: u8 = 82;

/// Para que a foto vai ser usada (define o tamanho final).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Post,
    Avatar,
    Daily,
    /// Capa de página: faixa larga 3:1.
    Cover,
}

impl Kind {
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "post" => Some(Self::Post),
            "avatar" => Some(Self::Avatar),
            "daily" => Some(Self::Daily),
            "cover" => Some(Self::Cover),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Post => "post",
            Self::Avatar => "avatar",
            Self::Daily => "daily",
            Self::Cover => "cover",
        }
    }
}

pub struct Processed {
    pub jpeg: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

/// Decodifica (JPEG, PNG ou WebP), aplica a orientação da câmera, reduz e
/// recodifica em JPEG sem metadados. CPU: chamar via `spawn_blocking`.
pub fn process(bytes: &[u8], kind: Kind) -> anyhow::Result<Processed> {
    let mut reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .context("formato")?;
    match reader.format() {
        Some(image::ImageFormat::Jpeg | image::ImageFormat::Png | image::ImageFormat::WebP) => {}
        _ => return Err(anyhow!("formato não suportado")),
    }
    let mut limits = Limits::default();
    limits.max_image_width = Some(12_000);
    limits.max_image_height = Some(12_000);
    limits.max_alloc = Some(256 * 1024 * 1024);
    reader.limits(limits);
    let mut decoder = reader.into_decoder().context("decoder")?;
    let orientation = decoder.orientation().ok();
    let mut img = DynamicImage::from_decoder(decoder).context("decodificar")?;
    if let Some(o) = orientation {
        img.apply_orientation(o);
    }

    let img = match kind {
        Kind::Avatar => {
            // Quadrado central de 512 px.
            let side = img.width().min(img.height());
            let x = (img.width() - side) / 2;
            let y = (img.height() - side) / 2;
            img.crop_imm(x, y, side, side)
                .resize_exact(512, 512, FilterType::Lanczos3)
        }
        Kind::Cover => {
            // Faixa central 3:1, até 1500 x 500.
            let (w, h) = (img.width(), img.height());
            let (cw, ch) = if w >= h * 3 {
                (h * 3, h)
            } else {
                (w, (w / 3).max(1))
            };
            let cropped = img.crop_imm((w - cw) / 2, (h - ch) / 2, cw, ch);
            if cw > 1500 {
                cropped.resize_exact(1500, 500, FilterType::Lanczos3)
            } else {
                cropped
            }
        }
        Kind::Post | Kind::Daily => {
            const MAX: u32 = 1600;
            if img.width() > MAX || img.height() > MAX {
                img.resize(MAX, MAX, FilterType::Lanczos3)
            } else {
                img
            }
        }
    };
    let rgb = img.to_rgb8();
    let (width, height) = rgb.dimensions();
    let mut jpeg = Vec::new();
    JpegEncoder::new_with_quality(&mut jpeg, JPEG_QUALITY)
        .encode_image(&rgb)
        .context("codificar")?;
    Ok(Processed {
        jpeg,
        width,
        height,
    })
}

// ---------------------------------------------------------------- armazenamento

#[derive(Clone)]
pub enum MediaStore {
    /// Fotos desligadas (variáveis do bucket não configuradas).
    Disabled,
    S3(Arc<S3Store>),
    /// Para testes.
    Memory(Arc<Mutex<HashMap<String, Vec<u8>>>>),
}

pub struct S3Store {
    bucket: Bucket,
    credentials: Credentials,
    http: reqwest::Client,
}

/// Variáveis no padrão AWS (as mesmas que o painel do Neon mostra) + o bucket.
pub struct S3Config {
    pub endpoint: String,
    pub region: String,
    pub access_key_id: String,
    pub secret_access_key: String,
    pub bucket: String,
}

impl std::fmt::Debug for S3Config {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Nunca imprime a chave secreta.
        f.debug_struct("S3Config")
            .field("endpoint", &self.endpoint)
            .field("region", &self.region)
            .field("bucket", &self.bucket)
            .finish_non_exhaustive()
    }
}

impl MediaStore {
    pub fn memory() -> Self {
        Self::Memory(Arc::default())
    }

    pub fn s3(cfg: S3Config) -> anyhow::Result<Self> {
        let endpoint = url::Url::parse(&cfg.endpoint).context("AWS_ENDPOINT_URL_S3 inválida")?;
        let bucket = Bucket::new(endpoint, UrlStyle::Path, cfg.bucket, cfg.region)
            .map_err(|e| anyhow!("bucket: {e}"))?;
        // TLS do cliente HTTP com o mesmo provedor (ring) do sqlx. Idempotente.
        let _ = rustls::crypto::ring::default_provider().install_default();
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .context("cliente http")?;
        Ok(Self::S3(Arc::new(S3Store {
            bucket,
            credentials: Credentials::new(cfg.access_key_id, cfg.secret_access_key),
            http,
        })))
    }

    pub fn enabled(&self) -> bool {
        !matches!(self, Self::Disabled)
    }

    pub async fn put(&self, key: &str, jpeg: Vec<u8>) -> anyhow::Result<()> {
        match self {
            Self::Disabled => Err(anyhow!("armazenamento desligado")),
            Self::Memory(m) => {
                m.lock()
                    .map_err(|_| anyhow!("lock"))?
                    .insert(key.to_owned(), jpeg);
                Ok(())
            }
            Self::S3(s) => {
                let url = s
                    .bucket
                    .put_object(Some(&s.credentials), key)
                    .sign(Duration::from_secs(300));
                let res = s
                    .http
                    .put(url)
                    .header("content-type", "image/jpeg")
                    .header("cache-control", "private, max-age=31536000, immutable")
                    .body(jpeg)
                    .send()
                    .await
                    .context("upload")?;
                if !res.status().is_success() {
                    return Err(anyhow!("upload: status {}", res.status()));
                }
                Ok(())
            }
        }
    }

    /// Apaga (melhor esforço: falhas só vão para o log).
    pub async fn delete(&self, key: &str) {
        match self {
            Self::Disabled => {}
            Self::Memory(m) => {
                if let Ok(mut m) = m.lock() {
                    m.remove(key);
                }
            }
            Self::S3(s) => {
                let url = s
                    .bucket
                    .delete_object(Some(&s.credentials), key)
                    .sign(Duration::from_secs(300));
                match s.http.delete(url).send().await {
                    Ok(r) if r.status().is_success() => {}
                    Ok(r) => tracing::warn!(status = %r.status(), "media delete failed"),
                    Err(e) => tracing::warn!(error = %e, "media delete failed"),
                }
            }
        }
    }

    /// Apaga várias, em segundo plano.
    pub fn delete_later(&self, keys: Vec<String>) {
        if keys.is_empty() {
            return;
        }
        let store = self.clone();
        tokio::spawn(async move {
            for k in keys {
                store.delete(&k).await;
            }
        });
    }

    /// Link para ler a foto. Assinado no início da hora atual e válido por
    /// 3 h: o mesmo link durante a hora inteira (cache do app) e sempre com
    /// pelo menos 2 h de validade.
    pub fn url(&self, key: &str) -> String {
        match self {
            Self::Disabled => String::new(),
            Self::Memory(_) => format!("memory://{key}"),
            Self::S3(s) => {
                let now = jiff::Timestamp::now().as_second();
                let hour = jiff::Timestamp::from_second(now - now.rem_euclid(3600))
                    .unwrap_or_else(|_| jiff::Timestamp::now());
                s.bucket
                    .get_object(Some(&s.credentials), key)
                    .sign_with_time(Duration::from_secs(3 * 3600), &hour)
                    .to_string()
            }
        }
    }

    /// Para testes: existe?
    pub fn contains(&self, key: &str) -> bool {
        match self {
            Self::Memory(m) => m.lock().map(|m| m.contains_key(key)).unwrap_or(false),
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(w: u32, h: u32) -> Vec<u8> {
        let img = image::RgbImage::from_pixel(w, h, image::Rgb([200, 30, 30]));
        let mut out = Vec::new();
        image::DynamicImage::ImageRgb8(img)
            .write_to(&mut Cursor::new(&mut out), image::ImageFormat::Png)
            .unwrap();
        out
    }

    #[test]
    fn reencodes_and_resizes() {
        let p = process(&png(3200, 1600), Kind::Post).unwrap();
        assert_eq!((p.width, p.height), (1600, 800));
        assert_eq!(&p.jpeg[..2], &[0xFF, 0xD8], "JPEG");
        let a = process(&png(800, 400), Kind::Avatar).unwrap();
        assert_eq!((a.width, a.height), (512, 512));
        let small = process(&png(100, 50), Kind::Daily).unwrap();
        assert_eq!((small.width, small.height), (100, 50));
    }

    #[test]
    fn rejects_non_images() {
        assert!(process(b"GIF89a....", Kind::Post).is_err());
        assert!(process(b"not an image at all", Kind::Post).is_err());
    }

    #[test]
    fn signed_url_is_stable_within_the_hour() {
        let store = MediaStore::s3(S3Config {
            endpoint: "https://storage.example.com".into(),
            region: "us-east-1".into(),
            access_key_id: "id".into(),
            secret_access_key: "secret".into(),
            bucket: "fotos".into(),
        })
        .unwrap();
        let a = store.url("media/x.jpg");
        let b = store.url("media/x.jpg");
        assert_eq!(a, b);
        assert!(a.starts_with("https://storage.example.com/fotos/media/x.jpg?"));
    }
}

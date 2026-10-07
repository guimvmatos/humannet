use anyhow::{Context, Result, bail};
use humannet_api::{
    AppState, Config, MIGRATOR, Policy, app,
    routes::invites::{create_invite, ensure_bootstrap_invite},
};
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::{EnvFilter, fmt, prelude::*};

const USAGE: &str = "\
uso: humannet-api [comando]

comandos:
  serve                 inicia a API (padrão); aplica migrações pendentes
  migrate               só aplica migrações
  invite [quantidade]   cria convites de administrador e imprime os códigos
";

#[tokio::main]
async fn main() -> Result<()> {
    let _ = dotenvy::dotenv();
    let config = Config::from_env()?;
    init_tracing(config.log_json);

    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("serve");

    let db = PgPoolOptions::new()
        .max_connections(20)
        .acquire_timeout(std::time::Duration::from_secs(5))
        .connect(&config.database_url)
        .await
        .context("falha ao conectar no Postgres")?;

    match cmd {
        "serve" => {
            MIGRATOR.run(&db).await.context("falha nas migrações")?;
            humannet_api::routes::admin::sync_admins(&db, &config.admin_usernames)
                .await
                .context("falha ao sincronizar ADMIN_USERNAMES")?;
            // Um BOOTSTRAP_INVITE_CODE inválido não pode derrubar a API.
            if let Some(code) = &config.bootstrap_invite {
                match ensure_bootstrap_invite(&db, code, config.invite_ttl_days).await {
                    Ok(true) => {
                        tracing::info!("convite inicial (BOOTSTRAP_INVITE_CODE) disponível")
                    }
                    Ok(false) => {}
                    Err(err) => tracing::error!(error = %err, "BOOTSTRAP_INVITE_CODE ignorado"),
                }
            }
            serve(config, db).await
        }
        "migrate" => {
            MIGRATOR.run(&db).await.context("falha nas migrações")?;
            tracing::info!("migrações aplicadas");
            Ok(())
        }
        "invite" => {
            let n: u32 = match args.get(1) {
                Some(s) => s.parse().context("quantidade inválida")?,
                None => 1,
            };
            if !(1..=100).contains(&n) {
                bail!("quantidade deve estar entre 1 e 100");
            }
            for _ in 0..n {
                let inv = create_invite(&db, None, config.invite_ttl_days).await?;
                println!("{}  (expira em {})", inv.code, inv.expires_at);
            }
            Ok(())
        }
        "-h" | "--help" | "help" => {
            print!("{USAGE}");
            Ok(())
        }
        other => {
            eprint!("comando desconhecido: {other}\n\n{USAGE}");
            std::process::exit(2);
        }
    }
}

async fn serve(config: Config, db: sqlx::PgPool) -> Result<()> {
    let state = AppState {
        db,
        policy: Policy::from(&config),
    };
    let listener = tokio::net::TcpListener::bind(config.bind_addr).await?;
    tracing::info!(addr = %config.bind_addr, "HumanNet API ouvindo");
    axum::serve(listener, app(state))
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

fn init_tracing(json: bool) {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("humannet_api=info,tower_http=info"));
    let registry = tracing_subscriber::registry().with(filter);
    if json {
        registry.with(fmt::layer().json()).init();
    } else {
        registry.with(fmt::layer()).init();
    }
}

async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    #[cfg(unix)]
    let terminate = async {
        if let Ok(mut s) = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            s.recv().await;
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => {},
        () = terminate => {},
    }
    tracing::info!("encerrando");
}

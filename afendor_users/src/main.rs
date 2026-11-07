// SPDX-License-Identifier: AGPL-3.0-or-later

mod app_attest;
mod pseudonym;
mod router_impl;
mod shard_impl;
mod types;

use afendor_svc::config::{DatabaseBackend, Mode, ServiceConfig};
use afendor_svc::transport::NatsTransport;
use router_impl::UsersRouter;
use shard_impl::UsersShard;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    afendor_svc::init_tracing();
    let config = ServiceConfig::from_env()?;
    let transport =
        NatsTransport::connect(&config.nats_url, config.nats_auth_token.as_deref()).await?;

    tracing::info!(
        service = config.service_name,
        mode = ?config.mode,
        shard_id = config.shard_id,
        shard_count = config.shard_count,
        listen_addr = %config.listen_addr,
        "starting users service"
    );

    match config.mode {
        Mode::Router => afendor_svc::router::run_router(&config, UsersRouter, transport).await,
        Mode::Shard => {
            let shard = build_shard(&config).await?;
            afendor_svc::shard::run_shard(&config, shard, transport).await
        }
        Mode::Combined => {
            let shard = build_shard(&config).await?;
            afendor_svc::combined::run_combined(&config, UsersRouter, shard, transport).await
        }
    }
}

async fn build_shard(config: &ServiceConfig) -> anyhow::Result<UsersShard> {
    pseudonym::configure_from_env()?;
    let app_attest = app_attest::AppAttestConfig::from_env()?;
    tracing::info!(
        app_ids = app_attest.app_ids.len(),
        allow_development = app_attest.allow_development,
        "app attest configuration"
    );
    match config.database_backend {
        DatabaseBackend::Postgres => {
            let postgres_config = afendor_svc::postgres::PostgresConfig::from_service_config(config);
            let pool = afendor_svc::postgres::connect(&postgres_config).await?;
            let kv = afendor_svc::postgres::KvClient::new(pool, &postgres_config)?;
            Ok(UsersShard::new_postgres(
                kv,
                config.cache_max_entries,
                config.cache_ttl,
                app_attest,
            ))
        }
        DatabaseBackend::Cassandra => {
            #[cfg(feature = "scylla")]
            {
                let scylla_config = afendor_svc::scylla::ScyllaConfig::from_service_config(config);
                let db = afendor_svc::scylla::connect(&scylla_config).await?;
                UsersShard::new_scylla(db, config.cache_max_entries, config.cache_ttl, app_attest)
                    .await
            }
            #[cfg(not(feature = "scylla"))]
            {
                anyhow::bail!("AFENDOR_DATABASE_BACKEND=cassandra requires the scylla feature");
            }
        }
    }
}

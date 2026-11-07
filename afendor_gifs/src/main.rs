// SPDX-License-Identifier: AGPL-3.0-or-later

mod klipy;
mod media_proxy;
mod router_impl;
mod shard_impl;
mod types;

use afendor_svc::config::{Mode, ServiceConfig};
use afendor_svc::transport::NatsTransport;
use router_impl::GifsRouter;
use shard_impl::GifsShard;

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
        "starting gifs service"
    );

    match config.mode {
        Mode::Router => {
            let router = GifsRouter::new(config.cache_max_entries, config.cache_ttl);
            afendor_svc::router::run_router(&config, router, transport).await
        }
        Mode::Shard => {
            let shard = GifsShard::new()?;
            afendor_svc::shard::run_shard(&config, shard, transport).await
        }
        Mode::Combined => {
            let router = GifsRouter::new(config.cache_max_entries, config.cache_ttl);
            let shard = GifsShard::new()?;
            afendor_svc::combined::run_combined(&config, router, shard, transport).await
        }
    }
}

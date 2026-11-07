// SPDX-License-Identifier: AGPL-3.0-or-later

use clap::Parser;
use afendor_push::{cli, run};

#[tokio::main(flavor = "multi_thread")]
async fn main() -> anyhow::Result<()> {
    let args = cli::Args::parse();
    if matches!(args.command, Some(cli::Command::Healthcheck)) {
        return afendor_common::healthcheck::run(
            "AFENDOR_PUSH_SERVICE_HOST",
            "AFENDOR_PUSH_SERVICE_PORT",
            args.mode.default_port(),
        )
        .await;
    }

    afendor_svc::init_tracing();

    let cfg = cli::load_config(&args)?;
    run(cfg).await
}

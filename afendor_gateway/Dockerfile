# SPDX-License-Identifier: AGPL-3.0-or-later
FROM erlang:28.5.0.8-slim AS build

ARG RUST_TOOLCHAIN=1.98.1

ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /usr/src/app

RUN apt-get update && apt-get install -y --no-install-recommends \
	git \
	curl \
	make \
	gcc \
	g++ \
	libc6-dev \
	ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

RUN curl --retry 5 --retry-delay 2 --retry-all-errors -fsSL https://github.com/erlang/rebar3/releases/download/3.27.3/rebar3 -o /usr/local/bin/rebar3 && \
	chmod +x /usr/local/bin/rebar3

RUN curl --retry 5 --retry-delay 2 --retry-all-errors --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | \
	sh -s -- -y --profile minimal --default-toolchain "${RUST_TOOLCHAIN}"

COPY . .
WORKDIR /usr/src/app/afendor_gateway
RUN rebar3 compile --deps_only

RUN cp config/sys.config.template config/sys.config && \
	rebar3 as prod release

FROM erlang:28.5.0.8-slim

ARG BUILD_VERSION=""
ARG SOURCE_SHA=""
ARG SOURCE_DATE=""

LABEL org.opencontainers.image.title="afendor-gateway"
LABEL org.opencontainers.image.description="Fluxer realtime gateway"
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"
LABEL org.opencontainers.image.vendor="Fluxer"
LABEL org.opencontainers.image.url="https://afendor.com"
LABEL org.opencontainers.image.documentation="https://docs.afendor.com"
LABEL org.opencontainers.image.source="https://github.com/afendorapp/afendor"
LABEL org.opencontainers.image.version="${BUILD_VERSION}"
LABEL org.opencontainers.image.revision="${SOURCE_SHA}"
LABEL org.opencontainers.image.created="${SOURCE_DATE}"
LABEL app.afendor.build-version="${BUILD_VERSION}"

WORKDIR /opt/afendor_gateway

RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates \
	curl \
	libstdc++6 \
	&& rm -rf /var/lib/apt/lists/* && \
	groupadd -r -g 65532 afendor && \
	useradd -r -u 65532 -g 65532 -s /sbin/nologin -d /opt/afendor_gateway afendor && \
	chown 65532:65532 /opt/afendor_gateway

COPY --from=build --chown=65532:65532 /usr/src/app/afendor_gateway/_build/prod/rel/afendor_gateway .
COPY --chown=65532:65532 afendor_gateway/scripts/docker_entrypoint.sh /opt/afendor_gateway/bin/docker_entrypoint.sh
COPY --chown=65532:65532 afendor_gateway/scripts/afendor_gateway_release_wrapper.sh /opt/afendor_gateway/bin/afendor_gateway.wrapper

RUN mv /opt/afendor_gateway/bin/afendor_gateway /opt/afendor_gateway/bin/afendor_gateway.real && \
	mv /opt/afendor_gateway/bin/afendor_gateway.wrapper /opt/afendor_gateway/bin/afendor_gateway && \
	chmod +x /opt/afendor_gateway/bin/docker_entrypoint.sh /opt/afendor_gateway/bin/afendor_gateway

USER 65532:65532

ENV BUILD_VERSION="${BUILD_VERSION}"

EXPOSE 8080 8081 4369

ENTRYPOINT ["/opt/afendor_gateway/bin/docker_entrypoint.sh"]

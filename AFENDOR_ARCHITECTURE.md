# AFENDOR CHAT — SYSTEM ARCHITECTURE SPECIFICATION

> **Classification:** Private Single-Node Microservices Platform  
> **Target Environment:** Google Cloud Platform (GCP) Compute Engine VPS (Ubuntu 22.04 / 24.04 LTS)  
> **License:** AGPL-3.0-or-later  

---

## 1. Executive Architecture Summary

**Afendor Chat** is an engineered private real-time communication platform designed strictly for personal use with invited peers. The system operates as a cohesive, containerized multi-service topology managed via Docker Compose and fronted by an existing host-level Nginx reverse proxy terminating TLS.

```
                      INTERNET / INCOMING TRAFFIC
                                  │
                                  ▼
                    ┌───────────────────────────┐
                    │  Host Nginx (VPS Engine)   │
                    │  Terminates TLS (Port 443) │
                    └─────────────┬─────────────┘
                                  │ Reverse Proxy (HTTP/1.1 + WS Upgrade)
                                  ▼
                    ┌───────────────────────────┐
                    │ Afendor Edge Dispatcher   │
                    │   (Internal Port 8080)    │
                    └─────────────┬─────────────┘
                                  │
    ┌──────────────┬──────────────┼──────────────┬──────────────┐
    ▼              ▼              ▼              ▼              ▼
┌────────┐   ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐
│AppProxy│   │REST API   │  │Gateway WS │  │Media Proxy│  │Admin Panel│
│(SolidJS│   │(Hono/Node)│  │(Erlang/RS)│  │(Rust S3)  │  │(Rust UI)  │
│& Shell)│   │           │  │           │  │           │  │           │
└────────┘   └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └───────────┘
                   │              │              │
                   └──────────────┼──────────────┘
                                  │
                                  ▼
                    ┌───────────────────────────┐
                    │ NATS Core + JetStream     │
                    │   (Internal Pub/Sub)      │
                    └─────────────┬─────────────┘
                                  │
    ┌──────────────┬──────────────┼──────────────┬──────────────┐
    ▼              ▼              ▼              ▼              ▼
┌────────┐   ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐
│ Worker │   │Snowflakes │  │   Users   │  │ Messages  │  │  Unfurl   │
│(Cron/  │   │(ID Gen)   │  │(Profile/  │  │(Storage & │  │(Link & GIF│
│Queues) │   │           │  │ Sessions) │  │ Timeline) │  │ Previews) │
└────────┘   └───────────┘  └───────────┘  └───────────┘  └───────────┘
                                  │
                   ┌──────────────┴──────────────┐
                   ▼                             ▼
       ┌───────────────────────┐     ┌───────────────────────┐
       │ PostgreSQL 16 DB      │     │ Valkey 8 Cache / KV   │
       │ (State & Relations)   │     │ (Sessions & Locks)    │
       └───────────────────────┘     └───────────────────────┘
```

---

## 2. Complete Application Service Directory

| Service | Technology | Role | Network Scope |
| :--- | :--- | :--- | :--- |
| **`edge`** | Caddy 2.9 (internal) | Internal multiplexer; routes subpaths and domains to backend containers. | Binds `127.0.0.1:8080` |
| **`api`** | Node.js 24 + TypeScript (Hono) | Primary business logic, auth, REST endpoints, webhooks, invitations. | Container network (`api:8080`) |
| **`worker`** | Node.js 24 + TypeScript | Background jobs, cron tasks, message sweepers, notification queuing. | Container network (no exposed port) |
| **`gateway`** | Erlang / OTP + Rust NIFs | High-concurrency stateful WebSocket engine for presence, typing, live events. | Container network (`gateway:8080`) |
| **`media-proxy`** | Rust (Axum/Tokio) | Secure media upload validator, image transformer, and S3 upload relayer. | Container network (`media-proxy:8080`) |
| **`app-proxy`** | Rust + Embedded SolidJS | Serves web SPA app shell, injects dynamic instance branding and themes. | Container network (`app-proxy:8080`) |
| **`admin`** | Rust (Axum + HTMX) | Private instance administration dashboard and moderation suite. | Container network (`admin:8080`) |
| **`push`** | Rust | Web Push (VAPID) notification dispatcher. | Container network (`push:8080`) |
| **`snowflakes`**| Rust | Distributed 64-bit unique ID generator. | Container network (`snowflakes:8080`) |
| **`users`** | Rust | User profile state and pseudonym manager. | Container network (`users:8080`) |
| **`gifs`** | Rust | GIF provider abstraction (KLIPY/GIPHY integration). | Container network (`gifs:8080`) |
| **`messages`** | Rust | High-throughput message storage and partition management. | Container network (`messages:8080`) |
| **`unfurl`** | Rust | SSRF-safe link preview crawler and embed metadata extractor. | Container network (`unfurl:8080`) |
| **`livekit`** | Go (LiveKit Server) | WebRTC selective forwarding unit (SFU) for voice, video, screen share. | `7880` (HTTP), `7881` (TCP), `7882/udp` |
| **`postgres`** | PostgreSQL 16 Alpine | Persistent primary relational datastore. | Container network (`postgres:5432`) |
| **`valkey`** | Valkey 8 Alpine | Low-latency in-memory cache and key-value store. | Container network (`valkey:6379`) |
| **`nats`** | NATS 2.10 Alpine | Internal message broker and JetStream event bus. | Container network (`nats:4222`) |
| **`meilisearch`**| Meilisearch v1.12 | Fast full-text search engine for messages and channels. | Container network (`meilisearch:7700`) |
| **`seaweedfs`** | SeaweedFS 3.79 | Bundled internal S3 object storage (Mode A only). | Container network (`seaweedfs:8333`) |

---

## 3. Storage Architecture: Mode A vs. Mode B

Afendor Chat features a decoupled storage interface:
1. **Mode A (Bundled SeaweedFS):** Uses SeaweedFS within Docker. All data is persisted to `/var/lib/docker/volumes/afendor_seaweedfs_data`. Best for zero external dependencies.
2. **Mode B (External S3 / Backblaze B2):** SeaweedFS containers are completely disabled. Uploads and media are streamed to/from Backblaze B2 buckets using presigned AWS SDK S3 v4 signatures. Zero media bytes touch the VPS disk.

---

## 4. Upstream Compatibility & Renaming Safety

During the transformation from Fluxer to Afendor Chat:
- **Environment Fallbacks:** Both TypeScript (`packages/config`) and Rust (`afendor_common::config`) feature bidirectional resolution: `AFENDOR_*` variables take primary precedence; `FLUXER_*` variables are checked as fallback.
- **Database Migrations:** Schema migrations check `__afendor_schema_migrations` and fallback to `__fluxer_schema_migrations`, preventing duplicate runs or schema corruption.
- **Discovery Endpoints:** The edge router matches both `/.well-known/afendor` and `/.well-known/fluxer` for client compatibility.
- **License Integrity:** The AGPL-3.0 license and upstream copyright notices remain preserved across all components.


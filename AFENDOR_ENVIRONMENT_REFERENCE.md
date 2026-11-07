# AFENDOR CHAT — COMPLETE ENVIRONMENT VARIABLE REFERENCE

> **File:** `config/env/production.env`  
> **Security:** Contains private credentials; permissions must be `chmod 600`  
> **Compatibility:** System supports `AFENDOR_*` as primary and `FLUXER_*` as fallback  

---

## 1. Domain & Networking Configurations

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `AFENDOR_ENV` | string | `production` | Deployment mode (`production`, `development`). |
| `NODE_ENV` | string | `production` | Node.js process runtime mode. |
| `AFENDOR_BASE_DOMAIN` | string | `afendor.cc` | Root apex domain. |
| `AFENDOR_PUBLIC_SCHEME` | string | `https` | Scheme used by client browsers (`http`, `https`). |
| `AFENDOR_PUBLIC_PORT` | number | `443` | External internet-facing port. |
| `AFENDOR_PUBLIC_URL` | string | `https://afendor.cc` | Canonical base URL. |
| `AFENDOR_APP_ENDPOINT` | string | `https://web.afendor.cc` | Web client URL. |
| `AFENDOR_API_ENDPOINT` | string | `https://api.afendor.cc` | Public REST API URL. |
| `AFENDOR_GATEWAY_ENDPOINT` | string | `wss://gateway.afendor.cc` | WebSocket gateway URL. |
| `AFENDOR_MEDIA_ENDPOINT` | string | `https://media.afendor.cc` | Media Proxy attachment URL. |
| `AFENDOR_STATIC_CDN_ENDPOINT`| string | `https://cdn.afendor.cc` | Static asset and emoji CDN URL. |
| `AFENDOR_ADMIN_ENDPOINT` | string | `https://admin.afendor.cc` | Admin dashboard URL. |
| `AFENDOR_TRUST_CLIENT_IP_HEADER`| boolean | `true` | Trust reverse proxy IP headers (`X-Forwarded-For`). |
| `AFENDOR_CLIENT_IP_HEADER_NAME` | string | `x-forwarded-for` | Name of header containing real client IP. |

---

## 2. Database & State Infrastructure

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `AFENDOR_DATABASE_BACKEND` | string | `postgres` | Primary DB backend (`postgres`, `cassandra`). |
| `AFENDOR_POSTGRES_HOST` | string | `postgres` | Hostname of PostgreSQL service. |
| `AFENDOR_POSTGRES_PORT` | number | `5432` | PostgreSQL port. |
| `AFENDOR_POSTGRES_DATABASE`| string | `afendor` | Database name. |
| `AFENDOR_POSTGRES_USERNAME`| string | `afendor` | Database username. |
| `AFENDOR_POSTGRES_PASSWORD`| secret | *(Generated)* | Database password. |
| `AFENDOR_POSTGRES_MAX_CONNECTIONS`| number | `50` | Maximum connection pool size. |
| `AFENDOR_POSTGRES_KV_TABLE`| string | `afendor_kv` | Core key-value table name. |
| `AFENDOR_KV_URL` | string | `redis://valkey:6379/0` | In-memory cache & lock URL. |
| `AFENDOR_NATS_URL` | string | `nats://nats:4222` | NATS message broker URL. |
| `AFENDOR_NATS_JETSTREAM_URL`| string | `nats://nats:4222` | NATS JetStream event log URL. |
| `AFENDOR_SEARCH_URL` | string | `http://meilisearch:7700` | Full-text search engine endpoint. |
| `AFENDOR_SEARCH_API_KEY` | secret | *(Generated)* | Meilisearch master authentication key. |

---

## 3. Object Storage (S3 / SeaweedFS / Backblaze B2)

| Variable | Type | Mode A Default | Mode B (Backblaze B2) Example |
| :--- | :--- | :--- | :--- |
| `AFENDOR_MEDIA_PROXY_STORAGE_BACKEND` | string | `s3` | `s3` |
| `AFENDOR_S3_ENDPOINT` | string | `http://seaweedfs:8333` | `https://s3.us-west-004.backblazeb2.com` |
| `AFENDOR_S3_REGION` | string | `us-east-1` | `us-west-004` (or `auto`) |
| `AFENDOR_S3_ACCESS_KEY_ID` | secret | `afendor` | `<B2-Key-ID>` |
| `AFENDOR_S3_SECRET_ACCESS_KEY` | secret | `afendor-secret` | `<B2-Application-Key>` |
| `AFENDOR_S3_FORCE_PATH_STYLE` | boolean | `true` | `false` |
| `AFENDOR_S3_BUCKET_UPLOADS` | string | `afendor-uploads` | `afendor-uploads` |
| `AFENDOR_S3_BUCKET_CDN` | string | `afendor` | `afendor-uploads` |

---

## 4. WebRTC Voice & Video (LiveKit)

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `AFENDOR_LIVEKIT_ENABLED` | boolean | `true` | Enable WebRTC voice/video calls. |
| `AFENDOR_LIVEKIT_URL` | string | `wss://livekit.afendor.cc` | Client-facing WebRTC signaling URL. |
| `AFENDOR_LIVEKIT_INTERNAL_URL`| string | `http://localhost:7880` | Internal server-to-server LiveKit API. |
| `AFENDOR_LIVEKIT_API_KEY` | string | `afendorkey` | LiveKit API Key. |
| `AFENDOR_LIVEKIT_API_SECRET` | secret | *(Generated)* | LiveKit API Secret (min 32 chars). |

---

## 5. Security, Secrets & Access Control

| Variable | Type | Sensitivity | Description |
| :--- | :--- | :--- | :--- |
| `AFENDOR_SETUP_TOKEN` | secret | High | One-time token to claim initial Admin account. |
| `AFENDOR_REGISTRATION_MODE`| string | Normal | `invite_only` (Strictly restricts registrations). |
| `AFENDOR_SUDO_MODE_SECRET` | secret | High | Signs sudo-mode authorization tokens. |
| `AFENDOR_CONNECTION_INITIATION_SECRET`| secret | High | Signs connection & invite tokens. |
| `AFENDOR_PROFILE_PSEUDONYM_SECRET`| secret | High | Derives pseudonym identifiers for hidden profiles. |
| `AFENDOR_MEDIA_PROXY_SECRET_KEY` | secret | High | HMAC key for signed attachment access URLs. |
| `AFENDOR_ADMIN_SECRET_KEY_BASE` | secret | High | Signs session cookies for admin dashboard. |
| `AFENDOR_ADMIN_OAUTH_CLIENT_SECRET`| secret | High | OAuth client secret for admin authentication. |


# AFENDOR CHAT — PRODUCTION INFRASTRUCTURE REQUIREMENTS

> **Platform:** Google Cloud Platform (GCP) Compute Engine  
> **Instance Specification:** Ubuntu Linux 22.04 LTS / 24.04 LTS, 8 vCPUs, 16 GB RAM  
> **Target Base Domain:** `afendor.cc`  

---

## 1. Host System Prerequisites

The following software must be present on the host Ubuntu Linux VPS:

| Software | Version | Purpose | Installation Method |
| :--- | :--- | :--- | :--- |
| **Docker Engine** | >= 26.0 | Container execution engine | `get.docker.com` or `apt install docker.io` |
| **Docker Compose** | >= 2.24 (v2 plugin) | Multi-container stack orchestration | `apt install docker-compose-plugin` |
| **Nginx** | >= 1.18 | Existing host-level reverse proxy & SSL termination | Pre-installed on user VPS |
| **Certbot / OpenSSL** | Modern | Management of Let's Encrypt TLS certificates | Pre-installed on user VPS |
| **tar, gzip, curl** | Standard | Backup processing and health check probing | Included in base Ubuntu image |

> [!IMPORTANT]
> Do NOT install PostgreSQL, Redis, or NATS directly on the VPS host system. All supporting databases, caches, and queues run exclusively inside isolated Docker containers.

---

## 2. Kernel & OS Tuning Parameters

Add the following production settings to `/etc/sysctl.d/99-afendor.conf` and apply with `sudo sysctl --system`:

```ini
# Support Redis / Valkey background snapshots without memory allocation failures
vm.overcommit_memory = 1

# Increase system-wide file descriptor limit for gateway WebSockets
fs.file-max = 2097152

# Increase max socket connections backlog
net.core.somaxconn = 65535

# Optimize connection tracking table for WebRTC & LiveKit traffic
net.netfilter.nf_conntrack_max = 524288
```

---

## 3. Network & Firewall Configuration (GCP & UFW)

### A. Google Cloud Platform (VPC Firewall Rules)
Configure the following ingress rules in your GCP Cloud Console (`VPC network -> Firewall`):

| Name | Direction | Protocol & Port | Source IP Range | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `allow-afendor-http` | Ingress | TCP: `80` | `0.0.0.0/0` | Let's Encrypt ACME verification & HTTP redirect |
| `allow-afendor-https`| Ingress | TCP: `443` | `0.0.0.0/0` | Primary secure web, API, gateway, and media proxy |
| `allow-livekit-tcp`  | Ingress | TCP: `7881` | `0.0.0.0/0` | LiveKit WebRTC TCP fallback (for restrictive firewalls) |
| `allow-livekit-udp`  | Ingress | UDP: `7882` | `0.0.0.0/0` | LiveKit WebRTC UDP audio/video media transmission |

### B. Internal VPS Ports (DO NOT EXPOSE TO INTERNET)
The following ports must remain bound to `127.0.0.1` or the internal Docker network only:
- `127.0.0.1:8080` — Afendor internal edge dispatcher (proxied via Nginx)
- `127.0.0.1:7880` — LiveKit internal signaling (proxied via Nginx)
- `5432` (PostgreSQL) — Container network only
- `6379` (Valkey) — Container network only
- `4222` (NATS) — Container network only
- `7700` (Meilisearch) — Container network only
- `8333` (SeaweedFS S3) — Container network only (Mode A)

---

## 4. Storage & Volume Mount Specifications

All persistent state is stored in Docker named volumes backed by VPS block storage:

| Volume Name | Target Path inside Container | Data Stored |
| :--- | :--- | :--- |
| `afendor_postgres_data` | `/var/lib/postgresql/data` | Database tables, indexes, user records, messages |
| `afendor_valkey_data` | `/data` | Ephemeral KV state, session records |
| `afendor_nats_data` | `/data/jetstream` | Message stream event journals |
| `afendor_meilisearch_data` | `/meili_data` | Search indexes |
| `afendor_seaweedfs_data` | `/data` | Raw media, avatar, and file attachments (Mode A only) |
| `afendor_media_proxy_tmp`| `/tmp` | Temporary image resize buffers |


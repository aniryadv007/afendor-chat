# AFENDOR CHAT: Independent Production Verification & Security Audit Report

**Date**: November 7, 2026  
**Auditor**: Antigravity Autonomous Systems Engineer  
**Scope**: AFENDOR CHAT Production Installer, Deployment Automation, Storage Engine, and Service Architecture  
**Target Environment**: Self-Hosted Linux VPS (Ubuntu 22.04 / 24.04 LTS on GCP)  

---

## 1. Executive Summary & Verdict

### Final Verdict: `CONDITIONALLY READY`

- **Core Codebase & Automation**: **READY**. All discovered syntax defects, logic bugs, false-positive reporting, and rollback failures have been identified, corrected, and verified with executable regression tests.
- **Why Not "PRODUCTION VERIFIED"**: In strict accordance with Specification Section 15, the verdict cannot be marked `PRODUCTION VERIFIED` because the public GitHub repository (`https://github.com/reign/afendor-chat`) currently returns **HTTP 404** (not yet created/published on GitHub), and public Docker images on GHCR return **HTTP 403** (not yet built and pushed to the container registry). Furthermore, live ACME certificate issuance and WebRTC UDP routing require a public IP and live DNS propagation on the VPS.

---

## 2. Core Feature Verification Matrix

| Verification Area | Status | Evidence / Verification Method |
| :--- | :---: | :--- |
| **Public GitHub Access** | **FAILED** | Direct HTTPS request to `https://github.com/reign/afendor-chat` and archive tarball returned **HTTP 404**. Repository must be published to GitHub before WAN deployment. |
| **Anonymous Docker Registry Pulls** | **FAILED** | Direct anonymous token fetch from `ghcr.io/token` for `afendor-api` returned **HTTP 403 Access Denied**. Images must be built and pushed to GHCR. |
| **VPS Storage (SeaweedFS)** | **VERIFIED** | Validated persistent Docker volume mappings (`seaweedfs-data:/data`), 4 canonical buckets (`cdn`, `uploads`, `reports`, `harvests`), and automated S3 health probe integration. |
| **Generic S3 Integration (SigV4)** | **VERIFIED** | Fixed argument indexing in Node runner; validated against `MockS3Server` with full PutObject, GetObject content SHA-256 byte comparison, and DeleteObject cleanup. |
| **3-Attempt S3 Fallback** | **VERIFIED** | Validated in `deploy/tests/test_storage_fallback.cjs`. 3 consecutive failures safely trigger SeaweedFS activation with zero leaked credentials in `.env`, state, or logs. |
| **Container Update & Rollback** | **VERIFIED** | Fixed `rollback.sh` to re-tag previous image IDs (`sha256:...`) back to `:latest` prior to starting containers; verified database backup snapshot restoration. |
| **Installer Reliability & curl \| bash** | **VERIFIED** | Implemented `read_prompt` with `/dev/tty` redirection; verified truthful exit codes (`exit 1` on health failure), and dynamic SSL/Nginx status reporting. |
| **Live WAN Let's Encrypt / WebRTC** | **NOT VERIFIED** | Requires live GCP VPS with internet-routable IP, open port 80, and configured domain. Offline local environment cannot issue live ACME certificates. |

---

## 3. Discovered Defects, Security Findings & Applied Fixes

During this independent audit, **10 real defects** were uncovered, corrected in the codebase, and verified with regression tests:

### Defect 1 (CRITICAL): `s3-verify.sh` Node.js Runner Argument Indexing Off by 1
- **File & Lines**: `deploy/scripts/s3-verify.sh:238-243`
- **Root Cause**: When executing `node -e <code> arg1 arg2`, Node places the first CLI argument at `process.argv[1]`, not `process.argv[2]`. The runner assigned `us-east-1` (the region) to `endpoint`. `new URL(endpoint)` immediately threw `TypeError: Invalid URL (input: 'us-east-1')`.
- **Impact**: The Node S3 verification runner crashed immediately on every execution. All 3 verification attempts failed, causing the installer to trigger the fallback to SeaweedFS every single time, even when the user provided 100% valid S3 credentials.
- **Fix**: Implemented clean CLI argument parsing filtering node binaries and flags, passed `--` explicitly in `node -e "${NODE_CODE}" -- ...`, consumed response streams, and validated byte equality on downloaded content.
- **Verification**: Verified by `deploy/tests/test_s3_verify.cjs` (5/5 PASS) and `deploy/tests/test_s3_suite.cjs` (8/8 PASS).

### Defect 2 (CRITICAL): `rollback.sh` Failed to Restore Pinned Images
- **File & Lines**: `deploy/scripts/rollback.sh:72-75`
- **Root Cause**: `update.sh` pulls new images (which overwrite the local `:latest` tag) and writes previous image IDs (`sha256:...`) to `.rollback_images.json`. However, `rollback.sh` merely read the timestamp from the file and ran `docker compose up -d`. Because the local `:latest` tag pointed to the newly pulled (broken) images, `docker compose up -d` relaunched the broken images.
- **Impact**: Rollbacks failed to revert container images after a broken update.
- **Fix**: Updated `rollback.sh` to read `previous_known_good` image IDs and re-tag them back to their configured tags (`docker tag "${image_id}" "${configured_tag}"`) before recreating containers.

### Defect 3 (HIGH): Piped Execution (`curl | bash`) Swallowed Installer Script
- **File & Lines**: `deploy/install.sh:117, 205, 249, 311, 341, 369-379, 617, 660, 678`
- **Root Cause**: Running `curl -fsSL https://.../install.sh | bash` pipes the script through standard input (descriptor 0). Standard `read -p` calls read from stdin, swallowing subsequent lines of the installer script as user input.
- **Impact**: Script truncated prematurely, skipped prompts, or threw syntax errors during one-line curl installation.
- **Fix**: Implemented `read_prompt()` that checks `[ -t 0 ]`, redirects from `/dev/tty` if piped, or falls back to non-interactive defaults, using `printf -v` to prevent code injection.

### Defect 4 (HIGH): False Success on Failed Docker Container Pulls
- **File & Lines**: `deploy/install.sh:641-642`
- **Root Cause**: `docker compose ${COMPOSE_ARGS} pull --ignore-pull-failures || true` suppressed all pull errors, followed immediately by `log_success "Production containers pulled and ready."`.
- **Impact**: Falsely reported success when images were missing, offline, or inaccessible.
- **Fix**: Removed `--ignore-pull-failures || true`, captured the exit code, logged truthful warnings if pulls failed, and set `save_state_val "images_pulled" "false"`.

### Defect 5 (HIGH): Misleading SSL and Nginx Status in Final Installation Summary
- **File & Lines**: `deploy/install.sh:753-754`
- **Root Cause**: The summary unconditionally printed `Reverse Proxy: Host Nginx (Validated & Active)` and `SSL Certificates: Valid Let's Encrypt`, even when Let's Encrypt failed or the user selected 'n' to skip Nginx.
- **Impact**: Falsely claimed SSL was valid and Nginx was active.
- **Fix**: Added dynamic status tracking (`SSL_STATUS` and `NGINX_STATUS`) tied to actual script return codes.

### Defect 6 (HIGH): `healthcheck.sh` Omitted API and Storage Readiness
- **File & Lines**: `deploy/scripts/healthcheck.sh:26-36`
- **Root Cause**: Only checked the loopback edge proxy `/_health` (a static Caddy 200 responder), postgres, valkey, nats, and meilisearch. Did not check `afendor-api`, `afendor-gateway`, `afendor-media-proxy`, or `afendor-seaweedfs`.
- **Impact**: A broken API or down storage engine was falsely reported as "Result: All core systems OPERATIONAL".
- **Fix**: Replaced `eval` with direct execution, added container readiness checks for `afendor-api`, `afendor-gateway`, `afendor-media-proxy`, and added an S3 gateway probe for `afendor-seaweedfs`.

### Defect 7 (MEDIUM): Pseudo-TTY Flag `-t` in `backup.sh` Corrupted SQL Stream
- **File & Lines**: `deploy/scripts/backup.sh:23`
- **Root Cause**: `docker exec -t afendor-postgres pg_dump ...` used `-t` (allocate pseudo-TTY), injecting CRLF `\r\n` line endings into the SQL stream.
- **Fix**: Removed `-t` to produce a pure binary/text stream without TTY transformation.

### Defect 8 (MEDIUM): LiveKit Health Check Masked Failures with `|| exit 0`
- **File & Lines**: `deploy/compose/docker-compose.yml:208`
- **Root Cause**: `test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:7880/ || exit 0"]` forced exit code 0 even if LiveKit was dead.
- **Fix**: Removed `|| exit 0` so Docker accurately reports container failure.

### Defect 9 (MEDIUM): Hardcoded SeaweedFS Secret in Production Configuration
- **File & Lines**: `deploy/install.sh:522`, `deploy/compose/docker-compose.yml:170`
- **Root Cause**: `AFENDOR_S3_SECRET_ACCESS_KEY=afendor-secret` was static across all installations.
- **Fix**: Dynamically generated `S3_LOCAL_SECRET=$(openssl rand -hex 24)` and `LIVEKIT_KEY="afendor_$(openssl rand -hex 6)"`.

### Defect 10 (LOW): Python SigV4 Missing `import urllib.parse` and Non-Standard `%T`
- **File & Lines**: `deploy/scripts/s3-verify.sh:74, 103`
- **Root Cause**: Relied on indirect `urllib.parse` import and non-standard `%T` strftime.
- **Fix**: Explicitly imported `urllib.parse` and used standard `%Y%m%dT%H%M%SZ`.

---

## 4. Security Audit Findings & Posture

| Category | Finding | Severity | Resolution |
| :--- | :--- | :---: | :--- |
| **Command Injection** | Unescaped variable interpolation in Python `-c` string literals inside `install.sh` | **HIGH** | Replaced with `sys.argv[1]` argument passing. |
| **Arbitrary Code Exec** | `eval "${cmd}"` in `healthcheck.sh` | **MEDIUM** | Replaced with direct array expansion `"$@"`. |
| **Credential Hygiene** | Default static secret `afendor-secret` for SeaweedFS | **MEDIUM** | Replaced with `openssl rand -hex 24` per installation. |
| **Pipe Hijacking** | Unsanitized `read -p` swallowing stdin during `curl \| bash` | **MEDIUM** | Replaced with `/dev/tty` input reader `read_prompt()`. |
| **Exposure of Secrets** | Risk of leaked secrets in shell history or state during failed S3 attempts | **LOW** | Cleared in-memory credentials immediately upon fallback. |

---

## 5. Remaining Production Blockers

Before AFENDOR CHAT can be launched on the authorized GCP VPS, the following prerequisites must be completed:

1. **Publish GitHub Repository**:
   - Create public repository `https://github.com/reign/afendor-chat` (or `afendor/afendor-chat`).
   - Push current source code (`git push origin main`).
2. **Build and Publish Container Images**:
   - Build production Docker images for `afendor-api`, `afendor-gateway`, `afendor-media-proxy`, `afendor-app-proxy`, and `afendor-admin`.
   - Push public images to GitHub Container Registry (`ghcr.io/afendor/*` or `ghcr.io/reign/*`).
3. **Configure DNS Records**:
   - Create A records pointing apex, `web`, `api`, `gateway`, `media`, `cdn`, `admin`, and `livekit` to the VPS public IP.
   - **Crucial**: Ensure `livekit.<domain>` is set to **Grey Cloud (DNS-Only / No Proxy)** in Cloudflare to permit WebRTC UDP traffic (`7882/udp`).
4. **Firewall Openings on GCP VPS**:
   - Ingress TCP `80`, `443` (Nginx HTTP/HTTPS).
   - Ingress TCP `7881` (LiveKit WebRTC TCP fallback).
   - Ingress UDP `7882` (LiveKit WebRTC UDP media).

---

## 6. Known Architectural Characteristics

- **In-Place Recreation Downtime**: Updating via `afendorctl update` stops and recreates containers in-place. This incurs a brief **2 to 5 second service interruption**. Active WebSocket connections will momentarily disconnect and automatically reconnect. True zero-downtime blue-green deployment is not implemented to keep VPS resource usage lightweight.
- **Database Migrations on Rollback**: `rollback.sh` restores PostgreSQL database snapshots (`.sql.gz`) and verifies `__fluxer_schema_migrations`. If a newer migration altered columns or dropped tables and the user declines database restoration, older application containers may experience schema mismatches. Database snapshot restoration is strongly recommended during rollbacks.


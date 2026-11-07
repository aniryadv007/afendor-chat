# AFENDOR CHAT — SECURITY & HARDENING CHECKLIST

> **Mandate:** Private personal platform; zero public SaaS exposure; robust defense-in-depth  

---

## 1. Access Control & Registration Policies

- [x] **Invite-Only Registration Enforcement:** Open public registration is disabled (`AFENDOR_REGISTRATION_MODE=invite_only`). Accounts cannot be created without an active cryptographically signed invitation link issued by the server owner.
- [x] **Setup Token Defense:** The initial administrator setup token (`AFENDOR_SETUP_TOKEN`) can be used only once to bootstrap the owner account.
- [x] **Sudo Mode for Critical Operations:** Changing passwords, managing API tokens, deleting servers, or expelling users requires a recent sudo-mode authentication challenge (`AFENDOR_SUDO_MODE_SECRET`).

---

## 2. End-to-End Encryption (E2EE) Reality Audit

> [!IMPORTANT]
> **Honest Cryptographic Transparency:**  
> - **Voice & Video Media (LiveKit):** WebRTC voice, video, and screen sharing stream directly between participants via the LiveKit SFU. End-to-end encryption (Insertable Streams / Frame Cryptor) is supported client-to-client for real-time voice streams.
> - **Chat Messages & Text History:** Text messages are encrypted in transit via **TLS 1.3** and stored encrypted at the volume level on PostgreSQL and Valkey. However, messages are **not** client-side asymmetric E2EE; the server must index them for full-text search (Meilisearch) and push notifications.
> - **Attachments:** Files in Backblaze B2 or SeaweedFS are stored with server-side encryption (SSE-S3). Access is governed strictly via temporary signed HMAC URLs.

---

## 3. Host & Container Isolation Hardening

- [x] **Database Isolation:** PostgreSQL, Valkey, and NATS ports are **not** mapped to host interfaces (`127.0.0.1` or `0.0.0.0`). They exist solely on the internal Docker bridge network (`afendor-net`).
- [x] **No Root in Containers:** Key application containers drop root privileges and execute as dedicated system users (`node` or unprivileged IDs).
- [x] **Environment File Permissions:** `config/env/production.env` is restricted to permissions `chmod 600` (readable only by the root user).
- [x] **Host Firewall Policy:** Only ports 80, 443, 7881, and 7882/udp are allowed ingress through the GCP Firewall. All other ingress is rejected by default.

---

## 4. Rate Limiting & Brute-Force Protection

- [x] **API Rate Limiting:** Endpoint calls are capped per IP and per session via in-memory Valkey sliding windows.
- [x] **Authentication Lockout:** Consecutive failed password attempts trigger progressive backoff delays.
- [x] **SSRF Protection in Unfurl:** The link crawler (`afendor-unfurl`) actively filters out private IP ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`, metadata endpoints `169.254.169.254`) to prevent Server-Side Request Forgery against the GCP VPS.


# AFENDOR CHAT — EXTERNAL DEPENDENCY & INTEGRATION AUDIT

> **Scope:** Full audit of all internal services, third-party APIs, and external accounts  
> **Privacy Mandate:** Zero external tracking, zero third-party telemetry, zero vendor lock-in  

---

## 1. Master Service Dependency Table

| Service / Component | In Repo? | In Docker? | External Host? | Domain Needed? | API Key? | Paid Service? | Optional? | Impact if Disabled |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Web App (`app-proxy`)** | Yes | Yes | No | `web.afendor.cc` | No | No | **No** | Web client cannot load. |
| **API Backend (`api`)** | Yes | Yes | No | `api.afendor.cc` | No | No | **No** | Login, channels, messages break. |
| **Gateway (`gateway`)** | Yes | Yes | No | `gateway.afendor.cc`| No | No | **No** | Real-time presence & live chat break. |
| **PostgreSQL (`postgres`)** | Yes | Yes | No | No | No | No | **No** | Entire datastore unavailable. |
| **Valkey (`valkey`)** | Yes | Yes | No | No | No | No | **No** | Sessions, locks & ratelimits fail. |
| **NATS (`nats`)** | Yes | Yes | No | No | No | No | **No** | Inter-service messaging halts. |
| **Meilisearch (`meilisearch`)**| Yes | Yes | No | No | No | No | Yes | In-chat message search unavailable. |
| **Media Proxy (`media-proxy`)**| Yes | Yes | No | `media.afendor.cc`| No | No | **No** | Attachment uploads/avatars fail. |
| **SeaweedFS (Mode A)** | Yes | Yes | No | No | No | No | Yes* | Swappable with Backblaze B2. |
| **Backblaze B2 (Mode B)** | No | No | Yes (Cloud) | No | Yes | Pay-as-you-go | Yes* | Swappable with SeaweedFS. |
| **Voice / Video (`livekit`)**| Yes | Yes | No | `livekit.afendor.cc`| Yes (Self) | No | Yes | Voice & video call features disabled. |
| **Push Service (`push`)** | Yes | Yes | No | No | No (VAPID) | No | Yes | Background mobile/web push fails. |
| **Unfurl Crawler (`unfurl`)**| Yes | Yes | No | No | No | No | Yes | Rich URL previews (OG cards) disabled.|
| **GIF Search (`gifs`)** | Yes | Yes | No | No | Optional | Optional | Yes | In-app GIF picker disabled. |
| **Email Delivery (SMTP)** | N/A | No | Yes (Host/Relay)| No | Yes | Optional | Yes | Password reset emails disabled. |

---

## 2. Third-Party Integrations Detail

### A. Backblaze B2 (Object Storage — Mode B)
- **Mandatory?** No (SeaweedFS can be used internally instead).
- **Cost:** Backblaze B2 provides **10 GB free** storage and **3x free egress** per day. For a private group of friends, total monthly cost is typically **$0.00**.
- **Credentials:** S3 Key ID and Application Key.

### B. GIF Provider (KLIPY or GIPHY)
- **Mandatory?** No (Optional).
- **Behavior if Unset:** The GIF picker modal in chat composer remains empty. Normal image and file uploads work independently.
- **Provider:** Free API key from KLIPY or GIPHY Developer portal.

### C. YouTube Data API v3
- **Mandatory?** No (Optional).
- **Behavior if Unset:** YouTube links in chat display as standard markdown hyperlinks rather than expanded rich media cards with title, thumbnail, and duration.
- **Provider:** Free Google Cloud Console YouTube Data API v3 key (up to 10,000 free quota units per day).

### D. Email Provider (SMTP)
- **Mandatory?** No (Optional).
- **Behavior if Unset:** Invitations and account recovery are managed directly by the administrator via the Admin Dashboard (`admin.afendor.cc`) using setup tokens or manual password resets.
- **Provider:** Any standard SMTP relay (e.g. Brevo free tier, Mailgun, or host-installed Postfix).

### E. Web Push (VAPID)
- **Mandatory?** No external paid service required.
- **Behavior:** Generated automatically using standard elliptic curve (P-256) cryptographic keypairs. Browsers deliver notifications directly to Mozilla, Google, and Apple notification gateways free of charge.

---

## 3. Minimum Monthly Operating Cost Breakdown

Apart from your existing GCP VPS (which you already maintain):

| Component | Provider | Tier | Monthly Cost |
| :--- | :--- | :--- | :--- |
| **Domain Name (`afendor.cc`)** | Existing Registrar | Registered | Already owned |
| **TLS Certificates** | Let's Encrypt | Automated ACME | **$0.00** |
| **Internal Storage (Mode A)**| SeaweedFS on VPS | Self-hosted | **$0.00** |
| **External Storage (Mode B)**| Backblaze B2 | First 10 GB Free | **$0.00** (or < $0.50/mo if > 10GB) |
| **YouTube Previews** | Google Cloud Console | 10k units/day free | **$0.00** |
| **GIF Search** | KLIPY API | Free Developer tier | **$0.00** |
| **Push Notifications** | VAPID (Direct W3C) | Native browser push | **$0.00** |
| **Total Added Cost** | — | — | **$0.00 / month** |


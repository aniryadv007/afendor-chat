# AFENDOR CHAT — DNS & NETWORK ENDPOINT ARCHITECTURE

> **Apex Domain:** `afendor.cc`  
> **VPS IPv4:** `<YOUR-GCP-VPS-PUBLIC-IP>`  
> **Reverse Proxy:** Host Nginx terminating SSL with Let's Encrypt Wildcard or Individual Certs  

---

## 1. Domain Directory & Endpoint Analysis

| Domain / FQDN | Public DNS? | Public HTTPS? | Protocols | Upstream Target | Purpose |
| :--- | :---: | :---: | :--- | :--- | :--- |
| **`afendor.cc`** | **Yes** | **Yes** | HTTP/1.1, HTTP/2 | `127.0.0.1:8080` | Apex domain; redirects to `web.afendor.cc` or displays portal. |
| **`web.afendor.cc`** | **Yes** | **Yes** | HTTP/1.1, HTTP/2 | `127.0.0.1:8080` | Primary SolidJS Web Client interface. |
| **`api.afendor.cc`** | **Yes** | **Yes** | HTTP/1.1, HTTP/2 | `127.0.0.1:8080` | REST API (Hono backend). |
| **`gateway.afendor.cc`** | **Yes** | **Yes** | HTTP/1.1 + **WebSocket**| `127.0.0.1:8080` | Real-time presence, typing, and channel events. |
| **`media.afendor.cc`** | **Yes** | **Yes** | HTTP/1.1, HTTP/2 | `127.0.0.1:8080` | Attachment downloads, uploads, and image rendering. |
| **`cdn.afendor.cc`** | **Yes** | **Yes** | HTTP/1.1, HTTP/2 | `127.0.0.1:8080` | Static JS/CSS chunks, system emojis, and fonts. |
| **`admin.afendor.cc`** | **Yes** | **Yes** | HTTP/1.1, HTTP/2 | `127.0.0.1:8080` | Private Admin Management Console. |
| **`livekit.afendor.cc`** | **Yes** | **Yes** | HTTP/1.1 + **WebSocket**| `127.0.0.1:7880` | WebRTC RTC signaling for voice & video calls. |

---

## 2. Required DNS Records

In your DNS provider (Cloudflare, Google Cloud DNS, Namecheap, etc.):

```
Type    Name                 Target (IPv4)                  TTL
──────────────────────────────────────────────────────────────────
A       afendor.cc           <YOUR-GCP-VPS-PUBLIC-IP>       300
CNAME   web.afendor.cc       afendor.cc                     300
CNAME   api.afendor.cc       afendor.cc                     300
CNAME   gateway.afendor.cc   afendor.cc                     300
CNAME   media.afendor.cc     afendor.cc                     300
CNAME   cdn.afendor.cc       afendor.cc                     300
CNAME   admin.afendor.cc     afendor.cc                     300
CNAME   livekit.afendor.cc   afendor.cc                     300
```

> [!TIP]
> Alternatively, you can configure a single wildcard DNS record:  
> `A  *.afendor.cc -> <YOUR-GCP-VPS-PUBLIC-IP>`  
> This immediately covers all 7 subdomains with zero maintenance.

---

## 3. End-to-End Packet Routing Diagram

```
[Browser / Desktop Client]
            │
            ├──── HTTPS (Port 443) ────────► [GCP Firewall] ──► [Host Nginx]
            │                                                      │
            │                                                      ├─► (afendor.cc, web, api, gateway, media, cdn, admin)
            │                                                      │   └──► Reverse Proxy to 127.0.0.1:8080 (Afendor Edge)
            │                                                      │          │
            │                                                      │          ├─► /api/*     ──► api:8080
            │                                                      │          ├─► /gateway   ──► gateway:8080 (WS)
            │                                                      │          ├─► /media/*   ──► media-proxy:8080
            │                                                      │          ├─► /admin/*   ──► admin:8080
            │                                                      │          └─► /*         ──► app-proxy:8080 (Web SPA)
            │                                                      │
            │                                                      └─► (livekit.afendor.cc)
            │                                                          └──► Reverse Proxy to 127.0.0.1:7880 (LiveKit Signaling)
            │
            ├──── WebRTC TCP (Port 7881) ──► [GCP Firewall] ───────────────────────────────────────────► [LiveKit Container:7881]
            │
            └──── WebRTC UDP (Port 7882) ──► [GCP Firewall] ───────────────────────────────────────────► [LiveKit Container:7882/udp]
```

---

## 4. WebSocket & Real-time Transport Rules

Both `gateway.afendor.cc` and `livekit.afendor.cc` require persistent bidirectional WebSocket connections.

In the provided `deploy/nginx/afendor.conf`:
- `proxy_http_version 1.1;`
- `proxy_set_header Upgrade $http_upgrade;`
- `proxy_set_header Connection $connection_upgrade;`
- `proxy_read_timeout 86400s;` (Prevents Nginx from severing idle chat connections)
- `proxy_buffering off;` (Ensures zero-latency delivery of live events)


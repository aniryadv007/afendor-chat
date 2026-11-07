# AFENDOR CHAT — STORAGE ARCHITECTURE & OPERATIONS GUIDE

> **Supported Storage Modes:** Mode A (Bundled SeaweedFS) & Mode B (External Backblaze B2 S3)  
> **Target Providers:** Local Docker Volume / Backblaze B2 Cloud Storage  

---

## 1. Storage Backend Overview

Afendor Chat cleanly decouples **database records** from **raw object files** (avatars, attachments, banners, emojis, and voice clips).

```
┌─────────────────────────────────────────────────────────────┐
│                       AFENDOR CHAT                          │
└───────────────┬─────────────────────────────┬───────────────┘
                │                             │
                ▼                             ▼
┌───────────────────────────────┐ ┌───────────────────────────┐
│     PostgreSQL 16 Engine      │ │    Media Proxy / S3 SDK   │
│  - User Accounts & Passwords  │ │  - Avatars & Profile Pics │
│  - Guilds, Channels, Roles    │ │  - Chat Attachments (PDF) │
│  - Message Metadata & Texts   │ │  - Custom Emojis & Sounds │
│  - Stored in: afendor_postgres│ │  - Stored in: Object Store│
└───────────────────────────────┘ └───────────────────────────┘
```

---

## 2. Mode A: Bundled Internal Storage (SeaweedFS)

In Mode A, SeaweedFS runs inside the Docker Compose network.

### Characteristics:
- **Zero External Dependencies:** No cloud accounts or credit cards required.
- **Persistent Volume:** Stored in Docker named volume `afendor_seaweedfs_data` (`/var/lib/docker/volumes/afendor_seaweedfs_data/_data`).
- **Internal S3 API:** Listens on `seaweedfs:8333` accessible only within the container bridge network.
- **Security:** SeaweedFS ports are never exposed to the public internet or VPS host interface. All uploads and downloads are strictly brokered through the authenticated `afendor-media-proxy`.

### Configuration in `production.env`:
```ini
AFENDOR_MEDIA_PROXY_STORAGE_BACKEND=s3
AFENDOR_S3_ENDPOINT=http://seaweedfs:8333
AFENDOR_S3_PUBLIC_ENDPOINT=https://media.afendor.cc
AFENDOR_S3_REGION=us-east-1
AFENDOR_S3_ACCESS_KEY_ID=afendor
AFENDOR_S3_SECRET_ACCESS_KEY=afendor-secret
AFENDOR_S3_FORCE_PATH_STYLE=true
AFENDOR_S3_BUCKET_CDN=afendor
AFENDOR_S3_BUCKET_UPLOADS=afendor-uploads
AFENDOR_S3_BUCKET_REPORTS=afendor-reports
AFENDOR_S3_BUCKET_HARVESTS=afendor-harvests
AFENDOR_S3_BUCKET_STATIC=afendor-static
```

---

## 3. Mode B: External S3 Storage (Backblaze B2)

In Mode B, all object storage is offloaded to Backblaze B2 (or Cloudflare R2 / AWS S3).

### Characteristics:
- **Zero VPS Disk Footprint:** Large video attachments and file uploads do not consume expensive VPS disk space.
- **High Durability:** 99.999999999% data durability provided by Backblaze B2.
- **Container Sizing:** The `seaweedfs` and `seaweedfs-init` containers are shut down and disabled via `docker-compose.s3.yml`.
- **Security:** S3 credentials (Key ID and Application Key) reside strictly in `config/env/production.env` (accessible only by `root`). They are never exposed to browsers or desktop clients.

### Backblaze B2 Setup Steps:
1. Log into Backblaze B2 console.
2. Create a Private Bucket named `afendor-uploads` (or your preferred name).
3. Under **App Keys**, generate a new Application Key with `Read and Write` permissions scoped to that bucket.
4. Note your S3 Endpoint (e.g. `https://s3.us-west-004.backblazeb2.com`), Key ID, and Application Key.

### Configuration in `production.env`:
```ini
AFENDOR_MEDIA_PROXY_STORAGE_BACKEND=s3
AFENDOR_S3_ENDPOINT=https://s3.us-west-004.backblazeb2.com
AFENDOR_S3_PUBLIC_ENDPOINT=https://media.afendor.cc
AFENDOR_S3_REGION=us-west-004
AFENDOR_S3_ACCESS_KEY_ID=<your-b2-application-key-id>
AFENDOR_S3_SECRET_ACCESS_KEY=<your-b2-application-key>
AFENDOR_S3_FORCE_PATH_STYLE=false
AFENDOR_S3_BUCKET_CDN=afendor-uploads
AFENDOR_S3_BUCKET_UPLOADS=afendor-uploads
AFENDOR_S3_BUCKET_REPORTS=afendor-uploads
AFENDOR_S3_BUCKET_HARVESTS=afendor-uploads
AFENDOR_S3_BUCKET_STATIC=afendor-uploads
```

---

## 4. Migration Procedure: Mode A (Internal) to Mode B (Backblaze B2)

If you start with Mode A and wish to migrate to Backblaze B2 without data loss:

### Step 1: Install `rclone` on the VPS
```bash
sudo apt-get install -y rclone
```

### Step 2: Configure `rclone`
Run `rclone config` to set up:
- `local_s3`: Endpoint `http://127.0.0.1:8333`, Access Key `afendor`, Secret `afendor-secret`.
- `b2_s3`: Endpoint `https://s3.us-west-004.backblazeb2.com`, Access Key `<key-id>`, Secret `<app-key>`.

### Step 3: Copy existing objects to Backblaze B2
```bash
# Sync all uploads from SeaweedFS to Backblaze B2
rclone copy local_s3:afendor-uploads b2_s3:afendor-uploads --progress
```

### Step 4: Verify checksums
```bash
rclone check local_s3:afendor-uploads b2_s3:afendor-uploads
```

### Step 5: Update `config/env/production.env`
Update the `AFENDOR_S3_*` variables to point to your Backblaze B2 credentials.

### Step 6: Restart Afendor Chat with S3 profile
```bash
afendorctl restart
```
Uploads will now be served seamlessly from Backblaze B2!


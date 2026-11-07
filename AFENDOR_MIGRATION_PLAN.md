# AFENDOR CHAT — MIGRATION & TRANSITION PLAN

> **Purpose:** Safe migration of database, objects, and configurations without data loss  

---

## 1. Migrating from Upstream Fluxer to Afendor Chat

If you have an existing upstream Fluxer deployment or database:

### A. Database Migration Safety
- Upstream Fluxer tracks migrations via the `__fluxer_schema_migrations` table in PostgreSQL.
- Afendor Chat's database executor (`afendor_svc/src/postgres.rs`) retains backwards-compatible schema migration detection: it inspects existing tables and will NOT re-run completed migrations or drop existing tables.
- All user IDs, guild IDs, channel snowflakes, and password hashes (Argon2id) remain completely valid and intact.

### B. Execution Steps:
1. Create a full dump of the existing database:
   ```bash
   docker exec -t existing-fluxer-postgres pg_dump -U fluxer fluxer > upstream_dump.sql
   ```
2. In Afendor Chat's PostgreSQL container:
   ```bash
   cat upstream_dump.sql | docker exec -i afendor-postgres psql -U afendor -d afendor
   ```
3. Restart Afendor Chat:
   ```bash
   afendorctl restart
   ```

---

## 2. Storage Backend Migration (SeaweedFS ➔ Backblaze B2)

When switching from bundled SeaweedFS to Backblaze B2:

1. **Keep Containers Running:** Ensure SeaweedFS is active during the copy phase.
2. **Execute Rclone Sync:**
   ```bash
   rclone copy local_seaweedfs:afendor-uploads b2:your-afendor-b2-bucket --progress --checksum
   ```
3. **Verify Integrity:**
   ```bash
   rclone check local_seaweedfs:afendor-uploads b2:your-afendor-b2-bucket
   ```
4. **Switch Configuration:** In `config/env/production.env`, update `AFENDOR_S3_ENDPOINT` to your Backblaze B2 URL and insert the B2 Key ID and Secret Key.
5. **Apply S3 Profile:**
   ```bash
   afendorctl restart
   ```
6. **Verify Attachments:** Open existing messages in `https://web.afendor.cc` and confirm images and files render correctly.

---

## 3. Domain Migration to `afendor.cc`

If changing host domain names:
1. Update DNS records (A and CNAME records) to point to your VPS IP.
2. Obtain a new TLS certificate via Certbot:
   ```bash
   sudo certbot certonly --nginx -d afendor.cc -d *.afendor.cc
   ```
3. Update `AFENDOR_BASE_DOMAIN=afendor.cc` and related endpoints in `config/env/production.env`.
4. Update Nginx server block in `/etc/nginx/sites-available/afendor.conf`.
5. Reload Nginx: `sudo systemctl reload nginx`.
6. Restart Afendor: `sudo afendorctl restart`.


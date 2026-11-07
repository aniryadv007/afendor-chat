# AFENDOR CHAT — BACKUP, RESTORE & DISASTER RECOVERY

> **Policy:** Database backups, configuration backups, and object storage are decoupled.  
> **Retention:** 14-day rolling local retention; unlimited off-site versioning.  

---

## 1. Backup Strategy Overview

| Data Tier | What is Backed Up | Tool | Format | Storage Location |
| :--- | :--- | :--- | :--- | :--- |
| **PostgreSQL Database** | User accounts, chat history, channel structure, roles | `pg_dump` | `.sql.gz` | `/opt/afendor/backups/` & Backblaze B2 |
| **Instance Configuration** | `production.env`, Nginx configs, Compose files | `tar` | `.tar.gz` | `/opt/afendor/backups/` & Backblaze B2 |
| **Object Media (Mode A)** | Avatars, file attachments | `rclone` / S3 | Raw S3 objects | Off-site S3 / Backblaze B2 bucket |
| **Object Media (Mode B)** | Avatars, file attachments | Native B2 | Cloud S3 | Maintained natively in Backblaze B2 |

---

## 2. On-Demand & Scheduled Automated Backups

### Run Instant Backup:
```bash
sudo afendorctl backup
```

### Automated Nightly Cron Job:
Add the following line to `crontab -e`:
```cron
# Run Afendor Chat full database and config backup every night at 3:00 AM UTC
0 3 * * * /usr/local/bin/afendorctl backup >> /var/log/afendor_backup.log 2>&1
```

---

## 3. Off-Site Backups to Backblaze B2 via Rclone

To ensure backups survive VPS loss, configure `rclone` to sync snapshots off-site:

1. Install rclone:
   ```bash
   sudo apt-get install -y rclone
   ```
2. Configure a remote named `b2`:
   ```bash
   rclone config
   # Select 'Backblaze B2', enter Account ID and Application Key
   ```
3. Test sync:
   ```bash
   rclone copy /opt/afendor/backups/ b2:afendor-backups-vault/
   ```

---

## 4. Disaster Recovery Procedure (Rebuilding from Scratch)

If your VPS is destroyed or migrated to a new machine:

1. Provision a fresh Ubuntu 24.04 VPS on GCP.
2. Ensure ports 80, 443, 7881, 7882/udp are open in GCP firewall.
3. Install Docker: `curl -fsSL https://get.docker.com | sh`.
4. Create directory: `sudo mkdir -p /opt/afendor && cd /opt/afendor`.
5. Restore your latest configuration archive:
   ```bash
   tar -xzf afendor_env_YYYYMMDD_HHMMSS.tar.gz -C /opt/afendor/
   ```
6. Start base services (Postgres):
   ```bash
   docker compose -f deploy/compose/docker-compose.yml up -d postgres
   ```
7. Restore database snapshot:
   ```bash
   gunzip -c afendor_backup_YYYYMMDD_HHMMSS.sql.gz | docker exec -i afendor-postgres psql -U afendor -d afendor
   ```
8. Start full stack:
   ```bash
   docker compose -f deploy/compose/docker-compose.yml up -d
   ```
9. Verify with `afendorctl health`.


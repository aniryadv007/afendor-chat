#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - AUTOMATED PRODUCTION BACKUP SCRIPT
# Supports: PostgreSQL pg_dump, Configuration archiving, and optional B2 sync
# Location: /opt/afendorchat/deploy/scripts/backup.sh
# Cron example (Daily at 3 AM): 0 3 * * * /opt/afendorchat/deploy/scripts/backup.sh >/dev/null 2>&1
# ==============================================================================

set -euo pipefail

AFENDOR_DIR="${AFENDOR_DIR:-/opt/afendorchat}"
if [ ! -d "${AFENDOR_DIR}" ] && [ -d "/opt/afendor" ]; then
    AFENDOR_DIR="/opt/afendor"
fi
BACKUP_DIR="${AFENDOR_DIR}/backups"
ENV_FILE="${AFENDOR_DIR}/config/env/production.env"

mkdir -p "${BACKUP_DIR}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DB_FILE="${BACKUP_DIR}/afendor_backup_${TIMESTAMP}.sql.gz"
CONF_FILE="${BACKUP_DIR}/afendor_env_${TIMESTAMP}.tar.gz"

echo "[AFENDOR BACKUP] Dumping PostgreSQL database..."
if docker exec afendor-postgres pg_isready -U afendor -d afendor >/dev/null 2>&1; then
    docker exec afendor-postgres pg_dump -U afendor afendor | gzip > "${DB_FILE}"
    chmod 600 "${DB_FILE}"
    echo "[AFENDOR BACKUP] Database saved: ${DB_FILE} ($(du -h "${DB_FILE}" | cut -f1))"
else
    echo "[AFENDOR BACKUP] ERROR: PostgreSQL container is not healthy!" >&2
    exit 1
fi

echo "[AFENDOR BACKUP] Archiving configurations..."
tar -czf "${CONF_FILE}" -C "${AFENDOR_DIR}" config/ deploy/
chmod 600 "${CONF_FILE}"
echo "[AFENDOR BACKUP] Configurations saved: ${CONF_FILE}"

# Optional: Sync backup to remote S3 storage if rclone is installed and configured
if command -v rclone &>/dev/null && [ -f "${HOME}/.config/rclone/rclone.conf" ]; then
    echo "[AFENDOR BACKUP] Uploading snapshot to remote object storage..."
    rclone copy "${DB_FILE}" remote:afendor-backups/database/ || true
    rclone copy "${CONF_FILE}" remote:afendor-backups/config/ || true
fi

# Retention Policy: Delete local database and config backups older than 14 days
find "${BACKUP_DIR}" -name "afendor_backup_*.sql.gz" -mtime +14 -delete || true
find "${BACKUP_DIR}" -name "afendor_env_*.tar.gz" -mtime +14 -delete || true

echo "[AFENDOR BACKUP] Backup cycle completed successfully."


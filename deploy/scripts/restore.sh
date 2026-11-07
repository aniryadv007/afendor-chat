#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - DATABASE RESTORATION SCRIPT
# Usage: ./restore.sh /path/to/backup.sql.gz
# Location: /opt/afendorchat/deploy/scripts/restore.sh
# ==============================================================================

set -euo pipefail

AFENDOR_DIR="${AFENDOR_DIR:-/opt/afendorchat}"
if [ ! -d "${AFENDOR_DIR}" ] && [ -d "/opt/afendor" ]; then
    AFENDOR_DIR="/opt/afendor"
fi
COMPOSE_FILE="${AFENDOR_DIR}/deploy/compose/docker-compose.yml"

BACKUP_FILE="${1:-}"

if [ -z "${BACKUP_FILE}" ] || [ ! -f "${BACKUP_FILE}" ]; then
    echo "ERROR: Please specify a valid .sql.gz backup file to restore."
    echo "Usage: $0 <path_to_backup.sql.gz>"
    exit 1
fi

echo "================================================================="
echo "                AFENDOR CHAT DATABASE RESTORE                    "
echo "================================================================="
echo "TARGET BACKUP: ${BACKUP_FILE}"
echo "WARNING: This operation will overwrite all data currently in the"
echo "PostgreSQL database 'afendor'."
echo "================================================================="
read -p "Type 'RESTORE' in capital letters to confirm: " CONFIRM

if [ "${CONFIRM}" != "RESTORE" ]; then
    echo "Restoration aborted."
    exit 0
fi

echo "[AFENDOR RESTORE] Stopping active API and Worker services..."
docker compose -f "${COMPOSE_FILE}" stop api worker || true

echo "[AFENDOR RESTORE] Streaming database dump into PostgreSQL..."
gunzip -c "${BACKUP_FILE}" | docker exec -i afendor-postgres psql -U afendor -d afendor

echo "[AFENDOR RESTORE] Restarting core services..."
docker compose -f "${COMPOSE_FILE}" start api worker

echo "[AFENDOR RESTORE] Verification completed successfully!"


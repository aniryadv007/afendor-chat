#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - PRODUCTION ROLLBACK SCRIPT
# Restores previous pinned known-good container images and database state
# Location: /opt/afendorchat/deploy/scripts/rollback.sh
# ==============================================================================

set -euo pipefail

AFENDOR_DIR="${AFENDOR_DIR:-/opt/afendorchat}"
if [ ! -d "${AFENDOR_DIR}" ] && [ -d "/opt/afendor" ]; then
    AFENDOR_DIR="/opt/afendor"
fi
COMPOSE_DIR="${AFENDOR_DIR}/deploy/compose"
ENV_FILE="${AFENDOR_DIR}/config/env/production.env"
BACKUP_DIR="${AFENDOR_DIR}/backups"
ROLLBACK_FILE="${AFENDOR_DIR}/.rollback_images.json"
cd "${AFENDOR_DIR}"

COMPOSE_ARGS="-f ${COMPOSE_DIR}/docker-compose.yml"
if [ -f "${ENV_FILE}" ]; then
    s3_endpoint=$(grep "^AFENDOR_S3_ENDPOINT=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 || echo "")
    if [[ -n "${s3_endpoint}" && ! "${s3_endpoint}" =~ seaweedfs ]]; then
        COMPOSE_ARGS="${COMPOSE_ARGS} -f ${COMPOSE_DIR}/docker-compose.s3.yml"
    fi
fi

echo "[AFENDOR ROLLBACK] Initiating emergency rollback..."

# 1. Check for recorded previous known-good images
if [ -f "${ROLLBACK_FILE}" ]; then
    echo "[AFENDOR ROLLBACK] Reading previous known-good container images from ${ROLLBACK_FILE}..."
    PREV_TIMESTAMP=$(python3 -c "import json; data=json.load(open('${ROLLBACK_FILE}')); print(data.get('recorded_at', 'unknown'))" 2>/dev/null || echo "unknown")
    echo "  Previous known-good snapshot timestamp: ${PREV_TIMESTAMP}"
else
    echo "[AFENDOR ROLLBACK] WARNING: No pinned .rollback_images.json found. Will rollback to local cached images."
fi

# 2. Database Snapshot Verification & Migration Compatibility Check
LATEST_BACKUP=$(ls -t "${BACKUP_DIR}"/afendor_backup_*.sql.gz 2>/dev/null | head -n 1 || true)

if [ -z "${LATEST_BACKUP}" ]; then
    echo "[AFENDOR ROLLBACK] WARNING: No database snapshot found in ${BACKUP_DIR}."
    read -p "Continue rolling back containers without database restoration? (y/N): " proceed
    if [[ ! "${proceed}" =~ ^[Yy]$ ]]; then
        echo "Aborting rollback."
        exit 1
    fi
else
    echo "[AFENDOR ROLLBACK] Most recent database snapshot: ${LATEST_BACKUP}"
    
    # Check current schema migration state
    CURRENT_MIGRATIONS=$(docker exec afendor-postgres psql -U afendor -d afendor -t -c "SELECT count(*) FROM __fluxer_schema_migrations;" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
    echo "  Current applied database migrations: ${CURRENT_MIGRATIONS}"
    
    read -p "Restore this database snapshot? (yes/no): " restore_db
    if [ "${restore_db}" = "yes" ]; then
        echo "[AFENDOR ROLLBACK] Restoring database..."
        "${AFENDOR_DIR}/deploy/scripts/restore.sh" "${LATEST_BACKUP}"
        
        # Verify post-restore schema state
        POST_RESTORE_MIGRATIONS=$(docker exec afendor-postgres psql -U afendor -d afendor -t -c "SELECT count(*) FROM __fluxer_schema_migrations;" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
        if [ "${CURRENT_MIGRATIONS}" != "unknown" ] && [ "${POST_RESTORE_MIGRATIONS}" != "unknown" ]; then
            if [ "${CURRENT_MIGRATIONS}" -gt "${POST_RESTORE_MIGRATIONS}" ]; then
                echo "[AFENDOR ROLLBACK] [NOTICE] Reverted $((CURRENT_MIGRATIONS - POST_RESTORE_MIGRATIONS)) newer database migration(s) to match the snapshot."
            fi
        fi
    else
        echo "[AFENDOR ROLLBACK] [CAUTION] Proceeding without database restoration. Schema mismatches may cause API errors if columns were altered."
    fi
fi

# 3. Rollback containers by restoring pinned previous image tags
echo "[AFENDOR ROLLBACK] Restoring previous known-good image tags from state..."
if [ -f "${ROLLBACK_FILE}" ]; then
    python3 -c "
import json, subprocess
try:
    with open('${ROLLBACK_FILE}', 'r') as f:
        data = json.load(f)
    prev = data.get('previous_known_good', {})
    for svc, info in prev.items():
        img_id = info.get('image_id')
        cfg_tag = info.get('configured_tag')
        if img_id and cfg_tag:
            print(f'  Restoring {svc} -> {cfg_tag} (ID: {img_id[:12]})')
            subprocess.run(['docker', 'tag', img_id, cfg_tag], check=False)
except Exception as e:
    print(f'  Warning restoring image tags: {e}')
" 2>/dev/null || true
fi

echo "[AFENDOR ROLLBACK] Recreating containers using restored known-good images..."
# Restart with local images without pulling latest
docker compose ${COMPOSE_ARGS} up -d --remove-orphans

echo "[AFENDOR ROLLBACK] Validating service health post-rollback..."
sleep 10
if "${AFENDOR_DIR}/deploy/scripts/healthcheck.sh"; then
    echo "[AFENDOR ROLLBACK] SUCCESS: Rollback completed and all services verified operational."
else
    echo "[AFENDOR ROLLBACK] ERROR: Services failed healthcheck after rollback. Review logs: afendorctl logs"
    exit 1
fi

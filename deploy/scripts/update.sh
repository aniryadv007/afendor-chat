#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - SAFE PRODUCTION UPDATE SCRIPT
# In-Place Container Recreation with Image Pinning and Automated Rollback State
# Location: /opt/afendorchat/deploy/scripts/update.sh
# ==============================================================================

set -euo pipefail

AFENDOR_DIR="${AFENDOR_DIR:-/opt/afendorchat}"
if [ ! -d "${AFENDOR_DIR}" ] && [ -d "/opt/afendor" ]; then
    AFENDOR_DIR="/opt/afendor"
fi
COMPOSE_DIR="${AFENDOR_DIR}/deploy/compose"
ENV_FILE="${AFENDOR_DIR}/config/env/production.env"
ROLLBACK_FILE="${AFENDOR_DIR}/.rollback_images.json"
cd "${AFENDOR_DIR}"

COMPOSE_ARGS="-f ${COMPOSE_DIR}/docker-compose.yml"
if [ -f "${ENV_FILE}" ]; then
    s3_endpoint=$(grep "^AFENDOR_S3_ENDPOINT=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 || echo "")
    if [[ -n "${s3_endpoint}" && ! "${s3_endpoint}" =~ seaweedfs ]]; then
        COMPOSE_ARGS="${COMPOSE_ARGS} -f ${COMPOSE_DIR}/docker-compose.s3.yml"
    fi
fi

echo "[AFENDOR UPDATE] 1/5 - Recording current container image digests for rollback..."
# Record running container image digests
python3 -c "
import subprocess, json, datetime
services = [
    'afendor-api', 'afendor-gateway', 'afendor-media-proxy', 
    'afendor-app-proxy', 'afendor-edge', 'afendor-livekit', 
    'afendor-postgres', 'afendor-valkey', 'afendor-nats', 'afendor-meilisearch'
]
current = {}
for s in services:
    try:
        img = subprocess.check_output(['docker', 'inspect', '--format', '{{.Image}}', s], text=True).strip()
        tag = subprocess.check_output(['docker', 'inspect', '--format', '{{.Config.Image}}', s], text=True).strip()
        if img:
            current[s] = {'image_id': img, 'configured_tag': tag}
    except Exception:
        pass

rollback_data = {
    'recorded_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'previous_known_good': current
}
with open('${ROLLBACK_FILE}', 'w') as f:
    json.dump(rollback_data, f, indent=2)
" 2>/dev/null || true
echo "[AFENDOR UPDATE] Current known-good image state pinned to ${ROLLBACK_FILE}"

echo "[AFENDOR UPDATE] 2/5 - Creating encrypted database and configuration snapshot..."
"${AFENDOR_DIR}/deploy/scripts/backup.sh"

echo "[AFENDOR UPDATE] 3/5 - Pulling latest release images from container registry..."
docker compose ${COMPOSE_ARGS} pull

echo "[AFENDOR UPDATE] 4/5 - Recreating containers in-place (brief 2-5s service interruption)..."
docker compose ${COMPOSE_ARGS} up -d --remove-orphans

echo "[AFENDOR UPDATE] Waiting for microservice convergence and database readiness (12s)..."
sleep 12

echo "[AFENDOR UPDATE] 5/5 - Executing automated post-update health check..."
if "${AFENDOR_DIR}/deploy/scripts/healthcheck.sh"; then
    # Record newly active image digests
    python3 -c "
import subprocess, json, datetime
try:
    with open('${ROLLBACK_FILE}', 'r') as f:
        data = json.load(f)
except Exception:
    data = {}

services = [
    'afendor-api', 'afendor-gateway', 'afendor-media-proxy', 
    'afendor-app-proxy', 'afendor-edge', 'afendor-livekit', 
    'afendor-postgres', 'afendor-valkey', 'afendor-nats', 'afendor-meilisearch'
]
deployed = {}
for s in services:
    try:
        img = subprocess.check_output(['docker', 'inspect', '--format', '{{.Image}}', s], text=True).strip()
        tag = subprocess.check_output(['docker', 'inspect', '--format', '{{.Config.Image}}', s], text=True).strip()
        if img:
            deployed[s] = {'image_id': img, 'configured_tag': tag}
    except Exception:
        pass

data['active_deployed'] = deployed
data['updated_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
with open('${ROLLBACK_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

    echo "[AFENDOR UPDATE] SUCCESS: Afendor Chat updated and verified operational!"
else
    echo "[AFENDOR UPDATE] CRITICAL ERROR: Post-update health check failed!"
    echo "To execute an automated rollback to the pinned previous version, run:"
    echo "    afendorctl rollback"
    exit 1
fi

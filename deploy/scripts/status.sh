#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - CLUSTER & SERVICE STATUS REPORTER
# Location: /opt/afendorchat/deploy/scripts/status.sh
# ==============================================================================

set -euo pipefail

AFENDOR_DIR="${AFENDOR_DIR:-/opt/afendorchat}"
if [ ! -d "${AFENDOR_DIR}" ] && [ -d "/opt/afendor" ]; then
    AFENDOR_DIR="/opt/afendor"
fi
cd "${AFENDOR_DIR}"

echo "================================================================="
echo "                AFENDOR CHAT PRODUCTION STATUS                  "
echo "================================================================="
echo "Date: $(date -u)"
echo "Host: $(hostname -f)"
echo "Uptime: $(uptime -p)"
echo ""

echo "--- 1. CONTAINER STATUS ---"
docker compose -f deploy/compose/docker-compose.yml ps
echo ""

echo "--- 2. RESOURCE CONSUMPTION ---"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" $(docker ps -q --filter "name=afendor-") 2>/dev/null || true
echo ""

echo "--- 3. PERSISTENT DISK USAGE ---"
df -h / | awk 'NR==1 || NR==2'
echo ""

echo "--- 4. LISTENING INTERNAL & EXTERNAL PORTS ---"
ss -tuln | grep -E ':8080|:7880|:7881|:7882|:5432|:6379|:4222' || true
echo "================================================================="


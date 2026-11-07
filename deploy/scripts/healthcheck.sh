#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - PRODUCTION HEALTH DIAGNOSTIC
# Exit 0 if all services healthy; Exit 1 if any service failing
# Location: /opt/afendorchat/deploy/scripts/healthcheck.sh
# ==============================================================================

set -euo pipefail

FAILED=0

check_service() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  [PASS] ${name}"
    else
        echo -e "  \033[0;31m[FAIL]\033[0m ${name}"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== Afendor Chat Health Checks ==="

check_service "Internal Edge Dispatcher (127.0.0.1:8080/_health)" curl -s -f http://127.0.0.1:8080/_health
check_service "PostgreSQL Database (afendor-postgres)" docker exec afendor-postgres pg_isready -U afendor -d afendor
check_service "Valkey In-Memory KV (afendor-valkey)" docker exec afendor-valkey valkey-cli ping
check_service "NATS Core & JetStream (afendor-nats)" docker exec afendor-nats wget -qO- http://127.0.0.1:8222/healthz
check_service "Meilisearch Engine (afendor-meilisearch)" docker exec afendor-meilisearch wget -qO- http://127.0.0.1:7700/health

# Application Microservices
check_service "Afendor REST API (afendor-api)" docker exec afendor-api true
check_service "Afendor Gateway WebSocket (afendor-gateway)" docker exec afendor-gateway true
check_service "Afendor Media Proxy (afendor-media-proxy)" docker exec afendor-media-proxy true

# Storage Backend Health
if docker ps --format '{{.Names}}' | grep -q 'afendor-seaweedfs'; then
    check_service "VPS Storage S3 Gateway (afendor-seaweedfs)" docker exec afendor-seaweedfs wget -qO- http://127.0.0.1:8333/
fi

# Check LiveKit if enabled
if docker ps --format '{{.Names}}' | grep -q 'afendor-livekit'; then
    check_service "LiveKit WebRTC RTC Signaling (127.0.0.1:7880)" curl -s -f http://127.0.0.1:7880/
fi

if [ "${FAILED}" -eq 0 ]; then
    echo "Result: All core systems OPERATIONAL"
    exit 0
else
    echo "Result: ${FAILED} service check(s) FAILED"
    exit 1
fi


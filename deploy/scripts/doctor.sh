#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - COMPREHENSIVE DOCTOR & DIAGNOSTICS UTILITY
# Inspects VPS infrastructure, Docker containers, ports, Nginx, SSL, and database
# Location: /opt/afendorchat/deploy/scripts/doctor.sh
# ==============================================================================

set -euo pipefail

AFENDOR_DIR="${AFENDOR_DIR:-/opt/afendorchat}"
if [ ! -d "${AFENDOR_DIR}" ] && [ -d "/opt/afendor" ]; then
    AFENDOR_DIR="/opt/afendor"
fi
ENV_FILE="${AFENDOR_DIR}/config/env/production.env"

DOMAIN="example.com"
if [ -f "${ENV_FILE}" ]; then
    DOMAIN=$(grep "^AFENDOR_BASE_DOMAIN=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 || echo "example.com")
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ISSUES=0

pass() { echo -e "  [${GREEN}PASS${NC}] $1"; }
warn() { echo -e "  [${YELLOW}WARN${NC}] $1"; }
fail() { echo -e "  [${RED}FAIL${NC}] $1"; ISSUES=$((ISSUES + 1)); }

echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}             AFENDOR CHAT - SYSTEM & SERVICE DOCTOR             ${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "Target Domain: ${CYAN}${DOMAIN}${NC}\n"

# 1. System Resources
echo -e "${BOLD}1. Hardware & Operating System${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    pass "Operating System: ${NAME} ${VERSION_ID}"
else
    warn "Cannot identify Linux distribution."
fi

CPUS=$(nproc || echo 1)
if [ "${CPUS}" -ge 4 ]; then
    pass "CPU Cores: ${CPUS} (Optimal)"
elif [ "${CPUS}" -ge 2 ]; then
    pass "CPU Cores: ${CPUS} (Meets minimum requirements)"
else
    fail "CPU Cores: ${CPUS} (Below recommended 2+ cores)"
fi

RAM_MB=$(free -m | awk '/^Mem:/{print $2}' || echo 0)
if [ "${RAM_MB}" -ge 7500 ]; then
    pass "Memory: ${RAM_MB} MB (Optimal for high concurrency)"
elif [ "${RAM_MB}" -ge 3800 ]; then
    pass "Memory: ${RAM_MB} MB (Meets 4GB minimum requirement)"
else
    fail "Memory: ${RAM_MB} MB (Insufficient RAM; min 4000MB required)"
fi

DISK_GB=$(df -BG "${AFENDOR_DIR}" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo 0)
if [ "${DISK_GB}" -ge 20 ]; then
    pass "Disk Free: ${DISK_GB} GB"
else
    warn "Disk Free: ${DISK_GB} GB (Recommend at least 20GB free)"
fi

# 2. Docker & Compose
echo -e "\n${BOLD}2. Container Engine & Orchestration${NC}"
if command -v docker &>/dev/null; then
    pass "Docker Engine: $(docker --version)"
    if systemctl is-active --quiet docker; then
        pass "Docker Daemon: Running"
    else
        fail "Docker Daemon is installed but NOT running"
    fi
else
    fail "Docker is NOT installed"
fi

if docker compose version &>/dev/null; then
    pass "Docker Compose v2: $(docker compose version --short)"
else
    fail "Docker Compose v2 is missing"
fi

# 3. Port Conflicts
echo -e "\n${BOLD}3. Required Host Ports & Bindings${NC}"
check_port() {
    local port="$1"
    local desc="$2"
    if ss -tuln | grep -q ":${port} "; then
        local proc
        proc=$(ss -tulpn "sport = :${port}" 2>/dev/null | awk 'NR==2 {print $NF}' || echo "unknown")
        if [[ "${proc}" =~ afendor|docker ]]; then
            pass "Port ${port} (${desc}) bound to Afendor/Docker (${proc})"
        else
            warn "Port ${port} (${desc}) is in use by another process: ${proc}"
        fi
    else
        pass "Port ${port} (${desc}) is available"
    fi
}
check_port "8080" "Internal Edge Ingress (Loopback)"
check_port "7880" "Internal LiveKit Signaling (Loopback)"
check_port "7881" "LiveKit TCP Fallback (Direct)"
check_port "7882" "LiveKit UDP Media (Direct)"

# 4. Host Nginx Reverse Proxy
echo -e "\n${BOLD}4. Nginx Reverse Proxy & Certificates${NC}"
if command -v nginx &>/dev/null; then
    if systemctl is-active --quiet nginx; then
        pass "Nginx: Active & Running"
        if nginx -t 2>/dev/null; then
            pass "Nginx Syntax: Valid"
        else
            fail "Nginx Syntax contains configuration errors"
        fi
    else
        warn "Nginx is installed but inactive"
    fi
else
    warn "Nginx is not installed on the host"
fi

if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
    enddate=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" 2>/dev/null | cut -d= -f2 || echo "")
    pass "SSL Certificate for ${DOMAIN}: Present (Expires: ${enddate})"
elif [ -d /etc/letsencrypt/live ]; then
    cert_found=false
    for cdir in /etc/letsencrypt/live/*; do
        if [ -f "${cdir}/fullchain.pem" ]; then
            enddate=$(openssl x509 -enddate -noout -in "${cdir}/fullchain.pem" 2>/dev/null | cut -d= -f2 || echo "")
            pass "SSL Certificate in ${cdir}: Present (Expires: ${enddate})"
            cert_found=true
            break
        fi
    done
    if [ "${cert_found}" = false ]; then
        warn "No Let's Encrypt certificates found in /etc/letsencrypt/live/"
    fi
else
    warn "No Let's Encrypt directory found at /etc/letsencrypt/live"
fi

# 5. Core Services Health
echo -e "\n${BOLD}5. Afendor Microservices Status${NC}"
if [ -f "${AFENDOR_DIR}/deploy/scripts/healthcheck.sh" ]; then
    bash "${AFENDOR_DIR}/deploy/scripts/healthcheck.sh" || ISSUES=$((ISSUES + 1))
else
    warn "Healthcheck script not found at ${AFENDOR_DIR}/deploy/scripts/healthcheck.sh"
fi

echo -e "\n================================================================"
if [ "${ISSUES}" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ DOCTOR REPORT: System is healthy and operational!${NC}"
    exit 0
else
    echo -e "${YELLOW}${BOLD}⚠ DOCTOR REPORT: ${ISSUES} issue(s) detected. Review logs above.${NC}"
    exit 1
fi

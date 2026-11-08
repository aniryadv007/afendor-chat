#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - DNS VERIFICATION UTILITY
# Tests all required application subdomains against VPS public IP and public resolvers
# Location: /opt/afendorchat/deploy/scripts/dns-verify.sh
# ==============================================================================

set -euo pipefail

AFENDOR_DIR="${AFENDOR_DIR:-/opt/afendorchat}"
if [ ! -d "${AFENDOR_DIR}" ] && [ -d "/opt/afendor" ]; then
    AFENDOR_DIR="/opt/afendor"
fi
ENV_FILE="${AFENDOR_DIR}/config/env/production.env"
DOMAIN="${1:-}"

if [ -z "${DOMAIN}" ] && [ -f "${ENV_FILE}" ]; then
    DOMAIN=$(grep "^AFENDOR_BASE_DOMAIN=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 || echo "example.com")
fi
DOMAIN="${DOMAIN:-example.com}"
TARGET_IP="${2:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Auto-detect public IP if not provided
if [ -z "${TARGET_IP}" ]; then
    TARGET_IP=$(curl -s -4 --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s -4 --max-time 5 https://ifconfig.me 2>/dev/null || \
                curl -s -4 --max-time 5 https://icanhazip.com 2>/dev/null || echo "")
fi

# List of required hostnames and their routing profile
RECORDS=(
    "${DOMAIN}:A:Orange Cloud (Proxied OK):Apex domain, marketing page, webfinger, and root redirects"
    "web.${DOMAIN}:A:Orange Cloud (Proxied OK):Main Afendor Web Chat client (SolidJS SPA)"
    "api.${DOMAIN}:A:Orange Cloud (Proxied OK):REST API, authentication, and user/guild management"
    "gateway.${DOMAIN}:A:Orange Cloud (Proxied OK):Real-time WebSocket event gateway (Requires WS enabled)"
    "media.${DOMAIN}:A:Orange Cloud (Proxied OK):Media proxy, avatar serving, and file attachment uploads"
    "livekit.${DOMAIN}:A:Grey Cloud (DNS-Only / NO PROXY):WebRTC Voice & Video signaling (Direct connection required)"
    "cdn.${DOMAIN}:A:Orange Cloud (Proxied OK):Static assets, cached media, and application icons"
    "admin.${DOMAIN}:A:Orange Cloud (Proxied OK):Administration panel and OAuth2 redirect callbacks"
)

echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}             AFENDOR CHAT - DNS RECORD SPECIFICATION            ${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "Target Server IPv4: ${CYAN}${TARGET_IP:-[Unable to auto-detect IP]}${NC}\n"

printf "%-4s %-25s %-18s %-22s\n" "TYPE" "HOSTNAME" "TARGET VALUE" "CLOUDFLARE PROXY"
echo "--------------------------------------------------------------------------------"
for record in "${RECORDS[@]}"; do
    IFS=':' read -r host type cf_proxy desc <<< "${record}"
    printf "%-4s %-25s %-18s %-22s\n" "${type}" "${host}" "${TARGET_IP}" "${cf_proxy}"
done
echo -e "--------------------------------------------------------------------------------\n"

echo -e "${BOLD}Detailed Record Descriptions & Cloudflare Guidance:${NC}"
echo -e "  * ${CYAN}livekit.${DOMAIN}${NC}: ${BOLD}${RED}MUST BE GREY CLOUD (DNS Only)${NC}."
echo -e "    Standard Cloudflare HTTP proxies do NOT route raw WebRTC UDP packets."
echo -e "    Audio/video streaming will fail if proxied through Cloudflare CDN."
echo -e "  * ${CYAN}gateway.${DOMAIN}${NC}: If using Cloudflare proxy (Orange Cloud), ensure"
echo -e "    ${BOLD}WebSockets${NC} are enabled under Cloudflare Network Settings."
echo -e "  * ${CYAN}media.${DOMAIN}${NC}: If using Cloudflare proxy, free tier limits single upload"
echo -e "    to 100MB. For larger uploads, direct DNS or chunked uploads are used."
echo -e "  * ${BOLD}SSL/TLS Encryption Mode${NC}: Set Cloudflare SSL/TLS to ${BOLD}Full (Strict)${NC}."
echo ""

# Function to resolve IPv4 of a domain
resolve_domain() {
    local host="$1"
    local resolved=""
    
    # 1. Try dig if available (querying 1.1.1.1 for unbiased public view)
    if command -v dig &>/dev/null; then
        resolved=$(dig +short +time=3 +tries=2 "@1.1.1.1" "${host}" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 1 || true)
        if [ -z "${resolved}" ]; then
            resolved=$(dig +short +time=3 +tries=2 "${host}" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 1 || true)
        fi
    # 2. Try host command
    elif command -v host &>/dev/null; then
        resolved=$(host -t A "${host}" 1.1.1.1 2>/dev/null | awk '/has address/ {print $NF}' | tail -n 1 || true)
        if [ -z "${resolved}" ]; then
            resolved=$(host -t A "${host}" 2>/dev/null | awk '/has address/ {print $NF}' | tail -n 1 || true)
        fi
    # 3. Try getent / python fallback
    elif command -v python3 &>/dev/null; then
        resolved=$(python3 -c "import socket; print(socket.gethostbyname('${host}'))" 2>/dev/null || true)
    elif command -v getent &>/dev/null; then
        resolved=$(getent ahostsv4 "${host}" 2>/dev/null | awk '{print $1}' | head -n 1 || true)
    fi

    echo "${resolved}"
}

# Function to check if an IP is a known Cloudflare proxy IP range
is_cloudflare_ip() {
    local ip="$1"
    if [[ "${ip}" =~ ^(172\.(6[4-9]|7[0-1])\.|104\.(1[6-9]|2[0-7])\.|108\.162\.|162\.158\.|190\.93\.|197\.234\.|198\.41\.|188\.114\.) ]]; then
        return 0
    else
        return 1
    fi
}

echo -e "${BOLD}Running DNS Resolution Diagnostics for '${DOMAIN}'...${NC}"
ALL_PASSED=true
FAILED_HOSTS=()

for record in "${RECORDS[@]}"; do
    IFS=':' read -r host type cf_proxy desc <<< "${record}"
    resolved_ip=$(resolve_domain "${host}")
    
    if [ -z "${resolved_ip}" ]; then
        echo -e "  [${RED}FAIL${NC}] ${BOLD}${host}${NC}: Not resolving (NXDOMAIN or query timeout)"
        ALL_PASSED=false
        FAILED_HOSTS+=("${host} (NXDOMAIN)")
    elif [ -n "${TARGET_IP}" ] && [ "${resolved_ip}" = "${TARGET_IP}" ]; then
        echo -e "  [${GREEN}PASS${NC}] ${BOLD}${host}${NC} -> ${resolved_ip} (Matches VPS IP directly)"
    elif is_cloudflare_ip "${resolved_ip}"; then
        if [ "${host}" = "livekit.${DOMAIN}" ]; then
            echo -e "  [${YELLOW}WARN${NC}] ${BOLD}${host}${NC} -> ${resolved_ip} (${YELLOW}Cloudflare Proxied${NC})"
            echo -e "         ${RED}^ WARNING: livekit.${DOMAIN} MUST be set to DNS-Only (Grey Cloud) in Cloudflare!${NC}"
            ALL_PASSED=false
            FAILED_HOSTS+=("${host} (Must be Grey Cloud, currently Proxied)")
        else
            echo -e "  [${GREEN}PASS${NC}] ${BOLD}${host}${NC} -> ${resolved_ip} (Cloudflare CDN Proxy active)"
        fi
    else
        if [ -n "${TARGET_IP}" ]; then
            echo -e "  [${RED}FAIL${NC}] ${BOLD}${host}${NC} -> ${resolved_ip} (${RED}Mismatch! Expected: ${TARGET_IP}${NC})"
            ALL_PASSED=false
            FAILED_HOSTS+=("${host} (Expected ${TARGET_IP}, got ${resolved_ip})")
        else
            echo -e "  [${GREEN}PASS${NC}] ${BOLD}${host}${NC} -> ${resolved_ip}"
        fi
    fi
done

echo ""
if [ "${ALL_PASSED}" = true ]; then
    echo -e "${GREEN}${BOLD}✓ All required DNS hostnames successfully verified for ${DOMAIN}!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ DNS verification failed for ${#FAILED_HOSTS[@]} record(s):${NC}"
    for fail in "${FAILED_HOSTS[@]}"; do
        echo -e "    - ${fail}"
    done
    exit 1
fi

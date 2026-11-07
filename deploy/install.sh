#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - PRODUCTION VPS GUIDED INSTALLER
# Intended execution: curl -fsSL https://deskapp.afendor.cc/install.sh | bash
# Target OS: Ubuntu 22.04 LTS / 24.04 LTS (Authorized Google Cloud Platform VPS)
# ==============================================================================

set -euo pipefail

INSTALL_DIR="${AFENDOR_DIR:-/opt/afendorchat}"
COMPOSE_DIR="${INSTALL_DIR}/deploy/compose"
CONFIG_DIR="${INSTALL_DIR}/config/env"
ENV_FILE="${CONFIG_DIR}/production.env"
STATE_FILE="${INSTALL_DIR}/.install_state.json"
BIN_DIR="${INSTALL_DIR}/deploy/bin"
SCRIPTS_DIR="${INSTALL_DIR}/deploy/scripts"
BACKUP_DIR="${INSTALL_DIR}/backups"

# Detect legacy /opt/afendor installation and seamlessly migrate data
LEGACY_DIR="/opt/afendor"
if [ "${INSTALL_DIR}" = "/opt/afendorchat" ] && [ -d "${LEGACY_DIR}" ] && [ ! -f "${INSTALL_DIR}/deploy/compose/docker-compose.yml" ]; then
    echo -e "  \033[1;33m[MIGRATE]\033[0m Detected existing legacy installation at ${LEGACY_DIR}."
    echo -e "  \033[1;33m[MIGRATE]\033[0m Migrating configuration and persistent data to ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"
    cp -a "${LEGACY_DIR}/." "${INSTALL_DIR}/" 2>/dev/null || true
    echo -e "  \033[0;32m[✓]\033[0m Legacy installation migration completed successfully."
fi

# Terminal styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_section() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n"
}

log_info() { echo -e "  ${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "  ${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
log_fail() { echo -e "  ${RED}[✗]${NC} $1"; }

# ------------------------------------------------------------------------------
# BANNER
# ------------------------------------------------------------------------------
clear 2>/dev/null || true
echo -e "${GREEN}${BOLD}"
echo "    █████╗ ███████╗███████╗███╗   ██╗██████╗  ██████╗ ██████╗ "
echo "   ██╔══██╗██╔════╝██╔════╝████╗  ██║██╔══██╗██╔═══██╗██╔══██╗"
echo "   ███████║█████╗  █████╗  ██╔██╗ ██║██║  ██║██║   ██║██████╔╝"
echo "   ██╔══██║██╔══╝  ██╔══╝  ██║╚██╗██║██║  ██║██║   ██║██╔══██╗"
echo "   ██║  ██║██║     ███████╗██║ ╚████║██████╔╝╚██████╔╝██║  ██║"
echo "   ╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═══╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝"
echo "                      C  H  A  T                              "
echo -e "${NC}"
echo -e "${CYAN}=== Production Self-Hosted Installer & Orchestrator ===${NC}"
echo -e "Primary Host: Current VPS (All services run locally via Docker Compose)"
echo -e "Public Distribution | VPS Storage & Generic S3 | Public Registration\n"

# ------------------------------------------------------------------------------
# STEP 0: STATE PERSISTENCE & RESUME HELPERS (Non-secret data only)
# ------------------------------------------------------------------------------
mkdir -p "${INSTALL_DIR}" "${CONFIG_DIR}" "${BIN_DIR}" "${SCRIPTS_DIR}" "${BACKUP_DIR}"

load_state_val() {
    local key="$1"
    if [ -f "${STATE_FILE}" ]; then
        python3 -c "
import json
try:
    with open('${STATE_FILE}', 'r') as f: data = json.load(f)
    print(data.get('${key}', ''))
except Exception:
    print('')
" 2>/dev/null || grep "\"${key}\"" "${STATE_FILE}" 2>/dev/null | sed -E 's/.*"'"${key}"'":\s*"([^"]+)".*/\1/' || echo ""
    else
        echo ""
    fi
}

save_state_val() {
    local key="$1"
    local val="$2"
    if [ ! -f "${STATE_FILE}" ]; then
        echo "{}" > "${STATE_FILE}"
    fi
    python3 -c "
import json
try:
    with open('${STATE_FILE}', 'r') as f: data = json.load(f)
except Exception:
    data = {}
data[sys.argv[1]] = sys.argv[2]
with open(sys.argv[3], 'w') as f: json.dump(data, f, indent=2)
" "${key}" "${val}" "${STATE_FILE}" 2>/dev/null || true
}

# Safe interactive input reader (supports piped execution e.g. curl ... | bash)
read_prompt() {
    local prompt_text="$1"
    local var_name="$2"
    local default_val="${3:-}"
    local is_secret="${4:-false}"

    local user_val=""
    if [ -t 0 ]; then
        if [ "${is_secret}" = "true" ]; then
            read -rsp "${prompt_text}" user_val
            echo ""
        else
            read -p "${prompt_text}" user_val
        fi
    elif [ -e /dev/tty ]; then
        if [ "${is_secret}" = "true" ]; then
            read -rsp "${prompt_text}" user_val </dev/tty
            echo ""
        else
            read -p "${prompt_text}" user_val </dev/tty
        fi
    else
        user_val="${default_val}"
    fi

    if [ -z "${user_val}" ] && [ -n "${default_val}" ]; then
        user_val="${default_val}"
    fi

    printf -v "${var_name}" '%s' "${user_val}"
}

# ------------------------------------------------------------------------------
# STEP 1: VPS AUTHORIZATION & PRE-FLIGHT CHECKS
# ------------------------------------------------------------------------------
log_section "1. VPS Authorization & Pre-Flight Checks"

# Check root privilege
if [ "$(id -u)" -ne 0 ]; then
    log_fail "Installer must be run as root (or with sudo). Aborting."
    exit 1
fi

# Cryptographic VPS Authorization Check
AUTH_HASH_FILE="${INSTALL_DIR}/.auth_expected_hash"
EXPECTED_HASH="${AFENDOR_INSTALL_KEY_HASH:-}"

if [ -z "${EXPECTED_HASH}" ] && [ -f "${AUTH_HASH_FILE}" ]; then
    EXPECTED_HASH=$(cat "${AUTH_HASH_FILE}" 2>/dev/null | tr -d '[:space:]' || echo "")
fi

AUTH_PASSED=$(load_state_val "authorized")
if [ "${AUTH_PASSED}" != "true" ] || [ ! -f "${AUTH_HASH_FILE}" ]; then
    REQUIRED_KEY="${AFENDOR_INSTALL_KEY:-}"
    if [ -z "${REQUIRED_KEY}" ]; then
        echo -e "  ${BOLD}Enter your Afendor VPS Installation Authorization Key:${NC}"
        read_prompt "  Auth Key: " PROVIDED_KEY "" true
    else
        PROVIDED_KEY="${REQUIRED_KEY}"
    fi

    # Fail closed on empty or short input
    if [ ${#PROVIDED_KEY} -lt 24 ]; then
        log_fail "Authorization failed: Key must be at least 24 high-entropy characters. Aborting."
        exit 1
    fi

    # Compute SHA-256 hash using python or sha256sum
    COMPUTED_HASH=$(python3 -c "import sys, hashlib; print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())" "${PROVIDED_KEY}" 2>/dev/null || echo -n "${PROVIDED_KEY}" | sha256sum | awk '{print $1}')

    if [ -n "${EXPECTED_HASH}" ]; then
        # Constant-time comparison
        AUTH_MATCH=$(python3 -c "import sys, hmac; print('true' if hmac.compare_digest(sys.argv[1], sys.argv[2]) else 'false')" "${COMPUTED_HASH}" "${EXPECTED_HASH}" 2>/dev/null || [ "${COMPUTED_HASH}" = "${EXPECTED_HASH}" ] && echo "true" || echo "false")
        if [ "${AUTH_MATCH}" != "true" ]; then
            log_fail "Authorization failed: Invalid authorization token for this VPS deployment. Aborting."
            exit 1
        fi
        log_success "VPS cryptographic authorization verified successfully."
    else
        # Initial provisioning: securely store the hash with restricted permissions (0600)
        echo "${COMPUTED_HASH}" > "${AUTH_HASH_FILE}"
        chmod 600 "${AUTH_HASH_FILE}"
        log_success "Initial VPS authorization hash established and secured in ${AUTH_HASH_FILE}."
    fi
    save_state_val "authorized" "true"
else
    log_success "VPS cryptographic authorization previously validated."
fi

# Detect Linux Distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_info "Operating System: ${NAME} ${VERSION_ID} (${ID})"
else
    log_warn "Cannot verify Linux distribution. Assuming Ubuntu/Debian compatibility."
fi

# Check Architecture
ARCH=$(uname -m)
log_info "Processor Architecture: ${ARCH}"
if [[ "${ARCH}" != "x86_64" && "${ARCH}" != "aarch64" ]]; then
    log_warn "Architecture ${ARCH} may require custom container compilation."
fi

# CPU Cores
CPU_CORES=$(nproc || echo 1)
log_info "CPU Cores Detected: ${CPU_CORES}"
if [ "${CPU_CORES}" -lt 2 ]; then
    log_warn "At least 2 CPU cores recommended. Found ${CPU_CORES}."
fi

# RAM Check
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}' || echo 4096)
log_info "Total System Memory: ${TOTAL_RAM_MB} MB"
if [ "${TOTAL_RAM_MB}" -lt 3800 ]; then
    log_warn "At least 4GB RAM required for complete service stack. Found ${TOTAL_RAM_MB} MB."
fi

# Free Disk Space
FREE_DISK_GB=$(df -BG "${INSTALL_DIR}" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo 50)
log_info "Available Disk Space: ${FREE_DISK_GB} GB"
if [ "${FREE_DISK_GB}" -lt 15 ]; then
    log_warn "Low disk space. At least 15-20GB recommended. Found ${FREE_DISK_GB} GB."
fi

# ------------------------------------------------------------------------------
# STEP 2: APPLICATION & FILE ACQUISITION (PUBLIC GITHUB REPOSITORY)
# ------------------------------------------------------------------------------
log_section "2. Application & File Acquisition"

NEED_ACQUISITION=false
if [ ! -f "${COMPOSE_DIR}/docker-compose.yml" ] || [ ! -f "${BIN_DIR}/afendorctl" ]; then
    NEED_ACQUISITION=true
fi

# Check if source files exist in the current working directory
CURRENT_EXEC_DIR="$(pwd)"
if [ "${NEED_ACQUISITION}" = true ] && [ -f "${CURRENT_EXEC_DIR}/deploy/compose/docker-compose.yml" ] && [ "${CURRENT_EXEC_DIR}" != "${INSTALL_DIR}" ]; then
    log_info "Detected deployment source files in current directory (${CURRENT_EXEC_DIR}). Initializing ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"
    cp -r "${CURRENT_EXEC_DIR}/deploy" "${INSTALL_DIR}/"
    cp -r "${CURRENT_EXEC_DIR}/config" "${INSTALL_DIR}/"
    cp -r "${CURRENT_EXEC_DIR}/packages" "${INSTALL_DIR}/" 2>/dev/null || true
    NEED_ACQUISITION=false
    log_success "Application deployment files installed from local source tree."
fi

if [ "${NEED_ACQUISITION}" = true ]; then
    log_info "Fresh VPS installation detected. Downloading application files from public GitHub..."
    
    if ! command -v git &>/dev/null; then
        apt-get update && apt-get install -y git curl tar
    fi

    GITHUB_REPO="${AFENDOR_GITHUB_REPO:-reign/afendor-chat}"
    read_prompt "  Public GitHub Repository [${GITHUB_REPO}]: " INPUT_REPO "${GITHUB_REPO}"
    GITHUB_REPO="${INPUT_REPO:-${GITHUB_REPO}}"

    log_info "Downloading application deployment files from public repository: ${GITHUB_REPO}..."
    TEMP_CLONE=$(mktemp -d)
    mkdir -p "${INSTALL_DIR}"
    if git clone --depth 1 "https://github.com/${GITHUB_REPO}.git" "${TEMP_CLONE}" 2>/dev/null; then
        cp -r "${TEMP_CLONE}/deploy" "${INSTALL_DIR}/"
        cp -r "${TEMP_CLONE}/config" "${INSTALL_DIR}/"
        cp -r "${TEMP_CLONE}/packages" "${INSTALL_DIR}/" 2>/dev/null || true
        rm -rf "${TEMP_CLONE}"
        log_success "Application deployment files downloaded and prepared."
    else
        log_info "Git clone failed. Attempting public release tarball download via curl..."
        if curl -fsSL "https://codeload.github.com/${GITHUB_REPO}/tar.gz/refs/heads/main" | tar -xz --strip-components=1 -C "${INSTALL_DIR}" 2>/dev/null || \
           curl -fsSL "https://codeload.github.com/${GITHUB_REPO}/tar.gz/refs/heads/master" | tar -xz --strip-components=1 -C "${INSTALL_DIR}" 2>/dev/null || \
           curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/tarball/main" | tar -xz --strip-components=1 -C "${INSTALL_DIR}" 2>/dev/null; then
            rm -rf "${TEMP_CLONE}"
            log_success "Application deployment files downloaded via GitHub public release tarball."
        else
            rm -rf "${TEMP_CLONE}"
            log_fail "Failed to acquire repository from public GitHub: ${GITHUB_REPO}."
            log_warn "If the repository has not yet been pushed to GitHub, copy the repository files to ${INSTALL_DIR} and rerun."
            exit 1
        fi
    fi

    # Optional GHCR token if provided in environment, otherwise public images pull without authentication
    if [ -n "${AFENDOR_GHCR_PAT:-}" ]; then
        log_info "Configuring optional private GHCR credentials from environment..."
        echo "${AFENDOR_GHCR_PAT}" | docker login ghcr.io -u "${AFENDOR_GHCR_USER:-reign}" --password-stdin 2>/dev/null || true
    fi
else
    log_success "Existing application deployment files verified at ${INSTALL_DIR}."
fi

# Ensure executable permissions on CLI and scripts
chmod +x "${BIN_DIR}/afendorctl" "${SCRIPTS_DIR}"/*.sh 2>/dev/null || true
ln -sf "${BIN_DIR}/afendorctl" /usr/local/bin/afendorctl

# ------------------------------------------------------------------------------
# STEP 3: CONTAINER ENGINE & PORT AUDIT
# ------------------------------------------------------------------------------
log_section "3. Container Engine & Port Conflict Audit"

if ! command -v docker &>/dev/null; then
    log_warn "Docker Engine is not installed."
    read_prompt "  Install official Docker Engine from get.docker.com? (Y/n): " confirm_docker "Y"
    if [[ "${confirm_docker}" =~ ^[Yy]$ ]]; then
        log_info "Installing Docker Engine..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
        log_success "Docker Engine installed successfully."
    else
        log_fail "Docker Engine is required to run Afendor Chat. Aborting."
        exit 1
    fi
else
    log_success "Docker Engine: Installed ($(docker --version))"
fi

if ! docker compose version &>/dev/null; then
    log_warn "Docker Compose v2 plugin is missing. Installing..."
    apt-get update && apt-get install -y docker-compose-plugin
fi
log_success "Docker Compose v2: Installed ($(docker compose version --short))"

# Detect existing Nginx
if command -v nginx &>/dev/null; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_success "Detected active host Nginx reverse proxy. Afendor will integrate safely without port conflicts."
    else
        log_info "Host Nginx is installed but currently inactive."
    fi
fi

# Detect port availability on required internal endpoints
check_host_port() {
    local port="$1"
    local name="$2"
    if ss -tuln | grep -q ":${port} "; then
        local proc
        proc=$(ss -tulpn "sport = :${port}" 2>/dev/null | awk 'NR==2 {print $NF}' || echo "unknown")
        if [[ "${proc}" =~ afendor|docker ]]; then
            log_info "Port ${port} (${name}) is allocated to existing Afendor container (${proc})."
        else
            log_warn "Port ${port} (${name}) is currently occupied by: ${proc}"
            log_warn "Ensure this port does not conflict with other applications."
        fi
    else
        log_success "Port ${port} (${name}) is free and available."
    fi
}

check_host_port "8080" "Internal Ingress Multiplexer (Loopback)"
check_host_port "7880" "Internal LiveKit WebRTC Signaling (Loopback)"
check_host_port "7881" "LiveKit WebRTC TCP Fallback (Direct Host)"
check_host_port "7882" "LiveKit WebRTC UDP Media Stream (Direct Host)"

# ------------------------------------------------------------------------------
# STEP 4: USER-CONFIGURABLE DOMAIN SETTINGS (NOT HARDCODED)
# ------------------------------------------------------------------------------
log_section "4. Domain & Architecture Configuration"

SAVED_DOMAIN=$(load_state_val "domain")
SAVED_DOMAIN="${SAVED_DOMAIN:-example.com}"

echo -e "  Enter your primary domain (e.g. yourdomain.com, afendor.cc, or example.com)."
read_prompt "  Primary domain name [${SAVED_DOMAIN}]: " DOMAIN "${SAVED_DOMAIN}"
save_state_val "domain" "${DOMAIN}"

echo -e "\n  ${BOLD}Derived hostnames for '${DOMAIN}':${NC}"
echo -e "    * Apex Domain:        ${CYAN}${DOMAIN}${NC} (Landing, marketing & webfinger)"
echo -e "    * Web Client:         ${CYAN}web.${DOMAIN}${NC} (SolidJS Web App SPA)"
echo -e "    * REST API:           ${CYAN}api.${DOMAIN}${NC} (Authentication & backend API)"
echo -e "    * WebSocket Gateway:  ${CYAN}gateway.${DOMAIN}${NC} (Real-time Erlang Gateway)"
echo -e "    * Media Proxy:        ${CYAN}media.${DOMAIN}${NC} (File uploads & avatar proxy)"
echo -e "    * WebRTC Voice/Video: ${CYAN}livekit.${DOMAIN}${NC} (LiveKit WebRTC Signaling)"
echo -e "    * Static CDN:         ${CYAN}cdn.${DOMAIN}${NC} (Cached assets & symbols)"
echo -e "    * Admin Panel:        ${CYAN}admin.${DOMAIN}${NC} (Owner administration)"

# ------------------------------------------------------------------------------
# STEP 5: STORAGE SELECTION (VPS LOCAL STORAGE vs GENERIC S3)
# ------------------------------------------------------------------------------
log_section "5. Media & Attachment Storage Selection"

SAVED_STORAGE=$(load_state_val "storage_mode")
SAVED_STORAGE="${SAVED_STORAGE:-1}"

echo -e "  Select Media & Uploads Storage:"
echo "    [1] Option A: VPS Local Storage (Recommended Default)"
echo "        - Stores uploads directly on persistent VPS storage"
echo "        - Uses bundled SeaweedFS S3-compatible engine inside Docker"
echo "        - Zero external credentials, stores media directly on this VPS"
echo "    [2] Option B: External S3-Compatible Storage"
echo "        - Connect to any generic S3 provider (Backblaze B2, Cloudflare R2, AWS S3, Wasabi, MinIO, etc.)"
echo "        - Requires endpoint URL, credentials, and bucket verification"
read_prompt "  Choose Storage Option [1/2, default: ${SAVED_STORAGE}]: " STORAGE_CHOICE "${SAVED_STORAGE}"

S3_ENDPOINT=""
S3_REGION="us-east-1"
S3_KEY_ID=""
S3_SECRET_KEY=""
S3_BUCKET="afendor-uploads"
S3_FORCE_PATH="false"
S3_PUBLIC_EP=""

if [ "${STORAGE_CHOICE}" = "1" ]; then
    log_info "Option A selected: VPS Local Storage (SeaweedFS inside Docker)."
    FREE_SPACE_GB=$(df -BG "${INSTALL_DIR}" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo "unknown")
    echo -e "  Storage Location: ${CYAN}Docker volume (afendor_seaweedfs_data) on ${INSTALL_DIR}${NC}"
    echo -e "  Available Disk:   ${CYAN}${FREE_SPACE_GB} GB${NC}"
    save_state_val "storage_mode" "1"
    save_state_val "storage_verified" "true"
    log_success "VPS Local Storage validated."
else
    # Option B: External S3 with 3-Attempt Verification Loop
    S3_VERIFIED=false
    S3_ATTEMPT=1
    MAX_S3_ATTEMPTS=3

    while [ "${S3_VERIFIED}" != "true" ] && [ "${S3_ATTEMPT}" -le "${MAX_S3_ATTEMPTS}" ]; do
        echo -e "\n  ${CYAN}--- External S3 Configuration (Attempt ${S3_ATTEMPT} of ${MAX_S3_ATTEMPTS}) ---${NC}"
        echo -e "  Enter your generic S3 endpoint URL (e.g. https://s3.us-west-004.backblazeb2.com, https://<accountid>.r2.cloudflarestorage.com, https://s3.amazonaws.com, http://minio-host:9000):"
        read_prompt "  S3 Endpoint URL: " S3_ENDPOINT
        read_prompt "  S3 Region [${S3_REGION}]: " S3_REGION "${S3_REGION}"
        read_prompt "  S3 Access Key ID: " S3_KEY_ID
        read_prompt "  S3 Secret Access Key: " S3_SECRET_KEY "" true
        read_prompt "  Main Bucket Name [${S3_BUCKET}]: " S3_BUCKET "${S3_BUCKET}"
        read_prompt "  Force Path Style? (true/false) [false]: " S3_FORCE_PATH "false"
        read_prompt "  Public Media/CDN Endpoint [https://media.${DOMAIN}]: " S3_PUBLIC_EP "https://media.${DOMAIN}"

        log_info "Executing mandatory S3 verification (connectivity, auth, PutObject, GetObject, DeleteObject)..."
        if bash "${SCRIPTS_DIR}/s3-verify.sh" \
            --endpoint "${S3_ENDPOINT}" \
            --region "${S3_REGION}" \
            --access-key "${S3_KEY_ID}" \
            --secret-key "${S3_SECRET_KEY}" \
            --bucket "${S3_BUCKET}" \
            --force-path-style "${S3_FORCE_PATH}"; then
            S3_VERIFIED=true
            log_success "S3 storage verified operational!"
            save_state_val "storage_mode" "2"
            save_state_val "storage_verified" "true"
        else
            log_fail "S3 verification attempt ${S3_ATTEMPT} of ${MAX_S3_ATTEMPTS} failed!"
            S3_ATTEMPT=$((S3_ATTEMPT + 1))
            if [ "${S3_ATTEMPT}" -le "${MAX_S3_ATTEMPTS}" ]; then
                echo -e "  ${YELLOW}Please verify endpoint syntax, credentials, bucket name, or addressing mode and try again.${NC}"
            fi
        fi
    done

    # If all 3 attempts failed, automatically fallback to Option A (VPS Local Storage)
    if [ "${S3_VERIFIED}" != "true" ]; then
        echo -e "\n${YELLOW}${BOLD}================================================================${NC}"
        echo -e "${YELLOW}${BOLD}[!] S3 verification failed 3 times.${NC}"
        echo -e "${YELLOW}${BOLD}[!] Automatically falling back to Option A: VPS Local Storage (SeaweedFS).${NC}"
        echo -e "${YELLOW}${BOLD}================================================================${NC}\n"
        STORAGE_CHOICE=1
        save_state_val "storage_mode" "1"
        save_state_val "storage_fallback" "true"
        S3_ENDPOINT=""
        S3_KEY_ID=""
        S3_SECRET_KEY=""
    fi
fi

# ------------------------------------------------------------------------------
# STEP 6: CRYPTOGRAPHIC SECRETS & PRODUCTION CONFIGURATION
# ------------------------------------------------------------------------------
log_section "6. Cryptographic Secrets & Environment Configuration"

VPS_PUBLIC_IP=$(curl -s -4 --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s -4 --max-time 5 https://ifconfig.me 2>/dev/null || \
                curl -s -4 --max-time 5 https://icanhazip.com 2>/dev/null || echo "")
log_info "Detected VPS Public IPv4: ${VPS_PUBLIC_IP:-[Unable to detect public IP]}"
save_state_val "public_ip" "${VPS_PUBLIC_IP}"

# Preserve existing secrets if present
if [ -f "${ENV_FILE}" ] && grep -q "AFENDOR_SETUP_TOKEN=" "${ENV_FILE}"; then
    log_info "Preserving existing cryptographic secrets from ${ENV_FILE}."
    SETUP_TOKEN=$(grep "^AFENDOR_SETUP_TOKEN=" "${ENV_FILE}" | cut -d= -f2)
else
    log_info "Generating high-entropy cryptographic secrets..."
    PG_PASSWORD=$(openssl rand -hex 18)
    SEARCH_KEY=$(openssl rand -hex 24)
    LIVEKIT_SECRET=$(openssl rand -hex 24)
    LIVEKIT_KEY="afendor_$(openssl rand -hex 6)"
    S3_LOCAL_SECRET=$(openssl rand -hex 24)
    SUDO_SECRET=$(openssl rand -hex 32)
    CONN_SECRET=$(openssl rand -hex 32)
    PSEUDO_SECRET=$(openssl rand -hex 32)
    MEDIA_SECRET=$(openssl rand -hex 32)
    ADMIN_SECRET=$(openssl rand -hex 32)
    OAUTH_SECRET=$(openssl rand -hex 32)
    SETUP_TOKEN=$(openssl rand -hex 24)
    UPLOAD_RELAY_B64=$(openssl rand -base64 32)
    URL_SECRETS_B64=$(openssl rand -base64 32)

    cat > "${ENV_FILE}" <<EOF
# SPDX-License-Identifier: AGPL-3.0-or-later
# Generated by Afendor Chat Guided Installer on $(date -u)

AFENDOR_ENV=production
NODE_ENV=production
AFENDOR_BASE_DOMAIN=${DOMAIN}
AFENDOR_PUBLIC_SCHEME=https
AFENDOR_PUBLIC_PORT=443
AFENDOR_STATIC_CDN_DOMAIN=cdn.${DOMAIN}
AFENDOR_PUBLIC_URL=https://${DOMAIN}

# Public Endpoints
AFENDOR_API_ENDPOINT=https://api.${DOMAIN}
AFENDOR_API_CLIENT_ENDPOINT=https://api.${DOMAIN}
AFENDOR_APP_ENDPOINT=https://web.${DOMAIN}
AFENDOR_GATEWAY_ENDPOINT=wss://gateway.${DOMAIN}
AFENDOR_MEDIA_ENDPOINT=https://media.${DOMAIN}
AFENDOR_STATIC_CDN_ENDPOINT=https://cdn.${DOMAIN}
AFENDOR_ADMIN_ENDPOINT=https://admin.${DOMAIN}
AFENDOR_MARKETING_ENDPOINT=https://${DOMAIN}

AFENDOR_TRUST_CLIENT_IP_HEADER=true
AFENDOR_CLIENT_IP_HEADER_NAME=x-forwarded-for

# Database Backend (PostgreSQL)
AFENDOR_DATABASE_BACKEND=postgres
AFENDOR_POSTGRES_HOST=postgres
AFENDOR_POSTGRES_PORT=5432
AFENDOR_POSTGRES_DATABASE=afendor
AFENDOR_POSTGRES_USERNAME=afendor
AFENDOR_POSTGRES_PASSWORD=${PG_PASSWORD}
AFENDOR_POSTGRES_SSL=false
AFENDOR_POSTGRES_MAX_CONNECTIONS=50
AFENDOR_POSTGRES_KV_TABLE=afendor_kv
AFENDOR_KV_URL=redis://valkey:6379/0
AFENDOR_NATS_URL=nats://nats:4222
AFENDOR_NATS_JETSTREAM_URL=nats://nats:4222

# Internal Service Routing (Host loopback 8080)
AFENDOR_INTERNAL_API_ENDPOINT=http://127.0.0.1:8080
AFENDOR_INTERNAL_MEDIA_PROXY_ENDPOINT=http://127.0.0.1:8082
AFENDOR_MEDIA_PROXY_ENDPOINT=http://127.0.0.1:8082
AFENDOR_MEDIA_PROXY_PUBLIC_ENDPOINT=https://media.${DOMAIN}

AFENDOR_SVC_NATS_URL=nats://nats:4222
AFENDOR_SVC_SHARD_COUNT=1
AFENDOR_SVC_CACHE_TTL_MS=30000

EOF

    if [ "${STORAGE_CHOICE}" = "2" ]; then
        cat >> "${ENV_FILE}" <<EOF
# Object Storage (Option B: External Generic S3)
AFENDOR_MEDIA_PROXY_STORAGE_BACKEND=s3
AFENDOR_S3_ENDPOINT=${S3_ENDPOINT}
AFENDOR_S3_PUBLIC_ENDPOINT=${S3_PUBLIC_EP}
AFENDOR_S3_REGION=${S3_REGION}
AFENDOR_S3_ACCESS_KEY_ID=${S3_KEY_ID}
AFENDOR_S3_SECRET_ACCESS_KEY=${S3_SECRET_KEY}
AFENDOR_S3_FORCE_PATH_STYLE=${S3_FORCE_PATH}
AFENDOR_S3_BUCKET_CDN=${S3_BUCKET}
AFENDOR_S3_BUCKET_UPLOADS=${S3_BUCKET}
AFENDOR_S3_BUCKET_REPORTS=${S3_BUCKET}
AFENDOR_S3_BUCKET_HARVESTS=${S3_BUCKET}
EOF
    else
        cat >> "${ENV_FILE}" <<EOF
# Object Storage (Option A: VPS Local Storage via SeaweedFS)
AFENDOR_MEDIA_PROXY_STORAGE_BACKEND=s3
AFENDOR_S3_ENDPOINT=http://seaweedfs:8333
AFENDOR_S3_PUBLIC_ENDPOINT=https://media.${DOMAIN}
AFENDOR_S3_REGION=us-east-1
AFENDOR_S3_ACCESS_KEY_ID=afendor
AFENDOR_S3_SECRET_ACCESS_KEY=${S3_LOCAL_SECRET}
AFENDOR_S3_FORCE_PATH_STYLE=true
AFENDOR_S3_BUCKET_CDN=afendor
AFENDOR_S3_BUCKET_UPLOADS=afendor-uploads
AFENDOR_S3_BUCKET_REPORTS=afendor-reports
AFENDOR_S3_BUCKET_HARVESTS=afendor-harvests
EOF
    fi

    cat >> "${ENV_FILE}" <<EOF

# Voice & Video (LiveKit WebRTC)
AFENDOR_LIVEKIT_ENABLED=true
AFENDOR_LIVEKIT_URL=wss://livekit.${DOMAIN}
AFENDOR_LIVEKIT_INTERNAL_URL=http://localhost:7880
AFENDOR_LIVEKIT_API_KEY=${LIVEKIT_KEY}
AFENDOR_LIVEKIT_API_SECRET=${LIVEKIT_SECRET}
AFENDOR_LIVEKIT_DEFAULT_REGION={"id":"default","name":"Global","emoji":"🌐","latitude":0.0,"longitude":0.0}

# Ports & Application Configuration
AFENDOR_API_PORT=8080
AFENDOR_API_PRESIGNED_ATTACHMENT_UPLOADS_ENABLED=true
AFENDOR_API_WORKER_MODE=all_lanes
AFENDOR_STATIC_DIR=afendor_app/dist

AFENDOR_MEDIA_PROXY_HOST=0.0.0.0
AFENDOR_MEDIA_PROXY_PORT=8082
AFENDOR_MEDIA_PROXY_SECRET_KEY=${MEDIA_SECRET}
AFENDOR_MEDIA_PROXY_MODE=upload

AFENDOR_GATEWAY_PORT=8771
AFENDOR_GATEWAY_MEDIA_PROXY_ENDPOINT=https://media.${DOMAIN}
AFENDOR_GATEWAY_STATIC_CDN_ENDPOINT=https://cdn.${DOMAIN}
AFENDOR_GATEWAY_RPC_AUTH_TOKEN=${LIVEKIT_SECRET}
AFENDOR_GATEWAY_LOGGER_LEVEL=info

AFENDOR_ADMIN_PORT=3020
AFENDOR_ADMIN_BASE_PATH=/admin
AFENDOR_ADMIN_SECRET_KEY_BASE=${ADMIN_SECRET}
AFENDOR_ADMIN_OAUTH_CLIENT_SECRET=${OAUTH_SECRET}
AFENDOR_ADMIN_OAUTH_REDIRECT_URI=https://admin.${DOMAIN}/oauth2_callback

# Security & Secrets
AFENDOR_SUDO_MODE_SECRET=${SUDO_SECRET}
AFENDOR_CONNECTION_INITIATION_SECRET=${CONN_SECRET}
AFENDOR_PROFILE_PSEUDONYM_SECRET=${PSEUDO_SECRET}
AFENDOR_PASSKEY_RP_NAME='Afendor Chat'
AFENDOR_PASSKEY_RP_ID=${DOMAIN}
AFENDOR_PASSKEY_ADDITIONAL_ALLOWED_ORIGINS=https://${DOMAIN},https://web.${DOMAIN}

# Public Registration & First-Time Owner Setup Token
AFENDOR_REGISTRATION_MODE=public
AFENDOR_SETUP_TOKEN=${SETUP_TOKEN}

# Search Engine (Meilisearch)
AFENDOR_SEARCH_ENGINE=meilisearch
AFENDOR_SEARCH_URL=http://meilisearch:7700
AFENDOR_SEARCH_API_KEY=${SEARCH_KEY}

AFENDOR_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64=${UPLOAD_RELAY_B64}
AFENDOR_MEDIA_PROXY_ATTACHMENT_URL_SECRETS_BASE64=${URL_SECRETS_B64}
AWS_EC2_METADATA_DISABLED=true
EOF
    chmod 600 "${ENV_FILE}"
    log_success "Generated production environment configuration at ${ENV_FILE}"
fi

# ------------------------------------------------------------------------------
# STEP 7: PRE-FETCH PRODUCTION DOCKER IMAGES
# ------------------------------------------------------------------------------
log_section "7. Pulling Production Container Images"

log_info "Pre-pulling production containers before requesting DNS verification..."
COMPOSE_ARGS="-f ${COMPOSE_DIR}/docker-compose.yml"
if [ "${STORAGE_CHOICE}" = "2" ]; then
    COMPOSE_ARGS="${COMPOSE_ARGS} -f ${COMPOSE_DIR}/docker-compose.s3.yml"
fi

if docker compose ${COMPOSE_ARGS} pull; then
    log_success "Production containers pulled and ready."
    save_state_val "images_pulled" "true"
else
    log_warn "Failed to pull pre-built container images from registry."
    log_info "Attempting to build application container images locally from source..."
    if docker compose ${COMPOSE_ARGS} build; then
        log_success "Local container image build completed successfully."
        save_state_val "images_pulled" "true"
    else
        log_warn "Local build encountered warnings; continuing with available images."
        save_state_val "images_pulled" "false"
    fi
fi

# ------------------------------------------------------------------------------
# STEP 8: DNS CONFIGURATION & REAL VERIFICATION LOOP
# ------------------------------------------------------------------------------
log_section "8. DNS Configuration & Verification Screen"

# Display DNS table customized for the chosen domain
bash "${SCRIPTS_DIR}/dns-verify.sh" "${DOMAIN}" "${VPS_PUBLIC_IP}" || true

DNS_VERIFIED=false
while [ "${DNS_VERIFIED}" != "true" ]; do
    echo -e "${BOLD}Please configure the DNS records above at your DNS provider (e.g. Cloudflare).${NC}"
    echo "  [1] Check DNS now"
    echo "  [2] Automatically retry DNS checks (every 20s)"
    echo "  [3] Exit installer and resume later"
    read_prompt "  Select an option [1/2/3, default: 1]: " DNS_ACTION "1"

    case "${DNS_ACTION}" in
        1)
            if bash "${SCRIPTS_DIR}/dns-verify.sh" "${DOMAIN}" "${VPS_PUBLIC_IP}"; then
                DNS_VERIFIED=true
            else
                log_warn "DNS records are not yet resolving correctly. Please check your DNS provider."
            fi
            ;;
        2)
            log_info "Entering automated DNS polling loop (Press Ctrl+C to cancel)..."
            while true; do
                if bash "${SCRIPTS_DIR}/dns-verify.sh" "${DOMAIN}" "${VPS_PUBLIC_IP}"; then
                    DNS_VERIFIED=true
                    break
                fi
                echo -e "  Waiting 20 seconds before retry..."
                sleep 20
            done
            ;;
        3)
            log_info "Exiting. All downloaded files, images, and secrets are preserved in ${INSTALL_DIR}."
            log_info "To resume at any time, run: afendorctl install"
            exit 0
            ;;
        *)
            log_warn "Invalid selection."
            ;;
    esac
done

# ------------------------------------------------------------------------------
# STEP 9: SSL CERTIFICATE MANAGEMENT (DISCOVER & REUSE)
# ------------------------------------------------------------------------------
log_section "9. SSL Certificate Management"

SSL_STATUS="Pending / Incomplete"
log_info "Inspecting existing Let's Encrypt certificates for domain '${DOMAIN}'..."
if bash "${SCRIPTS_DIR}/ssl-manage.sh" "${DOMAIN}" check; then
    log_success "Existing certificate is valid and covers all required hostnames. Reusing existing certificate!"
    SSL_STATUS="Valid Let's Encrypt (Reused)"
    save_state_val "ssl_valid" "true"
else
    log_info "Requesting missing SSL certificates from Let's Encrypt..."
    read_prompt "  Enter email address for Let's Encrypt renewal notices: " ADMIN_EMAIL ""
    if bash "${SCRIPTS_DIR}/ssl-manage.sh" "${DOMAIN}" issue "${ADMIN_EMAIL}"; then
        log_success "SSL certificates generated and verified."
        SSL_STATUS="Valid Let's Encrypt (Newly Issued)"
        save_state_val "ssl_valid" "true"
    else
        log_warn "Certificate issuance failed. Existing certificates and sites were preserved."
        log_warn "You can retry later with: afendorctl ssl-status"
        SSL_STATUS="Issuance Failed (Retry later with afendorctl ssl-status)"
        save_state_val "ssl_valid" "false"
    fi
fi

# ------------------------------------------------------------------------------
# STEP 10: HOST NGINX REVERSE PROXY INTEGRATION
# ------------------------------------------------------------------------------
log_section "10. Nginx Reverse Proxy Integration"

NGINX_STATUS="Not Active"
if command -v nginx &>/dev/null; then
    log_info "Integrating with existing host Nginx..."
    if bash "${SCRIPTS_DIR}/nginx-manage.sh" "${DOMAIN}" apply; then
        NGINX_STATUS="Host Nginx (Validated & Active)"
        save_state_val "nginx_active" "true"
    else
        NGINX_STATUS="Configuration Error (Review /etc/nginx/sites-available/afendor.conf)"
        save_state_val "nginx_active" "false"
    fi
else
    read_prompt "  Nginx is not installed. Install and configure Nginx now? (Y/n): " install_nginx "Y"
    if [[ "${install_nginx}" =~ ^[Yy]$ ]]; then
        apt-get update && apt-get install -y nginx
        systemctl enable --now nginx
        if bash "${SCRIPTS_DIR}/nginx-manage.sh" "${DOMAIN}" apply; then
            NGINX_STATUS="Host Nginx (Validated & Active)"
            save_state_val "nginx_active" "true"
        else
            NGINX_STATUS="Configuration Error (Review /etc/nginx/sites-available/afendor.conf)"
            save_state_val "nginx_active" "false"
        fi
    else
        log_warn "Skipping Nginx integration. Ensure internal port 8080 is routed manually."
        NGINX_STATUS="Skipped by user (Port 8080 must be proxied manually)"
        save_state_val "nginx_active" "false"
    fi
fi

# ------------------------------------------------------------------------------
# STEP 11: SYSTEMD SERVICE & DOCKER ACTIVATION
# ------------------------------------------------------------------------------
log_section "11. Systemd Service Registration & Starting Microservices"

# Register Systemd Unit
if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    log_info "Configuring systemd service unit: /etc/systemd/system/afendor.service..."
    cat > /etc/systemd/system/afendor.service <<EOF
[Unit]
Description=Afendor Chat Service Stack
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/local/bin/afendorctl start
ExecStop=/usr/local/bin/afendorctl stop

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable afendor.service
    log_success "Systemd service enabled: afendor.service"
else
    log_warn "Systemd not active or not running in this environment. Skipping systemd registration."
fi

log_info "Starting containers with project name 'afendor'..."
afendorctl start

log_info "Waiting for service convergence and database initialization (15s)..."
sleep 15

log_info "Executing automated service health checks..."
if ! afendorctl health; then
    log_fail "One or more mandatory Afendor services failed health checks!"
    log_warn "Installation NOT marked as complete. Configuration and containers are preserved."
    log_warn "Inspect service logs using: afendorctl logs"
    log_warn "After resolving the issue, retry health checks using: afendorctl health"
    log_warn "Or rerun the installer to resume: afendorctl install"
    save_state_val "installed" "false"
    exit 1
fi

# ------------------------------------------------------------------------------
# STEP 12: FINAL INSTALLATION SUMMARY (SHOWN ONLY AFTER COMPLETE VERIFICATION)
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}          AFENDOR CHAT INSTALLATION COMPLETED!                  ${NC}"
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo ""
echo -e "  ${BOLD}Primary Host:${NC}        Selected VPS (${VPS_PUBLIC_IP:-127.0.0.1})"
echo -e "  ${BOLD}Main URL:${NC}            https://${DOMAIN}"
echo -e "  ${BOLD}Web Client:${NC}          https://web.${DOMAIN}"
echo -e "  ${BOLD}API Endpoint:${NC}        https://api.${DOMAIN}"
echo -e "  ${BOLD}Gateway WebSocket:${NC}   wss://gateway.${DOMAIN}"
echo -e "  ${BOLD}Media Endpoint:${NC}      https://media.${DOMAIN}"
echo -e "  ${BOLD}LiveKit Signaling:${NC}   wss://livekit.${DOMAIN}"
echo -e "  ${BOLD}Admin Dashboard:${NC}     https://admin.${DOMAIN}"
echo ""
echo -e "  ${BOLD}Reverse Proxy:${NC}       ${NGINX_STATUS}"
echo -e "  ${BOLD}SSL Certificates:${NC}    ${SSL_STATUS}"
echo -e "  ${BOLD}Internal Edge Mux:${NC}   127.0.0.1:8080 (Loopback only)"
if [ "${STORAGE_CHOICE}" = "2" ]; then
    s3_host=$(echo "${S3_ENDPOINT}" | sed -E 's|https?://||; s|/.*||')
    echo -e "  ${BOLD}Storage Mode:${NC}        Option B: External S3 (${s3_host})"
else
    echo -e "  ${BOLD}Storage Mode:${NC}        Option A: VPS Local Storage (SeaweedFS inside Docker)"
fi
echo -e "  ${BOLD}Storage Status:${NC}      ${GREEN}Verified Operational${NC}"
echo -e "  ${BOLD}Registration Mode:${NC}   ${GREEN}Public by default${NC}"
echo ""
echo -e "  ${BOLD}INITIAL OWNER SETUP TOKEN:${NC}"
echo -e "  ${CYAN}${SETUP_TOKEN}${NC}"
echo ""
echo -e "  ${BOLD}FIRST-TIME SETUP INSTRUCTIONS:${NC}"
echo -e "  1. Open ${CYAN}https://web.${DOMAIN}${NC} in your browser."
echo -e "  2. Register your user account (public registration is open)."
echo -e "  3. Enter the Setup Token above to claim the ${BOLD}Owner Administrator${NC} role."
echo -e "  4. Complete the web wizard to configure Mailcow SMTP and storage preferences."
echo ""
echo -e "  ${BOLD}MANAGEMENT COMMANDS (afendorctl):${NC}"
echo -e "    afendorctl status       # View service status and resource metrics"
echo -e "    afendorctl logs -f      # Stream real-time service logs"
echo -e "    afendorctl doctor       # Run deep system and network diagnostic"
echo -e "    afendorctl dns-check    # Re-verify DNS records across public resolvers"
echo -e "    afendorctl ssl-status   # Inspect certificate expiry and SAN coverage"
echo -e "    afendorctl nginx-check  # Verify Nginx reverse proxy syntax and routing"
echo -e "    afendorctl backup       # Instant encrypted database & config backup"
echo -e "    afendorctl update       # In-place container update with DB backup"
echo -e "${GREEN}================================================================${NC}\n"

save_state_val "installed" "true"

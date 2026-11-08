#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - NGINX INTEGRATION AND REVERSE PROXY MANAGER
# Safely configures host Nginx reverse proxy without overwriting Mailcow or other sites
# Location: /opt/afendorchat/deploy/scripts/nginx-manage.sh
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

TEMPLATE_CONF="${AFENDOR_DIR}/deploy/nginx/afendor.conf.template"
DEST_AVAIL="/etc/nginx/sites-available/afendor.conf"
DEST_ENAB="/etc/nginx/sites-enabled/afendor.conf"
BACKUP_DIR="${AFENDOR_DIR}/backups/nginx"

# Certificate paths
CERT_FILE="${3:-/etc/letsencrypt/live/${DOMAIN}/fullchain.pem}"
KEY_FILE="${4:-/etc/letsencrypt/live/${DOMAIN}/privkey.pem}"

# If cert does not exist at default path, look for any match in /etc/letsencrypt/live/
if [ ! -f "${CERT_FILE}" ] && [ -d /etc/letsencrypt/live ]; then
    for cdir in /etc/letsencrypt/live/*; do
        if [ -f "${cdir}/fullchain.pem" ]; then
            CERT_FILE="${cdir}/fullchain.pem"
            KEY_FILE="${cdir}/privkey.pem"
            break
        fi
    done
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[NGINX-MANAGE]${NC} $1"; }
log_success() { echo -e "${GREEN}[NGINX-MANAGE]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[NGINX-MANAGE]${NC} $1"; }
log_error() { echo -e "${RED}[NGINX-MANAGE ERROR]${NC} $1" >&2; }

detect_nginx() {
    if ! command -v nginx &>/dev/null; then
        echo "missing"
    elif systemctl is-active --quiet nginx 2>/dev/null; then
        echo "running"
    else
        echo "installed_stopped"
    fi
}

cmd_check() {
    local status
    status=$(detect_nginx)
    log_info "Nginx System Status: ${status}"
    
    if [ "${status}" = "missing" ]; then
        log_warn "Nginx is not installed on this host."
        return 1
    fi

    log_info "Checking existing Nginx configuration syntax..."
    if nginx -t; then
        log_success "Current Nginx configuration syntax is valid."
    else
        log_error "Current Nginx configuration has errors. Resolve these before configuring Afendor."
        return 1
    fi

    echo -e "\n${BOLD}Active Virtual Hosts Detected:${NC}"
    ls -l /etc/nginx/sites-enabled/ 2>/dev/null || true
    return 0
}

cmd_apply() {
    local status
    status=$(detect_nginx)

    if [ "${status}" = "missing" ]; then
        log_error "Nginx is required. Please install Nginx first or permit the installer to install it."
        return 1
    fi

    mkdir -p "${BACKUP_DIR}" /var/www/certbot /etc/nginx/sites-available /etc/nginx/sites-enabled

    # Backup existing afendor configuration if it exists
    if [ -f "${DEST_AVAIL}" ]; then
        local timestamp
        timestamp=$(date +"%Y%m%d_%H%M%S")
        cp "${DEST_AVAIL}" "${BACKUP_DIR}/afendor.conf.bak_${timestamp}"
        log_info "Existing Afendor Nginx configuration backed up to ${BACKUP_DIR}/afendor.conf.bak_${timestamp}"
    fi

    log_info "Compiling Nginx template for domain '${DOMAIN}'..."
    if [ ! -f "${TEMPLATE_CONF}" ]; then
        log_error "Nginx configuration template missing from ${TEMPLATE_CONF}"
        return 1
    fi

    # Render template with variables
    sed -e "s|{{DOMAIN}}|${DOMAIN}|g" \
        -e "s|{{SSL_CERT_PATH}}|${CERT_FILE}|g" \
        -e "s|{{SSL_KEY_PATH}}|${KEY_FILE}|g" \
        "${TEMPLATE_CONF}" > "${DEST_AVAIL}"
    
    # Enable site symlink
    ln -sf "${DEST_AVAIL}" "${DEST_ENAB}"

    log_info "Testing Nginx syntax with new Afendor site configuration..."
    if nginx -t; then
        log_success "Nginx syntax verification passed!"
        log_info "Reloading Nginx with zero downtime..."
        systemctl reload nginx
        log_success "Nginx reloaded successfully. Afendor reverse proxy is active on domain '${DOMAIN}'."
        return 0
    else
        log_error "Nginx syntax test failed! Reverting changes to protect existing services..."
        rm -f "${DEST_ENAB}"
        if ls "${BACKUP_DIR}"/afendor.conf.bak_* 1>/dev/null 2>&1; then
            local latest_bak
            latest_bak=$(ls -t "${BACKUP_DIR}"/afendor.conf.bak_* | head -n 1)
            cp "${latest_bak}" "${DEST_AVAIL}"
            ln -sf "${DEST_AVAIL}" "${DEST_ENAB}"
            log_info "Restored previous working configuration from ${latest_bak}"
        else
            rm -f "${DEST_AVAIL}"
        fi
        nginx -t 2>/dev/null || true
        return 1
    fi
}

ACTION="${2:-check}"
case "${ACTION}" in
    check)
        cmd_check
        ;;
    apply)
        cmd_apply
        ;;
    *)
        cmd_check
        ;;
esac

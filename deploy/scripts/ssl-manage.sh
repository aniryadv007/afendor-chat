#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - SSL CERTIFICATE MANAGEMENT UTILITY
# Discovers, reuses, and safely issues Let's Encrypt certificates without breaking existing sites
# Location: /opt/afendorchat/deploy/scripts/ssl-manage.sh
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

WEBROOT="${AFENDOR_CERTBOT_WEBROOT:-/var/www/certbot}"
LE_DIR="/etc/letsencrypt/live"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REQUIRED_DOMAINS=(
    "${DOMAIN}"
    "web.${DOMAIN}"
    "api.${DOMAIN}"
    "gateway.${DOMAIN}"
    "media.${DOMAIN}"
    "livekit.${DOMAIN}"
    "admin.${DOMAIN}"
)

log_info() { echo -e "${BLUE}[SSL-MANAGE]${NC} $1"; }
log_success() { echo -e "${GREEN}[SSL-MANAGE]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[SSL-MANAGE]${NC} $1"; }
log_error() { echo -e "${RED}[SSL-MANAGE ERROR]${NC} $1" >&2; }

# Function to extract SANs from a certificate file
get_cert_sans() {
    local cert_file="$1"
    if [ ! -f "${cert_file}" ]; then
        echo ""
        return
    fi
    openssl x509 -noout -text -in "${cert_file}" 2>/dev/null | \
        awk '/Subject Alternative Name:/{getline; print}' | \
        tr -d ' ' | tr ',' '\n' | sed -e 's/^DNS://' || echo ""
}

# Function to get expiration date in epoch seconds
get_cert_expiry_epoch() {
    local cert_file="$1"
    if [ ! -f "${cert_file}" ]; then
        echo "0"
        return
    fi
    local end_date
    end_date=$(openssl x509 -enddate -noout -in "${cert_file}" 2>/dev/null | cut -d= -f2 || echo "")
    if [ -n "${end_date}" ]; then
        date -d "${end_date}" +%s 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Discover if an existing certificate covers all required hostnames
find_matching_certificate() {
    if [ ! -d "${LE_DIR}" ]; then
        echo ""
        return
    fi

    local current_time
    current_time=$(date +%s)
    local min_validity_buffer=604800 # 7 days in seconds

    for cert_dir in "${LE_DIR}"/*; do
        if [ -d "${cert_dir}" ] && [ -f "${cert_dir}/fullchain.pem" ]; then
            local cert_file="${cert_dir}/fullchain.pem"
            local expiry_epoch
            expiry_epoch=$(get_cert_expiry_epoch "${cert_file}")
            
            # Check if expired or expiring within 7 days
            if [ "$((expiry_epoch - current_time))" -lt "${min_validity_buffer}" ]; then
                continue
            fi

            local sans
            sans=$(get_cert_sans "${cert_file}")
            
            # Check if certificate has wildcard covering subdomains (*.example.com)
            local has_wildcard=false
            if echo "${sans}" | grep -q "^\*\.${DOMAIN}$"; then
                has_wildcard=true
            fi

            local all_covered=true
            for req in "${REQUIRED_DOMAINS[@]}"; do
                if [ "${has_wildcard}" = true ]; then
                    # Wildcard *.example.com covers all subdomains except root apex
                    if [ "${req}" = "${DOMAIN}" ]; then
                        if ! echo "${sans}" | grep -qx "${DOMAIN}"; then
                            all_covered=false
                            break
                        fi
                    fi
                else
                    if ! echo "${sans}" | grep -qx "${req}"; then
                        all_covered=false
                        break
                    fi
                fi
            done

            if [ "${all_covered}" = true ]; then
                echo "${cert_file}"
                return
            fi
        fi
    done
    echo ""
}

cmd_check() {
    log_info "Scanning system for existing Let's Encrypt certificates for domain '${DOMAIN}'..."
    local match
    match=$(find_matching_certificate)

    if [ -n "${match}" ]; then
        local cert_dir
        cert_dir=$(dirname "${match}")
        local cert_name
        cert_name=$(basename "${cert_dir}")
        local expiry_str
        expiry_str=$(openssl x509 -enddate -noout -in "${match}" | cut -d= -f2)

        log_success "Found valid existing certificate covering all hostnames for ${DOMAIN}!"
        echo -e "  Certificate Name: ${CYAN}${cert_name}${NC}"
        echo -e "  Certificate Path: ${CYAN}${match}${NC}"
        echo -e "  Expiration Date:  ${CYAN}${expiry_str}${NC}"
        echo -e "  Status:           ${GREEN}REUSABLE (No new certificate request needed)${NC}"
        return 0
    else
        log_warn "No single certificate currently covers all required subdomains for ${DOMAIN}."
        return 1
    fi
}

cmd_issue() {
    local email="${3:-}"
    
    # 1. First check if a certificate is already valid
    local existing_cert
    existing_cert=$(find_matching_certificate)
    if [ -n "${existing_cert}" ]; then
        log_success "Reusing existing valid certificate: ${existing_cert}"
        return 0
    fi

    # 2. Check Certbot availability
    if ! command -v certbot &>/dev/null; then
        log_info "Installing certbot and certbot-nginx plugin..."
        apt-get update && apt-get install -y certbot python3-certbot-nginx
    fi

    mkdir -p "${WEBROOT}/.well-known/acme-challenge"
    chown -R www-data:www-data "${WEBROOT}" 2>/dev/null || true
    chmod -R 755 "${WEBROOT}" 2>/dev/null || true

    log_info "Preparing to issue Let's Encrypt certificates for hostnames:"
    local domain_args=()
    for d in "${REQUIRED_DOMAINS[@]}"; do
        echo -e "    - ${CYAN}${d}${NC}"
        domain_args+=("-d" "${d}")
    done

    local email_arg=()
    if [ -n "${email}" ]; then
        email_arg=("--email" "${email}")
    else
        email_arg=("--register-unsafely-without-email")
    fi

    log_info "Executing Certbot via webroot challenge (${WEBROOT})..."
    
    # Safely invoke certbot with non-destructive flags
    if certbot certonly \
        --webroot -w "${WEBROOT}" \
        "${domain_args[@]}" \
        "${email_arg[@]}" \
        --agree-tos \
        --non-interactive \
        --cert-name "${DOMAIN}" \
        --keep-until-expiring \
        --expand; then
        log_success "Certificates issued or updated successfully for ${DOMAIN}!"
        return 0
    else
        log_error "Certbot issuance failed. Check DNS propagation and ensure port 80 reaches this host."
        log_warn "Existing certificates were preserved and not altered."
        return 1
    fi
}

# Main command handling
ACTION="${2:-check}"
case "${ACTION}" in
    check)
        cmd_check
        ;;
    issue)
        cmd_issue "$@"
        ;;
    *)
        cmd_check
        ;;
esac

#!/usr/bin/env bash
# Extract CNOE/Kind cluster CA certificate and import into Firefox/PWA NSS databases
# This enables Firefox and Firefox PWAs to trust CNOE services at *.cnoe.localtest.me:8443
#
# Usage: cnoe-trust-cert.sh [--extract-only]
#
# Requirements:
#   - kubectl configured with access to the Kind cluster
#   - certutil (from nssTools package)
#   - Running CNOE/idpbuilder cluster with cert-manager
#
# The certificate is extracted from the cert-manager root-ca secret and imported
# into all Firefox and Firefox PWA profile NSS databases.

set -euo pipefail

CERT_DIR="${HOME}/.local/share/certs"
CERT_FILE="${CERT_DIR}/cnoe-ca.crt"
CERT_NAME="CNOE-Kind-CA"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[cnoe-cert]${NC} $*"; }
warn() { echo -e "${YELLOW}[cnoe-cert]${NC} $*"; }
error() { echo -e "${RED}[cnoe-cert]${NC} $*" >&2; }
info() { echo -e "${BLUE}[cnoe-cert]${NC} $*"; }

# Show help
show_help() {
    cat <<'EOF'
Usage: cnoe-trust-cert.sh [OPTIONS]

Extract CNOE/Kind cluster CA certificate and import into Firefox/PWA NSS databases.

Options:
  --extract-only    Only extract the certificate, don't import to browsers
  --list            List currently imported certificates in Firefox profiles
  --remove          Remove the CNOE certificate from all profiles
  -h, --help        Show this help message

Examples:
  cnoe-trust-cert.sh                # Extract and import certificate
  cnoe-trust-cert.sh --extract-only # Only extract, don't import
  cnoe-trust-cert.sh --list         # Show imported certs
  cnoe-trust-cert.sh --remove       # Remove CNOE cert from profiles

The certificate is saved to: ~/.local/share/certs/cnoe-ca.crt
EOF
}

# Step 1: Extract CA from cluster (supports multiple configurations)
extract_cert() {
    log "Extracting CA certificate from cluster..."
    mkdir -p "$CERT_DIR"

    local extracted=false

    # Try 1: idpbuilder-cert in default namespace (idpbuilder clusters)
    if kubectl get secret -n default idpbuilder-cert &>/dev/null; then
        log "Found idpbuilder-cert in default namespace"
        kubectl get secret -n default idpbuilder-cert \
            -o jsonpath='{.data.ca\.crt}' | base64 -d > "$CERT_FILE"
        extracted=true
    # Try 2: cert-manager root-ca (cert-manager clusters)
    elif kubectl get secret -n cert-manager root-ca &>/dev/null; then
        log "Found root-ca in cert-manager namespace"
        kubectl get secret -n cert-manager root-ca \
            -o jsonpath='{.data.ca\.crt}' | base64 -d > "$CERT_FILE"
        extracted=true
    # Try 3: ingress-nginx tls.crt (fallback - extract CA from cert chain)
    elif kubectl get secret -n ingress-nginx idpbuilder-cert &>/dev/null; then
        log "Found idpbuilder-cert in ingress-nginx namespace (extracting from TLS cert)"
        kubectl get secret -n ingress-nginx idpbuilder-cert \
            -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CERT_FILE"
        extracted=true
    fi

    if [[ "$extracted" == "false" ]]; then
        error "No CA certificate found in cluster"
        error "Checked: default/idpbuilder-cert, cert-manager/root-ca, ingress-nginx/idpbuilder-cert"
        echo ""
        info "To check cluster status:"
        info "  kubectl get nodes"
        info "  kubectl get secrets --all-namespaces | grep -iE 'ca|cert|idp'"
        return 1
    fi

    # Verify it's a valid certificate
    if ! openssl x509 -in "$CERT_FILE" -noout 2>/dev/null; then
        error "Extracted file is not a valid certificate"
        return 1
    fi

    log "Certificate saved to: $CERT_FILE"
    echo ""
    info "Certificate details:"
    openssl x509 -in "$CERT_FILE" -noout -subject -dates -issuer 2>/dev/null | sed 's/^/  /'
}

# Step 2: Import into Firefox NSS database
import_firefox() {
    local profile_dir="$1"
    local db_path="$profile_dir"
    local profile_name
    profile_name=$(basename "$profile_dir")

    # Check if cert9.db exists (SQLite format)
    if [[ ! -f "$db_path/cert9.db" ]]; then
        # Profile may not have been used yet, skip silently
        return 0
    fi

    # Remove old cert if exists (ignore errors)
    certutil -D -n "$CERT_NAME" -d "sql:$db_path" 2>/dev/null || true

    # Import new cert as trusted CA
    # Trust flags: CT,C,C = trusted for SSL, email, and object signing
    if certutil -A -n "$CERT_NAME" -t "CT,C,C" -i "$CERT_FILE" -d "sql:$db_path" 2>/dev/null; then
        log "Imported to: $profile_name"
        return 0
    else
        warn "Failed to import to: $profile_name"
        return 1
    fi
}

# Step 3: Import to all Firefox and PWA profiles
import_all_profiles() {
    log "Importing certificate to Firefox profiles..."
    echo ""

    local imported=0
    local failed=0

    # Main Firefox profiles
    if [[ -d "${HOME}/.mozilla/firefox" ]]; then
        for profile in "${HOME}/.mozilla/firefox"/*.default* "${HOME}/.mozilla/firefox"/default; do
            if [[ -d "$profile" ]] && [[ -f "$profile/cert9.db" ]]; then
                if import_firefox "$profile"; then
                    ((imported++))
                else
                    ((failed++))
                fi
            fi
        done
    fi

    # Firefox PWA profiles
    if [[ -d "${HOME}/.local/share/firefoxpwa/profiles" ]]; then
        for profile in "${HOME}/.local/share/firefoxpwa/profiles"/*; do
            if [[ -d "$profile" ]] && [[ -f "$profile/cert9.db" ]]; then
                if import_firefox "$profile"; then
                    ((imported++))
                else
                    ((failed++))
                fi
            fi
        done
    fi

    echo ""
    if [[ $imported -gt 0 ]]; then
        log "Certificate imported to $imported profile(s)"
    fi
    if [[ $failed -gt 0 ]]; then
        warn "Failed to import to $failed profile(s)"
    fi
    if [[ $imported -eq 0 ]] && [[ $failed -eq 0 ]]; then
        warn "No Firefox profiles with NSS databases found"
        info "Firefox profiles are created after first launch"
    fi
}

# List certificates in profiles
list_certs() {
    log "Listing certificates in Firefox profiles..."
    echo ""

    # Main Firefox profiles
    if [[ -d "${HOME}/.mozilla/firefox" ]]; then
        for profile in "${HOME}/.mozilla/firefox"/*.default* "${HOME}/.mozilla/firefox"/default; do
            if [[ -d "$profile" ]] && [[ -f "$profile/cert9.db" ]]; then
                echo -e "${BLUE}Profile:${NC} $(basename "$profile")"
                certutil -L -d "sql:$profile" 2>/dev/null | grep -E "^$CERT_NAME|^CNOE" || echo "  (no CNOE cert)"
                echo ""
            fi
        done
    fi

    # Firefox PWA profiles (sample first 5)
    if [[ -d "${HOME}/.local/share/firefoxpwa/profiles" ]]; then
        local count=0
        for profile in "${HOME}/.local/share/firefoxpwa/profiles"/*; do
            if [[ -d "$profile" ]] && [[ -f "$profile/cert9.db" ]]; then
                echo -e "${BLUE}PWA Profile:${NC} $(basename "$profile")"
                certutil -L -d "sql:$profile" 2>/dev/null | grep -E "^$CERT_NAME|^CNOE" || echo "  (no CNOE cert)"
                echo ""
                ((count++))
                if [[ $count -ge 5 ]]; then
                    info "(showing first 5 PWA profiles only)"
                    break
                fi
            fi
        done
    fi
}

# Remove certificate from all profiles
remove_cert() {
    log "Removing CNOE certificate from Firefox profiles..."
    echo ""

    local removed=0

    # Main Firefox profiles
    if [[ -d "${HOME}/.mozilla/firefox" ]]; then
        for profile in "${HOME}/.mozilla/firefox"/*.default* "${HOME}/.mozilla/firefox"/default; do
            if [[ -d "$profile" ]] && [[ -f "$profile/cert9.db" ]]; then
                if certutil -D -n "$CERT_NAME" -d "sql:$profile" 2>/dev/null; then
                    log "Removed from: $(basename "$profile")"
                    ((removed++))
                fi
            fi
        done
    fi

    # Firefox PWA profiles
    if [[ -d "${HOME}/.local/share/firefoxpwa/profiles" ]]; then
        for profile in "${HOME}/.local/share/firefoxpwa/profiles"/*; do
            if [[ -d "$profile" ]] && [[ -f "$profile/cert9.db" ]]; then
                if certutil -D -n "$CERT_NAME" -d "sql:$profile" 2>/dev/null; then
                    log "Removed from: $(basename "$profile")"
                    ((removed++))
                fi
            fi
        done
    fi

    echo ""
    log "Removed certificate from $removed profile(s)"
}

# Main
main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --extract-only)
            extract_cert
            exit 0
            ;;
        --list)
            list_certs
            exit 0
            ;;
        --remove)
            remove_cert
            exit 0
            ;;
        "")
            # Default: extract and import
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac

    # Check dependencies
    if ! command -v certutil &>/dev/null; then
        error "certutil not found. Install nssTools package."
        info "On NixOS: nix-shell -p nssTools"
        exit 1
    fi

    if ! command -v kubectl &>/dev/null; then
        error "kubectl not found."
        exit 1
    fi

    if ! command -v openssl &>/dev/null; then
        error "openssl not found."
        exit 1
    fi

    # Extract and import
    extract_cert || exit 1
    echo ""
    import_all_profiles

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "Done! Restart Firefox and PWAs to apply certificate trust."
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    info "Test commands:"
    info "  curl https://argocd.cnoe.localtest.me:8443"
    info "  firefox https://backstage.cnoe.localtest.me:8443"
}

main "$@"

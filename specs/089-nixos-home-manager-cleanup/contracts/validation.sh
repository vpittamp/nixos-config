#!/usr/bin/env bash
# Validates both active configurations build successfully
# This script is the primary validation contract for Feature 089

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Feature 089: NixOS Configuration Cleanup Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Track validation results
VALIDATION_FAILED=0

# Helper function for timestamped output
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*" >&2
    VALIDATION_FAILED=1
}

success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $*"
}

# Validate hetzner-sway configuration
log "Validating hetzner-sway configuration..."
if sudo nixos-rebuild dry-build --flake .#hetzner-sway; then
    success "hetzner-sway configuration builds successfully"
else
    error "hetzner-sway configuration failed to build"
fi

echo ""

# Validate m1 configuration
log "Validating m1 configuration..."
if sudo nixos-rebuild dry-build --flake .#m1 --impure; then
    success "m1 configuration builds successfully"
else
    error "m1 configuration failed to build"
fi

echo ""

# Validate flake structure (optional - may fail on non-M1 hardware)
log "Validating flake structure..."
if nix flake check; then
    success "Flake structure validation passed"
else
    log "⚠️  Flake structure validation failed (expected on non-M1 hardware due to Asahi firmware requirement)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo "✅ All validations passed"
    exit 0
else
    echo "❌ One or more validations failed"
    exit 1
fi

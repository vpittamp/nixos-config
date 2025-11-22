#!/usr/bin/env bash
# Validates hardware-specific features are preserved
# This ensures critical hardware support is not broken during cleanup

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Feature 089: Hardware-Specific Feature Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

VALIDATION_FAILED=0

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ❌ CRITICAL: $*" >&2
    VALIDATION_FAILED=1
}

success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $*"
}

# M1 Asahi firmware check
log "Checking M1 Asahi firmware configuration..."
if grep -r "hardware.asahi" configurations/m1.nix >/dev/null 2>&1; then
    success "M1 Asahi firmware configuration present"
else
    error "M1 Asahi firmware configuration missing in configurations/m1.nix"
fi

# WayVNC check (both targets use VNC for remote access)
log "Checking WayVNC configuration..."
if grep -r "wayvnc" configurations/ >/dev/null 2>&1 || \
   grep -r "wayvnc" modules/ >/dev/null 2>&1; then
    success "WayVNC configuration present"
else
    error "WayVNC configuration missing - required for remote access"
fi

# Tailscale check (both targets use Tailscale VPN)
log "Checking Tailscale configuration..."
if grep -r "tailscale" modules/ configurations/ >/dev/null 2>&1; then
    success "Tailscale configuration present"
else
    error "Tailscale configuration missing - required for VPN access"
fi

# Sway compositor check (both targets use Sway)
log "Checking Sway compositor configuration..."
if grep -r "programs.sway" configurations/ modules/ >/dev/null 2>&1 || \
   grep -r "wayland.windowManager.sway" home-modules/ >/dev/null 2>&1; then
    success "Sway compositor configuration present"
else
    error "Sway compositor configuration missing - required for desktop"
fi

# Home-manager integration check
log "Checking home-manager integration..."
if grep -r "home-manager" flake.nix >/dev/null 2>&1; then
    success "Home-manager integration present"
else
    error "Home-manager integration missing in flake.nix"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo "✅ All hardware-specific features validated"
    exit 0
else
    echo "❌ One or more critical hardware features are missing"
    echo ""
    echo "CRITICAL: Do NOT proceed with cleanup if hardware features are missing."
    echo "This could break system boot, remote access, or desktop functionality."
    exit 1
fi

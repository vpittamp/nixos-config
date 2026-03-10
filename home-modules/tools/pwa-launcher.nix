{ config, lib, pkgs, ... }:

# PWA Launcher - Thin wrapper for Firefox PWAs
# Routes PWA launches through unified app-launcher-wrapper for i3pm integration
#
# This launcher:
# 1. Resolves PWA display name → app registry name (e.g., "Claude" → "claude-pwa")
# 2. Delegates to app-launcher-wrapper.sh for unified launch logic
# 3. Falls back to desktop file search if PWA not in registry
# 4. Feature 113: Optionally accepts a URL argument for deep linking
#
# Benefits of unified approach:
# - Consistent I3PM_* environment variable injection
# - Launch notifications to daemon for Tier 0 window correlation
# - Workspace assignment via I3PM_TARGET_WORKSPACE
# - Project context propagation
# - Deterministic class matching (FFPWA-{ULID})

let
  launch-pwa-by-name = pkgs.writeShellScriptBin "launch-pwa-by-name" ''
    #!/usr/bin/env bash
    # PWA Launcher - Routes to unified app-launcher-wrapper
    # Usage: launch-pwa-by-name <PWA Name or ULID> [URL]
    # Feature 113: Optional URL argument for deep linking

    set -euo pipefail

    if [[ $# -lt 1 ]]; then
      echo "Usage: launch-pwa-by-name <PWA Name or ULID> [URL]" >&2
      echo "  URL: Optional URL to open in the PWA (Feature 113)" >&2
      exit 1
    fi

    NAME="$1"
    # Feature 113: URL for deep linking - check env var first (from pwa-url-router), then argument
    URL="''${I3PM_PWA_URL:-''${2:-}}"

    # ============================================================================
    # PHASE 1: Resolve PWA ULID from pwa-registry.json
    # ============================================================================

    REGISTRY="$HOME/.config/i3/pwa-registry.json"
    PWA_DATA=""

    if [[ ! -f "$REGISTRY" ]]; then
      echo "Error: Registry file not found: $REGISTRY" >&2
      exit 1
    fi

    # Method 1: Check if NAME is already a ULID (26 character ULID format)
    if [[ "$NAME" =~ ^[0-9A-HJKMNP-TV-Z]{26}$ ]]; then
      PWA_DATA=$(${pkgs.jq}/bin/jq -c --arg ulid "$NAME" '.pwas[] | select(.ulid == $ulid)' "$REGISTRY")
    else
      # Method 2: Search by name (case-insensitive)
      NAME_LOWER=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
      PWA_DATA=$(${pkgs.jq}/bin/jq -c --arg name "$NAME_LOWER" '.pwas[] | select(.name == $name)' "$REGISTRY")
    fi

    if [[ -z "$PWA_DATA" ]]; then
      echo "Error: PWA '$NAME' not found in registry" >&2
      echo "Available PWAs:" >&2
      ${pkgs.jq}/bin/jq -r '.pwas[].name' "$REGISTRY" | sort >&2
      exit 1
    fi

    PWA_ID=$(echo "$PWA_DATA" | ${pkgs.jq}/bin/jq -r '.ulid')
    PWA_URL=$(echo "$PWA_DATA" | ${pkgs.jq}/bin/jq -r '.url')
    
    # If URL argument is provided, use it instead of base URL
    TARGET_URL="''${URL:-$PWA_URL}"

    # ============================================================================
    # PHASE 2: Launch PWA
    # ============================================================================
    # Feature 056: Chrome uses --class to set the window app_id under native Wayland.
    # By running out of the main profile directly, we instantly inherit all extensions
    # (including 1Password) and authentication state perfectly, while the unique class
    # ensures i3pm can still track and route the PWA independently!
    
    exec ${pkgs.google-chrome}/bin/google-chrome-stable \
      --profile-directory="Default" \
      --class="WebApp-$PWA_ID" \
      --enable-native-messaging \
      --no-first-run \
      --no-default-browser-check \
      "$TARGET_URL"
  '';
in
{
  home.packages = [ launch-pwa-by-name ];
}

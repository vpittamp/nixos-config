{ config, lib, pkgs, ... }:

# PWA Launcher - Declarative Google Chrome PWA launcher
# Resolves declarative PWA entries from pwa-registry.json and launches them
# with deterministic Chrome profile/class settings for i3pm integration.
#
# This launcher:
# 1. Resolves PWA display name → app registry name (e.g., "Claude" → "claude-pwa")
# 2. Uses the declarative ULID as the profile and class identity
# 3. Launches Chrome directly with WebApp-<ULID> window identity
# 4. Feature 113: Optionally accepts a URL argument for deep linking
#
# Benefits of current approach:
# - Deterministic Wayland/XWayland class matching (WebApp-<ULID>)
# - Stable per-PWA Chrome profile directories
# - Compatibility with i3pm launch/open and generated desktop entries

let
  launch-pwa-by-name = pkgs.writeShellScriptBin "launch-pwa-by-name" ''
    #!/usr/bin/env bash
    # PWA Launcher - Resolves declarative PWA metadata and launches Chrome directly
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
    # PHASE 2: Setup Google Chrome Profile
    # ============================================================================

    PROFILE_DIR="$HOME/.local/share/webapps/webapp-$PWA_ID"
    mkdir -p "$PROFILE_DIR/Default"

    # Ensure 1Password native messaging hosts are available in the PWA profile
    # Chrome with --user-data-dir looks for user-level hosts here
    NMH_DIR="$PROFILE_DIR/NativeMessagingHosts"
    mkdir -p "$NMH_DIR"
    for host_json in /etc/opt/chrome/native-messaging-hosts/com.1password.*.json; do
      [ -f "$host_json" ] && ln -sf "$host_json" "$NMH_DIR/$(basename "$host_json")"
    done

    # Ensure Wayland variables are available
    export WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-wayland-1}

    # ============================================================================
    # PHASE 3: Launch PWA
    # ============================================================================
    # Chrome uses --class to set the window app_id under native Wayland or WM_CLASS under XWayland
    
    exec ${pkgs.google-chrome}/bin/google-chrome-stable \
      --user-data-dir="$PROFILE_DIR" \
      --class="WebApp-$PWA_ID" \
      --app="$TARGET_URL" \
      --no-first-run \
      --no-default-browser-check \
      --password-store=basic
  '';
in
{
  home.packages = [ launch-pwa-by-name ];
}

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
    # PHASE 2: Setup Google Chrome Profile
    # ============================================================================

    PROFILE_DIR="$HOME/.local/share/webapps/webapp-$PWA_ID"
    MAIN_CHROME_PROFILE="$HOME/.config/google-chrome/Default"
    ONEPASSWORD_EXT_ID="aeblfdkhhhdcdjpifhhbdiojplfjncoa"

    mkdir -p "$PROFILE_DIR/Default/Local Extension Settings"
    mkdir -p "$PROFILE_DIR/External Extensions"
    mkdir -p "$PROFILE_DIR/NativeMessagingHosts"

    # Install 1Password extension via External Extensions mechanism
    cat > "$PROFILE_DIR/External Extensions/''${ONEPASSWORD_EXT_ID}.json" <<EOF
{"external_update_url":"https://clients2.google.com/service/update2/crx"}
EOF

    # Link 1Password native messaging host configuration
    ln -sf "$HOME/.config/google-chrome/NativeMessagingHosts/com.1password.1password.json" \
      "$PROFILE_DIR/NativeMessagingHosts/com.1password.1password.json" 2>/dev/null || true
    ln -sf "$HOME/.config/google-chrome/NativeMessagingHosts/com.1password.browser_support.json" \
      "$PROFILE_DIR/NativeMessagingHosts/com.1password.browser_support.json" 2>/dev/null || true

    # Share 1Password extension data from main Chrome profile for persistent authentication
    if [ -d "$MAIN_CHROME_PROFILE/Local Extension Settings/''${ONEPASSWORD_EXT_ID}" ]; then
      rm -rf "$PROFILE_DIR/Default/Local Extension Settings/''${ONEPASSWORD_EXT_ID}" 2>/dev/null
      ln -sf "$MAIN_CHROME_PROFILE/Local Extension Settings/''${ONEPASSWORD_EXT_ID}" \
        "$PROFILE_DIR/Default/Local Extension Settings/''${ONEPASSWORD_EXT_ID}"
    fi

    # Share extension state and sync data for seamless authentication
    if [ -d "$MAIN_CHROME_PROFILE/Extension State" ]; then
      rm -rf "$PROFILE_DIR/Default/Extension State" 2>/dev/null
      ln -sf "$MAIN_CHROME_PROFILE/Extension State" "$PROFILE_DIR/Default/Extension State"
    fi

    # Share extension cookies for authentication
    if [ -f "$MAIN_CHROME_PROFILE/Extension Cookies" ]; then
      ln -sf "$MAIN_CHROME_PROFILE/Extension Cookies" "$PROFILE_DIR/Default/Extension Cookies" 2>/dev/null
    fi

    # Pin the 1Password extension so it's visible in the PWA toolbar
    PREFS_FILE="$PROFILE_DIR/Default/Preferences"
    if [ ! -f "$PREFS_FILE" ]; then
      ${pkgs.jq}/bin/jq -n --arg ext "$ONEPASSWORD_EXT_ID" '{"extensions": {"pinned_extensions": [$ext]}}' > "$PREFS_FILE"
    else
      # If file exists, update it without wiping other preferences
      ${pkgs.jq}/bin/jq --arg ext "$ONEPASSWORD_EXT_ID" '.extensions.pinned_extensions = (if .extensions.pinned_extensions then (.extensions.pinned_extensions + [$ext] | unique) else [$ext] end)' "$PREFS_FILE" > "$PREFS_FILE.tmp" && mv "$PREFS_FILE.tmp" "$PREFS_FILE"
    fi

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
      --enable-native-messaging \
      --no-first-run \
      --no-default-browser-check \
      --password-store=basic
  '';
in
{
  home.packages = [ launch-pwa-by-name ];
}

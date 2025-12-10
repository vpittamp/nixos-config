{ config, lib, pkgs, ... }:

# PWA Launcher - Thin wrapper for Firefox PWAs
# Routes PWA launches through unified app-launcher-wrapper for i3pm integration
#
# This launcher:
# 1. Resolves PWA display name → app registry name (e.g., "Claude" → "claude-pwa")
# 2. Delegates to app-launcher-wrapper.sh for unified launch logic
# 3. Falls back to direct firefoxpwa launch if PWA not in registry
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
    # PHASE 1: Resolve PWA ULID from name
    # ============================================================================

    PWA_ID=""

    # Method 1: Check if NAME is already a ULID (26 character ULID format)
    if [[ "$NAME" =~ ^[0-9A-HJKMNP-TV-Z]{26}$ ]]; then
    PWA_ID="$NAME"
  fi

    # Method 2: Query firefoxpwa directly for dynamic PWA ID lookup
    if [[ -z "$PWA_ID" ]]; then
      PWA_ID=$(${pkgs.firefoxpwa}/bin/firefoxpwa profile list 2>/dev/null | \
               grep -E "^- $NAME:" | \
               grep -oP '[0-9A-HJKMNP-TV-Z]{26}' | \
               head -1)
    fi

    # Method 3: Fallback to desktop file search (exact or with suffix like [WS4])
    if [[ -z "$PWA_ID" ]]; then
      for pattern in "FFPWA*.desktop" "*-pwa.desktop"; do
        DESKTOP_FILE=$(grep -l "^Name=$NAME\(\s\|$\)" ~/.local/share/applications/$pattern 2>/dev/null | head -1)
        if [[ -n "$DESKTOP_FILE" ]]; then
          # Try extracting ULID from Exec line
          PWA_ID=$(grep "^Exec=" "$DESKTOP_FILE" | grep -oP '[0-9A-HJKMNP-TV-Z]{26}' | head -1)
          # Also try StartupWMClass field
          if [[ -z "$PWA_ID" ]]; then
            PWA_ID=$(grep "^StartupWMClass=" "$DESKTOP_FILE" | grep -oP '[0-9A-HJKMNP-TV-Z]{26}' | head -1)
          fi
          [[ -n "$PWA_ID" ]] && break
        fi
      done
    fi

    if [[ -z "$PWA_ID" ]]; then
      echo "Error: PWA '$NAME' not found" >&2
      echo "Available PWAs:" >&2
      ${pkgs.firefoxpwa}/bin/firefoxpwa profile list 2>/dev/null | grep -E "^- " | cut -d: -f1 | sed 's/^- //' | sort >&2
      exit 1
    fi

    # Ensure 1Password extension and prefs are applied before launch
    if command -v pwa-enable-1password >/dev/null 2>&1; then
      pwa-enable-1password --profile "$PWA_ID" >/dev/null 2>&1 || true
    fi
    if command -v pwa-fix-dialogs >/dev/null 2>&1; then
      pwa-fix-dialogs --profile "$PWA_ID" >/dev/null 2>&1 || true
    fi

    # ============================================================================
    # PHASE 2: Launch PWA directly via firefoxpwa
    # ============================================================================
    # NOTE: This script is called BY app-launcher-wrapper.sh which has already:
    # - Injected I3PM_* environment variables
    # - Sent launch notification to daemon
    # - Set up workspace assignment
    #
    # This script's only job is to resolve the PWA name → ULID and launch it.
    # DO NOT route back to app-launcher-wrapper.sh (would cause infinite loop)

    export WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-wayland-1}
    export MOZ_ENABLE_WAYLAND=1
    export MOZ_DBUS_REMOTE=1
    export EGL_PLATFORM=wayland
    export GDK_BACKEND=wayland

    # ============================================================================
    # PHASE 3: Launch PWA (Feature 113: with optional URL for deep linking)
    # ============================================================================
    if [[ -n "$URL" ]]; then
      # Feature 113: Launch with URL for deep linking
      # The -- separator ensures URL is passed as argument, not option
      exec ${pkgs.firefoxpwa}/bin/firefoxpwa site launch "$PWA_ID" -- "$URL"
    else
      # Standard launch without URL
      exec ${pkgs.firefoxpwa}/bin/firefoxpwa site launch "$PWA_ID"
    fi
  '';
in
{
  home.packages = [ launch-pwa-by-name ];
}

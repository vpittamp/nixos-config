{ pkgs, lib, osConfig ? null, ... }:

# PWA Launcher - Declarative Google Chrome PWA launcher
# Resolves declarative PWA entries from pwa-registry.json and launches them
# from the user's main Chrome profile in app mode.
#
# This launcher:
# 1. Resolves PWA display name → app registry name (e.g., "Claude" → "claude-pwa")
# 2. Launches Chrome from the main profile so 1Password uses its supported path
# 3. Relies on Chrome's native dynamic Wayland/XWayland app identity
# 4. Feature 113: Optionally accepts a URL argument for deep linking
#
# Benefits of current approach:
# - Uses the real Chrome profile where the 1Password extension already lives
# - Avoids unsupported per-PWA profile cloning/bootstrap
# - Remains compatible with i3pm domain-based PWA matching

let
  hostName =
    if osConfig != null && osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else "";

  captureSafeChromeArgs = lib.optionals (hostName == "ryzen") [
    "--disable-accelerated-video-decode"
    "--disable-zero-copy"
  ];

  launch-pwa-by-name = pkgs.writeShellScriptBin "launch-pwa-by-name" ''
    #!/usr/bin/env bash
    # PWA Launcher - Resolves declarative PWA metadata and launches Chrome app mode
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

    PWA_URL=$(echo "$PWA_DATA" | ${pkgs.jq}/bin/jq -r '.url')
    EXTRA_CHROME_FLAGS=$(echo "$PWA_DATA" | ${pkgs.jq}/bin/jq -r '.extraChromeFlags // [] | .[]')

    # If URL argument is provided, use it instead of base URL
    TARGET_URL="''${URL:-$PWA_URL}"

    if command -v nix-usage-log-launch >/dev/null 2>&1; then
      nix-usage-log-launch \
        --source pwa \
        --app "$NAME" \
        --package google-chrome \
        --record-only \
        >/dev/null 2>&1 || true
    fi

    # ============================================================================
    # PHASE 2: Launch Chrome From Main Profile
    # ============================================================================

    # Ensure Wayland variables are available
    export WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-wayland-1}

    CHROME_CONFIG_DIR="$HOME/.config/google-chrome"
    SINGLETON_LOCK="$CHROME_CONFIG_DIR/SingletonLock"
    SINGLETON_COOKIE="$CHROME_CONFIG_DIR/SingletonCookie"
    SINGLETON_SOCKET="$CHROME_CONFIG_DIR/SingletonSocket"

    cleanup_stale_singleton() {
      if [[ ! -L "$SINGLETON_LOCK" ]]; then
        return 0
      fi

      local lock_target lock_pid=""
      lock_target=$(readlink "$SINGLETON_LOCK" 2>/dev/null || true)
      if [[ "$lock_target" =~ -([0-9]+)$ ]]; then
        lock_pid="''${BASH_REMATCH[1]}"
      fi

      if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        return 0
      fi

      echo "Removing stale Chrome singleton state from $CHROME_CONFIG_DIR" >&2

      local socket_target socket_dir
      socket_target=$(readlink "$SINGLETON_SOCKET" 2>/dev/null || true)
      rm -f "$SINGLETON_LOCK" "$SINGLETON_COOKIE" "$SINGLETON_SOCKET"

      if [[ -n "$socket_target" ]]; then
        rm -f "$socket_target" 2>/dev/null || true
        socket_dir=$(dirname "$socket_target")
        rmdir "$socket_dir" 2>/dev/null || true
      fi
    }

    cleanup_stale_singleton

    use_legacy_onepassword_forwarding() {
      if [[ ! -L "$SINGLETON_LOCK" ]]; then
        return 1
      fi

      local lock_target lock_pid=""
      lock_target=$(readlink "$SINGLETON_LOCK" 2>/dev/null || true)
      if [[ "$lock_target" =~ -([0-9]+)$ ]]; then
        lock_pid="''${BASH_REMATCH[1]}"
      fi

      if [[ -z "$lock_pid" ]] || [[ ! -d "/proc/$lock_pid" ]]; then
        return 1
      fi

      [[ "$(stat -c %G "/proc/$lock_pid" 2>/dev/null || true)" == "onepassword" ]]
    }

    # ============================================================================
    # PHASE 3: Launch PWA
    # ============================================================================
    # Use the main Chrome profile. This keeps 1Password integration on the
    # supported browser/profile path instead of trying to recreate extension
    # state inside synthetic per-PWA profiles.
    #
    # Do not launch Chrome via `sg onepassword` by default. On NixOS the native
    # host wrapper itself is already setgid onepassword, and forcing the browser
    # process into that group creates a long-lived Chrome process the daemon
    # cannot safely introspect or correlate.
    #
    # Compatibility bridge: if the current Chrome singleton owner is still a
    # legacy browser session running under the onepassword group, forward this
    # launch through `sg onepassword` too. Without that, Chrome 145 can TRAP
    # while trying to hand off `--app=` launches to the existing session.

    cmd=(
      ${pkgs.google-chrome}/bin/google-chrome-stable
      ${lib.concatStringsSep "\n      " (map (arg: lib.escapeShellArg arg) captureSafeChromeArgs)}
      --profile-directory=Default
      --app="$TARGET_URL"
      --new-window
      --no-first-run
      --no-default-browser-check
      --password-store=basic
      --disable-features=DesktopPWAsElidedExtensionsMenu
    )

    # Append per-PWA Chrome flags from registry (e.g. --js-flags for heap limits)
    if [[ -n "$EXTRA_CHROME_FLAGS" ]]; then
      while IFS= read -r flag; do
        cmd+=("$flag")
      done <<< "$EXTRA_CHROME_FLAGS"
    fi

    if use_legacy_onepassword_forwarding; then
      echo "Forwarding PWA launch through legacy onepassword Chrome session" >&2
      printf -v quoted_cmd '%q ' "''${cmd[@]}"
      exec sg onepassword -c "$quoted_cmd"
    fi

    exec "''${cmd[@]}"
  '';
in
{
  home.packages = [ launch-pwa-by-name ];
}

{ config, lib, pkgs, ... }:

# Dynamic PWA Launcher
# Launches Firefox PWAs by display name, querying the ID at runtime
# This makes PWA configurations portable across different systems

let
  launch-pwa-by-name = pkgs.writeShellScriptBin "launch-pwa-by-name" ''
    #!/usr/bin/env bash
    # Launch a Firefox PWA by its display name
    # Usage: launch-pwa-by-name "YouTube"

    set -euo pipefail

    if [[ $# -lt 1 ]]; then
      echo "Usage: launch-pwa-by-name <PWA Name>" >&2
      exit 1
    fi

    NAME="$1"

    # Try multiple discovery methods for flexibility
    PWA_ID=""

    # Method 1: Check if NAME is already a profile ID (starts with 01K)
    if [[ "$NAME" =~ ^01K[A-Z0-9]+ ]]; then
      PWA_ID="$NAME"
    fi

    # Method 2: Query firefoxpwa directly for dynamic PWA ID lookup
    # This works across different systems (hetzner-sway, m1) without hardcoding IDs
    if [[ -z "$PWA_ID" ]]; then
      PWA_ID=$(${pkgs.firefoxpwa}/bin/firefoxpwa profile list 2>/dev/null | \
               grep -E "^- $NAME:" | \
               grep -oP '\(01K[A-Z0-9]+\)' | \
               tr -d '()' | \
               head -1)
    fi

    # Method 3: Fallback to desktop file search (exact or with suffix like [WS4])
    if [[ -z "$PWA_ID" ]]; then
      for pattern in "FFPWA*.desktop" "*-pwa.desktop"; do
        DESKTOP_FILE=$(grep -l "^Name=$NAME\(\s\|$\)" ~/.local/share/applications/$pattern 2>/dev/null | head -1)
        if [[ -n "$DESKTOP_FILE" ]]; then
          # Try extracting PWA ID from Exec line
          PWA_ID=$(grep "^Exec=" "$DESKTOP_FILE" | grep -oP '01K[A-Z0-9]+' | head -1)
          # Also try StartupWMClass field
          if [[ -z "$PWA_ID" ]]; then
            PWA_ID=$(grep "^StartupWMClass=" "$DESKTOP_FILE" | grep -oP '01K[A-Z0-9]+' | head -1)
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

    # Launch the PWA with Wayland support and software rendering
    # Required for headless/VNC environments without GPU acceleration
    export WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-wayland-1}
    export MOZ_ENABLE_WAYLAND=1
    export MOZ_DISABLE_RDD_SANDBOX=1
    export LIBGL_ALWAYS_SOFTWARE=1

    exec ${pkgs.firefoxpwa}/bin/firefoxpwa site launch "$PWA_ID"
  '';
in
{
  home.packages = [ launch-pwa-by-name ];
}

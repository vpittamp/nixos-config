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

    # Find the desktop file with this name
    DESKTOP_FILE=$(grep -l "^Name=$NAME$" ~/.local/share/applications/FFPWA*.desktop 2>/dev/null | head -1)

    if [[ -z "$DESKTOP_FILE" ]]; then
      echo "Error: PWA '$NAME' not found" >&2
      echo "Available PWAs:" >&2
      grep "^Name=" ~/.local/share/applications/FFPWA*.desktop 2>/dev/null | cut -d= -f2 | sort >&2
      exit 1
    fi

    # Extract the PWA ID from the Exec line
    PWA_ID=$(grep "^Exec=" "$DESKTOP_FILE" | grep -oP '01K[A-Z0-9]+')

    if [[ -z "$PWA_ID" ]]; then
      echo "Error: Could not extract PWA ID from $DESKTOP_FILE" >&2
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

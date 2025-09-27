# Auto-detecting PWA Configuration Module
# This module automatically generates desktop files for installed PWAs
{ config, lib, pkgs, ... }:

with lib;

let
  # Script to generate desktop files for all installed PWAs
  updatePWAsScript = pkgs.writeShellScript "update-pwas" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.findutils}/bin:$PATH"
    FFPWA="${pkgs.firefoxpwa}/bin/firefoxpwa"
    DESKTOP_DIR="$HOME/.local/share/applications"

    # Ensure directory exists
    mkdir -p "$DESKTOP_DIR"

    # Remove old PWA desktop files to avoid stale entries
    rm -f "$DESKTOP_DIR"/FFPWA-*.desktop 2>/dev/null || true

    # Check if firefoxpwa is available
    if [ ! -x "$FFPWA" ]; then
      echo "firefoxpwa not found, skipping PWA desktop file generation" >&2
      exit 0
    fi

    echo "Detecting installed PWAs..."

    # Parse firefoxpwa profile list output
    # Format: "- Name: URL (ID)"
    $FFPWA profile list 2>/dev/null | grep "^- " | while IFS= read -r line; do
      # Extract name, URL, and ID using sed
      name=$(echo "$line" | sed -n 's/^- \([^:]*\):.*/\1/p' | xargs)
      url=$(echo "$line" | sed -n 's/^[^:]*: \([^(]*\).*/\1/p' | xargs)
      id=$(echo "$line" | sed -n 's/.*(\([^)]*\)).*/\1/p' | xargs)

      # Skip if we couldn't parse the ID
      if [ -z "$id" ] || [ "$id" = "" ]; then
        continue
      fi

      echo "  Found PWA: $name ($id)"

      # Create desktop file
      cat > "$DESKTOP_DIR/FFPWA-$id.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Version=1.4
Name=$name
Comment=Firefox Progressive Web App - $url
Icon=FFPWA-$id
Exec=${pkgs.firefoxpwa}/bin/firefoxpwa site launch $id --protocol %u
Terminal=false
StartupNotify=true
StartupWMClass=FFPWA-$id
Categories=Network;
MimeType=x-scheme-handler/https;x-scheme-handler/http;
DESKTOP

      chmod 644 "$DESKTOP_DIR/FFPWA-$id.desktop"
    done

    # Update desktop database
    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi

    echo "PWA desktop files updated successfully"
  '';

in {
  # Run the update script on home-manager activation
  home.activation.updatePWAs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Updating PWA desktop files..."
    ${updatePWAsScript}
  '';
  
  # Also create a user service to update PWAs periodically or on login
  systemd.user.services.update-pwas = {
    Unit = {
      Description = "Update Firefox PWA desktop files";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${updatePWAsScript}";
      StandardOutput = "journal";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
  
  # Timer to update PWAs daily (in case new ones are installed)
  systemd.user.timers.update-pwas = {
    Unit = {
      Description = "Update Firefox PWA desktop files daily";
    };
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # Ensure firefoxpwa is available
  home.packages = [ pkgs.firefoxpwa ];
}

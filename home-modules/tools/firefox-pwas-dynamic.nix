# Dynamic PWA Configuration Module
# This module checks for installed PWAs and generates desktop files accordingly
{ config, lib, pkgs, ... }:

with lib;

let
  # This script will detect installed PWAs at runtime
  detectPWAsScript = pkgs.writeScript "detect-pwas" ''
    #!${pkgs.bash}/bin/bash
    
    # Check if firefoxpwa is available
    FFPWA="${pkgs.firefoxpwa}/bin/firefoxpwa"
    if [ ! -x "$FFPWA" ]; then
      echo "firefoxpwa not found" >&2
      exit 1
    fi
    
    # Get list of installed PWAs
    $FFPWA profile list 2>/dev/null | grep -E "^- " | while IFS=': ' read -r dash name url id rest; do
      # Extract just the ID from the line
      id=$(echo "$id" | sed 's/[()]//g')
      name=$(echo "$name" | xargs)
      
      # Skip if ID is empty
      [ -z "$id" ] && continue
      
      # Create desktop file
      cat > "$HOME/.local/share/applications/FFPWA-$id.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Version=1.4
Name=$name
Comment=Firefox Progressive Web App
Icon=FFPWA-$id
Exec=${pkgs.firefoxpwa}/bin/firefoxpwa site launch $id --protocol %u
Terminal=false
StartupNotify=true
StartupWMClass=FFPWA-$id
Categories=Network;
MimeType=x-scheme-handler/https;x-scheme-handler/http;
DESKTOP
    done
    
    # Update desktop database
    ${pkgs.desktop-file-utils}/bin/update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  '';

in {
  # Run the detection script on activation
  home.activation.updatePWAs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Updating PWA desktop files based on installed profiles..."
    ${detectPWAsScript}
  '';

  # Ensure firefoxpwa is available
  home.packages = [ pkgs.firefoxpwa ];
}

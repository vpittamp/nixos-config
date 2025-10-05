{ config, lib, pkgs, ... }:

let
  # Import PWA definitions
  pwaData = import ./data.nix { inherit lib config; };

  # Import activity data for UUID lookup
  activityData = import ../project-activities/data.nix { inherit lib config pkgs; };

  # Script to generate PWA WM class mappings at activation time
  generatePWAMappings = pkgs.writeShellScript "generate-pwa-mappings" ''
    set -euo pipefail

    DESKTOP_DIR="$HOME/.local/share/applications"
    OUTPUT_FILE="$HOME/.config/plasma-pwas/pwa-classes.json"

    # Ensure output directory exists
    mkdir -p "$(dirname "$OUTPUT_FILE")"

    # Start JSON object
    echo "{" > "$OUTPUT_FILE"

    FIRST=true

    # Scan all FFPWA desktop files
    if [ -d "$DESKTOP_DIR" ]; then
      for desktop_file in "$DESKTOP_DIR"/FFPWA-*.desktop; do
        if [ ! -f "$desktop_file" ]; then
          continue
        fi

        # Extract PWA name and WM class from desktop file
        NAME=$(grep "^Name=" "$desktop_file" | cut -d= -f2- | head -1)
        WMCLASS=$(grep "^StartupWMClass=" "$desktop_file" | cut -d= -f2- | head -1)
        URL=$(grep "^Comment=" "$desktop_file" | grep -oP 'https?://[^ ]+' || echo "")

        if [ -n "$NAME" ] && [ -n "$WMCLASS" ]; then
          # Add comma separator for all but first entry
          if [ "$FIRST" = false ]; then
            echo "," >> "$OUTPUT_FILE"
          fi
          FIRST=false

          # Write JSON entry
          cat >> "$OUTPUT_FILE" <<ENTRY
  "$NAME": {
    "wmclass": "$WMCLASS",
    "url": "$URL"
  }
ENTRY
        fi
      done
    fi

    # Close JSON object
    echo "" >> "$OUTPUT_FILE"
    echo "}" >> "$OUTPUT_FILE"

    echo "Generated PWA mappings: $OUTPUT_FILE"
  '';

in {
  # Run the generator on activation
  home.activation.generatePWAMappings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Generating PWA WM class mappings..."
    ${generatePWAMappings}
  '';

  # Ensure the directory exists
  home.file.".config/plasma-pwas/.keep".text = "";
}

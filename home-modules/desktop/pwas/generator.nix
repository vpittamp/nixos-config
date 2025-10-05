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

  # Script to patch window rules with actual PWA WM classes
  patchWindowRules = pkgs.writeShellScript "patch-pwa-window-rules" ''
    set -euo pipefail

    KWINRULES="$HOME/.config/kwinrulesrc"
    MAPPING_FILE="$HOME/.config/plasma-pwas/pwa-classes.json"

    if [ ! -f "$MAPPING_FILE" ]; then
      echo "PWA mapping file not found, skipping window rule patching"
      exit 0
    fi

    if [ ! -f "$KWINRULES" ]; then
      echo "KWin rules file not found, skipping patching"
      exit 0
    fi

    echo "Patching PWA window rules with actual WM classes..."

    # Create temporary file for modifications
    TEMP_FILE=$(mktemp)
    cp "$KWINRULES" "$TEMP_FILE"

    # Read each PWA mapping and patch the corresponding rule
    ${pkgs.jq}/bin/jq -r 'to_entries[] | "\(.key):\(.value.wmclass)"' "$MAPPING_FILE" | while IFS=: read -r name wmclass; do
      # Replace FFPWA-PLACEHOLDER-{name} with actual WM class
      ${pkgs.gnused}/bin/sed -i "s|wmclass=FFPWA-PLACEHOLDER-$name|wmclass=$wmclass|g" "$TEMP_FILE"
    done

    # Only update if changes were made
    if ! diff -q "$KWINRULES" "$TEMP_FILE" >/dev/null 2>&1; then
      mv "$TEMP_FILE" "$KWINRULES"
      echo "PWA window rules patched successfully"

      # Reconfigure KWin to reload rules
      ${pkgs.kdePackages.qttools}/bin/qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    else
      rm "$TEMP_FILE"
      echo "No changes needed to window rules"
    fi
  '';

in {
  # Run the generator on activation
  home.activation.generatePWAMappings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Generating PWA WM class mappings..."
    ${generatePWAMappings}

    # Patch window rules with actual WM classes
    ${patchWindowRules}
  '';

  # Ensure the directory exists
  home.file.".config/plasma-pwas/.keep".text = "";
}

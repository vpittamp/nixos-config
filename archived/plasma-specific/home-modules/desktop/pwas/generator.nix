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

  # Script to patch window rules with actual PWA WM classes and activity UUIDs
  # Updated: 2025-10-05 - Support null activity for all-activities assignment
  patchWindowRules = pkgs.writeShellScript "patch-pwa-window-rules-v5" ''
    set -euo pipefail
    # Version: 5.0 - Support null activity assignment for all-activities

    echo "=== PWA Window Rules Patching - v5.0 ==="
    echo "Timestamp: $(date)"
    echo "User: $USER"
    echo "Home: $HOME"

    KWINRULES="$HOME/.config/kwinrulesrc"
    MAPPING_FILE="$HOME/.config/plasma-pwas/pwa-classes.json"
    ACTIVITY_CONFIG="$HOME/.config/kactivitymanagerdrc"

    echo "Checking configuration files..."
    echo "  - KWin rules: $KWINRULES $([ -f "$KWINRULES" ] && echo "[EXISTS]" || echo "[MISSING]")"
    echo "  - PWA mappings: $MAPPING_FILE $([ -f "$MAPPING_FILE" ] && echo "[EXISTS]" || echo "[MISSING]")"
    echo "  - Activities: $ACTIVITY_CONFIG $([ -f "$ACTIVITY_CONFIG" ] && echo "[EXISTS]" || echo "[MISSING]")"

    if [ ! -f "$KWINRULES" ]; then
      echo "KWin rules file not found, skipping patching"
      exit 0
    fi

    echo ""
    echo "Patching window rules with runtime-discovered IDs..."

    # Create temporary file for modifications
    TEMP_FILE=$(mktemp)
    cp "$KWINRULES" "$TEMP_FILE"

    # Patch PWA WM classes
    if [ -f "$MAPPING_FILE" ]; then
      echo "  - Patching PWA WM classes..."
      ${pkgs.jq}/bin/jq -r 'to_entries[] | "\(.key):\(.value.wmclass)"' "$MAPPING_FILE" | while IFS=: read -r name wmclass; do
        echo "    Processing $name -> $wmclass"

        # Replace FFPWA-PLACEHOLDER-{name} with actual WM class
        ${pkgs.gnused}/bin/sed -i "s|wmclass=FFPWA-PLACEHOLDER-$name|wmclass=$wmclass|g" "$TEMP_FILE"

        # Also patch rules that have generic wmclass=FFPWA or wmclass=firefoxpwa with matching Description
        # This handles cases where plasma-manager preserves the original export value
        ${pkgs.gnused}/bin/sed -i "/^Description=$name\\( -\\|$\\)/,/^\[/ {
          s|^wmclass=FFPWA$|wmclass=$wmclass|
          s|^wmclass=firefoxpwa$|wmclass=$wmclass|
        }" "$TEMP_FILE"

        # Remove title matching for PWA rules - only use WM class matching
        # Find the section for this PWA and remove title/titlematch fields
        ${pkgs.gnused}/bin/sed -i "/^Description=$name\\( -\\|$\\)/,/^\[/ {
          /^title=/d
          /^titlematch=/d
        }" "$TEMP_FILE"
      done
    fi

    # Patch activity UUIDs from runtime activity manager config
    if [ -f "$ACTIVITY_CONFIG" ]; then
      echo "  - Patching activity UUIDs..."

      # Build mapping from activity names to runtime UUIDs
      # The config has sections like [6ed332bc-fa61-5381-511d-4d5ba44a293b] with Name=NixOS
      declare -A ACTIVITY_MAP

      # Parse activity config to get name->UUID mapping
      while IFS= read -r line; do
        if [[ "$line" =~ ^\[([a-f0-9-]+)\]$ ]]; then
          current_uuid="''${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^Name=(.+)$ ]] && [ -n "''${current_uuid:-}" ]; then
          activity_name="''${BASH_REMATCH[1]}"
          ACTIVITY_MAP["$activity_name"]="$current_uuid"
          current_uuid=""
        fi
      done < "$ACTIVITY_CONFIG"

      # Apply PWA->Activity mappings from declarative config
      ${lib.concatMapStrings (pwaName: let
        pwa = pwaData.pwas.${pwaName};
      in
        if pwa.activity == null then ''
          # ${pwa.name} -> all activities (null activity assignment)
          # Set to all-activities UUID (all zeros)
          ${pkgs.gnused}/bin/sed -i "/^Description=${lib.escapeShellArg pwa.name}\\( -\\|$\\)/,/^\[/ {
            s|^activity=.*|activity=00000000-0000-0000-0000-000000000000|
            s|^activities=.*|activities=00000000-0000-0000-0000-000000000000|
          }" "$TEMP_FILE"
        ''
        else ''
          # ${pwa.name} -> ${pwa.activity} activity
          if [ -n "''${ACTIVITY_MAP[${lib.escapeShellArg activityData.activities.${pwa.activity}.name}]:-}" ]; then
            activity_uuid="''${ACTIVITY_MAP[${lib.escapeShellArg activityData.activities.${pwa.activity}.name}]}"
            # Find and replace activity UUID for ${pwa.name} window rules
            # Match "Description=PWA Name" or "Description=PWA Name - ..."
            ${pkgs.gnused}/bin/sed -i "/^Description=${lib.escapeShellArg pwa.name}\\( -\\|$\\)/,/^\[/ {
              s|^activity=.*|activity=$activity_uuid|
              s|^activities=.*|activities=$activity_uuid|
            }" "$TEMP_FILE"
          fi
        ''
      ) (lib.attrNames pwaData.pwas)}
    fi

    # Only update if changes were made
    echo ""
    echo "Comparing original and patched versions..."
    if ! diff -q "$KWINRULES" "$TEMP_FILE" >/dev/null 2>&1; then
      echo "Changes detected - applying patches..."
      echo "Diff summary:"
      diff -u "$KWINRULES" "$TEMP_FILE" | head -30 || true
      mv "$TEMP_FILE" "$KWINRULES"
      echo "✓ Window rules patched successfully"

      # Reconfigure KWin to reload rules
      echo "Reloading KWin configuration..."
      ${pkgs.kdePackages.qttools}/bin/qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    else
      rm "$TEMP_FILE"
      echo "✓ No changes needed to window rules (already up to date)"
    fi
    echo "=== PWA Window Rules Patching Complete ==="
  '';

in {
  # Run the mapping generator early
  home.activation.generatePWAMappings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Generating PWA WM class mappings..."
    ${generatePWAMappings}
  '';

  # Patch window rules AFTER plasma-manager writes kwinrulesrc
  # Must run after configure-plasma to avoid race condition where plasma-manager overwrites our patches
  home.activation.patchPWAWindowRules = lib.hm.dag.entryAfter ["writeBoundary" "linkGeneration" "configure-plasma"] ''
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running PWA Window Rules Patching..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ${patchWindowRules} || echo "Warning: Window rule patching failed (kwinrulesrc may not exist yet)"
    echo ""
  '';

  # Ensure the directory exists
  home.file.".config/plasma-pwas/.keep".text = "";
}

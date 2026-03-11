{ lib, pkgs }:

let
  getKnownBarOutputs = hostname:
    if hostname == "hetzner" then [
      { name = "HEADLESS-1"; label = "Headless 1"; logicalWidth = 1920; topBar = true; workspaceBar = true; showTray = true; }
      { name = "HEADLESS-2"; label = "Headless 2"; logicalWidth = 1920; topBar = false; workspaceBar = true; showTray = false; }
      { name = "HEADLESS-3"; label = "Headless 3"; logicalWidth = 1920; topBar = false; workspaceBar = true; showTray = false; }
    ] else if hostname == "ryzen" then [
      # Ryzen logical widths should match live Sway output widths.
      { name = "DP-1"; label = "Primary"; logicalWidth = 1920; topBar = true; workspaceBar = true; showTray = true; }
      { name = "HDMI-A-1"; label = "HDMI"; logicalWidth = 1920; topBar = true; workspaceBar = true; showTray = false; }
      { name = "DP-2"; label = "DP-2"; logicalWidth = 1920; topBar = true; workspaceBar = true; showTray = false; }
      { name = "DP-3"; label = "DP-3"; logicalWidth = 1920; topBar = true; workspaceBar = true; showTray = false; }
    ] else [
      # ThinkPad: 1920 physical / 1.25 scale = 1536 logical
      { name = "eDP-1"; label = "Built-in"; logicalWidth = 1536; topBar = true; workspaceBar = true; showTray = true; }
    ];

  mkOpenActiveEwwWindowsScript = {
    scriptName,
    configDir,
    windowMappings,
  }:
    pkgs.writeShellScriptBin scriptName ''
      set -euo pipefail

      EWW="${pkgs.eww}/bin/eww"
      CONFIG="$HOME/.config/${configDir}"
      TIMEOUT="${pkgs.coreutils}/bin/timeout"
      JQ="${pkgs.jq}/bin/jq"
      KNOWN_WINDOWS='${builtins.toJSON windowMappings}'

      for i in $(seq 1 50); do
        $TIMEOUT 1s $EWW --config "$CONFIG" ping >/dev/null 2>&1 && break
        sleep 0.2
      done

      active_json="$(swaymsg -t get_outputs -r 2>/dev/null || echo '[]')"
      mapfile -t windows < <(
        printf '%s' "$KNOWN_WINDOWS" | "$JQ" -r --argjson outputs "$active_json" '
          ($outputs | map(select(.active == true) | .name) | INDEX(.)) as $active
          | .[]
          | select($active[.name])
          | .window
        '
      )

      $EWW --config "$CONFIG" close-all 2>/dev/null || true

      if [[ ''${#windows[@]} -eq 0 ]]; then
        exit 0
      fi

      for window in "''${windows[@]}"; do
        $TIMEOUT 5s $EWW --config "$CONFIG" open "$window" || true
      done
    '';
in
{
  inherit getKnownBarOutputs mkOpenActiveEwwWindowsScript;
}

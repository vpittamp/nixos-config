{ pkgs, ... }:

let
  hardwareDetectScript = pkgs.writeText "hardware-detect.py" ''
    #!/usr/bin/env python3
    import json
    from pathlib import Path

    def detect_battery():
        return any(Path("/sys/class/power_supply").glob("BAT*"))

    def detect_bluetooth():
        try:
            return any(Path("/sys/class/bluetooth").glob("hci*"))
        except Exception:
            return False

    def detect_thermal():
        return any(Path("/sys/class/thermal").glob("thermal_zone*"))

    if __name__ == "__main__":
        capabilities = {
            "battery": detect_battery(),
            "bluetooth": detect_bluetooth(),
            "thermal": detect_thermal(),
        }
        print(json.dumps(capabilities))
  '';

  topbarSpinnerScript = pkgs.writeShellScriptBin "eww-topbar-spinner-frame" ''
    #!/usr/bin/env bash
    IDX_FILE="/tmp/eww-topbar-spinner-idx"
    IDX=$(cat "$IDX_FILE" 2>/dev/null || echo 0)
    FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    echo "''${FRAMES[$IDX]}"
    NEXT=$(( (IDX + 1) % 10 ))
    echo "$NEXT" > "$IDX_FILE"
  '';

  topbarSpinnerOpacityScript = pkgs.writeShellScriptBin "eww-topbar-spinner-opacity" ''
    #!/usr/bin/env bash
    IDX=$(cat /tmp/eww-topbar-spinner-idx 2>/dev/null || echo 0)
    case $IDX in
      0|9)  echo "0.4" ;; 
      1|8)  echo "0.6" ;; 
      2|7)  echo "0.8" ;; 
      3|4|5|6)  echo "1.0" ;; 
      *)  echo "1.0" ;; 
    esac
  '';

  togglePowermenuScript = pkgs.writeShellScriptBin "toggle-topbar-powermenu" ''
    set -euo pipefail
    CFG="$HOME/.config/eww/eww-top-bar"
    EWW="${pkgs.eww}/bin/eww"
    sanitize() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' :/_-'; }
    target_raw="''${1:-}"
    active="$($EWW --config "$CFG" active-windows 2>/dev/null || true)"
    if echo "$active" | grep -q '^powermenu-'; then
      echo "$active" | grep '^powermenu-' | while read -r w; do
        [ -n "$w" ] && "$EWW" --config "$CFG" close "$w" || true
      done
      "$EWW" --config "$CFG" update powermenu_confirm_action=\"\" 2>/dev/null || true
      exit 0
    fi
    windows="$($EWW --config "$CFG" list-windows 2>/dev/null || true)"
    if [ -z "$windows" ]; then exit 1; fi
    target_id=""
    if [ -n "$target_raw" ]; then
      target_id="$(sanitize "$target_raw")"
    else
      if command -v swaymsg >/dev/null 2>&1; then
        focused_output="$(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[] | select(.focused==true) | .name' | head -n1 || true)"
        if [ -n "$focused_output" ] && [ "$focused_output" != "null" ]; then target_id="$(sanitize "$focused_output")"; fi
      fi
    fi
    target_window=""
    if [ -n "$target_id" ] && echo "$windows" | grep -qx "powermenu-$target_id"; then
      target_window="powermenu-$target_id"
    else
      target_window="$(echo "$windows" | grep '^powermenu-' | head -n1 || true)"
    fi
    if [ -z "$target_window" ]; then exit 1; fi
    "$EWW" --config "$CFG" update powermenu_confirm_action=\"\" 2>/dev/null || true
    "$EWW" --config "$CFG" open "$target_window"
  '';
in
{
  inherit hardwareDetectScript topbarSpinnerScript topbarSpinnerOpacityScript togglePowermenuScript;
}

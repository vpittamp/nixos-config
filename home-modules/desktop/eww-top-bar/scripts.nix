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

  toggleBadgeShelfScript = pkgs.writeShellScriptBin "toggle-topbar-badge-shelf" ''
    set -euo pipefail
    CFG="$HOME/.config/eww/eww-top-bar"
    EWW="${pkgs.eww}/bin/eww"
    ACTION="toggle"
    TARGET_RAW=""

    sanitize() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' :/_-'; }

    if [ $# -ge 1 ]; then
      case "$1" in
        open|close|toggle)
          ACTION="$1"
          TARGET_RAW="''${2:-}"
          ;;
        *)
          TARGET_RAW="$1"
          ;;
      esac
    fi

    list_target_window() {
      local windows target_id target_window focused_output
      windows="$($EWW --config "$CFG" list-windows 2>/dev/null || true)"
      [ -n "$windows" ] || return 1

      target_id=""
      if [ -n "$TARGET_RAW" ]; then
        target_id="$(sanitize "$TARGET_RAW")"
      elif command -v swaymsg >/dev/null 2>&1; then
        focused_output="$(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[] | select(.focused==true) | .name' | head -n1 || true)"
        if [ -n "$focused_output" ] && [ "$focused_output" != "null" ]; then
          target_id="$(sanitize "$focused_output")"
        fi
      fi

      target_window=""
      if [ -n "$target_id" ] && echo "$windows" | grep -qx "badge-shelf-$target_id"; then
        target_window="badge-shelf-$target_id"
      else
        target_window="$(echo "$windows" | grep '^badge-shelf-' | head -n1 || true)"
      fi

      [ -n "$target_window" ] || return 1
      echo "$target_window"
    }

    active_shelves() {
      local active line id
      active="$($EWW --config "$CFG" active-windows 2>/dev/null || true)"
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        id="$(echo "$line" | cut -d':' -f1 | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        if echo "$id" | grep -q '^badge-shelf-'; then
          echo "$id"
        fi
      done <<< "$active"
    }

    is_window_open() {
      local window="$1"
      active_shelves | grep -Fxq "$window"
    }

    close_window_if_open() {
      local window="$1"
      if is_window_open "$window"; then
        "$EWW" --config "$CFG" close "$window" || true
      fi
    }

    close_active_shelves() {
      local w
      while read -r w; do
        [ -n "$w" ] && "$EWW" --config "$CFG" close "$w" || true
      done < <(active_shelves)
    }

    target_window="$(list_target_window || true)"
    [ -n "$target_window" ] || exit 0

    case "$ACTION" in
      close)
        if [ -n "$TARGET_RAW" ]; then
          close_window_if_open "$target_window"
        else
          close_active_shelves
        fi
        ;;
      open)
        if ! is_window_open "$target_window"; then
          close_active_shelves
          "$EWW" --config "$CFG" open "$target_window"
        fi
        ;;
      toggle|*)
        if is_window_open "$target_window"; then
          "$EWW" --config "$CFG" close "$target_window" || true
        else
          close_active_shelves
          "$EWW" --config "$CFG" open "$target_window"
        fi
        ;;
    esac
  '';
in
{
  inherit hardwareDetectScript togglePowermenuScript toggleBadgeShelfScript;
}

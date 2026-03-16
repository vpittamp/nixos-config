{ config, lib, pkgs, osConfig ? null, ... }:

let
  cfg = config.programs.quickshell-runtime-shell;
  hostName =
    if osConfig != null && osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else "unknown";

  shellConfigDir = pkgs.runCommandLocal "i3pm-quickshell-runtime-shell" { } ''
    mkdir -p "$out"
    cp ${./shell.qml} "$out/shell.qml"
    cp ${./SessionRow.qml} "$out/SessionRow.qml"
    cp ${./NotificationToast.qml} "$out/NotificationToast.qml"
    cp ${./NotificationRailCard.qml} "$out/NotificationRailCard.qml"
    cp ${./AssistantPanel.qml} "$out/AssistantPanel.qml"
    cp ${./AssistantService.qml} "$out/AssistantService.qml"
    cp ${./AssistantProviderLogic.js} "$out/AssistantProviderLogic.js"
    cat >"$out/ShellConfig.qml" <<'EOF'
import QtQuick

QtObject {
  readonly property string configName: "${cfg.configName}"
  readonly property int topBarHeight: ${toString cfg.topBarHeight}
  readonly property bool topBarShowSeconds: ${if cfg.topBarShowSeconds then "true" else "false"}
  readonly property int panelWidth: ${toString cfg.panelWidth}
  readonly property int barHeight: ${toString cfg.barHeight}
  readonly property int dashboardHeartbeatMs: ${toString cfg.dashboardHeartbeatMs}
  readonly property string notificationBackend: "${cfg.notifications.backend}"
  readonly property int notificationHistoryLimit: ${toString cfg.notifications.historyLimit}
  readonly property int notificationToastMaxPerOutput: ${toString cfg.notifications.toastMaxPerOutput}
  readonly property int notificationDefaultTimeoutMs: ${toString cfg.notifications.defaultTimeoutMs}
  readonly property int notificationCriticalTimeoutMs: ${toString cfg.notifications.criticalTimeoutMs}
  readonly property bool notificationImagesEnabled: ${if cfg.notifications.enableImages then "true" else "false"}
  readonly property bool notificationMarkupEnabled: ${if cfg.notifications.enableMarkup then "true" else "false"}
  readonly property string hostName: "${hostName}"
  readonly property string i3pmBin: "${config.home.profileDirectory}/bin/i3pm"
  readonly property string notificationMonitorBin: "${notificationMonitorScript}/bin/quickshell-notification-monitor"
  readonly property string networkStatusBin: "${networkStatusScript}/bin/quickshell-network-status"
  readonly property string systemStatsBin: "${systemStatsScript}/bin/quickshell-system-stats"
  readonly property string launcherQueryBin: "${launcherQueryScript}/bin/quickshell-elephant-launcher-query"
  readonly property string launcherLaunchBin: "${launcherLaunchScript}/bin/quickshell-elephant-launcher-launch"
  readonly property string fileListBin: "${fileListScript}/bin/quickshell-elephant-file-list"
  readonly property string fileActionBin: "${fileActionScript}/bin/quickshell-elephant-file-action"
  readonly property string urlListBin: "${config.home.profileDirectory}/bin/chrome-url-list"
  readonly property string urlOpenBin: "${config.home.profileDirectory}/bin/chrome-url-open"
  readonly property string runnerListBin: "${runnerListScript}/bin/quickshell-runner-list"
  readonly property string snippetsListBin: "${snippetsListScript}/bin/quickshell-snippets-list"
  readonly property string snippetsManageBin: "${snippetsManageScript}/bin/quickshell-snippets-manage"
  readonly property string launcherCommandActionBin: "${launcherCommandActionScript}/bin/quickshell-launcher-command-action"
  readonly property string onePasswordListBin: "${onePasswordListScript}/bin/quickshell-onepassword-list"
  readonly property string onePasswordActionBin: "${onePasswordActionScript}/bin/quickshell-onepassword-action"
  readonly property string clipboardListBin: "${clipboardListScript}/bin/quickshell-clipboard-list"
  readonly property string clipboardActionBin: "${clipboardActionScript}/bin/quickshell-clipboard-action"
  readonly property string onePasswordIcon: "${../../../assets/icons/1password.svg}"
  readonly property var primaryOutputs: ${builtins.toJSON cfg.primaryOutputs}
  readonly property bool perMonitorBars: ${if cfg.perMonitorBars then "true" else "false"}
  readonly property string panelOutputPolicy: "${cfg.panelOutputPolicy}"
  readonly property string codexIcon: "${../../../assets/icons/codex.svg}"
  readonly property string claudeIcon: "${../../../assets/icons/claude.svg}"
  readonly property string geminiIcon: "${../../../assets/icons/gemini.svg}"
  readonly property string aiFallbackIcon: "${../../../assets/icons/ai-chatbot.svg}"
}
EOF
  '';


  quickshellBin = lib.getExe pkgs.quickshell;

  notificationMonitorScript = pkgs.writeShellScriptBin "quickshell-notification-monitor" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.python3} -u - <<'PY'
import json
import subprocess
import sys
import time

INITIAL_RETRY_DELAY = 1.0
MAX_RETRY_DELAY = 30.0
BACKOFF_MULTIPLIER = 2.0


def initial_state() -> dict:
    return {
        "count": 0,
        "dnd": False,
        "visible": False,
        "inhibited": False,
        "has_unread": False,
        "display_count": "0",
        "error": False,
    }


def error_state() -> dict:
    payload = initial_state()
    payload["error"] = True
    return payload


def transform_event(raw_event: dict) -> dict:
    count = raw_event.get("count", 0)
    return {
        "count": count,
        "dnd": raw_event.get("dnd", False),
        "visible": raw_event.get("visible", False),
        "inhibited": raw_event.get("inhibited", False),
        "has_unread": count > 0,
        "display_count": "9+" if count > 9 else str(count),
        "error": False,
    }


def emit(data: dict) -> None:
    print(json.dumps(data), flush=True)


def subscribe_loop() -> None:
    retry_delay = INITIAL_RETRY_DELAY

    while True:
        try:
            proc = subprocess.Popen(
                ["swaync-client", "--subscribe"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )

            retry_delay = INITIAL_RETRY_DELAY

            assert proc.stdout is not None
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue

                try:
                    emit(transform_event(json.loads(line)))
                except json.JSONDecodeError as error:
                    print(f"[notification-monitor] malformed JSON: {error}", file=sys.stderr)

            proc.wait()

        except FileNotFoundError:
            print("[notification-monitor] swaync-client not found, retrying...", file=sys.stderr)
            emit(error_state())
        except Exception as error:
            print(f"[notification-monitor] error: {error}", file=sys.stderr)
            emit(error_state())

        print(f"[notification-monitor] reconnecting in {retry_delay}s...", file=sys.stderr)
        time.sleep(retry_delay)
        retry_delay = min(retry_delay * BACKOFF_MULTIPLIER, MAX_RETRY_DELAY)


emit(initial_state())
subscribe_loop()
PY
  '';

  networkStatusScript = pkgs.writeShellScriptBin "quickshell-network-status" ''
    set -euo pipefail

    if ! command -v nmcli >/dev/null 2>&1; then
      echo '{"connected":false,"kind":"offline","label":"Offline","signal":null}'
      exit 0
    fi

    active_line="$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null | ${pkgs.gawk}/bin/awk -F: '$3=="connected" { print; exit }')"

    if [ -z "$active_line" ]; then
      echo '{"connected":false,"kind":"offline","label":"Offline","signal":null}'
      exit 0
    fi

    IFS=: read -r device type _state connection <<<"$active_line"

    if [ "$type" = "wifi" ]; then
      signal="$(nmcli -t -f IN-USE,SIGNAL dev wifi list ifname "$device" 2>/dev/null | ${pkgs.gawk}/bin/awk -F: '$1=="*" { print $2; exit }')"
      if [ -z "$signal" ]; then
        signal=null
      fi
      printf '{"connected":true,"kind":"wifi","label":%s,"signal":%s}\n' \
        "$(${lib.getExe pkgs.jq} -Rn --arg value "$connection" '$value')" \
        "$signal"
      exit 0
    fi

    printf '{"connected":true,"kind":"ethernet","label":%s,"signal":null}\n' \
      "$(${lib.getExe pkgs.jq} -Rn --arg value "$connection" '$value')"
  '';

  systemStatsScript = pkgs.writeShellScriptBin "quickshell-system-stats" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.python3} -u - <<'PY'
import json
import time
from pathlib import Path


def read_meminfo() -> dict[str, int]:
    values: dict[str, int] = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        token = value.strip().split()[0]
        try:
            values[key] = int(token)
        except ValueError:
            continue
    return values


def read_loadavg() -> list[float]:
    tokens = Path("/proc/loadavg").read_text().strip().split()
    values: list[float] = []
    for token in tokens[:3]:
        try:
            values.append(float(token))
        except ValueError:
            values.append(0.0)
    while len(values) < 3:
        values.append(0.0)
    return values


def read_temperature_c() -> int | None:
    thermal_root = Path("/sys/class/thermal")
    if thermal_root.exists():
        for zone in sorted(thermal_root.glob("thermal_zone*")):
            temp_path = zone / "temp"
            if not temp_path.exists():
                continue
            try:
                value = int(temp_path.read_text().strip())
            except ValueError:
                continue
            if value > 0:
                return round(value / 1000)

    hwmon_root = Path("/sys/class/hwmon")
    if hwmon_root.exists():
        for sensor in sorted(hwmon_root.glob("hwmon*")):
            for temp_path in sorted(sensor.glob("temp*_input")):
                try:
                    value = int(temp_path.read_text().strip())
                except ValueError:
                    continue
                if value > 0:
                    return round(value / 1000)

    return None


while True:
    try:
        meminfo = read_meminfo()
        total_kb = max(1, int(meminfo.get("MemTotal", 0)))
        available_kb = max(0, int(meminfo.get("MemAvailable", meminfo.get("MemFree", 0))))
        used_kb = max(0, total_kb - available_kb)
        swap_total_kb = max(0, int(meminfo.get("SwapTotal", 0)))
        swap_free_kb = max(0, int(meminfo.get("SwapFree", 0)))
        swap_used_kb = max(0, swap_total_kb - swap_free_kb)
        load1, load5, load15 = read_loadavg()

        payload = {
            "memory_percent": round((used_kb / total_kb) * 100, 1),
            "memory_used_gb": round(used_kb / (1024 * 1024), 1),
            "memory_total_gb": round(total_kb / (1024 * 1024), 1),
            "swap_used_gb": round(swap_used_kb / (1024 * 1024), 1),
            "swap_total_gb": round(swap_total_kb / (1024 * 1024), 1),
            "load1": round(load1, 2),
            "load5": round(load5, 2),
            "load15": round(load15, 2),
            "temperature_c": read_temperature_c(),
        }
        print(json.dumps(payload), flush=True)
    except Exception as error:
        print(json.dumps({
            "memory_percent": 0,
            "memory_used_gb": 0,
            "memory_total_gb": 0,
            "swap_used_gb": 0,
            "swap_total_gb": 0,
            "load1": 0,
            "load5": 0,
            "load15": 0,
            "temperature_c": None,
            "error": str(error),
        }), flush=True)
    time.sleep(1)
PY
  '';

  launcherQueryScript = pkgs.writeShellScriptBin "quickshell-elephant-launcher-query" ''
    set -euo pipefail

    query="''${1:-}"
    limit="''${2:-12}"
    min_score="''${3:-20}"

    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
      limit=12
    fi

    if ! [[ "$min_score" =~ ^[0-9]+$ ]]; then
      min_score=20
    fi

    elephant query "desktopapplications;''${query};''${min_score};false" --json 2>/dev/null \
      | ${lib.getExe pkgs.jq} -cs --argjson limit "$limit" '
          map(select(.item? and (.item.identifier? // "") != ""))
          | map(.item | {
              identifier: .identifier,
              text: (.text // ""),
              subtext: (.subtext // ""),
              icon: (.icon // ""),
              score: (.score // 0),
              state: (.state // []),
              actions: (.actions // [])
            })
          | .[:$limit]
        '
  '';

  launcherLaunchScript = pkgs.writeShellScriptBin "quickshell-elephant-launcher-launch" ''
    set -euo pipefail

    identifier="''${1:-}"
    if [ -z "$identifier" ]; then
      echo "missing desktop entry identifier" >&2
      exit 1
    fi

    if [ -f "$identifier" ]; then
      exec ${pkgs.glib}/bin/gio launch "$identifier"
    fi

    find_desktop_file() {
      local candidate="$1"
      local base_dir

      if [ -n "''${XDG_DATA_HOME:-}" ] && [ -f "$XDG_DATA_HOME/applications/$candidate" ]; then
        printf '%s\n' "$XDG_DATA_HOME/applications/$candidate"
        return 0
      fi

      local data_dirs="''${XDG_DATA_DIRS:-}"
      IFS=: read -r -a search_dirs <<<"$data_dirs"
      for base_dir in "''${search_dirs[@]}"; do
        [ -n "$base_dir" ] || continue
        if [ -f "$base_dir/applications/$candidate" ]; then
          printf '%s\n' "$base_dir/applications/$candidate"
          return 0
        fi
      done

      return 1
    }

    if desktop_file=$(find_desktop_file "$identifier"); then
      exec ${pkgs.glib}/bin/gio launch "$desktop_file"
    fi

    exec ${pkgs.gtk3}/bin/gtk-launch "''${identifier%.desktop}"
  '';

  fileListScript = pkgs.writeShellScriptBin "quickshell-elephant-file-list" ''
    set -euo pipefail

    query="''${1:-}"
    limit="''${2:-40}"

    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
      limit=40
    fi

    export QUICKSHELL_FILE_QUERY="$query"
    export QUICKSHELL_FILE_LIMIT="$limit"

    # Elephant's files query surface currently returns empty/crashes in this environment,
    # so use the same search roots/ignore shape with fd + fzf filtering for QuickShell.
    exec ${lib.getExe pkgs.python3} - <<'PY'
import json
import os
import subprocess
from pathlib import Path

query = os.environ.get("QUICKSHELL_FILE_QUERY", "").strip()
limit = int(os.environ.get("QUICKSHELL_FILE_LIMIT", "40") or "40")
home = Path.home()

roots = []


def add_root(value: str) -> None:
    if not value:
        return
    path = Path(value).expanduser()
    if not path.is_dir():
        return
    resolved = str(path.resolve())
    if resolved not in roots:
        roots.append(resolved)


context_json = "{}"
try:
    context_run = subprocess.run(
        ["${config.home.profileDirectory}/bin/i3pm", "context", "current", "--json"],
        capture_output=True,
        text=True,
        check=False,
    )
    context_json = context_run.stdout or "{}"
except Exception:
    context_json = "{}"

try:
    context = json.loads(context_json)
except Exception:
    context = {}

add_root(str(context.get("local_directory") or context.get("directory") or ""))
add_root(str(home))
add_root("/etc/nixos")

if not roots:
    print("[]")
    raise SystemExit(0)

fd_cmd = [
    "${lib.getExe pkgs.fd}",
    "--hidden",
    "--ignore-vcs",
    "--absolute-path",
    "--type",
    "file",
    "--type",
    "directory",
    "--exclude",
    ".cache",
    "--exclude",
    ".local/share/Trash",
    "--exclude",
    ".npm",
    "--exclude",
    ".cargo",
    "--exclude",
    "node_modules",
    "--exclude",
    ".nix-profile",
    ".",
    *roots,
]

fd_run = subprocess.run(fd_cmd, capture_output=True, text=True, check=False)
candidates = [line.strip() for line in fd_run.stdout.splitlines() if line.strip()]
if not candidates:
    print("[]")
    raise SystemExit(0)

if query:
    fzf_run = subprocess.run(
        ["${lib.getExe pkgs.fzf}", "--filter", query, "--scheme=path"],
        input="\n".join(candidates) + "\n",
        capture_output=True,
        text=True,
        check=False,
    )
    filtered = fzf_run.stdout.splitlines()
else:
    filtered = candidates

results = []
seen = set()
for raw in filtered:
    value = raw.strip()
    if not value or value in seen:
        continue
    seen.add(value)
    path = Path(value)
    is_dir = path.is_dir()
    display_name = path.name or value
    if is_dir and not display_name.endswith("/"):
        display_name += "/"
    results.append(
        {
            "kind": "file",
            "identifier": value,
            "text": display_name,
            "subtext": str(path if is_dir else path.parent),
            "icon": "folder" if is_dir else "",
            "state": ["directory"] if is_dir else ["file"],
            "actions": ["open", "opendir"],
            "provider": "files",
        }
    )
    if len(results) >= limit:
        break

print(json.dumps(results))
PY
  '';

  fileActionScript = pkgs.writeShellScriptBin "quickshell-elephant-file-action" ''
    set -euo pipefail

    action="''${1:-open}"
    identifier="''${2:-}"

    case "$action" in
      open|opendir) ;;
      *)
        echo "unsupported file action: $action" >&2
        exit 1
        ;;
    esac

    if [[ -z "$identifier" ]]; then
      echo "missing file identifier" >&2
      exit 1
    fi

    if [[ ! -e "$identifier" ]]; then
      echo "file path does not exist: $identifier" >&2
      exit 1
    fi

    target="$identifier"
    if [[ "$action" == "opendir" && ! -d "$target" ]]; then
      target=$(${pkgs.coreutils}/bin/dirname -- "$identifier")
    fi

    exec ${pkgs.glib}/bin/gio open "$target"
  '';

  runnerListScript = pkgs.writeShellScriptBin "quickshell-runner-list" ''
    set -euo pipefail

    query="''${1:-}"
    trimmed=$(${pkgs.coreutils}/bin/printf '%s' "$query" | ${pkgs.gnused}/bin/sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [[ -z "$trimmed" ]]; then
      printf '[]\n'
      exit 0
    fi

    context_json=$("${config.home.profileDirectory}/bin/i3pm" context current --json 2>/dev/null || printf '{}')
    context_dir=$(printf '%s\n' "$context_json" | ${lib.getExe pkgs.jq} -r '.local_directory // .directory // ""' 2>/dev/null || true)

    if [[ -z "$context_dir" || ! -d "$context_dir" ]]; then
      context_dir="$HOME"
    fi

    display_dir="$context_dir"
    if [[ "$display_dir" == "$HOME" ]]; then
      display_dir="~"
    elif [[ "$display_dir" == "$HOME/"* ]]; then
      display_dir="~''${display_dir#$HOME}"
    fi

    ${lib.getExe pkgs.jq} -cn \
      --arg identifier "$trimmed" \
      --arg text "$trimmed" \
      --arg subtext "Run in $display_dir" \
      '[{
        kind: "runner",
        identifier: $identifier,
        text: $text,
        subtext: $subtext,
        icon: "utilities-terminal"
      }]'
  '';

  snippetsListScript = pkgs.writeShellScriptBin "quickshell-snippets-list" ''
    set -euo pipefail

    query="''${1:-}"
    limit="''${2:-40}"

    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
      limit=40
    fi

    export QUICKSHELL_SNIPPETS_QUERY="$query"
    export QUICKSHELL_SNIPPETS_LIMIT="$limit"

    exec ${lib.getExe pkgs.python3} - <<'PY'
import json
import os
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib

query = os.environ.get("QUICKSHELL_SNIPPETS_QUERY", "").strip().lower()
tokens = [token for token in query.split() if token]
limit = int(os.environ.get("QUICKSHELL_SNIPPETS_LIMIT", "40") or "40")
path = Path.home() / ".config" / "elephant" / "snippets.toml"

if not path.exists():
    print("[]")
    raise SystemExit(0)

try:
    with path.open("rb") as handle:
        data = tomllib.load(handle)
except Exception:
    print("[]")
    raise SystemExit(0)

entries = []
for index, item in enumerate(data.get("snippets", [])):
    if not isinstance(item, dict):
        continue

    name = str(item.get("name", "") or "").strip()
    command = str(item.get("snippet", "") or "").strip()
    description = str(item.get("description", "") or "").strip()

    if not name and not command:
        continue

    haystack = " ".join(part for part in [name, description, command] if part).lower()
    if tokens and not all(token in haystack for token in tokens):
        continue

    subtitle_parts = []
    if description:
        subtitle_parts.append(description)
    if command:
        subtitle_parts.append(command)

    entries.append(
        {
            "kind": "snippet",
            "index": index,
            "identifier": name or command,
            "text": name or command,
            "subtext": "  •  ".join(subtitle_parts),
            "description": description,
            "command": command,
            "icon": "insert-text",
        }
    )

print(json.dumps(entries[:limit]))
PY
  '';

  snippetsManageScript = pkgs.writeShellScriptBin "quickshell-snippets-manage" ''
    set -euo pipefail

    action="''${1:-}"
    shift || true

    case "$action" in
      upsert)
        export QUICKSHELL_SNIPPETS_ACTION="$action"
        export QUICKSHELL_SNIPPETS_INDEX="''${1:--1}"
        export QUICKSHELL_SNIPPETS_NAME="''${2:-}"
        export QUICKSHELL_SNIPPETS_COMMAND="''${3:-}"
        export QUICKSHELL_SNIPPETS_DESCRIPTION="''${4:-}"
        ;;
      remove)
        export QUICKSHELL_SNIPPETS_ACTION="$action"
        export QUICKSHELL_SNIPPETS_INDEX="''${1:-}"
        ;;
      move)
        export QUICKSHELL_SNIPPETS_ACTION="$action"
        export QUICKSHELL_SNIPPETS_INDEX="''${1:-}"
        export QUICKSHELL_SNIPPETS_DIRECTION="''${2:-}"
        ;;
      *)
        echo "unsupported snippets action: $action" >&2
        exit 1
        ;;
    esac

    exec ${lib.getExe pkgs.python3} - <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib

path = Path.home() / ".config" / "elephant" / "snippets.toml"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def load_data() -> dict:
    if not path.exists():
        return {}
    try:
        with path.open("rb") as handle:
            data = tomllib.load(handle)
    except Exception as exc:
        fail(f"unable to parse snippets file: {exc}")
    return dict(data) if isinstance(data, dict) else {}


def toml_escape(value: str) -> str:
    escaped = (
        str(value)
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\b", "\\b")
        .replace("\f", "\\f")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def format_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return toml_escape(value)
    if isinstance(value, list) and all(isinstance(item, (str, bool, int, float)) for item in value):
        return "[" + ", ".join(format_value(item) for item in value) + "]"
    return None


def write_data(data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Elephant Snippets Provider Configuration",
        "# Managed by QuickShell command settings",
        "",
    ]
    top_level_preferred_keys = ["icon", "min_score", "name_pretty", "hide_from_providerlist"]
    for key in top_level_preferred_keys:
        if key in data and key != "snippets":
            rendered = format_value(data.get(key))
            if rendered is not None:
                lines.append(f"{key} = {rendered}")
    for key in sorted(data.keys()):
        if key in top_level_preferred_keys or key == "snippets":
            continue
        rendered = format_value(data.get(key))
        if rendered is not None:
            lines.append(f"{key} = {rendered}")
    if len(lines) > 3:
        lines.append("")
    preferred_keys = ["name", "snippet", "description"]
    entries = [dict(item) for item in data.get("snippets", []) if isinstance(item, dict)]
    for index, entry in enumerate(entries):
        if index > 0:
            lines.append("")
        lines.append("[[snippets]]")
        for key in preferred_keys:
            if key in entry:
                rendered = format_value(entry.get(key))
                if rendered is not None:
                    lines.append(f"{key} = {rendered}")
        for key in sorted(entry.keys()):
            if key in preferred_keys:
                continue
            rendered = format_value(entry.get(key))
            if rendered is not None:
                lines.append(f"{key} = {rendered}")
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def reload_elephant() -> None:
    try:
        subprocess.run(
            ["systemctl", "--user", "restart", "elephant"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


action = os.environ.get("QUICKSHELL_SNIPPETS_ACTION", "").strip()
data = load_data()
entries = [dict(item) for item in data.get("snippets", []) if isinstance(item, dict)]
if "icon" not in data:
    data["icon"] = "insert-text"
if "min_score" not in data:
    data["min_score"] = 30

if action == "upsert":
    raw_index = os.environ.get("QUICKSHELL_SNIPPETS_INDEX", "-1").strip() or "-1"
    try:
        index = int(raw_index)
    except ValueError:
        fail(f"invalid snippets index: {raw_index}")
    name = os.environ.get("QUICKSHELL_SNIPPETS_NAME", "").strip()
    command = os.environ.get("QUICKSHELL_SNIPPETS_COMMAND", "").strip()
    description = os.environ.get("QUICKSHELL_SNIPPETS_DESCRIPTION", "").strip()

    if not name:
        fail("command name is required")
    if not command:
        fail("command text is required")

    next_entry = dict(entries[index]) if 0 <= index < len(entries) else {}
    next_entry["name"] = name
    next_entry["snippet"] = command
    if description:
        next_entry["description"] = description
    else:
        next_entry.pop("description", None)

    if 0 <= index < len(entries):
        entries[index] = next_entry
        result_index = index
        message = f"Updated curated command '{name}'"
    else:
        entries.append(next_entry)
        result_index = len(entries) - 1
        message = f"Added curated command '{name}'"

    data["snippets"] = entries
    write_data(data)
    reload_elephant()
    print(json.dumps({"ok": True, "action": action, "index": result_index, "identifier": name, "message": message}))
    raise SystemExit(0)

if action == "remove":
    raw_index = os.environ.get("QUICKSHELL_SNIPPETS_INDEX", "").strip()
    try:
        index = int(raw_index)
    except ValueError:
        fail(f"invalid snippets index: {raw_index}")
    if index < 0 or index >= len(entries):
        fail("curated command not found")
    removed = entries.pop(index)
    data["snippets"] = entries
    write_data(data)
    reload_elephant()
    next_index = max(0, min(index, len(entries) - 1))
    print(json.dumps({"ok": True, "action": action, "index": next_index, "identifier": str(removed.get("name") or removed.get("snippet") or ""), "message": f"Removed curated command '{removed.get('name') or removed.get('snippet') or 'entry'}'"}))
    raise SystemExit(0)

if action == "move":
    raw_index = os.environ.get("QUICKSHELL_SNIPPETS_INDEX", "").strip()
    direction = os.environ.get("QUICKSHELL_SNIPPETS_DIRECTION", "").strip().lower()
    try:
        index = int(raw_index)
    except ValueError:
        fail(f"invalid snippets index: {raw_index}")
    if direction not in {"up", "down"}:
        fail(f"invalid move direction: {direction}")
    if index < 0 or index >= len(entries):
        fail("curated command not found")
    target = index - 1 if direction == "up" else index + 1
    if target < 0 or target >= len(entries):
        fail(f"cannot move command {direction}")
    entries[index], entries[target] = entries[target], entries[index]
    data["snippets"] = entries
    write_data(data)
    reload_elephant()
    moved = entries[target]
    print(json.dumps({"ok": True, "action": action, "index": target, "identifier": str(moved.get("name") or moved.get("snippet") or ""), "message": f"Moved curated command {direction}"}))
    raise SystemExit(0)

fail(f"unsupported snippets action: {action}")
PY
  '';

  launcherCommandActionScript = pkgs.writeShellScriptBin "quickshell-launcher-command-action" ''
    set -euo pipefail

    mode="''${1:-background}"
    command="''${2:-}"

    case "$mode" in
      background|terminal) ;;
      *)
        echo "unsupported launcher command mode: $mode" >&2
        exit 1
        ;;
    esac

    if [[ -z "$command" ]]; then
      echo "missing launcher command" >&2
      exit 1
    fi

    context_json=$("${config.home.profileDirectory}/bin/i3pm" context current --json 2>/dev/null || printf '{}')
    context_dir=$(printf '%s\n' "$context_json" | ${lib.getExe pkgs.jq} -r '.local_directory // .directory // ""' 2>/dev/null || true)

    if [[ -z "$context_dir" || ! -d "$context_dir" ]]; then
      context_dir="$HOME"
    fi

    run_in_context() {
      cd "$context_dir"
      export PATH="${pkgs.libnotify}/bin:$PATH"
      exec ${pkgs.bash}/bin/bash -lc "$command"
    }

    shell_quote() {
      ${lib.getExe pkgs.jq} -Rn --arg value "$1" '$value | @sh'
    }

    resolve_terminal() {
      local candidate=""
      for candidate in "''${TERMINAL:-}" ${pkgs.ghostty}/bin/ghostty ${pkgs.alacritty}/bin/alacritty ${pkgs.xterm}/bin/xterm; do
        [[ -n "$candidate" ]] || continue
        if command -v "$candidate" >/dev/null 2>&1; then
          printf '%s\n' "$candidate"
          return 0
        fi
        if [[ -x "$candidate" ]]; then
          printf '%s\n' "$candidate"
          return 0
        fi
      done
      return 1
    }

    if [[ "$mode" == "background" ]]; then
      run_in_context
    fi

    launch_in_scratchpad() {
      local context_key execution_mode remote_host remote_user remote_port remote_dir
      local terminal_json tmux_session state shell_payload tmux_command

      context_key=$(printf '%s\n' "$context_json" | ${lib.getExe pkgs.jq} -r '.context_key // ""' 2>/dev/null || true)
      execution_mode=$(printf '%s\n' "$context_json" | ${lib.getExe pkgs.jq} -r '.execution_mode // "local"' 2>/dev/null || true)
      remote_host=$(printf '%s\n' "$context_json" | ${lib.getExe pkgs.jq} -r '.remote.host // ""' 2>/dev/null || true)
      remote_user=$(printf '%s\n' "$context_json" | ${lib.getExe pkgs.jq} -r '.remote.user // ""' 2>/dev/null || true)
      remote_port=$(printf '%s\n' "$context_json" | ${lib.getExe pkgs.jq} -r '.remote.port // 22' 2>/dev/null || true)
      remote_dir=$(printf '%s\n' "$context_json" | ${lib.getExe pkgs.jq} -r '.remote.remote_dir // .directory // ""' 2>/dev/null || true)

      if [[ -z "$context_key" ]]; then
        return 1
      fi

      terminal_json=$("${config.home.profileDirectory}/bin/i3pm" scratchpad status --context-key "$context_key" --json 2>/dev/null || printf '{"terminals":[],"count":0}')
      tmux_session=$(printf '%s\n' "$terminal_json" | ${lib.getExe pkgs.jq} -r '.terminals[0].tmux_session_name // ""' 2>/dev/null || true)
      state=$(printf '%s\n' "$terminal_json" | ${lib.getExe pkgs.jq} -r '.terminals[0].state // ""' 2>/dev/null || true)

      if [[ -z "$tmux_session" ]]; then
        terminal_json=$("${config.home.profileDirectory}/bin/i3pm" scratchpad launch --context-key "$context_key" --json 2>/dev/null || printf '{}')
        tmux_session=$(printf '%s\n' "$terminal_json" | ${lib.getExe pkgs.jq} -r '.tmux_session_name // ""' 2>/dev/null || true)
        state="visible"
      elif [[ "$state" != "visible" ]]; then
        "${config.home.profileDirectory}/bin/i3pm" scratchpad toggle --context-key "$context_key" --json >/dev/null 2>&1 || true
      fi

      if [[ -z "$tmux_session" ]]; then
        return 1
      fi

      shell_payload="${pkgs.bash}/bin/bash -lc $(shell_quote "$command; exec ${pkgs.bash}/bin/bash -l")"

      if [[ "$execution_mode" == "ssh" && -n "$remote_host" && -n "$remote_user" ]]; then
        tmux_command="tmux new-window -t $(shell_quote "$tmux_session") -c $(shell_quote "$remote_dir") $(shell_quote "$shell_payload")"
        if [[ -n "$remote_port" && "$remote_port" != "22" ]]; then
          ssh -p "$remote_port" "$remote_user@$remote_host" "$tmux_command"
          return $?
        fi
        ssh "$remote_user@$remote_host" "$tmux_command"
        return $?
      fi

      ${pkgs.tmux}/bin/tmux new-window -t "$tmux_session" -c "$context_dir" "$shell_payload"
    }

    if launch_in_scratchpad; then
      exit 0
    fi

    if ! terminal=$(resolve_terminal); then
      echo "no supported terminal found" >&2
      exit 1
    fi

    case "$terminal" in
      *ghostty)
        exec "$terminal" --working-directory="$context_dir" -e ${pkgs.bash}/bin/bash -lc "$command"
        ;;
      *xterm)
        exec "$terminal" -e ${pkgs.bash}/bin/bash -lc "cd \"$context_dir\" && $command"
        ;;
      *)
        exec "$terminal" --working-directory "$context_dir" -e ${pkgs.bash}/bin/bash -lc "$command"
        ;;
    esac
  '';

  onePasswordListScript = pkgs.writeShellScriptBin "quickshell-onepassword-list" ''
    set -euo pipefail

    walker_list="${config.home.profileDirectory}/bin/walker-1password-list"
    if [[ ! -x "$walker_list" ]]; then
      printf '[]\n'
      exit 0
    fi

    "$walker_list" 2>/dev/null | ${lib.getExe pkgs.jq} -Rsc '
      def icon_for($category):
        if $category == "login" then "dialog-password-symbolic"
        elif $category == "secure_note" then "accessories-text-editor-symbolic"
        elif $category == "ssh_key" then "utilities-terminal-symbolic"
        elif $category == "credit_card" then "auth-smartcard-symbolic"
        elif $category == "identity" then "avatar-default-symbolic"
        elif $category == "document" then "folder-documents-symbolic"
        elif $category == "password" then "dialog-password-symbolic"
        elif $category == "api_credential" then "network-server-symbolic"
        else "1password"
        end;

      split("\n")
      | map(select(length > 0))
      | map(split("\t"))
      | map(select(length >= 4))
      | map({
          kind: "onepassword",
          identifier: .[2],
          text: .[0],
          subtext: .[1],
          category: .[3],
          icon: (if length >= 5 and (.[4] | length > 0) then .[4] else icon_for(.[3]) end)
        })
    '
  '';

  onePasswordActionScript = pkgs.writeShellScriptBin "quickshell-onepassword-action" ''
    set -euo pipefail

    mode="''${1:-password}"
    item_id="''${2:-}"
    if [[ -z "$item_id" ]]; then
      echo "missing 1password item id" >&2
      exit 1
    fi

    exec "${config.home.profileDirectory}/bin/walker-1password-copy" "$mode" "$item_id"
  '';

  clipboardListScript = pkgs.writeShellScriptBin "quickshell-clipboard-list" ''
    set -euo pipefail

    query="''${1:-}"
    min_score="''${2:-30}"

    if ! [[ "$min_score" =~ ^[0-9]+$ ]]; then
      min_score=30
    fi

    elephant query "clipboard;''${query};''${min_score};false" --json 2>/dev/null \
      | ${lib.getExe pkgs.jq} -cs '
          map(select(.item? and (.item.identifier? // "") != ""))
          | map(.item | {
              kind: "clipboard",
              identifier: .identifier,
              text: (.text // ""),
              subtext: (.subtext // ""),
              preview: (.preview // ""),
              preview_type: (.preview_type // ""),
              icon: (
                if (.preview_type // "") == "file" then "image-x-generic"
                else "edit-paste"
                end
              ),
              state: (.state // []),
              actions: (.actions // []),
              provider: (.provider // "clipboard")
            })
        '
  '';

  clipboardActionScript = pkgs.writeShellScriptBin "quickshell-clipboard-action" ''
    set -euo pipefail

    action="''${1:-copy}"
    identifier="''${2:-}"

    case "$action" in
      copy|remove) ;;
      *)
        echo "unsupported clipboard action: $action" >&2
        exit 1
        ;;
    esac

    if [[ -z "$identifier" ]]; then
      echo "missing clipboard identifier" >&2
      exit 1
    fi

    exec elephant activate "clipboard;''${identifier};''${action};;"
  '';

  mkIpcScript = name: functionName: extraBody:
    pkgs.writeShellScriptBin name ''
      set -euo pipefail
      ${extraBody}
      exec ${quickshellBin} ipc -c ${cfg.configName} call shell ${functionName} "$@"
    '';

  togglePanelScript = pkgs.writeShellScriptBin "toggle-monitoring-panel" ''
    set -euo pipefail
    exec ${quickshellBin} ipc -c ${cfg.configName} call shell togglePanel
  '';

  toggleDockScript = pkgs.writeShellScriptBin "toggle-panel-dock-mode" ''
    set -euo pipefail
    exec ${quickshellBin} ipc -c ${cfg.configName} call shell toggleDockMode
  '';

  togglePowerMenuScript = mkIpcScript "toggle-runtime-power-menu" "togglePowerMenu" "";
  toggleLauncherScript = mkIpcScript "toggle-app-launcher" "toggleLauncher" "";
  toggleSettingsScript = mkIpcScript "toggle-runtime-settings" "toggleSettings" "";
  showRuntimeDevicesScript = pkgs.writeShellScriptBin "show-runtime-devices" ''
    set -euo pipefail
    exec ${quickshellBin} ipc -c ${cfg.configName} call shell showSettings devices
  '';
  toggleNotificationsScript = mkIpcScript "toggle-runtime-notifications" "toggleNotifications" "";
  toggleNotificationDndScript = mkIpcScript "toggle-runtime-notification-dnd" "toggleNotificationDnd" "";
  clearNotificationsScript = mkIpcScript "clear-runtime-notifications" "clearNotifications" "";

  monitorPanelTabScript = pkgs.writeShellScriptBin "monitor-panel-tab" ''
    set -euo pipefail
    case "''${1:-0}" in
      0) exec ${quickshellBin} ipc -c ${cfg.configName} call shell showWindowsTab ;;
      1) exec ${quickshellBin} ipc -c ${cfg.configName} call shell showSessionsTab ;;
      *) exec ${quickshellBin} ipc -c ${cfg.configName} call shell showHealthTab ;;
    esac
  '';

  cycleSessionsScript = pkgs.writeShellScriptBin "cycle-active-ai-session-action" ''
    set -euo pipefail
    case "''${1:-next}" in
      prev) exec ${quickshellBin} ipc -c ${cfg.configName} call shell prevSession ;;
      *) exec ${quickshellBin} ipc -c ${cfg.configName} call shell nextSession ;;
    esac
  '';

  showAiSwitcherScript = pkgs.writeShellScriptBin "show-ai-mru-switcher-action" ''
    set -euo pipefail
    case "''${1:-next}" in
      prev) exec ${quickshellBin} ipc -c ${cfg.configName} call shell prevLauncherSession ;;
      *) exec ${quickshellBin} ipc -c ${cfg.configName} call shell nextLauncherSession ;;
    esac
  '';

  commitAiSwitcherScript = pkgs.writeShellScriptBin "commit-ai-session-switch-action" ''
    set -euo pipefail
    exec ${quickshellBin} ipc -c ${cfg.configName} call shell commitLauncherSession
  '';

  focusLastSessionScript = pkgs.writeShellScriptBin "toggle-last-ai-session-action" ''
    set -euo pipefail
    exec ${quickshellBin} ipc -c ${cfg.configName} call shell focusLastSession
  '';

  cycleDisplayLayoutScript = pkgs.writeShellScriptBin "cycle-display-layout" ''
    set -euo pipefail
    exec ${config.home.profileDirectory}/bin/i3pm display cycle
  '';
in
{
  options.programs.quickshell-runtime-shell = {
    enable = lib.mkEnableOption "daemon-backed Quickshell runtime shell";

    configName = lib.mkOption {
      type = lib.types.str;
      default = "i3pm-shell";
      description = "Quickshell configuration name.";
    };

    panelWidth = lib.mkOption {
      type = lib.types.int;
      default = 440;
      description = "Width of the right-side monitoring panel in pixels.";
    };

    topBarHeight = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Height of the top QuickShell system bar in pixels.";
    };

    topBarShowSeconds = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether the top QuickShell bar clock should show seconds.";
    };

    barHeight = lib.mkOption {
      type = lib.types.int;
      default = 38;
      description = "Height of the bottom workspace bar in pixels.";
    };

    dashboardHeartbeatMs = lib.mkOption {
      type = lib.types.int;
      default = 5000;
      description = "Fallback dashboard refresh cadence in milliseconds for the shell watcher.";
    };

    primaryOutputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        if hostName == "ryzen" then [ "DP-1" "HDMI-A-1" "DP-2" "DP-3" ]
        else if hostName == "thinkpad" then [ "eDP-1" "HDMI-A-1" "DP-1" "DP-2" ]
        else [ "HEADLESS-1" "eDP-1" "DP-1" "HDMI-A-1" ];
      description = "Ordered list of preferred output names for the QuickShell primary panel.";
    };

    perMonitorBars = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Render one QuickShell workspace/status bar per connected monitor.";
    };

    panelOutputPolicy = lib.mkOption {
      type = lib.types.enum [ "primary" ];
      default = "primary";
      description = "Policy for choosing the monitor that hosts the AI detail panel.";
    };

    toggleKey = lib.mkOption {
      type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
      default = "$mod+m";
      description = "Keybinding(s) used to toggle the runtime shell panel.";
    };

    notifications = {
      backend = lib.mkOption {
        type = lib.types.enum [ "native" "swaync" ];
        default = "native";
        description = "Notification backend owned by the runtime shell.";
      };

      historyLimit = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "Maximum number of notifications retained in the in-memory QuickShell feed.";
      };

      toastMaxPerOutput = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Maximum number of visible notification toasts per output.";
      };

      defaultTimeoutMs = lib.mkOption {
        type = lib.types.int;
        default = 8000;
        description = "Default notification toast timeout in milliseconds.";
      };

      criticalTimeoutMs = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Critical notification timeout in milliseconds. Zero keeps the toast resident until dismissed.";
      };

      enableImages = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether the native QuickShell notification UI should render notification images.";
      };

      enableMarkup = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the native QuickShell notification UI should render markup bodies.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    qt.enable = true;

    home.packages = [
      pkgs.quickshell
      pkgs.qt6.qtdeclarative
      togglePanelScript
      toggleDockScript
      togglePowerMenuScript
      toggleLauncherScript
      toggleSettingsScript
      showRuntimeDevicesScript
      toggleNotificationsScript
      toggleNotificationDndScript
      clearNotificationsScript
      monitorPanelTabScript
      cycleSessionsScript
      showAiSwitcherScript
      commitAiSwitcherScript
      focusLastSessionScript
      cycleDisplayLayoutScript
      notificationMonitorScript
      networkStatusScript
      systemStatsScript
      launcherQueryScript
      launcherLaunchScript
      runnerListScript
      snippetsListScript
      launcherCommandActionScript
    ];

    home.activation.migrateQuickshellRuntimeShellConfig = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      set -euo pipefail

      CONFIG_DIR="$HOME/.config/quickshell/${cfg.configName}"

      if [ -L "$CONFIG_DIR" ]; then
        TARGET="$(${pkgs.coreutils}/bin/readlink -f "$CONFIG_DIR" || true)"
        case "$TARGET" in
          /nix/store/*) ${pkgs.coreutils}/bin/rm -f "$CONFIG_DIR" ;;
        esac
      fi
    '';

    # Link individual files so the config directory stays writable for qmlls.
    xdg.configFile."quickshell/${cfg.configName}/shell.qml".source = shellConfigDir + "/shell.qml";
    xdg.configFile."quickshell/${cfg.configName}/ShellConfig.qml".source = shellConfigDir + "/ShellConfig.qml";
    xdg.configFile."quickshell/${cfg.configName}/SessionRow.qml".source = shellConfigDir + "/SessionRow.qml";
    xdg.configFile."quickshell/${cfg.configName}/NotificationToast.qml".source = shellConfigDir + "/NotificationToast.qml";
    xdg.configFile."quickshell/${cfg.configName}/NotificationRailCard.qml".source = shellConfigDir + "/NotificationRailCard.qml";
    xdg.configFile."quickshell/${cfg.configName}/AssistantPanel.qml".source = shellConfigDir + "/AssistantPanel.qml";
    xdg.configFile."quickshell/${cfg.configName}/AssistantService.qml".source = shellConfigDir + "/AssistantService.qml";
    xdg.configFile."quickshell/${cfg.configName}/AssistantProviderLogic.js".source = shellConfigDir + "/AssistantProviderLogic.js";

    home.activation.ensureQuickshellQmllsConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      set -euo pipefail

      CONFIG_DIR="$HOME/.config/quickshell/${cfg.configName}"
      QMLLS_INI="$CONFIG_DIR/.qmlls.ini"

      if [ ! -d "$CONFIG_DIR" ]; then
        exit 0
      fi

      if [ ! -e "$QMLLS_INI" ] || [ -L "$QMLLS_INI" ]; then
        ${pkgs.coreutils}/bin/rm -f "$QMLLS_INI"
        ${pkgs.coreutils}/bin/touch "$QMLLS_INI"
        ${pkgs.coreutils}/bin/chmod 0644 "$QMLLS_INI"
      fi
    '';

    systemd.user.services.quickshell-runtime-shell = {
      Unit = {
        Description = "Quickshell runtime shell";
        After = [ "sway-session.target" "i3-project-daemon.service" ];
        PartOf = [ "sway-session.target" ];
        BindsTo = [ "sway-session.target" ];
        X-Restart-Triggers = [ shellConfigDir ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${quickshellBin} -c ${cfg.configName}";
        Restart = "on-failure";
        RestartSec = "1s";
        Environment = [
          "QT_QUICK_CONTROLS_STYLE=Fusion"
          "QT_QPA_PLATFORM=wayland"
        ];
      };
      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}

{ config, lib, pkgs, inputs ? null, osConfig ? null, ... }:

let
  cfg = config.programs.quickshell-runtime-shell;
  appRegistrySyncTool = import ../app-registry-sync-tool.nix { inherit pkgs lib; };
  hostName =
    if osConfig != null && osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else "unknown";
  supportsPowerProfiles =
    osConfig != null
    && osConfig ? services
    && osConfig.services ? "power-profiles-daemon"
    && osConfig.services."power-profiles-daemon".enable;
  supportsLidPolicyControls = hostName == "thinkpad";
  # NVIDIA's Qt6/Wayland EGL buffer import is unstable, so those hosts fall back
  # to the software Qt Quick backend. Intel/AMD hosts must NOT — software
  # rendering of the animated shell there produces glitchy/stuttering UI.
  # Gate on the actual NVIDIA X/Wayland driver being selected. Note
  # hardware.nvidia.modesetting.enable defaults to true everywhere and is NOT a
  # reliable signal; services.xserver.videoDrivers is ["nvidia"] only on hosts
  # that actually drive NVIDIA (ryzen), vs ["modesetting"] on Intel (thinkpad).
  usesNvidia = osConfig != null
    && lib.elem "nvidia" (lib.attrByPath [ "services" "xserver" "videoDrivers" ] [ ] osConfig);
  lidPolicyFragmentPath = "/etc/nixos/configurations/thinkpad-lid-policy.nix";
  clipboardHistoryFile = "${config.home.homeDirectory}/.cache/i3pm/clipboard-history.json";

  # ---- Keybinding cheat sheet -------------------------------------------
  # The launcher's Keys mode renders the same described list sway is built
  # from (sway-keybindings-data.nix), plus the runtime-shell-owned bindings
  # defined in this module and, last, whatever else is in sway's final
  # keybinding attrset (Home Manager's stock workspace bindings) so the sheet
  # is complete rather than merely the bindings someone remembered to describe.
  swayModifier = lib.attrByPath [ "wayland" "windowManager" "sway" "config" "modifier" ] "Mod4" config;
  swayKeybindings = lib.attrByPath [ "wayland" "windowManager" "sway" "config" "keybindings" ] { } config;
  keybindingData = import ../sway-keybindings-data.nix {
    inherit lib;
    modifier = swayModifier;
    hasRuntimeShell = true;
  };
  toggleKeys =
    let keys = if lib.isList cfg.toggleKey then cfg.toggleKey else [ cfg.toggleKey ];
    in lib.unique (map (key: lib.replaceStrings [ "$mod" ] [ swayModifier ] key) keys);
  runtimeShellOwnedBindings =
    (map (key: { inherit key; cmd = "exec toggle-runtime-panel"; desc = "Toggle the runtime panel"; group = "Shell"; hidden = false; }) toggleKeys)
    ++ [ { key = "${swayModifier}+Shift+a"; cmd = "exec toggle-agent-monitor"; desc = "Toggle the AI-agents monitor strip"; group = "Shell"; hidden = false; } ];
  describedBindings = keybindingData.bindings ++ runtimeShellOwnedBindings;
  describedKeys = map (b: b.key) describedBindings;
  describeSwayCommand = cmd:
    let
      switchWs = builtins.match "workspace number ([0-9]+)" cmd;
      moveWs = builtins.match "move container to workspace number ([0-9]+)" cmd;
      stock = {
        "kill" = "Close window";
        "focus parent" = "Focus parent container";
        "fullscreen toggle" = "Toggle fullscreen";
        "mode resize" = "Resize mode";
        "exec i3pm launch open terminal" = "Open a terminal";
        "exec cast toggle" = "Cast toggle — TV as wireless display / stop";
      };
    in
    if switchWs != null then { desc = "Switch to workspace ${lib.head switchWs}"; group = "Workspaces"; }
    else if moveWs != null then { desc = "Move window to workspace ${lib.head moveWs}"; group = "Workspaces"; }
    else if stock ? ${cmd} then { desc = stock.${cmd}; group = "Windows"; }
    else { desc = cmd; group = "Other"; };
  undescribedBindings = lib.mapAttrsToList
    (key: cmd: { inherit key cmd; hidden = false; } // describeSwayCommand cmd)
    (lib.filterAttrs (key: cmd: cmd != null && !(lib.elem key describedKeys)) swayKeybindings);
  keyNames = {
    XF86MonBrightnessUp = "Brightness Up";
    XF86MonBrightnessDown = "Brightness Down";
    XF86KbdBrightnessUp = "Kbd Backlight Up";
    XF86KbdBrightnessDown = "Kbd Backlight Down";
    XF86AudioRaiseVolume = "Volume Up";
    XF86AudioLowerVolume = "Volume Down";
    XF86AudioMute = "Mute";
    XF86AudioMicMute = "Mic Mute";
    XF86AudioPlay = "Play/Pause";
    XF86AudioNext = "Next Track";
    XF86AudioPrev = "Previous Track";
  };
  humanKey = key: keyNames.${key} or (lib.replaceStrings
    [ "Mod4" "Mod1" "Control" "bracketright" "bracketleft" "backslash" "grave" "slash" "minus" "space" "Return" "Escape" "+" ]
    [ "Super" "Alt" "Ctrl" "]" "[" "\\" "`" "/" "-" "Space" "Enter" "Esc" " + " ]
    key);
  keybindingEntries = map
    (b: { key = humanKey b.key; raw = b.key; command = b.cmd; description = b.desc; group = b.group; })
    (lib.filter (b: !b.hidden) (describedBindings ++ undescribedBindings));
  quickshellPackage =
    if inputs != null
      && lib.hasAttrByPath [ "quickshell" "packages" pkgs.stdenv.hostPlatform.system "default" ] inputs
    then inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
    else pkgs.quickshell;

  # voxtype binary, for the dictation status indicator watcher.
  voxtypePkg = pkgs.callPackage ../../../packages/voxtype.nix { };

  # Live mic-level meter for the dictation overlay: reads the PipeWire default
  # source and prints a 0-100 level ~20x/sec. Quickshell runs it only while
  # recording. Uses absolute tool paths so it works under the bare service PATH.
  dictationLevelScript = pkgs.writeShellScriptBin "quickshell-dictation-level" ''
    exec ${pkgs.python3}/bin/python3 ${../scripts/dictation-level.py} ${pkgs.pipewire}/bin/pw-record
  '';

  # Build Theme.qml with accent color substitution.
  #
  # The palette now lives in the Theme singleton, so this substitution follows
  # it there. It also verifies each edit landed: a sed pattern that silently
  # stops matching would leave the accent* options looking configurable while
  # doing nothing, which is exactly what would have happened when the palette
  # moved out of shell.qml.
  # ---- Theme ------------------------------------------------------------
  # Theme.qml is generated from themes.nix: the configured theme's 24 base
  # tokens are baked in as fallbacks, and a runtime `overrides` map (fed from
  # the watched theme state file) can replace any of them live. Every other
  # token is derived inside the singleton and parametrised on `dark`, so a
  # light theme lifts surfaces with a dark film instead of a white one.
  themes = import ./themes.nix;
  themeName = cfg.theme;
  baseTheme = themes.${themeName} or (throw "programs.quickshell-runtime-shell.theme: unknown theme '${themeName}' (have: ${lib.concatStringsSep ", " (lib.attrNames themes)})");
  # The per-host accent options keep their old meaning: they replace the blue
  # family of the *configured* theme at build time.
  defaultTheme = baseTheme // {
    colors = baseTheme.colors // {
      blue = cfg.accentColor;
      blueBg = cfg.accentBg;
      blueMuted = cfg.accentMuted;
      blueWash = cfg.accentWash;
    };
  };
  themesExport = lib.mapAttrs (id: t: {
    inherit id;
    label = t.label;
    description = t.description or "";
    dark = t.dark;
    colors = if id == themeName then defaultTheme.colors else t.colors;
    terminal = t.terminal;
  }) themes;
  themesJson = pkgs.writeText "quickshell-runtime-shell-themes.json" (builtins.toJSON themesExport);
  themeStatePath = "${config.xdg.stateHome}/quickshell-runtime-shell/theme.json";
  colorProp = key: ''    readonly property color ${key}: pick("${key}", "${defaultTheme.colors.${key}}")'';
  themeQml = pkgs.writeText "Theme.qml" ''
    pragma Singleton

    import QtQuick
    import Quickshell

    // GENERATED from themes.nix (theme "${themeName}") by quickshell-runtime-shell/default.nix.
    // Components ask for semantic tokens ("the colour of a border", "the film
    // that lifts a surface") and never for literals. The base tokens fall back
    // to the built-in theme; `overrides` (set from the watched theme state
    // file) replaces them live, and everything derived follows.
    Singleton {
        id: theme

        property var overrides: ({})
        readonly property string name: (overrides && typeof overrides.name === "string" && overrides.name) ? overrides.name : "${themeName}"
        readonly property bool dark: (overrides && typeof overrides.dark === "boolean") ? overrides.dark : ${if defaultTheme.dark then "true" else "false"}

        function pick(key, fallback) {
            const value = overrides ? overrides[key] : undefined;
            return (typeof value === "string" && value) ? value : fallback;
        }

        // ---- base tokens (from themes.nix) ----
    ${lib.concatMapStringsSep "\n" colorProp [
      "bg" "panel" "panelAlt" "card" "cardAlt"
      "border" "borderStrong" "lineSoft"
      "text" "textDim" "muted" "subtle"
      "accent" "accentBg"
      "blue" "blueBg" "blueMuted" "blueWash"
      "green" "red" "amber" "orange" "teal" "violet"
    ]}

        // ---- derived: status chip fills (the hue at low alpha) ----
        readonly property real statusFillAlpha: 0.15
        readonly property color greenBg: Qt.rgba(theme.green.r, theme.green.g, theme.green.b, theme.statusFillAlpha)
        readonly property color redBg: Qt.rgba(theme.red.r, theme.red.g, theme.red.b, theme.statusFillAlpha)
        readonly property color amberBg: Qt.rgba(theme.amber.r, theme.amber.g, theme.amber.b, theme.statusFillAlpha)
        readonly property color orangeBg: Qt.rgba(theme.orange.r, theme.orange.g, theme.orange.b, theme.statusFillAlpha)
        readonly property color tealBg: Qt.rgba(theme.teal.r, theme.teal.g, theme.teal.b, theme.statusFillAlpha)
        readonly property color violetBg: Qt.rgba(theme.violet.r, theme.violet.g, theme.violet.b, theme.statusFillAlpha)

        // ---- derived: elevation films (white on dark, black on light) ----
        readonly property real film: dark ? 1 : 0
        readonly property color elevationFaint: Qt.rgba(film, film, film, 0.02)
        readonly property color elevationSoft: Qt.rgba(film, film, film, 0.04)
        readonly property color elevation: Qt.rgba(film, film, film, 0.06)
        readonly property color elevationStrong: Qt.rgba(film, film, film, 0.16)
        readonly property color hoverWash: Qt.rgba(film, film, film, 0.012)
        readonly property color hoverWashStrong: Qt.rgba(film, film, film, 0.018)

        // ---- derived: edges and depth ----
        readonly property color edgeHighlight: Qt.rgba(film, film, film, 0.08)
        readonly property color edgeHighlightSoft: Qt.rgba(film, film, film, 0.05)
        readonly property color edgeShadow: Qt.rgba(0, 0, 0, dark ? 0.4 : 0.18)
        readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.55 : 0.22)
        readonly property color shadowSoft: Qt.rgba(0, 0, 0, dark ? 0.25 : 0.10)

        // ---- derived: scrims, tinted toward the background ----
        readonly property color scrim: Qt.rgba(theme.bg.r, theme.bg.g, theme.bg.b, 0.4)
        readonly property color scrimStrong: Qt.rgba(theme.bg.r, theme.bg.g, theme.bg.b, 0.8)

        // ---- derived: frosted surfaces, same hue as their opaque twin ----
        readonly property color panelGlass: Qt.rgba(theme.panel.r, theme.panel.g, theme.panel.b, 0.88)
        readonly property color cardGlass: Qt.rgba(theme.card.r, theme.card.g, theme.card.b, 0.86)
        readonly property color toastGlass: Qt.rgba(theme.panel.r, theme.panel.g, theme.panel.b, 0.92)

        // ---- derived: status washes ----
        readonly property color redWash: Qt.rgba(theme.red.r, theme.red.g, theme.red.b, 0.08)
        readonly property color greenWash: Qt.rgba(theme.green.r, theme.green.g, theme.green.b, 0.06)
        readonly property color amberWash: Qt.rgba(theme.amber.r, theme.amber.g, theme.amber.b, 0.08)
        readonly property color tealWash: Qt.rgba(theme.teal.r, theme.teal.g, theme.teal.b, 0.09)
        readonly property color blueSelection: Qt.rgba(theme.blue.r, theme.blue.g, theme.blue.b, 0.10)
        readonly property color subtleWash: Qt.rgba(theme.subtle.r, theme.subtle.g, theme.subtle.b, 0.08)
    }
  '';

  shellConfigDir = pkgs.runCommandLocal "i3pm-quickshell-runtime-shell" { } ''
    mkdir -p "$out"
    cp ${./shell.qml} "$out/shell.qml"
    cp ${themeQml} "$out/Theme.qml"
    cp -r ${./controllers} "$out/controllers"
    cp -r ${./windows} "$out/windows"
    cp ${./SessionRow.qml} "$out/SessionRow.qml"
    cp ${./BarTooltip.qml} "$out/BarTooltip.qml"
    cp ${./NotificationToast.qml} "$out/NotificationToast.qml"
    cp ${./NotificationRailCard.qml} "$out/NotificationRailCard.qml"
    cat >"$out/ShellConfig.qml" <<'EOF'
import QtQuick

QtObject {
  readonly property string configName: "${cfg.configName}"
  readonly property int topBarHeight: ${toString cfg.topBarHeight}
  readonly property bool topBarShowSeconds: ${if cfg.topBarShowSeconds then "true" else "false"}
  readonly property int panelWidth: ${toString cfg.panelWidth}
  readonly property int barHeight: ${toString cfg.barHeight}
  readonly property string notificationBackend: "${cfg.notifications.backend}"
  readonly property int notificationHistoryLimit: ${toString cfg.notifications.historyLimit}
  readonly property int notificationToastMaxPerOutput: ${toString cfg.notifications.toastMaxPerOutput}
  readonly property int notificationDefaultTimeoutMs: ${toString cfg.notifications.defaultTimeoutMs}
  readonly property int notificationCriticalTimeoutMs: ${toString cfg.notifications.criticalTimeoutMs}
  readonly property bool notificationImagesEnabled: ${if cfg.notifications.enableImages then "true" else "false"}
  readonly property bool notificationMarkupEnabled: ${if cfg.notifications.enableMarkup then "true" else "false"}
  readonly property string hostName: "${hostName}"
  readonly property string userName: "${config.home.username}"
  readonly property string notificationStorePath: "${config.xdg.stateHome}/quickshell-runtime-shell/notifications.json"
  readonly property int idleScreenOffSeconds: ${toString cfg.idle.screenOffSeconds}
  readonly property int idleLockSeconds: ${toString cfg.idle.lockSeconds}
  readonly property string lockPamService: "${cfg.lock.pamService}"
  readonly property string agentUsageDir: "${agentUsageDir}"
  readonly property var themes: ${builtins.toJSON (lib.mapAttrs (_: t: removeAttrs t [ "terminal" ]) themesExport)}
  readonly property string defaultTheme: "${themeName}"
  readonly property string themeStatePath: "${themeStatePath}"
  readonly property string themeSetBin: "${runtimeThemeScript}/bin/runtime-theme"
  readonly property var agentUsageAgents: ${builtins.toJSON agentUsageAgents}
  readonly property string agentUsageUpdateBin: "${agentUsageUpdateScript}/bin/quickshell-agent-usage-update"
  readonly property string i3pmBin: "${config.home.profileDirectory}/bin/i3pm"
  readonly property string herdrBin: "${config.home.profileDirectory}/bin/herdr"
  readonly property string i3pmWatchBin: "${quickshellI3pmWatchScript}/bin/quickshell-i3pm-watch"
  readonly property string notificationMonitorBin: "${notificationMonitorScript}/bin/quickshell-notification-monitor"
  readonly property string networkStatusBin: "${networkStatusScript}/bin/quickshell-network-status"
  readonly property string systemStatsBin: "${systemStatsScript}/bin/quickshell-system-stats"
  readonly property string brightnessStatusBin: "${brightnessStatusScript}/bin/quickshell-brightness-status"
  readonly property string voxtypeStatusBin: "${voxtypePkg}/bin/voxtype"
  readonly property string dictationBin: "${config.home.homeDirectory}/.local/bin/dictation"
  readonly property string dictationLevelBin: "${dictationLevelScript}/bin/quickshell-dictation-level"
  readonly property string oskToggleBin: "${config.home.homeDirectory}/.local/bin/osk-toggle"
  readonly property string touchModeBin: "${config.home.homeDirectory}/.local/bin/touch-mode"
  readonly property string touchModeStatusBin: "${touchModeStatusScript}/bin/quickshell-touch-mode-status"
  readonly property string oskStatusBin: "${oskStatusScript}/bin/quickshell-osk-status"
  readonly property string lidClamshellBin: "${config.home.homeDirectory}/.local/bin/lid-clamshell"
  readonly property string brightnessActionBin: "${brightnessActionScript}/bin/quickshell-brightness-action"
  readonly property string castExtendBin: "${config.home.homeDirectory}/.local/bin/cast-extend"
  readonly property string castBin: "${config.home.profileDirectory}/bin/cast"
  readonly property string castStatusBin: "${castStatusScript}/bin/quickshell-cast-status"
  readonly property string lidPolicyStatusBin: "${lidPolicyStatusScript}/bin/quickshell-lid-policy-status"
  readonly property string lidPolicyApplyBin: "${lidPolicyApplyScript}/bin/quickshell-lid-policy-apply"
  readonly property string lidInhibitBin: "${lidInhibitScript}/bin/quickshell-lid-inhibit"
  readonly property string pkexecBin: "${pkgs.polkit}/bin/pkexec"
  readonly property string daemonActionBin: "${daemonActionScript}/bin/quickshell-daemon-action"
  readonly property string daemonHealthBin: "${daemonHealthScript}/bin/quickshell-daemon-health"
  readonly property string launcherQueryBin: "${launcherQueryScript}/bin/quickshell-app-launcher-query"
  readonly property string launcherLaunchBin: "${launcherLaunchScript}/bin/quickshell-elephant-launcher-launch"
  readonly property string fileListBin: "${fileListScript}/bin/quickshell-elephant-file-list"
  readonly property string fileActionBin: "${fileActionScript}/bin/quickshell-elephant-file-action"
  readonly property string urlListBin: "${config.home.profileDirectory}/bin/chrome-url-list"
  readonly property string urlOpenBin: "${config.home.profileDirectory}/bin/chrome-url-open"
  readonly property string runnerListBin: "${runnerListScript}/bin/quickshell-runner-list"
  readonly property string snippetsListBin: "${snippetsListScript}/bin/quickshell-snippets-list"
  readonly property string snippetsManageBin: "${snippetsManageScript}/bin/quickshell-snippets-manage"
  readonly property string appRegistryListBin: "${appRegistryListScript}/bin/quickshell-app-registry-list"
  readonly property string appRegistryManageBin: "${appRegistryManageScript}/bin/quickshell-app-registry-manage"
  readonly property string launcherCommandActionBin: "${launcherCommandActionScript}/bin/quickshell-launcher-command-action"
  readonly property string showRuntimeDisplaysBin: "${showRuntimeDisplaysScript}/bin/show-runtime-displays"
  readonly property string onePasswordListBin: "${onePasswordListScript}/bin/quickshell-onepassword-list"
  readonly property string onePasswordActionBin: "${onePasswordActionScript}/bin/quickshell-onepassword-action"
  readonly property string clipboardListBin: "${clipboardListScript}/bin/quickshell-clipboard-list"
  readonly property string clipboardActionBin: "${clipboardActionScript}/bin/quickshell-clipboard-action"
  readonly property string onePasswordIcon: "${../../../assets/icons/1password.svg}"
  readonly property var primaryOutputs: ${builtins.toJSON cfg.primaryOutputs}
  readonly property var keybindings: ${builtins.toJSON keybindingEntries}
  readonly property bool perMonitorBars: ${if cfg.perMonitorBars then "true" else "false"}
  readonly property string panelOutputPolicy: "${cfg.panelOutputPolicy}"
  readonly property string codexIcon: "${../../../assets/icons/codex.svg}"
  readonly property string claudeIcon: "${../../../assets/icons/claude.svg}"
  readonly property string geminiIcon: "${../../../assets/icons/gemini.png}"
  readonly property string kimiIcon: "${../../../assets/icons/kimi.svg}"
  readonly property string aiFallbackIcon: "${../../../assets/icons/ai-chatbot.svg}"
  readonly property string tailscaleIcon: "${../../../assets/icons/tailscale.svg}"
  // Per-host Herdr glyphs (local herdr.svg + herdr-<host>.svg remotes) used by
  // the monitor's host group headers and host badges. The directory lets QML
  // resolve herdr-<host>.svg for hosts that have no dedicated ShellConfig entry.
  readonly property string herdrIcon: "${../../../assets/icons/herdr.svg}"
  readonly property string herdrIconsDir: "${../../../assets/icons}"
  readonly property bool supportsPowerProfiles: ${if supportsPowerProfiles then "true" else "false"}
  readonly property bool supportsLidPolicyControls: ${if supportsLidPolicyControls then "true" else "false"}
  readonly property string lidPolicyFragmentPath: "${lidPolicyFragmentPath}"
}
EOF
  '';


  quickshellBin = lib.getExe quickshellPackage;

  quickshellI3pmWatchScript = pkgs.writeShellScriptBin "quickshell-i3pm-watch" ''
    set -euo pipefail

    i3pm_bin="${config.home.profileDirectory}/bin/i3pm"
    if [ "$#" -lt 2 ]; then
      exec "$i3pm_bin" "$@"
    fi

    case "$1:$2" in
      dashboard:watch)
        :
        ;;
      *)
        exec "$i3pm_bin" "$@"
        ;;
    esac

    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/i3pm-quickshell"
    ${pkgs.coreutils}/bin/mkdir -p "$runtime_dir"
    lock_file="$runtime_dir/dashboard-watch.lock"
    pid_file="$runtime_dir/dashboard-watch.pid"

    exec 9>"$lock_file"
    if ! ${pkgs.util-linux}/bin/flock -n 9; then
      old_pid="$(${pkgs.coreutils}/bin/cat "$pid_file" 2>/dev/null || true)"
      if [[ "$old_pid" =~ ^[0-9]+$ ]] && [ "$old_pid" != "$$" ]; then
        old_cmd="$(${pkgs.procps}/bin/ps -p "$old_pid" -o command= 2>/dev/null || true)"
        if [[ "$old_cmd" =~ dashboard[[:space:]]+watch ]]; then
          kill "$old_pid" 2>/dev/null || true
        fi
      fi

      for _ in 1 2 3 4 5 6 7 8 9 10; do
        if ${pkgs.util-linux}/bin/flock -n 9; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      if ! ${pkgs.util-linux}/bin/flock -n 9; then
        echo "dashboard watch lock is still held by pid ''${old_pid:-unknown}" >&2
        exit 1
      fi
    fi

    printf '%s\n' "$$" >"$pid_file"
    exec "$i3pm_bin" "$@"
  '';

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
      # --rescan no: read NM's cached scan results only; triggering a rescan
      # on every bar refresh would churn the Wi-Fi radio for no benefit.
      signal="$(nmcli -t -f IN-USE,SIGNAL dev wifi list ifname "$device" --rescan no 2>/dev/null | ${pkgs.gawk}/bin/awk -F: '$1=="*" { print $2; exit }')"
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


def read_system_generation() -> int:
    try:
        target = Path("/nix/var/nix/profiles/system").readlink()
        name = target.name  # e.g. "system-1609-link"
        return int(name.split("-")[1])
    except Exception:
        return 0


def read_disk_usage() -> dict:
    try:
        st = __import__("os").statvfs("/")
        total = st.f_frsize * st.f_blocks
        free = st.f_frsize * st.f_bfree
        used = total - free
        total_gb = total / (1024 ** 3)
        used_gb = used / (1024 ** 3)
        percent = round((used / total) * 100, 1) if total > 0 else 0
        return {"disk_percent": percent, "disk_used_gb": round(used_gb, 1), "disk_total_gb": round(total_gb, 1)}
    except Exception:
        return {"disk_percent": 0, "disk_used_gb": 0, "disk_total_gb": 0}


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

        disk = read_disk_usage()
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
            "system_generation": read_system_generation(),
            **disk,
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
            "system_generation": 0,
            "disk_percent": 0,
            "disk_used_gb": 0,
            "disk_total_gb": 0,
            "error": str(error),
        }), flush=True)
    time.sleep(1)
PY
  '';

  brightnessStatusScript = pkgs.writeShellScriptBin "quickshell-brightness-status" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.python3} -u - <<'PY'
import json
import time
from pathlib import Path


DISPLAY_PREFERENCE = [
    "apple-panel-bl",
    "intel_backlight",
]


def clamp_percent(value: float) -> int:
    return max(0, min(100, int(round(value))))


def list_dirs(path: str):
    root = Path(path)
    if not root.exists():
        return []
    return [entry for entry in root.iterdir() if entry.is_dir()]


def preferred_display_device():
    devices = list_dirs("/sys/class/backlight")
    if not devices:
        return None

    def score(device: Path):
        name = device.name
        if name in DISPLAY_PREFERENCE:
            return (DISPLAY_PREFERENCE.index(name), name)
        if name.startswith("amdgpu_bl"):
            return (len(DISPLAY_PREFERENCE), name)
        return (len(DISPLAY_PREFERENCE) + 1, name)

    return sorted(devices, key=score)[0]


def preferred_keyboard_device():
    devices = [
        entry
        for entry in list_dirs("/sys/class/leds")
        if "kbd_backlight" in entry.name
    ]
    if not devices:
        return None
    return sorted(devices, key=lambda entry: entry.name)[0]


def device_state(device: Path | None, label: str):
    if device is None:
        return {
            "available": False,
            "label": label,
            "device": "",
            "percent": 0,
            "current": 0,
            "max": 0,
        }

    try:
        current = int((device / "brightness").read_text().strip())
        maximum = int((device / "max_brightness").read_text().strip())
    except Exception:
        return {
            "available": False,
            "label": label,
            "device": device.name,
            "percent": 0,
            "current": 0,
            "max": 0,
        }

    percent = clamp_percent((current / maximum) * 100) if maximum > 0 else 0
    return {
        "available": True,
        "label": label,
        "device": device.name,
        "percent": percent,
        "current": current,
        "max": maximum,
    }


def emit():
    payload = {
        "display": device_state(preferred_display_device(), "Display brightness"),
        "keyboard": device_state(preferred_keyboard_device(), "Keyboard backlight"),
    }
    print(json.dumps(payload), flush=True)


emit()
while True:
    time.sleep(2)
    emit()
PY
  '';

  brightnessActionScript = pkgs.writeShellScriptBin "quickshell-brightness-action" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.python3} -u - "$@" <<'PY'
import json
import subprocess
import sys
from pathlib import Path


BRIGHTNESSCTL = "${lib.getExe pkgs.brightnessctl}"
DISPLAY_PREFERENCE = [
    "apple-panel-bl",
    "intel_backlight",
]


def fail(message: str, code: int = 1):
    print(message, file=sys.stderr, flush=True)
    raise SystemExit(code)


def clamp_percent(value: str) -> int:
    try:
        percent = int(round(float(value)))
    except ValueError:
        fail(f"invalid brightness percent: {value}")
    return max(0, min(100, percent))


def list_dirs(path: str):
    root = Path(path)
    if not root.exists():
        return []
    return [entry for entry in root.iterdir() if entry.is_dir()]


def preferred_display_device():
    devices = list_dirs("/sys/class/backlight")
    if not devices:
        return None

    def score(device: Path):
        name = device.name
        if name in DISPLAY_PREFERENCE:
            return (DISPLAY_PREFERENCE.index(name), name)
        if name.startswith("amdgpu_bl"):
            return (len(DISPLAY_PREFERENCE), name)
        return (len(DISPLAY_PREFERENCE) + 1, name)

    return sorted(devices, key=score)[0]


def preferred_keyboard_device():
    devices = [
        entry
        for entry in list_dirs("/sys/class/leds")
        if "kbd_backlight" in entry.name
    ]
    if not devices:
        return None
    return sorted(devices, key=lambda entry: entry.name)[0]


action = sys.argv[1] if len(sys.argv) > 1 else ""
target = sys.argv[2] if len(sys.argv) > 2 else ""
percent = sys.argv[3] if len(sys.argv) > 3 else ""

if action != "set":
    fail(f"unsupported brightness action: {action}")

if target == "display":
    device = preferred_display_device()
elif target == "keyboard":
    device = preferred_keyboard_device()
else:
    fail(f"unsupported brightness target: {target}")

if device is None:
    fail(f"brightness target unavailable: {target}")

clamped_percent = clamp_percent(percent)

result = subprocess.run(
    [BRIGHTNESSCTL, "-d", device.name, "set", f"{clamped_percent}%"],
    check=False,
    capture_output=True,
    text=True,
)

if result.returncode != 0:
    fail(result.stderr.strip() or result.stdout.strip() or f"brightnessctl failed for {target}", result.returncode)

print(json.dumps({
    "success": True,
    "target": target,
    "device": device.name,
    "percent": clamped_percent,
}), flush=True)
PY
  '';
  # Long-running touch-mode state feed for the bar chip. Emits a line only when
  # the state actually changes (plus one at startup so the chip has a value
  # immediately), so this costs one sleeping shell rather than a process spawn
  # per tick.
  #
  # Three states, because the chip should not exist at all on a machine with no
  # touchscreen: "none" (nothing to toggle), "off", "on".
  touchModeStatusScript = pkgs.writeShellScriptBin "quickshell-touch-mode-status" ''
    set -uo pipefail

    runtime="''${XDG_RUNTIME_DIR:-/tmp}"
    saved="$runtime/touch-mode.saved"      # written by touch-mode while it is on
    bindings="$runtime/touch-map.state"    # written by touch-map

    last=""
    while :; do
      # Presence of the saved-scales file is the authoritative "on" signal. The
      # output scale alone is not: the user may have chosen 2.0 themselves, and
      # the chip must not then claim touch mode owns it.
      if [ -s "$saved" ]; then
        cur=on
      elif ${pkgs.gnugrep}/bin/grep -qP '\ttouch$' "$bindings" 2>/dev/null; then
        cur=off
      else
        cur=none
      fi

      if [ "$cur" != "$last" ]; then
        printf '%s\n' "$cur"
        last="$cur"
      fi
      sleep 1
    done
  '';

  # On-screen keyboard visibility feed for the shell. osk-toggle records every
  # transition in $XDG_RUNTIME_DIR/osk.state (wvkbd itself cannot be queried);
  # the launcher reads this to give the keyboard room the moment it appears —
  # however it was raised: field tap, bar chip, edge gesture or CLI. Emits only
  # on change, plus one line at startup.
  oskStatusScript = pkgs.writeShellScriptBin "quickshell-osk-status" ''
    set -uo pipefail
    state_file="''${XDG_RUNTIME_DIR:-/tmp}/osk.state"
    last=""
    while :; do
      cur="$(cat "$state_file" 2>/dev/null | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
      cur="''${cur:-hidden}"
      if [ "$cur" != "$last" ]; then
        printf '%s\n' "$cur"
        last="$cur"
      fi
      sleep 0.3
    done
  '';

  # One-shot cast probe for the bar chip: prints a single JSON line and exits.
  # Primary source is the `cast` CLI (desktop/casting.nix), which reports the
  # real CDP-driven cast session (mode + receiver, verified against the live
  # route) plus caster health and the cast-extend headless output in one
  # probe. Fast path: with no session and no headless output, skip the CLI
  # (a Deno boot every 10s is not free). The sway-only fallback emits
  # active:false — it cannot see the cast session, so it must never claim one.
  castStatusScript = pkgs.writeShellScriptBin "quickshell-cast-status" ''
    set -euo pipefail

    runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    if [ ! -f "$runtime/cast.state" ] \
      && ! ${pkgs.sway}/bin/swaymsg -t get_outputs 2>/dev/null \
        | ${pkgs.jq}/bin/jq -e 'any(.[]; (.name | startswith("HEADLESS-")) and .active)' >/dev/null 2>&1; then
      printf '{"active":false,"output":"","detail":"Off — cast extend turns the TV into a display"}\n'
      exit 0
    fi

    if payload="$("${config.home.profileDirectory}/bin/cast" status --json 2>/dev/null)"; then
      printf '%s\n' "$payload"
      exit 0
    fi

    payload="$(${pkgs.sway}/bin/swaymsg -t get_outputs 2>/dev/null || true)"
    if [ -z "$payload" ]; then
      printf '{"active":false,"output":"","detail":"Sway IPC unavailable"}\n'
      exit 0
    fi
    printf '%s' "$payload" | ${pkgs.jq}/bin/jq -c '
      [.[] | select(.name | startswith("HEADLESS-"))] as $h
      | ([$h[] | select(.active)] | .[0]) as $live
      | if $live != null then
          {active: false, output: $live.name,
           detail: ("Cast output " + $live.name + " live (" + ($live.current_mode.width | tostring) + "x" + ($live.current_mode.height | tostring) + ") — no cast session (run: cast extend)")}
        elif ($h | length) > 0 then
          {active: false, output: $h[0].name, detail: "Cast output disabled — re-enable to resume casting"}
        else
          {active: false, output: "", detail: "Off — cast extend turns the TV into a display"}
        end'
  '';

  lidPolicyStatusScript = pkgs.writeShellScriptBin "quickshell-lid-policy-status" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.python3} -u - <<'PY'
import json
import os
import re
import time
from pathlib import Path


HOST_NAME = "${hostName}"
FRAGMENT_PATH = Path("${lidPolicyFragmentPath}")
ALLOWED = {"ignore", "lock", "suspend", "hibernate", "poweroff"}
DEFAULTS = {
    "battery": "suspend",
    "externalPower": "lock",
    "docked": "ignore",
}


def runtime_dir() -> Path:
    value = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    if value:
        return Path(value)
    return Path(f"/run/user/{os.getuid()}")


def pidfile() -> Path:
    return runtime_dir() / "quickshell-lid-inhibit.pid"


def extract(text: str, key: str, fallback: str) -> str:
    match = re.search(rf'{key}\\s*=\\s*"([^"]+)";', text)
    if not match:
        return fallback
    value = match.group(1)
    return value if value in ALLOWED else fallback


def read_policy() -> dict:
    if not FRAGMENT_PATH.exists():
        return dict(DEFAULTS)
    text = FRAGMENT_PATH.read_text()
    return {
        "battery": extract(text, "battery", DEFAULTS["battery"]),
        "externalPower": extract(text, "externalPower", DEFAULTS["externalPower"]),
        "docked": extract(text, "docked", DEFAULTS["docked"]),
    }


def active_inhibit_pid() -> int | None:
    path = pidfile()
    if not path.exists():
        return None
    try:
        pid = int(path.read_text().strip())
    except ValueError:
        path.unlink(missing_ok=True)
        return None
    try:
        os.kill(pid, 0)
    except OSError:
        path.unlink(missing_ok=True)
        return None
    return pid


def payload() -> dict:
    policy = read_policy()
    inhibit_pid = active_inhibit_pid()
    return {
        "supported": HOST_NAME == "thinkpad",
        "host": HOST_NAME,
        "fragment_path": str(FRAGMENT_PATH),
        "battery": policy["battery"],
        "externalPower": policy["externalPower"],
        "docked": policy["docked"],
        "inhibitActive": inhibit_pid is not None,
        "inhibitPid": inhibit_pid or 0,
    }


print(json.dumps(payload()), flush=True)
while True:
    time.sleep(5)
    print(json.dumps(payload()), flush=True)
PY
  '';

  lidInhibitScript = pkgs.writeShellScriptBin "quickshell-lid-inhibit" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.python3} -u - "$@" <<'PY'
import json
import os
import signal
import subprocess
import sys
from pathlib import Path


HOST_NAME = "${hostName}"
SYSTEMD_INHIBIT = "${pkgs.systemd}/bin/systemd-inhibit"


def fail(message: str, code: int = 1):
    print(message, file=sys.stderr, flush=True)
    raise SystemExit(code)


def runtime_dir() -> Path:
    value = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    if value:
        return Path(value)
    return Path(f"/run/user/{os.getuid()}")


def pidfile() -> Path:
    return runtime_dir() / "quickshell-lid-inhibit.pid"


def active_pid() -> int | None:
    path = pidfile()
    if not path.exists():
        return None
    try:
        pid = int(path.read_text().strip())
    except ValueError:
        path.unlink(missing_ok=True)
        return None
    try:
        os.kill(pid, 0)
    except OSError:
        path.unlink(missing_ok=True)
        return None
    return pid


def emit() -> None:
    pid = active_pid()
    print(json.dumps({
        "supported": HOST_NAME == "thinkpad",
        "inhibitActive": pid is not None,
        "inhibitPid": pid or 0,
    }), flush=True)


def enable() -> None:
    pid = active_pid()
    if pid is not None:
        emit()
        return
    proc = subprocess.Popen(
        [
            SYSTEMD_INHIBIT,
            "--what=handle-lid-switch:sleep",
            "--who=QuickShell Runtime Shell",
            "--why=Temporary lid-close keep-awake override",
            "sleep",
            "infinity",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    pidfile().write_text(f"{proc.pid}\n")
    emit()


def disable() -> None:
    pid = active_pid()
    if pid is not None:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    pidfile().unlink(missing_ok=True)
    emit()


action = sys.argv[1] if len(sys.argv) > 1 else "status"
if action == "enable":
    enable()
elif action == "disable":
    disable()
elif action == "status":
    emit()
else:
    fail(f"unsupported lid inhibit action: {action}")
PY
  '';

  lidPolicyApplyScript = pkgs.writeShellScriptBin "quickshell-lid-policy-apply" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.python3} -u - "$@" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path


HOST_NAME = subprocess.run(
    ["/run/current-system/sw/bin/hostname", "--short"],
    check=False,
    capture_output=True,
    text=True,
).stdout.strip().lower()
FRAGMENT_PATH = Path("${lidPolicyFragmentPath}")
ALLOWED = {"ignore", "lock", "suspend", "hibernate", "poweroff"}


def fail(message: str, code: int = 1):
    print(message, file=sys.stderr, flush=True)
    raise SystemExit(code)


def runtime_dir() -> Path:
    uid = os.environ.get("PKEXEC_UID", "").strip() or os.environ.get("SUDO_UID", "").strip()
    if uid:
        return Path(f"/run/user/{uid}")
    return Path(f"/run/user/{os.getuid()}")


def pidfile() -> Path:
    return runtime_dir() / "quickshell-lid-inhibit.pid"


def active_pid() -> int | None:
    path = pidfile()
    if not path.exists():
        return None
    try:
        pid = int(path.read_text().strip())
    except ValueError:
        path.unlink(missing_ok=True)
        return None
    try:
        os.kill(pid, 0)
    except OSError:
        path.unlink(missing_ok=True)
        return None
    return pid


def validate(value: str, field: str) -> str:
    normalized = value.strip().lower()
    if normalized not in ALLOWED:
        fail(f"unsupported {field} lid action: {value}")
    return normalized


action = sys.argv[1] if len(sys.argv) > 1 else ""
if action != "apply":
    fail(f"unsupported lid policy action: {action}")

if HOST_NAME != "thinkpad":
    fail(f"lid policy apply is only supported on thinkpad, current host is {HOST_NAME or 'unknown'}")

battery = validate(sys.argv[2] if len(sys.argv) > 2 else "", "battery")
external_power = validate(sys.argv[3] if len(sys.argv) > 3 else "", "external-power")
docked = validate(sys.argv[4] if len(sys.argv) > 4 else "", "docked")

FRAGMENT_PATH.parent.mkdir(parents=True, exist_ok=True)
tmp_path = FRAGMENT_PATH.with_suffix(".tmp")
tmp_path.write_text(
    "{\n"
    "  services.bare-metal.lidPolicy = {\n"
    f'    battery = "{battery}";\n'
    f'    externalPower = "{external_power}";\n'
    f'    docked = "{docked}";\n'
    "  };\n"
    "}\n"
)
os.replace(tmp_path, FRAGMENT_PATH)

result = subprocess.run(
    ["/run/current-system/sw/bin/nixos-rebuild", "switch", "--flake", "/etc/nixos#thinkpad"],
    check=False,
    capture_output=True,
    text=True,
)

if result.returncode != 0:
    fail(result.stderr.strip() or result.stdout.strip() or "nixos-rebuild switch failed", result.returncode)

inhibit_pid = active_pid()
print(json.dumps({
    "supported": True,
    "host": HOST_NAME,
    "fragment_path": str(FRAGMENT_PATH),
    "battery": battery,
    "externalPower": external_power,
    "docked": docked,
    "inhibitActive": inhibit_pid is not None,
    "inhibitPid": inhibit_pid or 0,
    "rebuild": "ok",
}), flush=True)
PY
  '';

  daemonHealthScript = pkgs.writeShellScriptBin "quickshell-daemon-health" ''
    exec ${lib.getExe pkgs.python3} -u - <<'PY'
import json
import os
import socket
import stat
import time


SOCKET_PATH = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}",
    "i3-project-daemon",
    "ipc.sock",
)
INTERVAL_SECONDS = 5.0
TIMEOUT_SECONDS = 1.5
FAILURE_THRESHOLD = 3


def emit(payload):
    print(json.dumps(payload, separators=(",", ":")), flush=True)


def rpc_health():
    if not stat_is_socket(SOCKET_PATH):
        raise FileNotFoundError(SOCKET_PATH)

    request = {"jsonrpc": "2.0", "id": 1, "method": "health_check", "params": {}}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(TIMEOUT_SECONDS)
        client.connect(SOCKET_PATH)
        client.sendall((json.dumps(request, separators=(",", ":")) + "\n").encode("utf-8"))
        with client.makefile("rb") as stream:
            line = stream.readline(1024 * 1024)
    if not line:
        raise TimeoutError("daemon returned no response")

    response = json.loads(line.decode("utf-8"))
    if response.get("error"):
        message = response["error"].get("message") if isinstance(response["error"], dict) else response["error"]
        raise RuntimeError(str(message or "daemon health_check returned an error"))
    result = response.get("result") or {}
    raw_status = str(result.get("overall_status") or "unknown")
    status = "unhealthy" if raw_status == "critical" else raw_status
    issues = result.get("health_issues") or []
    if not isinstance(issues, list):
        issues = [str(issues)]
    return {
        "status": status,
        "events": int(result.get("total_events_processed") or 0),
        "windows": int(result.get("total_windows") or 0),
        "uptime": float(result.get("uptime_seconds") or 0),
        "issues": "; ".join(str(issue) for issue in issues if str(issue)),
        "consecutive_failures": 0,
        "last_error": "",
    }


def stat_is_socket(path):
    try:
        return stat.S_ISSOCK(os.stat(path).st_mode)
    except FileNotFoundError:
        return False


last_good = None
consecutive_failures = 0

while True:
    try:
        payload = rpc_health()
        consecutive_failures = 0
        last_good = payload
        emit(payload)
    except Exception as exc:
        consecutive_failures += 1
        if consecutive_failures < FAILURE_THRESHOLD:
            if last_good is not None:
                payload = dict(last_good)
                payload["consecutive_failures"] = consecutive_failures
                payload["last_error"] = str(exc)
                emit(payload)
            else:
                emit({
                    "status": "unknown",
                    "events": 0,
                    "windows": 0,
                    "uptime": 0,
                    "issues": "",
                    "consecutive_failures": consecutive_failures,
                    "last_error": str(exc),
                })
        else:
            emit({
                "status": "dead" if not stat_is_socket(SOCKET_PATH) else "unreachable",
                "events": int((last_good or {}).get("events") or 0),
                "windows": int((last_good or {}).get("windows") or 0),
                "uptime": float((last_good or {}).get("uptime") or 0),
                "issues": str(exc),
                "consecutive_failures": consecutive_failures,
                "last_error": str(exc),
            })
    time.sleep(INTERVAL_SECONDS)
PY
  '';

  daemonActionPython = pkgs.writeText "quickshell-daemon-action.py" ''
import json
import os
import socket
import sys
import threading
from concurrent.futures import ThreadPoolExecutor


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or ""
if not runtime_dir:
    fail("XDG_RUNTIME_DIR is not set")

socket_path = os.path.join(runtime_dir, "i3-project-daemon", "ipc.sock")


def rpc_call(method: str, params: dict, request_id=1) -> dict:
    request = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
        "params": params,
    }
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(5.0)
        client.connect(socket_path)
        client.sendall((json.dumps(request, separators=(",", ":")) + "\n").encode("utf-8"))
        chunks = []
        while True:
            chunk = client.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break

    raw_response = b"".join(chunks).splitlines()[0] if chunks else b""
    if not raw_response:
        raise RuntimeError("daemon action returned an empty response")
    return json.loads(raw_response.decode("utf-8"))


def parse_params(value: str) -> dict:
    params = json.loads(value or "{}")
    if not isinstance(params, dict):
        raise ValueError("daemon action params must be a JSON object")
    return params


emit_lock = threading.Lock()


def emit(payload: dict) -> None:
    with emit_lock:
        print(json.dumps(payload, separators=(",", ":")), flush=True)


def handle_jsonl_request(line: str) -> None:
    request_id = 1
    try:
        payload = json.loads(line)
        if not isinstance(payload, dict):
            raise ValueError("request must be a JSON object")
        method = str(payload.get("method") or "").strip()
        if not method:
            raise ValueError("daemon action method is required")
        params = payload.get("params") or {}
        if not isinstance(params, dict):
            raise ValueError("daemon action params must be a JSON object")
        request_id = payload.get("id") or 1
        emit(rpc_call(method, params, request_id=request_id))
    except Exception as exc:
        emit({
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32000, "message": str(exc)},
        })


if len(sys.argv) >= 2 and sys.argv[1] == "--jsonl":
    # More than one worker so a slow call cannot head-of-line block the rest.
    # Every request opens its own socket and stdout writes are serialized under
    # emit_lock, so concurrent workers are safe. This matters because slow and
    # fast methods share the lane: a herdr focus that hands off over SSH, or a
    # window.focus that retries with tree verification, would otherwise stall
    # each following workspace-pill click until the 5s socket timeout fired.
    try:
        worker_count = int(os.environ.get("QUICKSHELL_DAEMON_ACTION_WORKERS") or "4")
    except ValueError:
        worker_count = 4
    with ThreadPoolExecutor(max_workers=max(1, worker_count)) as executor:
        for line in sys.stdin:
            executor.submit(handle_jsonl_request, line)
    raise SystemExit(0)


if len(sys.argv) < 2:
    fail("usage: quickshell-daemon-action <method> [params-json] | --jsonl")

method = sys.argv[1].strip()
if not method:
    fail("daemon action method is required")

try:
    response = rpc_call(method, parse_params(sys.argv[2] if len(sys.argv) > 2 else "{}"))
except Exception as exc:
    fail(f"daemon action failed: {exc}")

error = response.get("error")
if error:
    if isinstance(error, dict):
        fail(str(error.get("message") or error))
    fail(str(error))
  '';

  daemonActionScript = pkgs.writeShellScriptBin "quickshell-daemon-action" ''
    set -euo pipefail

    exec ${lib.getExe pkgs.python3} ${daemonActionPython} "$@"
  '';

  launcherQueryScript = pkgs.writeShellScriptBin "quickshell-app-launcher-query" ''
    set -euo pipefail

    query="''${1:-}"
    limit="''${2:-12}"
    min_score="''${3:-20}"
    app_filter="''${4:-all}"

    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
      limit=12
    fi

    if ! [[ "$min_score" =~ ^[0-9]+$ ]]; then
      min_score=20
    fi

    export QUICKSHELL_LAUNCHER_QUERY="$query"
    export QUICKSHELL_LAUNCHER_LIMIT="$limit"
    export QUICKSHELL_LAUNCHER_MIN_SCORE="$min_score"
    export QUICKSHELL_LAUNCHER_APP_FILTER="$app_filter"

    # Use the declarative application registry as the source of truth for app mode.
    # Elephant's desktopapplications provider intermittently returns an empty set for
    # generated PWA desktop entries, which makes PWAs disappear until the launcher is reopened.
    exec ${lib.getExe pkgs.python3} - <<'PY'
import json
import os
import re
import sys
from pathlib import Path

query = os.environ.get("QUICKSHELL_LAUNCHER_QUERY", "").strip()
limit = int(os.environ.get("QUICKSHELL_LAUNCHER_LIMIT", "12") or "12")
min_score = int(os.environ.get("QUICKSHELL_LAUNCHER_MIN_SCORE", "20") or "20")
app_filter = str(os.environ.get("QUICKSHELL_LAUNCHER_APP_FILTER", "all") or "all").strip().lower()

registry_path = Path.home() / ".config" / "i3" / "application-registry.json"
base_registry_path = Path.home() / ".local" / "share" / "i3pm" / "registry" / "base.json"


def normalize(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", " ", str(value or "").lower()).strip()


def compact(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value or "").lower())


def safe_int(value: object) -> int | None:
    try:
        if value is None:
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def entry_subtext(app: dict) -> str:
    parts: list[str] = []
    description = str(app.get("description") or "").strip()
    workspace = safe_int(app.get("preferred_workspace"))
    scope = str(app.get("scope") or "").strip()

    if description:
        parts.append(description)
    if workspace is not None:
        parts.append(f"WS{workspace}")
    if scope:
        parts.append(scope)

    return " • ".join(parts)


def extract_query_filters(raw_query: str) -> tuple[str, dict]:
    filters = {
        "scope": None,
        "workspace": None,
        "monitor": None,
        "pwa": False,
    }
    remaining: list[str] = []

    for token in raw_query.split():
        lower = token.strip().lower()
        if lower in ("@scoped", "scope:scoped"):
            filters["scope"] = "scoped"
            continue
        if lower in ("@global", "scope:global"):
            filters["scope"] = "global"
            continue
        if lower in ("@pwa", "pwa", "type:pwa"):
            filters["pwa"] = True
            continue
        if lower.startswith("ws:"):
            suffix = lower[3:]
            if suffix.isdigit():
                filters["workspace"] = int(suffix)
                continue
        if lower.startswith("monitor:"):
            suffix = lower.split(":", 1)[1]
            if suffix in ("primary", "secondary", "tertiary"):
                filters["monitor"] = suffix
                continue

        remaining.append(token)

    return " ".join(remaining).strip(), filters


def matches_filters(app: dict, query_filters: dict) -> bool:
    name = str(app.get("name") or "").strip()
    scope = str(app.get("scope") or "").strip().lower()
    workspace = safe_int(app.get("preferred_workspace"))
    monitor_role = str(app.get("preferred_monitor_role") or "").strip().lower()
    is_pwa = name.endswith("-pwa")

    if app_filter == "scoped" and scope != "scoped":
        return False
    if app_filter == "global" and scope != "global":
        return False
    if app_filter == "pwa" and not is_pwa:
        return False
    if app_filter == "workspace" and workspace is None:
        return False

    if query_filters["scope"] and scope != query_filters["scope"]:
        return False
    if query_filters["workspace"] is not None and workspace != query_filters["workspace"]:
        return False
    if query_filters["monitor"] and monitor_role != query_filters["monitor"]:
        return False
    if query_filters["pwa"] and not is_pwa:
        return False

    return True


def app_badges(app: dict) -> list[dict]:
    badges: list[dict] = []
    name = str(app.get("name") or "").strip()
    scope = str(app.get("scope") or "").strip().lower()
    workspace = safe_int(app.get("preferred_workspace"))

    if name.endswith("-pwa"):
        badges.append({"label": "PWA", "tone": "teal"})
    if scope == "scoped":
        badges.append({"label": "Scoped", "tone": "orange"})
    elif scope == "global":
        badges.append({"label": "Global", "tone": "blue"})
    if workspace is not None:
        badges.append({"label": f"WS{workspace}", "tone": "violet"})

    return badges


def score_app(app: dict, index: int, query_norm: str, query_compact: str, query_tokens: list[str]) -> int:
    if not query_norm:
        return 1000 - min(index, 999)

    name = str(app.get("name") or "")
    display_name = str(app.get("display_name") or name)
    description = str(app.get("description") or "")
    domain = str(app.get("pwa_domain") or "")
    aliases = app.get("aliases") or []
    if not isinstance(aliases, list):
        aliases = []
    match_domains = app.get("pwa_match_domains") or []
    if not isinstance(match_domains, list):
        match_domains = []

    name_without_suffix = name[:-4] if name.endswith("-pwa") else name
    fields = [
        normalize(display_name),
        normalize(name),
        normalize(name_without_suffix),
        normalize(description),
        normalize(domain),
    ] + [normalize(item) for item in aliases] + [normalize(item) for item in match_domains]
    compact_fields = [compact(value) for value in fields if value]

    exact_values = {value for value in fields if value}
    prefix_values = [value for value in fields if value]

    score = 0

    if query_norm in exact_values:
        score = max(score, 320)

    if any(value.startswith(query_norm) for value in prefix_values):
        score = max(score, 260)

    if query_compact and any(query_compact in value for value in compact_fields):
        score = max(score, 200)

    if any(query_norm in value for value in prefix_values):
        score = max(score, 140)

    token_hits = 0
    exact_token_hits = 0
    for token in query_tokens:
        matched = False
        for value in prefix_values:
            words = value.split()
            if token in words:
                exact_token_hits += 1
                token_hits += 1
                matched = True
                break
            if token in value:
                token_hits += 1
                matched = True
                break
        if not matched:
            return 0

    score += exact_token_hits * 24
    score += (token_hits - exact_token_hits) * 12

    if len(query_tokens) > 1 and token_hits == len(query_tokens):
        score += 36

    return score


try:
    data = json.loads(registry_path.read_text())
except (OSError, json.JSONDecodeError):
    try:
        data = json.loads(base_registry_path.read_text())
    except (OSError, json.JSONDecodeError):
        json.dump([], sys.stdout)
        sys.stdout.write("\n")
        raise SystemExit(0)

applications = data.get("applications") or []
if not isinstance(applications, list):
    json.dump([], sys.stdout)
    sys.stdout.write("\n")
    raise SystemExit(0)

query, query_filters = extract_query_filters(query)
query_norm = normalize(query)
query_compact = compact(query)
query_tokens = [token for token in query_norm.split() if token]

scored_results: list[tuple[int, int, dict]] = []
for index, raw_app in enumerate(applications):
    if not isinstance(raw_app, dict):
        continue

    if not matches_filters(raw_app, query_filters):
        continue

    score = score_app(raw_app, index, query_norm, query_compact, query_tokens)
    if score < min_score:
        continue

    name = str(raw_app.get("name") or "").strip()
    display_name = str(raw_app.get("display_name") or name).strip()
    if not name or not display_name:
        continue

    workspace = safe_int(raw_app.get("preferred_workspace"))
    monitor_role = str(raw_app.get("preferred_monitor_role") or "").strip()
    aliases = raw_app.get("aliases") or []
    if not isinstance(aliases, list):
        aliases = []
    state = []
    if name.endswith("-pwa"):
        state.append("pwa")
    scope = str(raw_app.get("scope") or "").strip().lower()
    if scope:
        state.append(scope)
    if workspace is not None:
        state.append("workspace-pinned")

    identifier = name
    scored_results.append(
        (
            score,
            index,
            {
                "kind": "app",
                "identifier": identifier,
                "text": display_name,
                "subtext": entry_subtext(raw_app),
                "icon": str(raw_app.get("icon") or ""),
                "score": score,
                "state": state,
                "scope": raw_app.get("scope"),
                "preferred_workspace": workspace,
                "preferred_monitor_role": monitor_role or None,
                "aliases": [str(alias).strip() for alias in aliases if str(alias).strip()],
                "badges": app_badges(raw_app),
                "actions": [],
            },
        )
    )

scored_results.sort(key=lambda item: (-item[0], item[1], item[2]["text"].lower()))

result = [entry for _, _, entry in scored_results[:limit]]
json.dump(result, sys.stdout)
sys.stdout.write("\n")
PY
  '';

  launcherLaunchScript = pkgs.writeShellScriptBin "quickshell-elephant-launcher-launch" ''
    set -euo pipefail

    identifier="''${1:-}"
    if [ -z "$identifier" ]; then
      echo "missing desktop entry identifier" >&2
      exit 1
    fi

    # The i3pm/PWA desktop files are installed to
    # ~/.local/share/i3pm-applications/applications/ (intentionally off the
    # standard XDG path so Walker/Elephant do not list duplicates). gtk-launch
    # only searches <dir>/applications for each entry in XDG_DATA_DIRS, and the
    # QuickShell service environment does NOT include these dirs — so registry
    # and PWA launches fail with "no such application" while system apps (whose
    # .desktop lives in the profile/system share dirs) still work. Prepend the
    # i3pm dirs here so gtk-launch can resolve every launcher entry.
    export XDG_DATA_DIRS="$HOME/.local/share/i3pm-applications:$HOME/.local/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

    # gtk-launch searches XDG_DATA_DIRS for <name>.desktop
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

    # Runner commands are host-global: there is no daemon-owned active worktree
    # to inherit a directory from, so $HOME is the honest working directory.
    context_dir="$HOME"

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

  appRegistryListScript = pkgs.writeShellScriptBin "quickshell-app-registry-list" ''
    set -euo pipefail

    query="''${1:-}"
    limit="''${2:-200}"

    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
      limit=200
    fi

    export QUICKSHELL_APP_REGISTRY_QUERY="$query"
    export QUICKSHELL_APP_REGISTRY_LIMIT="$limit"

    exec ${lib.getExe pkgs.python3} - <<'PY'
import json
import os
from pathlib import Path

query = str(os.environ.get("QUICKSHELL_APP_REGISTRY_QUERY", "") or "").strip().lower()
tokens = [token for token in query.split() if token]
limit = int(os.environ.get("QUICKSHELL_APP_REGISTRY_LIMIT", "200") or "200")
effective_path = Path.home() / ".config" / "i3" / "application-registry.json"
base_path = Path.home() / ".local" / "share" / "i3pm" / "registry" / "base.json"
working_copy_path = Path.home() / ".config" / "i3" / "app-registry-working-copy.json"


def load_json(path: Path, default):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return default


def badge_list(name: str, scope: str, workspace, dirty: bool) -> list[dict]:
    badges: list[dict] = []
    if name.endswith("-pwa"):
        badges.append({"label": "PWA", "tone": "teal"})
    if scope == "scoped":
        badges.append({"label": "Scoped", "tone": "orange"})
    elif scope == "global":
        badges.append({"label": "Global", "tone": "blue"})
    if workspace is not None:
        badges.append({"label": f"WS{workspace}", "tone": "violet"})
    if dirty:
        badges.append({"label": "Live", "tone": "accent"})
    return badges


registry = load_json(effective_path, None)
if not isinstance(registry, dict):
    registry = load_json(base_path, {})
working_copy = load_json(working_copy_path, {"applications": {}})
working_apps = working_copy.get("applications", {}) if isinstance(working_copy, dict) else {}
if not isinstance(working_apps, dict):
    working_apps = {}

applications = registry.get("applications", []) if isinstance(registry, dict) else []
entries = []
for app in applications:
    if not isinstance(app, dict):
        continue

    name = str(app.get("name", "") or "").strip()
    display_name = str(app.get("display_name", "") or name).strip()
    description = str(app.get("description", "") or "").strip()
    aliases = app.get("aliases") or []
    if not isinstance(aliases, list):
        aliases = []
    alias_values = [str(value).strip() for value in aliases if str(value).strip()]

    haystack = " ".join([
        name,
        display_name,
        description,
        " ".join(alias_values),
        str(app.get("scope", "") or ""),
        str(app.get("preferred_monitor_role", "") or ""),
        str(app.get("icon", "") or ""),
    ]).lower()
    if tokens and not all(token in haystack for token in tokens):
        continue

    workspace = app.get("preferred_workspace")
    scope = str(app.get("scope", "") or "").strip().lower()
    is_dirty = name in working_apps
    workspace_label = f"WS{workspace}" if workspace is not None else "dynamic"
    subtext_parts = [workspace_label, str(app.get("scope", "") or "")]
    if description:
        subtext_parts.insert(0, description)

    entries.append({
        "kind": "app-registry",
        "identifier": name,
        "name": name,
        "text": display_name,
        "display_name": display_name,
        "description": description,
        "subtext": "  •  ".join([part for part in subtext_parts if part]),
        "icon": str(app.get("icon", "") or ""),
        "scope": str(app.get("scope", "") or ""),
        "command": str(app.get("command", "") or ""),
        "expected_class": str(app.get("expected_class", "") or ""),
        "preferred_workspace": workspace,
        "preferred_monitor_role": app.get("preferred_monitor_role"),
        "floating": bool(app.get("floating", False)),
        "floating_size": app.get("floating_size"),
        "multi_instance": bool(app.get("multi_instance", False)),
        "fallback_behavior": str(app.get("fallback_behavior", "") or ""),
        "aliases": alias_values,
        "dirty": is_dirty,
        "is_pwa": name.endswith("-pwa"),
        "state": ([scope] if scope else []) + (["workspace"] if workspace is not None else []) + (["pwa"] if name.endswith("-pwa") else []) + (["dirty"] if is_dirty else []),
        "badges": badge_list(name, scope, workspace, is_dirty),
    })

entries.sort(key=lambda item: (str(item.get("text", "")).lower(), str(item.get("name", "")).lower()))
print(json.dumps(entries[:limit]))
PY
  '';

  appRegistryManageScript = pkgs.writeShellScriptBin "quickshell-app-registry-manage" ''
    set -euo pipefail

    action="''${1:-}"
    shift || true

    case "$action" in
      upsert)
        export QS_APP_NAME="''${1:-}"
        export QS_APP_DISPLAY_NAME="''${2:-}"
        export QS_APP_DESCRIPTION="''${3:-}"
        export QS_APP_WORKSPACE="''${4:-}"
        export QS_APP_MONITOR_ROLE="''${5:-}"
        export QS_APP_FLOATING="''${6:-}"
        export QS_APP_FLOATING_SIZE="''${7:-}"
        export QS_APP_MULTI_INSTANCE="''${8:-}"
        export QS_APP_FALLBACK="''${9:-}"
        export QS_APP_ICON="''${10:-}"
        export QS_APP_ALIASES="''${11:-[]}"
        ;;
      remove|apply|reset|diff)
        export QS_APP_NAME="''${1:-}"
        ;;
      *)
        echo "unsupported app-registry action: $action" >&2
        exit 1
        ;;
    esac

    export QS_APP_ACTION="$action"
    export QS_APP_REGISTRY_SYNC_BIN="${appRegistrySyncTool}/bin/i3pm-app-registry-sync"

    exec ${lib.getExe pkgs.python3} - <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

WORKING_COPY_PATH = Path.home() / ".config" / "i3" / "app-registry-working-copy.json"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def load_data() -> dict:
    if not WORKING_COPY_PATH.exists():
        return {"version": "1.0.0", "applications": {}}
    try:
        with WORKING_COPY_PATH.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception as exc:
        fail(f"unable to parse working copy: {exc}")
    if not isinstance(data, dict):
        return {"version": "1.0.0", "applications": {}}
    if not isinstance(data.get("applications"), dict):
        data["applications"] = {}
    if "version" not in data:
        data["version"] = "1.0.0"
    return data


def write_data(data: dict) -> None:
    WORKING_COPY_PATH.parent.mkdir(parents=True, exist_ok=True)
    with WORKING_COPY_PATH.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def render_live() -> None:
    try:
        subprocess.run([os.environ["QS_APP_REGISTRY_SYNC_BIN"], "render-live"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as exc:
        fail(f"unable to refresh live registry: {exc}")


def commit_working_copy(previous_data: dict, next_data: dict) -> None:
    write_data(next_data)
    try:
        render_live()
    except SystemExit:
        write_data(previous_data)
        try:
            render_live()
        except SystemExit:
            pass
        raise


def as_bool(raw: str) -> bool | None:
    value = str(raw or "").strip().lower()
    if value in ("", "null"):
        return None
    if value in ("1", "true", "yes", "on"):
        return True
    if value in ("0", "false", "no", "off"):
        return False
    fail(f"invalid boolean value: {raw}")


def as_optional_int(raw: str) -> int | None:
    value = str(raw or "").strip().lower()
    if value in ("", "null"):
        return None
    try:
        return int(value)
    except ValueError:
        fail(f"invalid workspace value: {raw}")


def as_optional_string(raw: str) -> str | None:
    value = str(raw or "").strip()
    return value or None


action = os.environ.get("QS_APP_ACTION", "").strip()
if action == "apply":
    result = subprocess.run([os.environ["QS_APP_REGISTRY_SYNC_BIN"], "apply"], check=True, capture_output=True, text=True)
    print(result.stdout.strip() or "{}")
    raise SystemExit(0)

if action == "reset":
    result = subprocess.run([os.environ["QS_APP_REGISTRY_SYNC_BIN"], "reset-working-copy"], check=True, capture_output=True, text=True)
    print(result.stdout.strip() or "{}")
    raise SystemExit(0)

if action == "diff":
    result = subprocess.run([os.environ["QS_APP_REGISTRY_SYNC_BIN"], "diff"], check=True, capture_output=True, text=True)
    print(result.stdout.strip() or "[]")
    raise SystemExit(0)

data = load_data()
previous_data = json.loads(json.dumps(data))
applications = data["applications"]
name = str(os.environ.get("QS_APP_NAME", "") or "").strip()
if not name:
    fail("application name is required")

if action == "remove":
    applications.pop(name, None)
    commit_working_copy(previous_data, data)
    print(json.dumps({"ok": True, "action": action, "name": name, "message": f"Cleared live override for '{name}'"}))
    raise SystemExit(0)

if action != "upsert":
    fail(f"unsupported app-registry action: {action}")

aliases_raw = str(os.environ.get("QS_APP_ALIASES", "[]") or "[]")
try:
    aliases = json.loads(aliases_raw)
except Exception as exc:
    fail(f"invalid aliases payload: {exc}")
if not isinstance(aliases, list):
    fail("aliases payload must be a JSON array")
aliases = [str(item).strip() for item in aliases if str(item).strip()]

override = {}

display_name = as_optional_string(os.environ.get("QS_APP_DISPLAY_NAME", ""))
if display_name is not None:
    override["display_name"] = display_name

description = as_optional_string(os.environ.get("QS_APP_DESCRIPTION", ""))
if description is not None:
    override["description"] = description

workspace = as_optional_int(os.environ.get("QS_APP_WORKSPACE", ""))
if workspace is not None:
    override["preferred_workspace"] = workspace

monitor_role = as_optional_string(os.environ.get("QS_APP_MONITOR_ROLE", ""))
if monitor_role is not None:
    override["preferred_monitor_role"] = monitor_role

floating = as_bool(os.environ.get("QS_APP_FLOATING", ""))
if floating is not None:
    override["floating"] = floating

floating_size = as_optional_string(os.environ.get("QS_APP_FLOATING_SIZE", ""))
if floating_size is not None:
    override["floating_size"] = floating_size

multi_instance = as_bool(os.environ.get("QS_APP_MULTI_INSTANCE", ""))
if multi_instance is not None:
    override["multi_instance"] = multi_instance

fallback = as_optional_string(os.environ.get("QS_APP_FALLBACK", ""))
if fallback is not None:
    override["fallback_behavior"] = fallback

icon = as_optional_string(os.environ.get("QS_APP_ICON", ""))
if icon is not None:
    override["icon"] = icon

if aliases:
    override["aliases"] = aliases

if override:
    applications[name] = override
else:
    applications.pop(name, None)

commit_working_copy(previous_data, data)
print(json.dumps({"ok": True, "action": action, "name": name, "message": f"Saved live override for '{name}'"}))
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

    # Launcher commands are host-global: there is no daemon-owned active
    # worktree to inherit a directory from, so $HOME is the honest working
    # directory. (This also retired the scratchpad hand-off, which could only
    # ever fire for a context key the daemon no longer produces.)
    context_dir="$HOME"

    run_in_context() {
      cd "$context_dir"
      export PATH="${pkgs.libnotify}/bin:$PATH"
      exec ${pkgs.bash}/bin/bash -lc "$command"
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
    history_file=${lib.escapeShellArg clipboardHistoryFile}

    if ! [[ "$min_score" =~ ^[0-9]+$ ]]; then
      min_score=30
    fi

    local_json="$(
      if [[ -f "$history_file" ]]; then
        ${lib.getExe pkgs.jq} -c --arg query "$query" '
          def matches($query; $text):
            ($query | length) == 0
            or (($text // "") | ascii_downcase | contains($query | ascii_downcase));

          (if type == "array" then . else [] end)
          | map(select((.id? // "") | startswith("i3pm:")))
          | map(select(matches($query; .text // "")))
          | map({
              kind: "clipboard",
              identifier: .id,
              text: (.text // ""),
              subtext: (.timestamp // ""),
              preview: (.text // ""),
              preview_type: "text",
              icon: "edit-paste",
              state: [],
              actions: ["copy", "remove"],
              provider: "i3pm-clipboard"
            })
          | .[:30]
        ' "$history_file" 2>/dev/null || printf '[]\n'
      else
        printf '[]\n'
      fi
    )"

    elephant_json="$(
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
        ' 2>/dev/null || printf '[]\n'
    )"

    # Merge via stdin, NOT --argjson: a single argv element is capped at
    # MAX_ARG_STRLEN (128 KiB), so passing the clipboard JSON as an argument
    # fails with "Argument list too long" the moment a large entry is copied.
    # Piping both arrays and slurping (-s) has no size limit; `add` concatenates
    # them in the same order as the previous `$local + $elephant`.
    printf '%s\n%s\n' "$local_json" "$elephant_json" | ${lib.getExe pkgs.jq} -cs '
      add
      | reduce .[] as $item (
          {items: [], seen: {}};
          ($item.text // "") as $text
          | if $text == "" or .seen[$text] then .
            else .seen[$text] = true | .items += [$item]
            end
        )
      | .items[:30]
    '
  '';

  clipboardActionScript = pkgs.writeShellScriptBin "quickshell-clipboard-action" ''
    set -euo pipefail

    action="''${1:-copy}"
    identifier="''${2:-}"
    history_file=${lib.escapeShellArg clipboardHistoryFile}

    case "$action" in
      copy|remove|delete) ;;
      *)
        echo "unsupported clipboard action: $action" >&2
        exit 1
        ;;
    esac

    if [[ -z "$identifier" ]]; then
      echo "missing clipboard identifier" >&2
      exit 1
    fi

    if [[ "$identifier" == i3pm:* ]]; then
      case "$action" in
        copy)
          ${lib.getExe pkgs.jq} -r --arg identifier "$identifier" '
            (if type == "array" then . else [] end)
            | map(select(.id == $identifier))
            | .[0].text // empty
          ' "$history_file" 2>/dev/null | ${pkgs.wl-clipboard}/bin/wl-copy --type text/plain
          ;;
        remove|delete)
          if [[ -f "$history_file" ]]; then
            tmp="$(${pkgs.coreutils}/bin/mktemp -p "$(${pkgs.coreutils}/bin/dirname "$history_file")" .clipboard-history.XXXXXX)"
            ${lib.getExe pkgs.jq} --arg identifier "$identifier" '
              (if type == "array" then . else [] end)
              | map(select(.id != $identifier))
            ' "$history_file" >"$tmp"
            ${pkgs.coreutils}/bin/chmod 600 "$tmp"
            ${pkgs.coreutils}/bin/mv "$tmp" "$history_file"
          fi
          ;;
      esac
      exit 0
    fi

    if [[ "$action" == "delete" ]]; then
      action="remove"
    fi

    exec elephant activate "clipboard;''${identifier};''${action};;"
  '';

  runtimeShellIpcScript = pkgs.writeShellScriptBin "quickshell-runtime-shell-ipc" ''
    set -euo pipefail

    main_pid="$(${pkgs.systemd}/bin/systemctl --user show quickshell-runtime-shell.service -p MainPID --value 2>/dev/null || true)"
    if [ -z "$main_pid" ] || [ "$main_pid" = "0" ]; then
      echo "quickshell-runtime-shell.service is not running" >&2
      exit 1
    fi

    exec ${quickshellBin} ipc --pid "$main_pid" "$@"
  '';

  mkIpcScript = name: functionName: extraBody:
    pkgs.writeShellScriptBin name ''
      set -euo pipefail
      ${extraBody}
      exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell ${functionName} "$@"
    '';

  togglePanelScript = pkgs.writeShellScriptBin "toggle-runtime-panel" ''
    set -euo pipefail
    exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell togglePanel
  '';

  toggleDockScript = pkgs.writeShellScriptBin "toggle-panel-dock-mode" ''
    set -euo pipefail
    exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell toggleDockMode
  '';

  # Generic surface CLI, the shell-side twin of Omarchy's
  # `omarchy-shell shell summon|hide|toggle <id> <json>`. Every surface the
  # shell owns is addressable by id, so a keybinding, a herdr hook, or a script
  # can open exactly the thing it wants without a wrapper script per function.
  runtimeShellCliScript = pkgs.writeShellScriptBin "runtime-shell" ''
    set -euo pipefail
    ipc=${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc

    usage() {
      cat >&2 <<'USAGE'
Usage: runtime-shell <command> [args]
  summon <surface> [payload-json]   open a surface
  hide <surface>                    close a surface
  toggle <surface> [payload-json]   open if closed, close if open
  list                              every surface and whether it is open
  call <function> [args...]         call any function on the shell IPC target
  ping                              exit 0 when the shell answers

Surfaces: launcher, keybindings, panel, settings, expose, agent-monitor,
  power-menu, notifications, display-selector, audio, bluetooth, cast
Payloads: launcher {"mode":"files","query":"nix"}  panel {"section":"sessions"}
  settings {"section":"devices"}
USAGE
    }

    cmd="''${1:-}"
    if [ $# -gt 0 ]; then shift; fi
    case "$cmd" in
      summon|toggle)
        [ $# -ge 1 ] || { usage; exit 2; }
        payload="''${2:-}"
        [ -n "$payload" ] || payload='{}'
        exec "$ipc" call shell "$cmd" "$1" "$payload"
        ;;
      hide)
        [ $# -ge 1 ] || { usage; exit 2; }
        exec "$ipc" call shell hide "$1"
        ;;
      list) exec "$ipc" call shell listSurfaces ;;
      call)
        [ $# -ge 1 ] || { usage; exit 2; }
        exec "$ipc" call shell "$@"
        ;;
      ping) exec "$ipc" call shell ping ;;
      *) usage; exit 2 ;;
    esac
  '';

  # Brightness keys: brightnessctl stays authoritative (works with the shell
  # down), then the new level is handed to the OSD. The 2s brightness poll is
  # too slow to drive key feedback on its own.
  brightnessKeyScript = pkgs.writeShellScriptBin "quickshell-brightness-key" ''
    set -euo pipefail
    target="''${1:-display}"
    direction="''${2:-up}"
    case "$target" in
      display) dev=() ;;
      keyboard) dev=(-d '*kbd_backlight*' -n 5) ;;
      *) echo "usage: quickshell-brightness-key display|keyboard up|down" >&2; exit 2 ;;
    esac
    case "$direction" in
      up) delta="+5%" ;; down) delta="5%-" ;;
      *) echo "usage: quickshell-brightness-key display|keyboard up|down" >&2; exit 2 ;;
    esac
    if [ "$target" = keyboard ]; then delta="''${delta/5/10}"; fi
    out="$(${lib.getExe pkgs.brightnessctl} "''${dev[@]}" -m set "$delta")"
    if [ "$target" = display ]; then
      percent="$(printf '%s\n' "$out" | ${pkgs.coreutils}/bin/cut -d, -f4 | ${pkgs.coreutils}/bin/tr -d '%')"
      ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell showOsd brightness "$percent" >/dev/null 2>&1 || true
    fi
  '';

  # ---- Agent usage (Claude Code / Codex subscriptions) ------------------
  # Collectors are Omarchy's (MIT, vendored under ./agent-usage with only the
  # cache path changed). Each prints one display-ready JSON record; the update
  # script writes them atomically to the usage dir, which the shell watches.
  # Adding an agent is adding a collector: the panel renders whatever appears.
  agentUsageDir = "${config.xdg.stateHome}/quickshell-runtime-shell/agents/usage";
  agentUsageAgents = [ "claude" "codex" ];
  agentUsageCollector = name: pkgs.writeShellScriptBin "quickshell-agent-usage-${name}" ''
    exec ${lib.getExe pkgs.python3} ${./agent-usage + "/${name}.py"} "$@"
  '';
  agentUsageCollectors = map agentUsageCollector agentUsageAgents;
  agentUsageUpdateScript = pkgs.writeShellScriptBin "quickshell-agent-usage-update" ''
    set -uo pipefail
    usage_dir="${agentUsageDir}"
    mkdir -p "$usage_dir"
    pids=()
    collect() {
      local agent="$1"; shift
      local record tmp
      if ! record="$("${"$"}{collector}" "$@")" || [ -z "$record" ]; then
        echo "quickshell-agent-usage-update: $agent collector failed" >&2
        return 1
      fi
      if ! printf '%s' "$record" | ${pkgs.jq}/bin/jq -e . >/dev/null 2>&1; then
        echo "quickshell-agent-usage-update: $agent collector printed no JSON" >&2
        return 1
      fi
      tmp="$(mktemp "$usage_dir/.$agent.XXXXXX")"
      printf '%s\n' "$record" >"$tmp"
      mv "$tmp" "$usage_dir/$agent.json"
    }
    ${lib.concatMapStringsSep "\n" (name: ''
      collector=${agentUsageCollector name}/bin/quickshell-agent-usage-${name}
      collect ${name} "$@" & pids+=($!)
    '') agentUsageAgents}
    status=0
    for pid in "''${pids[@]}"; do wait "$pid" || status=1; done
    exit $status
  '';

  # Theme switcher. Writes the state file the shell watches (live restyle)
  # and Ghostty's palette include; new terminals pick it up, running ones on
  # Ctrl+Shift+, (reload_config) — Ghostty has no reload signal.
  runtimeThemeScript = pkgs.writeShellScriptBin "runtime-theme" ''
    set -euo pipefail
    themes=${themesJson}
    state=${themeStatePath}
    ghostty_theme="''${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/theme.conf"
    jq=${pkgs.jq}/bin/jq

    usage() {
      cat >&2 <<'USAGE'
Usage: runtime-theme <command>
  list             themes and which one is active
  current          the active theme id
  set <theme>      switch the shell (live) and the terminal palette (new terminals)
  toggle           switch between the dark and light theme
USAGE
    }

    current() {
      if [ -r "$state" ] && name="$("$jq" -r '.name // empty' "$state" 2>/dev/null)" && [ -n "$name" ] \
         && "$jq" -e --arg n "$name" 'has($n)' "$themes" >/dev/null; then
        printf '%s\n' "$name"
      else
        printf '%s\n' "${themeName}"
      fi
    }

    set_theme() {
      local name="$1"
      if ! "$jq" -e --arg n "$name" 'has($n)' "$themes" >/dev/null; then
        echo "runtime-theme: unknown theme '$name' (see: runtime-theme list)" >&2
        exit 2
      fi
      mkdir -p "$(dirname "$state")" "$(dirname "$ghostty_theme")"
      tmp="$(mktemp "$(dirname "$state")/.theme.XXXXXX")"
      "$jq" -n --arg n "$name" --arg at "$(date -Is)" '{name: $n, set_at: $at}' >"$tmp"
      mv "$tmp" "$state"
      {
        echo "# Managed by runtime-theme ($name). Included by ~/.config/ghostty/config."
        "$jq" -r --arg n "$name" '.[$n].terminal
          | "background = \(.background)", "foreground = \(.foreground)",
            "cursor-color = \(.cursor)",
            "selection-background = \(.selectionBackground)", "selection-foreground = \(.selectionForeground)",
            (.palette | to_entries[] | "palette = \(.key)=#\(.value)")' "$themes"
      } >"$ghostty_theme.tmp" && mv "$ghostty_theme.tmp" "$ghostty_theme"
      label="$("$jq" -r --arg n "$name" '.[$n].label' "$themes")"
      echo "theme: $label ($name)"
      ${pkgs.libnotify}/bin/notify-send -a runtime-theme -t 4000 "Theme: $label" "Shell restyled. New terminals use the matching palette; press Ctrl+Shift+, in an open Ghostty to reload." >/dev/null 2>&1 || true
    }

    cmd="''${1:-}"
    case "$cmd" in
      list)
        active="$(current)"
        "$jq" -r --arg a "$active" 'to_entries[] | "\(if .key == $a then "*" else " " end) \(.key)\t\(.value.label)\t\(.value.description)"' "$themes" | column -t -s $'\t'
        ;;
      current) current ;;
      set) [ $# -ge 2 ] || { usage; exit 2; }; set_theme "$2" ;;
      toggle)
        active="$(current)"
        if "$jq" -e --arg a "$active" '.[$a].dark' "$themes" >/dev/null; then want=false; else want=true; fi
        next="$("$jq" -r --argjson d "$want" 'to_entries[] | select(.value.dark == $d) | .key' "$themes" | head -1)"
        [ -n "$next" ] || { echo "runtime-theme: no theme to toggle to" >&2; exit 1; }
        set_theme "$next"
        ;;
      *) usage; exit 2 ;;
    esac
  '';

  # Lock through the shell when it is up (themed ext-session-lock + PAM),
  # swaylock otherwise — a lock request must never be dropped.
  lockSessionScript = pkgs.writeShellScriptBin "lock-session" ''
    if out="$(${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell lock 2>/dev/null)" && [ "$out" = "ok" ]; then
      exit 0
    fi
    exec ${pkgs.swaylock}/bin/swaylock -f
  '';

  togglePowerMenuScript = mkIpcScript "toggle-runtime-power-menu" "togglePowerMenu" "";
  toggleKeybindingsHelpScript = mkIpcScript "toggle-keybindings-help" "toggleKeybindings" "";
  toggleLauncherScript = mkIpcScript "toggle-app-launcher" "toggleLauncher" "";
  toggleAgentMonitorScript = mkIpcScript "toggle-agent-monitor" "toggleAgentMonitor" "";
  toggleSettingsScript = mkIpcScript "toggle-runtime-settings" "toggleSettings" "";
  showRuntimeDevicesScript = pkgs.writeShellScriptBin "show-runtime-devices" ''
    set -euo pipefail
    exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell showSettings devices
  '';
  showRuntimeDisplaysScript = pkgs.writeShellScriptBin "show-runtime-displays" ''
    set -euo pipefail
    exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell showSettings devices
  '';
  toggleNotificationsScript = mkIpcScript "toggle-runtime-notifications" "toggleNotifications" "";
  toggleNotificationDndScript = mkIpcScript "toggle-runtime-notification-dnd" "toggleNotificationDnd" "";
  clearNotificationsScript = mkIpcScript "clear-runtime-notifications" "clearNotifications" "";

  monitorPanelTabScript = pkgs.writeShellScriptBin "monitor-panel-tab" ''
    set -euo pipefail
    case "''${1:-0}" in
      0) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell showWindowsTab ;;
      1) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell showSessionsTab ;;
      *) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell showHealthTab ;;
    esac
  '';

  cycleSessionsScript = pkgs.writeShellScriptBin "cycle-active-ai-session-action" ''
    set -euo pipefail
    case "''${1:-next}" in
      prev) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell prevSession ;;
      *) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell nextSession ;;
    esac
  '';

  showAiSwitcherScript = pkgs.writeShellScriptBin "show-ai-mru-switcher-action" ''
    set -euo pipefail
    case "''${1:-next}" in
      prev) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell prevLauncherSession ;;
      *) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell nextLauncherSession ;;
    esac
  '';

  showWindowSwitcherScript = pkgs.writeShellScriptBin "show-window-switcher-action" ''
    set -euo pipefail
    case "''${1:-next}" in
      prev) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell prevLauncherWindow ;;
      open) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell openWindowSwitcher ;;
      toggle) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell toggleWindowSwitcher ;;
      *) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell nextLauncherWindow ;;
    esac
  '';

  # Alt+Tab: MRU ring of running apps (launcher mode "running").
  showAppSwitcherScript = pkgs.writeShellScriptBin "show-app-switcher-action" ''
    set -euo pipefail
    case "''${1:-next}" in
      prev) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell prevLauncherRunning ;;
      *) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell nextLauncherRunning ;;
    esac
  '';

  # Bound to sway `--release Alt_L`: commits an open Alt-held window switcher
  # (running-app ring or exposé). The compositor sees the modifier release
  # even when the overlay has not grabbed the keyboard yet, which is what made
  # a quick tap leave the switcher open waiting for Enter.
  commitWindowSwitcherScript = pkgs.writeShellScriptBin "commit-window-switch-action" ''
    set -euo pipefail
    exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell commitWindowSwitch
  '';

  # Mod+grave: cycle the focused app's windows (fixed order), no UI.
  cycleAppWindowsScript = pkgs.writeShellScriptBin "cycle-app-windows-action" ''
    set -euo pipefail
    case "''${1:-next}" in
      prev) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell prevAppWindow ;;
      *) exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell nextAppWindow ;;
    esac
  '';

  # Mod+Escape: back to the previously focused window, no UI.
  focusLastWindowScript = pkgs.writeShellScriptBin "toggle-last-window-action" ''
    set -euo pipefail
    exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell focusLastWindow
  '';

  commitAiSwitcherScript = pkgs.writeShellScriptBin "commit-ai-session-switch-action" ''
    set -euo pipefail
    exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell commitLauncherSession
  '';

  focusLastSessionScript = pkgs.writeShellScriptBin "toggle-last-ai-session-action" ''
    set -euo pipefail
    exec ${runtimeShellIpcScript}/bin/quickshell-runtime-shell-ipc call shell focusLastSession
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

    accentColor = lib.mkOption {
      type = lib.types.str;
      default = "#93c5fd";
      description = "Primary accent color (replaces blue family in shell.qml).";
    };

    accentBg = lib.mkOption {
      type = lib.types.str;
      default = "#16243a";
      description = "Accent background color.";
    };

    accentMuted = lib.mkOption {
      type = lib.types.str;
      default = "#5d7ba2";
      description = "Muted accent color.";
    };

    accentWash = lib.mkOption {
      type = lib.types.str;
      default = "#152231";
      description = "Accent wash/tint color.";
    };

    toggleKey = lib.mkOption {
      type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
      default = "$mod+m";
      description = "Keybinding(s) used to toggle the runtime shell panel.";
    };

    theme = lib.mkOption {
      type = lib.types.str;
      default = "zinc-dark";
      description = "Built-in theme baked into the shell (see themes.nix). `runtime-theme set <name>` switches live at runtime.";
    };

    idle = {
      screenOffSeconds = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 300;
        description = "Seconds of inactivity before outputs are powered off (0 disables). Honours app idle inhibitors and pauses while casting.";
      };
      lockSeconds = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 600;
        description = "Seconds of inactivity before the in-shell lock engages (0 disables).";
      };
    };

    lock = {
      pamService = lib.mkOption {
        type = lib.types.str;
        default = "swaylock";
        description = "PAM service (in /etc/pam.d) the lock screen authenticates against. `swaylock` is the plain pam_unix stack the NixOS sway module creates on every host.";
      };
    };

    notifications = {
      backend = lib.mkOption {
        # SwayNC was retired 2026-07: QuickShell owns org.freedesktop.Notifications
        # natively (Quickshell.Services.Notifications in shell.qml). Kept as a
        # single-value enum so the nativeQuickshellNotifications guards still resolve.
        type = lib.types.enum [ "native" ];
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
        description = "Maximum number of visible notification toasts per output. Set to 0 to disable overlay toasts.";
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
      quickshellPackage
      pkgs.qt6.qtdeclarative
      togglePanelScript
      toggleDockScript
      togglePowerMenuScript
      runtimeShellCliScript
      toggleKeybindingsHelpScript
      brightnessKeyScript
      lockSessionScript
      runtimeThemeScript
      agentUsageUpdateScript
    ] ++ agentUsageCollectors ++ [
      toggleLauncherScript
      toggleAgentMonitorScript
      toggleSettingsScript
      showRuntimeDevicesScript
      showRuntimeDisplaysScript
      toggleNotificationsScript
      toggleNotificationDndScript
      clearNotificationsScript
      monitorPanelTabScript
      cycleSessionsScript
      showAiSwitcherScript
      showWindowSwitcherScript
      showAppSwitcherScript
      commitWindowSwitcherScript
      cycleAppWindowsScript
      focusLastWindowScript
      commitAiSwitcherScript
      focusLastSessionScript
      cycleDisplayLayoutScript
      notificationMonitorScript
      networkStatusScript
      systemStatsScript
      brightnessStatusScript
      brightnessActionScript
      castStatusScript
      lidPolicyStatusScript
      lidPolicyApplyScript
      lidInhibitScript
      daemonActionScript
      daemonHealthScript
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
    # The notification store lives in XDG state; the placeholder makes sure
    # the directory exists before the shell's first atomic write.
    xdg.stateFile."quickshell-runtime-shell/.keep".text = "";
    xdg.stateFile."quickshell-runtime-shell/agents/usage/.keep".text = "";

    # Regenerate the usage records every 15 minutes; the shell file-watches
    # the directory, and its refresh button runs the same script on demand.
    systemd.user.services.quickshell-agent-usage = {
      Unit.Description = "Refresh AI coding agent usage records for the runtime shell";
      Service = {
        Type = "oneshot";
        ExecStart = "${agentUsageUpdateScript}/bin/quickshell-agent-usage-update";
        Environment = [
          "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin:%h/.local/bin:/run/wrappers/bin"
        ];
        TimeoutStartSec = "180s";
      };
    };
    systemd.user.timers.quickshell-agent-usage = {
      Unit.Description = "Refresh AI coding agent usage records every 15 minutes";
      Timer = {
        OnStartupSec = "90s";
        OnUnitActiveSec = "15min";
        RandomizedDelaySec = "60s";
        AccuracySec = "1min";
      };
      Install.WantedBy = [ "timers.target" ];
    };

    xdg.configFile."quickshell/${cfg.configName}" = {
      source = shellConfigDir;
      recursive = true;
    };

    home.activation.ensureQuickshellQmllsConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      set -euo pipefail

      CONFIG_DIR="$HOME/.config/quickshell/${cfg.configName}"
      QMLLS_INI="$CONFIG_DIR/.qmlls.ini"

      # NOTE: never `exit` from an activation snippet — home-manager
      # concatenates all snippets into one script, so exit would abort every
      # later step (including linkGeneration) with a fake success.
      if [ -d "$CONFIG_DIR" ]; then
        if [ ! -e "$QMLLS_INI" ] || [ -L "$QMLLS_INI" ]; then
          ${pkgs.coreutils}/bin/rm -f "$QMLLS_INI"
          ${pkgs.coreutils}/bin/touch "$QMLLS_INI"
          ${pkgs.coreutils}/bin/chmod 0644 "$QMLLS_INI"
        fi
      fi
    '';

    systemd.user.services.quickshell-runtime-shell = {
      Unit = {
        Description = "Quickshell runtime shell";
        After = [ "sway-session.target" "i3-project-daemon.service" ];
        PartOf = [ "sway-session.target" ];
        BindsTo = [ "sway-session.target" ];
        X-Restart-Triggers = [ shellConfigDir ];
        StartLimitIntervalSec = "30s";
        StartLimitBurst = 5;
      };
      Service = {
        Type = "simple";
        ExecStart = "${quickshellBin} -c ${cfg.configName}";
        Restart = "on-failure";
        RestartSec = "1s";
        # No SuccessExitStatus=255: quickshell exits 255 for a broken QML config
        # as well as for compositor teardown, so whitelisting it would stop
        # systemd restarting a shell that failed to load.
        Environment = [
          "QT_QUICK_CONTROLS_STYLE=Fusion"
          "QT_QPA_PLATFORM=wayland"
          "QS_DISABLE_FILE_WATCHER=1"
        ] ++ lib.optionals usesNvidia [
          # NVIDIA/Qt6 Wayland buffer import is unstable; software Quick
          # rendering keeps the shell alive until the EGL path is fixed. Gated
          # to NVIDIA hosts — Intel/AMD render in hardware (software there is
          # the source of glitchy/stuttering shell UI, e.g. on thinkpad).
          "QT_QUICK_BACKEND=software"
        ];
      };
      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}

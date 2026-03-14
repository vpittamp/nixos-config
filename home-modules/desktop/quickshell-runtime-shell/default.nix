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
    cat >"$out/ShellConfig.qml" <<'EOF'
import QtQuick

QtObject {
  readonly property string configName: "${cfg.configName}"
  readonly property int topBarHeight: ${toString cfg.topBarHeight}
  readonly property bool topBarShowSeconds: ${if cfg.topBarShowSeconds then "true" else "false"}
  readonly property int panelWidth: ${toString cfg.panelWidth}
  readonly property int barHeight: ${toString cfg.barHeight}
  readonly property int dashboardHeartbeatMs: ${toString cfg.dashboardHeartbeatMs}
  readonly property string hostName: "${hostName}"
  readonly property string i3pmBin: "${config.home.profileDirectory}/bin/i3pm"
  readonly property string notificationMonitorBin: "${notificationMonitorScript}/bin/quickshell-notification-monitor"
  readonly property string networkStatusBin: "${networkStatusScript}/bin/quickshell-network-status"
  readonly property string launcherQueryBin: "${launcherQueryScript}/bin/quickshell-elephant-launcher-query"
  readonly property string launcherLaunchBin: "${launcherLaunchScript}/bin/quickshell-elephant-launcher-launch"
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
    exec ${lib.getExe pkgs.python3} ${../eww-top-bar/scripts/notification-monitor.py}
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
      prev) exec ${quickshellBin} ipc -c ${cfg.configName} call shell prevSession ;;
      *) exec ${quickshellBin} ipc -c ${cfg.configName} call shell nextSession ;;
    esac
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
      monitorPanelTabScript
      cycleSessionsScript
      showAiSwitcherScript
      focusLastSessionScript
      cycleDisplayLayoutScript
      notificationMonitorScript
      networkStatusScript
      launcherQueryScript
      launcherLaunchScript
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

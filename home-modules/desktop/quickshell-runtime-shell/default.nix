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
  readonly property int panelWidth: ${toString cfg.panelWidth}
  readonly property int barHeight: ${toString cfg.barHeight}
  readonly property int dashboardHeartbeatMs: ${toString cfg.dashboardHeartbeatMs}
  readonly property string hostName: "${hostName}"
  readonly property string i3pmBin: "${config.home.profileDirectory}/bin/i3pm"
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

  mkIpcScript = name: functionName: extraBody:
    pkgs.writeShellScriptBin name ''
      set -euo pipefail
      ${extraBody}
      exec ${quickshellBin} ipc call -c ${cfg.configName} shell ${functionName} "$@"
    '';

  togglePanelScript = pkgs.writeShellScriptBin "toggle-monitoring-panel" ''
    set -euo pipefail
    exec ${quickshellBin} -c ${cfg.configName} ipc call shell togglePanel
  '';

  toggleDockScript = pkgs.writeShellScriptBin "toggle-panel-dock-mode" ''
    set -euo pipefail
    exec ${quickshellBin} -c ${cfg.configName} ipc call shell toggleDockMode
  '';

  monitorPanelTabScript = pkgs.writeShellScriptBin "monitor-panel-tab" ''
    set -euo pipefail
    case "''${1:-0}" in
      0) exec ${quickshellBin} -c ${cfg.configName} ipc call shell showWindowsTab ;;
      1) exec ${quickshellBin} -c ${cfg.configName} ipc call shell showSessionsTab ;;
      *) exec ${quickshellBin} -c ${cfg.configName} ipc call shell showHealthTab ;;
    esac
  '';

  cycleSessionsScript = pkgs.writeShellScriptBin "cycle-active-ai-session-action" ''
    set -euo pipefail
    case "''${1:-next}" in
      prev) exec ${quickshellBin} -c ${cfg.configName} ipc call shell prevSession ;;
      *) exec ${quickshellBin} -c ${cfg.configName} ipc call shell nextSession ;;
    esac
  '';

  showAiSwitcherScript = pkgs.writeShellScriptBin "show-ai-mru-switcher-action" ''
    set -euo pipefail
    case "''${1:-next}" in
      prev) exec ${quickshellBin} -c ${cfg.configName} ipc call shell prevSession ;;
      *) exec ${quickshellBin} -c ${cfg.configName} ipc call shell nextSession ;;
    esac
  '';

  focusLastSessionScript = pkgs.writeShellScriptBin "toggle-last-ai-session-action" ''
    set -euo pipefail
    exec ${quickshellBin} -c ${cfg.configName} ipc call shell focusLastSession
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
      monitorPanelTabScript
      cycleSessionsScript
      showAiSwitcherScript
      focusLastSessionScript
      cycleDisplayLayoutScript
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

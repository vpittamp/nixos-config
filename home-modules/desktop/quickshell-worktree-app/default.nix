{ config, lib, pkgs, osConfig ? null, ... }:

let
  cfg = config.programs.quickshell-worktree-app;
  hostName =
    if osConfig != null && osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else "unknown";

  appConfigDir = pkgs.runCommandLocal "i3pm-quickshell-worktree-app" { } ''
    mkdir -p "$out"
    cp ${./shell.qml} "$out/shell.qml"
    cp ${./WorktreeAppService.qml} "$out/WorktreeAppService.qml"
    cat >"$out/AppConfig.qml" <<'EOF'
import QtQuick

QtObject {
  readonly property string configName: "${cfg.configName}"
  readonly property string hostName: "${hostName}"
  readonly property string windowTitle: "${cfg.windowTitle}"
  readonly property int windowWidth: ${toString cfg.windowWidth}
  readonly property int windowHeight: ${toString cfg.windowHeight}
  readonly property int dashboardHeartbeatMs: ${toString cfg.dashboardHeartbeatMs}
  readonly property string i3pmBin: "${config.home.profileDirectory}/bin/i3pm"
  readonly property string gioBin: "${pkgs.glib}/bin/gio"
}
EOF
  '';

  quickshellBin = lib.getExe pkgs.quickshell;
  swaymsgBin = lib.getExe pkgs.sway;

  openAppScript = pkgs.writeShellScriptBin cfg.commandName ''
    set -euo pipefail

    focus_existing_window() {
      ${swaymsgBin} '[app_id="org.quickshell" title="${cfg.windowTitle}"] focus' >/dev/null 2>&1 || true
    }

    if ${quickshellBin} ipc -c ${cfg.configName} call app open >/dev/null 2>&1; then
      focus_existing_window
      exit 0
    fi

    systemd_args=(
      --user
      --scope
      --quiet
      --collect
      --unit
      "${cfg.configName}-$(date +%s%N)"
    )

    for env_name in \
      DISPLAY \
      WAYLAND_DISPLAY \
      SWAYSOCK \
      DBUS_SESSION_BUS_ADDRESS \
      XDG_RUNTIME_DIR \
      XDG_CURRENT_DESKTOP \
      DESKTOP_SESSION \
      HOME \
      PATH
    do
      if [ -n "''${!env_name:-}" ]; then
        systemd_args+=(--setenv="$env_name=''${!env_name}")
      fi
    done

    while IFS='=' read -r env_name _; do
      if [[ "$env_name" == I3PM_* ]] && [ -n "''${!env_name:-}" ]; then
        systemd_args+=(--setenv="$env_name=''${!env_name}")
      fi
    done < <(env)

    ${pkgs.systemd}/bin/systemd-run "''${systemd_args[@]}" \
      ${quickshellBin} --no-duplicate -c ${cfg.configName} >/dev/null 2>&1

    for _ in $(seq 1 30); do
      if ${quickshellBin} ipc -c ${cfg.configName} call app open >/dev/null 2>&1; then
        focus_existing_window
        exit 0
      fi
      sleep 0.1
    done

    echo "failed to start QuickShell worktree app" >&2
    exit 1
  '';

  toggleAppScript = pkgs.writeShellScriptBin cfg.toggleCommandName ''
    set -euo pipefail

    if ${quickshellBin} ipc -c ${cfg.configName} call app toggle >/dev/null 2>&1; then
      exit 0
    fi

    exec ${openAppScript}/bin/${cfg.commandName}
  '';
in
{
  options.programs.quickshell-worktree-app = {
    enable = lib.mkEnableOption "standalone QuickShell worktree manager";

    configName = lib.mkOption {
      type = lib.types.str;
      default = "i3pm-worktree-app";
      description = "QuickShell configuration name for the standalone worktree app.";
    };

    commandName = lib.mkOption {
      type = lib.types.str;
      default = "open-worktree-manager";
      description = "Launcher command that opens the QuickShell worktree app.";
    };

    toggleCommandName = lib.mkOption {
      type = lib.types.str;
      default = "toggle-worktree-manager";
      description = "Command that toggles the QuickShell worktree app window.";
    };

    toggleKey = lib.mkOption {
      type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
      default = "$mod+g";
      description = "Keybinding(s) used to toggle the worktree app.";
    };

    windowTitle = lib.mkOption {
      type = lib.types.str;
      default = "AI Worktree Manager";
      description = "Window title for the standalone worktree app.";
    };

    windowWidth = lib.mkOption {
      type = lib.types.int;
      default = 1180;
      description = "Window width in pixels.";
    };

    windowHeight = lib.mkOption {
      type = lib.types.int;
      default = 820;
      description = "Window height in pixels.";
    };

    dashboardHeartbeatMs = lib.mkOption {
      type = lib.types.int;
      default = 5000;
      description = "Fallback dashboard refresh cadence in milliseconds for the worktree app watcher.";
    };
  };

  config = lib.mkIf cfg.enable {
    qt.enable = true;

    home.packages = [
      pkgs.quickshell
      pkgs.qt6.qtdeclarative
      openAppScript
      toggleAppScript
    ];

    home.activation.migrateQuickshellWorktreeAppConfig = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      set -euo pipefail

      CONFIG_DIR="$HOME/.config/quickshell/${cfg.configName}"

      if [ -L "$CONFIG_DIR" ]; then
        TARGET="$(${pkgs.coreutils}/bin/readlink -f "$CONFIG_DIR" || true)"
        case "$TARGET" in
          /nix/store/*) ${pkgs.coreutils}/bin/rm -f "$CONFIG_DIR" ;;
        esac
      fi
    '';

    xdg.configFile."quickshell/${cfg.configName}/shell.qml".source = appConfigDir + "/shell.qml";
    xdg.configFile."quickshell/${cfg.configName}/AppConfig.qml".source = appConfigDir + "/AppConfig.qml";
    xdg.configFile."quickshell/${cfg.configName}/WorktreeAppService.qml".source = appConfigDir + "/WorktreeAppService.qml";

    home.activation.ensureQuickshellWorktreeAppQmllsConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
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
  };
}

{ config, lib, pkgs, osConfig ? null, ... }:

with lib;

let
  cfg = config.programs.eww-workspace-bar;
  hostname = osConfig.networking.hostName or "";
  isHeadless = hostname == "hetzner";
  isRyzen = hostname == "ryzen";

  mocha = {
    base = "#1e1e2e";
    mantle = "#181825";
    surface0 = "#313244";
    surface1 = "#45475a";
    overlay0 = "#6c7086";
    text = "#cdd6f4";
    subtext0 = "#a6adc8";
    blue = "#89b4fa";
    mauve = "#cba6f7";
    yellow = "#f9e2af";
    red = "#f38ba8";
    green = "#a6e3a1";
    teal = "#94e2d5";
  };

  workspaceOutputs =
    if isHeadless then [
      { name = "HEADLESS-1"; label = "Headless 1"; }
      { name = "HEADLESS-2"; label = "Headless 2"; }
      { name = "HEADLESS-3"; label = "Headless 3"; }
    ]
    else if isRyzen then [
      { name = "DP-1"; label = "Primary"; }
      { name = "HDMI-A-1"; label = "HDMI"; }
      { name = "DP-2"; label = "DP-2"; }
      { name = "DP-3"; label = "DP-3"; }
    ]
    else [
      { name = "eDP-1"; label = "Built-in"; }
    ];

  sanitize = name:
    lib.toLower (
      lib.replaceStrings [" " ":" "/" "_" "-"] ["-" "-" "-" "-" "-"] name
    );

  sanitizeVar = name:
    lib.toLower (
      lib.replaceStrings [" " ":" "/" "-" "."] ["_" "_" "_" "_" "_"] name
    );

  pythonEnv = pkgs.python311.withPackages (ps: with ps; [ i3ipc pyxdg pydantic ]);

  workspacePanelDir = pkgs.stdenv.mkDerivation {
    name = "sway-workspace-panel-v20";
    src = builtins.path {
      path = ../../tools/sway-workspace-panel;
      name = "sway-workspace-panel-source-078";
    };
    installPhase = ''
      mkdir -p $out
      cp *.py $out/
      cp workspace-preview-daemon $out/
      if [ -d selection_models ]; then
        cp -r selection_models $out/
      fi
      chmod +x $out/workspace_panel.py
      chmod +x $out/workspace-preview-daemon
    '';
  };

  workspacePanelBin = pkgs.writeShellScriptBin "sway-workspace-panel" ''
    export PYTHONPATH="${workspacePanelDir}:$PYTHONPATH"
    exec ${pythonEnv}/bin/python -u ${workspacePanelDir}/workspace_panel.py "$@"
  '';

  workspacePanelCommand = "sway-workspace-panel";

  workspacePreviewDaemonBin = pkgs.writeShellScriptBin "workspace-preview-daemon" ''
    export PYTHONPATH="${workspacePanelDir}:$PYTHONPATH"
    exec ${pythonEnv}/bin/python -u ${workspacePanelDir}/workspace-preview-daemon "$@"
  '';

  restoreBarScript = pkgs.writeShellScriptBin "restore-workspace-bar" ''
    if ${pkgs.procps}/bin/pgrep -f "eww.*workspace-preview" >/dev/null; then
      ${pkgs.procps}/bin/pkill -f "eww.*workspace-preview"
      sleep 0.5
    fi
    ${pkgs.systemd}/bin/systemctl --user restart eww-workspace-bar
  '';

  # Generate window names for all outputs
  windowNames = map (output: "workspace-bar-" + sanitize output.name) workspaceOutputs;

  # Wrapper script that starts daemon and opens all bar windows
  wrapperScript = pkgs.writeShellScriptBin "eww-workspace-bar-wrapper" ''
    #!${pkgs.bash}/bin/bash

    EWW="${pkgs.eww}/bin/eww"
    CONFIG="$HOME/.config/${ewwConfigDir}"
    TIMEOUT="${pkgs.coreutils}/bin/timeout"
    PREVIEW_DAEMON="${workspacePreviewDaemonBin}/bin/workspace-preview-daemon"

    # Cleanup on exit
    cleanup() {
      kill $PREVIEW_DAEMON_PID 2>/dev/null
      kill $DAEMON_PID 2>/dev/null
    }
    trap cleanup EXIT

    # Start daemon in background, capture PID
    $EWW --config "$CONFIG" daemon --no-daemonize &
    DAEMON_PID=$!

    # Wait for daemon ready (max 6 seconds)
    for i in $(seq 1 30); do
      $TIMEOUT 1s $EWW --config "$CONFIG" ping 2>/dev/null && break
      ${pkgs.coreutils}/bin/sleep 0.2
    done

    # Open all workspace bar windows
    # IMPORTANT: Run eww open with timeout - it can hang indefinitely due to IPC issues
    ${lib.concatMapStringsSep "\n    " (name: ''$TIMEOUT 5s $EWW --config "$CONFIG" open ${name} &'') windowNames}
    ${pkgs.coreutils}/bin/sleep 0.5

    # Start workspace preview daemon (Feature 057, 072)
    # This daemon listens to i3pm workspace_mode/project_mode events and
    # opens/closes the preview pane accordingly
    $PREVIEW_DAEMON &
    PREVIEW_DAEMON_PID=$!

    # Wait for daemon process
    wait $DAEMON_PID
  '';

  markupVar = output: "workspace_rows_" + sanitizeVar output.name;

  workspaceMarkupDefs = lib.concatStringsSep "\n\n" (map (output: 
    let
      varName = markupVar output;
    in 
      "(deflisten ${varName} :initial \"\" \"${workspacePanelCommand} --format yuck --output ${output.name}\")"
  ) workspaceOutputs);

  workspacePreviewDefs = ''
    (defvar workspace_preview_data "{\"visible\": false}")
    (defvar keyboard_hints "")
  '';

  windowBlocks = lib.concatStringsSep "\n\n" (map (output: 
    let 
      windowId = "workspace-bar-" + sanitize output.name;
      varName = markupVar output;
    in 
      ''
        (defwindow ${windowId}
          :monitor "${output.name}"
          :windowtype "dock"
          :exclusive true
          :focusable false
          :geometry (geometry :anchor "bottom center"
                                :x "0px"
                                :y "0px"
                                :width "100%"
                                :height "32px")
          :reserve (struts :side "bottom" :distance "36px")
          (workspace-strip :output_label "${output.label}" :markup_var ${varName})
        )
      ''
  ) workspaceOutputs);

  ewwConfigDir = "eww-workspace-bar";
  ewwConfigPath = "%h/.config/${ewwConfigDir}";

  mainYuck = import ./yuck/main.yuck.nix {
    inherit workspaceMarkupDefs workspacePreviewDefs windowBlocks isHeadless isRyzen;
  };

  workspacePreviewYuck = import ./yuck/workspace-preview.yuck.nix {};
  workspaceStripYuck = import ./yuck/workspace-strip.yuck.nix {};

  mainScss = import ./scss/main.scss.nix {
    inherit mocha;
  };

in
{
  options.programs.eww-workspace-bar.enable = mkEnableOption "Eww-driven workspace bar with SVG icons";

  config = mkIf cfg.enable {
    home.packages = [ pkgs.eww workspacePanelBin workspacePreviewDaemonBin restoreBarScript wrapperScript ];

    xdg.configFile."${ewwConfigDir}/eww.yuck".text = mainYuck;
    xdg.configFile."${ewwConfigDir}/workspace-preview.yuck".text = workspacePreviewYuck;
    xdg.configFile."${ewwConfigDir}/workspace-strip.yuck".text = workspaceStripYuck;
    xdg.configFile."${ewwConfigDir}/eww.scss".text = mainScss;

    systemd.user.services.eww-workspace-bar = {
      Unit = {
        Description = "Eww workspace bar";
        After = [
          "sway-session.target"
          "i3-project-daemon.service"
          "home-manager-vpittamp.service"
        ];
        PartOf = [ "sway-session.target" ];
        Wants = [ "i3-project-daemon.service" ];
      };

      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.eww}/bin/eww --config ${ewwConfigPath} kill 2>/dev/null || true'";
        ExecStart = "${wrapperScript}/bin/eww-workspace-bar-wrapper";
        ExecStopPost = "${pkgs.bash}/bin/bash -c '${pkgs.eww}/bin/eww --config ${ewwConfigPath} kill 2>/dev/null || true'";
        Restart = "on-failure";
        RestartSec = "3s";
        KillMode = "control-group";
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}

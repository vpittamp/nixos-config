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
    home.packages = [ pkgs.eww workspacePanelBin workspacePreviewDaemonBin restoreBarScript ];

    xdg.configFile."${ewwConfigDir}/eww.yuck".text = mainYuck;
    xdg.configFile."${ewwConfigDir}/workspace-preview.yuck".text = workspacePreviewYuck;
    xdg.configFile."${ewwConfigDir}/workspace-strip.yuck".text = workspaceStripYuck;
    xdg.configFile."${ewwConfigDir}/eww.scss".text = mainScss;

    systemd.user.services.eww-workspace-bar = {
      Unit = {
        Description = "Eww workspace bar";
        After = [ "sway-session.target" ];
        PartOf = [ "sway-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.eww}/bin/eww --config ${ewwConfigPath} kill 2>/dev/null || true'";
        ExecStart = "${pkgs.eww}/bin/eww --config ${ewwConfigPath} daemon --no-daemonize";
        ExecStopPost = "${pkgs.eww}/bin/eww --config ${ewwConfigPath} kill 2>/dev/null || true";
        Restart = "on-failure";
        KillMode = "control-group";
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}

{ config, lib, pkgs, osConfig ? null, ... }:

let
  cfg = config.programs.eww-workspace-bar;
  isHeadless = osConfig != null && (osConfig.networking.hostName or "") == "nixos-hetzner-sway";

  workspaceOutputs =
    if isHeadless then [
      { name = "HEADLESS-1"; label = "Headless 1"; }
      { name = "HEADLESS-2"; label = "Headless 2"; }
      { name = "HEADLESS-3"; label = "Headless 3"; }
    ] else [
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

  pythonEnv = pkgs.python311.withPackages (ps: with ps; [ i3ipc pyxdg ]);

  workspacePanelScript = ../tools/sway-workspace-panel/workspace_panel.py;

  workspacePanelBin = pkgs.writeShellScriptBin "sway-workspace-panel" ''
    exec ${pythonEnv}/bin/python -u ${workspacePanelScript} "$@"
  '';

  workspacePanelCommand = "${workspacePanelBin}/bin/sway-workspace-panel";

  ewwConfigDir = "eww-workspace-bar";
  ewwConfigPath = "%h/.config/${ewwConfigDir}";

  markupVar = output: "workspace_rows_" + sanitizeVar output.name;

  workspaceMarkupDefs = lib.concatStringsSep "\n\n" (map (output:
    let
      varName = markupVar output;
    in
      ''
(deflisten ${varName} :initial "" "${workspacePanelCommand} --format yuck --output ${output.name}")
      ''
  ) workspaceOutputs);

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

  ewwYuck = ''
${workspaceMarkupDefs}

(defwidget workspace-button [number_label workspace_name app_name icon_path icon_fallback workspace_id focused visible urgent empty]
  (button
    :class {
      "workspace-button "
      + (focused ? "focused " : "")
      + ((visible && !focused) ? "visible " : "")
      + (urgent ? "urgent " : "")
      + ((icon_path != "") ? "has-icon " : "no-icon ")
      + (empty ? "empty" : "populated")
    }
    :tooltip { app_name != "" ? (number_label + " · " + app_name) : workspace_name }
    :onclick {
      "swaymsg workspace \""
      + replace(workspace_name, "\"", "\\\"")
      + "\""
    }
    (box :class "workspace-pill"
      (box :class "workspace-icon-stack"
        (image :class "workspace-icon-image"
               :path icon_path
               :image-width 20
               :image-height 20)
        (label :class "workspace-icon-fallback" :text icon_fallback))))
)

(defwidget workspace-strip [output_label markup_var]
  (box :class "workspace-bar"
    (label :class "workspace-output" :text output_label)
    (box :class "workspace-strip"
         :orientation "h"
         :halign "center"
          :spacing 3
      (literal :content markup_var))))

${windowBlocks}
'';

  ewwScss = ''
/* Catppuccin Mocha color palette */
$base: #1e1e2e;
$mantle: #181825;
$surface0: #313244;
$surface1: #45475a;
$text: #cdd6f4;
$subtext0: #a6adc8;
$mauve: #cba6f7;
$blue: #89b4fa;
$red: #f38ba8;

* {
  font-family: sans-serif;
  font-size: 11pt;
  color: $text;
}

.workspace-bar {
  background: $base;
  padding: 6px;
  margin: 8px;
  border-radius: 8px;
}

.workspace-output {
  font-size: 9pt;
  color: $subtext0;
  margin-right: 8px;
}

.workspace-strip {
  margin-left: 0px;
}

.workspace-button {
  background: $surface0;
  padding: 6px;
  border-radius: 8px;
  border: 2px solid transparent;
  min-width: 0;
  transition: all 0.2s ease;
}

.workspace-button:hover {
  background: $surface1;
  border-color: $blue;
}

.workspace-button.focused {
  background: $mauve;
  border-color: $mauve;
}

.workspace-button.visible:not(.focused) {
  border-color: $blue;
}

.workspace-button.urgent {
  background: $red;
  border-color: $red;
}

.workspace-button.empty {
  opacity: 0.4;
}

.workspace-pill {
  margin: 0;
  padding: 0;
}

.workspace-icon-stack {
  min-width: 24px;
  min-height: 24px;
  padding: 0px;
  margin: 0px;
}

.workspace-icon-image {
  opacity: 1.0;
}

.workspace-button.no-icon .workspace-icon-image {
  opacity: 0;
}

.workspace-button.has-icon .workspace-icon-fallback {
  opacity: 0;
}

.workspace-icon-fallback {
  font-weight: 600;
  font-size: 12pt;
  color: $text;
}

.workspace-button.focused .workspace-icon-fallback {
  color: $base;
}
'';

  windowNames = map (output: "workspace-bar-" + sanitize output.name) workspaceOutputs;
  openCommand =
    let
      args = lib.escapeShellArgs windowNames;
    in
      ''${pkgs.eww}/bin/eww --config ${ewwConfigPath} open-many ${args}'';

in
{
  options.programs.eww-workspace-bar.enable = lib.mkEnableOption "Eww-driven workspace bar with SVG icons";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.eww workspacePanelBin ];

    xdg.configFile."${ewwConfigDir}/eww.yuck".text = ewwYuck;
    xdg.configFile."${ewwConfigDir}/eww.scss".text = ewwScss;

    systemd.user.services.eww-workspace-bar = {
      Unit = {
        Description = "Eww workspace bar";
        After = [ "graphical-session.target" "sway-session.target" ];
        PartOf = [ "sway-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = ''${pkgs.eww}/bin/eww --config ${ewwConfigPath} daemon --no-daemonize'';
        ExecStartPost = openCommand;
        ExecStopPost = ''${pkgs.eww}/bin/eww --config ${ewwConfigPath} close-all'';
        Restart = "on-failure";
        RestartSec = 2;
        # Match Walker's XDG_DATA_DIRS for icon theme access (Papirus, Breeze, etc.)
        # Priority: curated apps → user apps → icon themes → system fallback
        Environment = [
          "XDG_DATA_DIRS=${config.home.homeDirectory}/.local/share/i3pm-applications:${config.home.homeDirectory}/.local/share:${config.home.profileDirectory}/share:/run/current-system/sw/share"
        ];
      };
      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}

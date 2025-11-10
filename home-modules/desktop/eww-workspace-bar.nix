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
      { name = "HDMI-A-1"; label = "External"; }
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
                        :height "44px")
  :reserve (struts :side "bottom" :distance "48px")
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
    :cursor "pointer"
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
               :image-width "20px"
               :image-height "20px")
        (label :class "workspace-icon-fallback" :text icon_fallback))
      (label :class "workspace-number" :text number_label)))
)

(defwidget workspace-strip [output_label markup_var]
  (box :class "workspace-bar"
    (label :class "workspace-output" :text output_label)
    (box :class "workspace-strip"
         :orientation "h"
         :halign "center"
          :spacing 6
      (literal :content markup_var))))

${windowBlocks}
'';

  ewwScss = ''
$bg: #1e1e2e;
$bg-soft: #313244;
$fg: #cdd6f4;
$accent: #89b4fa;
$urgent: #f38ba8;
$border: rgba(137, 180, 250, 0.35);
$inactive: rgba(205, 214, 244, 0.45);

* {
  font-family: "FiraCode Nerd Font", "Font Awesome 6 Free", sans-serif;
  font-size: 0.95rem;
  color: $fg;
}

.workspace-bar {
  background-color: rgba(30, 30, 46, 0.90);
  border: 1px solid $border;
  border-radius: 14px;
  padding: 6px 14px;
  margin: 8px 20px;
}

.workspace-output {
  font-size: 0.70rem;
  color: $inactive;
}

.workspace-strip {
  margin-left: 4px;
}

.workspace-button {
  background-color: $bg-soft;
  padding: 4px 10px;
  border-radius: 10px;
  border: 1px solid transparent;
  transition: background-color 0.2s ease, border-color 0.2s ease;
}

.workspace-button:hover {
  border-color: $accent;
}

.workspace-button.focused {
  background-color: $accent;
  color: #1e1e2e;
}

.workspace-button.focused .workspace-number {
  color: #1e1e2e;
}

.workspace-button.visible:not(.focused) {
  border-color: rgba(137, 180, 250, 0.6);
}

.workspace-button.urgent {
  background-color: $urgent;
  color: #1e1e2e;
}

.workspace-button.empty {
  opacity: 0.45;
}

.workspace-pill {
  margin-right: 8px;
}

.workspace-icon-stack {
  width: 20px;
  height: 20px;
  text-align: center;
}

.workspace-icon-image {
  opacity: 0.9;
}

.workspace-button.no-icon .workspace-icon-image {
  opacity: 0;
}

.workspace-button.has-icon .workspace-icon-fallback {
  opacity: 0;
}

.workspace-icon-fallback {
  font-weight: 600;
  font-size: 0.85rem;
}

.workspace-number {
  font-weight: 700;
  letter-spacing: 0.02em;
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
        ExecStart = ''${pkgs.eww}/bin/eww --config ${ewwConfigPath} daemon'';
        ExecStartPost = openCommand;
        ExecStopPost = ''${pkgs.eww}/bin/eww --config ${ewwConfigPath} close-all'';
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}

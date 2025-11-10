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
$bg: #010409;
$bg-soft: #0b1220;
$fg: #dce6ff;
$accent: #60a5fa;
$accent-muted: rgba(96, 165, 250, 0.45);
$accent-strong: rgba(96, 165, 250, 0.85);
$urgent: #fb7185;
$border: rgba(96, 165, 250, 0.25);
$inactive: rgba(173, 188, 216, 0.35);

* {
  font-family: "FiraCode Nerd Font", "Font Awesome 6 Free", sans-serif;
  font-size: 0.95rem;
  color: $fg;
}

.workspace-bar {
  background: rgba(1, 4, 9, 0.96);
  border: 1px solid $border;
  border-radius: 14px;
  box-shadow: 0 18px 30px rgba(2, 4, 9, 0.65);
  padding: 6px 14px;
  margin: 8px 20px;
}

.workspace-output {
  font-size: 0.75rem;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.55);
}

.workspace-strip {
  margin-left: 4px;
}

.workspace-button {
  background: linear-gradient(180deg, rgba(11, 18, 32, 0.95), rgba(5, 9, 16, 0.95));
  padding: 6px 18px;
  border-radius: 14px;
  border: 1px solid rgba(255, 255, 255, 0.03);
  transition: background-color 0.2s ease, border-color 0.2s ease, transform 0.15s ease;
}

.workspace-button:hover {
  border-color: $accent-strong;
  transform: translateY(-1px);
}

.workspace-button.focused {
  background: radial-gradient(circle at top left, rgba(96, 165, 250, 0.95), rgba(37, 99, 235, 0.9));
  border-color: rgba(147, 197, 253, 0.8);
  color: #010409;
  box-shadow: 0 0 12px rgba(96, 165, 250, 0.35);
}

.workspace-button.focused .workspace-number {
  color: #010409;
}

.workspace-button.visible:not(.focused) {
  border-color: $accent-muted;
  box-shadow: 0 0 8px rgba(96, 165, 250, 0.25);
}

.workspace-button.urgent {
  background-color: $urgent;
  color: #050505;
}

.workspace-button.empty {
  opacity: 0.45;
}

.workspace-pill {
  margin-right: 8px;
}

.workspace-icon-stack {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.02);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  box-shadow: inset 0 0 8px rgba(255, 255, 255, 0.02);
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
        ExecStart = ''${pkgs.eww}/bin/eww --config ${ewwConfigPath} daemon --no-daemonize'';
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

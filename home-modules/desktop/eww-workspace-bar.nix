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

  pythonEnv = pkgs.python311.withPackages (ps: with ps; [ i3ipc pyxdg ]);

  workspacePanelScript = ../tools/sway-workspace-panel/workspace_panel.py;

  panelArgs =
    if workspaceOutputs == [] then ""
    else lib.escapeShellArgs (["--outputs"] ++ map (output: output.name) workspaceOutputs);

  workspacePanelBin = pkgs.writeShellScriptBin "sway-workspace-panel" ''
    exec ${pythonEnv}/bin/python -u ${workspacePanelScript} ${panelArgs} "$@"
  '';

  workspacePanelCommand = "${workspacePanelBin}/bin/sway-workspace-panel";

  ewwConfigDir = "eww-workspace-bar";
  ewwConfigPath = "%h/.config/${ewwConfigDir}";

  windowBlocks = lib.concatStringsSep "\n\n" (map (output:
    let
      windowId = "workspace-bar-" + sanitize output.name;
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
  (workspace-strip :output_key "${output.name}" :output_label "${output.label}")
)
      ''
  ) workspaceOutputs);

  ewwYuck = ''
(deflisten workspace_state :initial "{\"workspaces\":{}}" "${workspacePanelCommand}")

(defwidget workspace-button [ws]
  (button
    :class {
      "workspace-button "
      + (ws.focused ? "focused " : "")
      + ((ws.visible && !ws.focused) ? "visible " : "")
      + (ws.urgent ? "urgent " : "")
      + (ws.iconPath != "" ? "has-icon " : "no-icon ")
      + (ws.isEmpty ? "empty" : "populated")
    }
    :cursor "pointer"
    :tooltip { ws.appName != "" ? (ws.numberLabel + " · " + ws.appName) : ws.name }
    :onclick {
      "swaymsg workspace \""
      + replace(ws.name, "\"", "\\\"")
      + "\""
    }
    (box :class "workspace-pill"
      (box :class "workspace-icon-stack"
        (image :class "workspace-icon-image"
               :path ws.iconPath
               :image-width "20px"
               :image-height "20px")
        (label :class "workspace-icon-fallback" :text ws.iconFallback))
      (label :class "workspace-number" :text ws.numberLabel)))
)

(defwidget workspace-strip [output_key output_label]
  (box :class "workspace-bar"
    (label :class "workspace-output" :text output_label)
    (box :class "workspace-strip"
         :orientation "h"
         :halign "center"
          :spacing 6
      (for ws in (workspace_state.workspaces[output_key] ?: [])
        (workspace-button :ws ws)))))

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
  display: flex;
  align-items: center;
  gap: 12px;
}

.workspace-output {
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-size: 0.70rem;
  color: $inactive;
}

.workspace-strip {
  display: flex;
  gap: 8px;
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
  display: flex;
  align-items: center;
  gap: 8px;
}

.workspace-icon-stack {
  position: relative;
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.workspace-icon-image {
  opacity: 0.9;
}

.workspace-button.no-icon .workspace-icon-image {
  display: none;
}

.workspace-button.has-icon .workspace-icon-fallback {
  display: none;
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

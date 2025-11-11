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

  # Use PATH instead of hardcoded Nix store path to avoid stale config after rebuilds
  workspacePanelCommand = "sway-workspace-panel";

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

; SwayNC notification indicator (Feature 058 enhancement)
(defpoll swaync_count :interval "2s"
  "${pkgs.swaynotificationcenter}/bin/swaync-client -c")

(defpoll swaync_dnd :interval "2s"
  "${pkgs.swaynotificationcenter}/bin/swaync-client -D")

(defwidget workspace-button [number_label workspace_name app_name icon_path icon_fallback workspace_id focused visible urgent pending empty]
  (overlay
    ; Base button (first child determines overlay size)
    (button
      :class {
        "workspace-button "
        + (pending ? "pending " : "")
        + (focused ? "focused " : "")
        + ((visible && !focused) ? "visible " : "")
        + (urgent ? "urgent " : "")
        + ((icon_path != "") ? "has-icon " : "no-icon ")
        + (empty ? "empty" : "populated")
      }
      :tooltip {
      urgent ?
        (app_name != "" ? (number_label + " · " + app_name + " (urgent)") : (workspace_name + " (urgent)"))
        : (app_name != "" ? (number_label + " · " + app_name) : workspace_name)
    }
      :onclick {
        "swaymsg workspace \""
        + replace(workspace_name, "\"", "\\\"")
        + "\""
      }
      (box :class "workspace-pill" :orientation "h" :space-evenly false :spacing 3
        (image :class "workspace-icon-image"
               :path icon_path
               :image-width 16
               :image-height 16)
        (label :class "workspace-number" :text number_label)))

    ; Notification badge overlay (User Story 3 - T034)
    (box
      :class "notification-badge-container"
      :valign "start"
      :halign "end"
      :visible urgent
      (label :class "notification-badge" :text "")))
)

(defwidget swaync-indicator []
  (button
    :class {
      "swaync-button "
      + (swaync_dnd == "true" ? "dnd-active " : "")
      + (swaync_count > 0 ? "has-notifications" : "no-notifications")
    }
    :tooltip {
      swaync_dnd == "true"
        ? "Do Not Disturb (" + swaync_count + " notifications)"
        : (swaync_count > 0 ? swaync_count + " notification(s)" : "No notifications")
    }
    :onclick "sleep 0.1 && ${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw"
    :onrightclick "sleep 0.1 && ${pkgs.swaynotificationcenter}/bin/swaync-client -d -sw"
    (box :class "swaync-pill" :orientation "h" :space-evenly false :spacing 3
      (label :class "swaync-icon" :text {swaync_dnd == "true" ? "🔕" : "🔔"})
      (label :class "swaync-count" :text {swaync_count > 0 ? swaync_count : ""}))))

(defwidget workspace-strip [output_label markup_var]
  (box :class "workspace-bar"
    (label :class "workspace-output" :text output_label)
    (box :class "workspace-strip"
         :orientation "h"
         :halign "center"
          :spacing 3
      (literal :content markup_var))
    (swaync-indicator)))

${windowBlocks}
'';

  ewwScss = ''
/* Catppuccin Mocha color palette */
$base: #1e1e2e;
$mantle: #181825;
$surface0: #313244;
$surface1: #45475a;
$overlay0: #6c7086;
$text: #cdd6f4;
$subtext0: #a6adc8;
$mauve: #cba6f7;
$blue: #89b4fa;
$teal: #94e2d5;
$red: #f38ba8;
$yellow: #f9e2af;  /* Feature 058: Pending workspace state */

* {
  font-family: sans-serif;
  font-size: 11pt;
  color: $text;
  background-color: transparent;
}

window {
  background-color: transparent;
}

.workspace-bar {
  background: rgba(30, 30, 46, 0.85);
  padding: 4px 8px;
  margin: 6px;
  border-radius: 6px;
  border: 1px solid rgba(203, 166, 247, 0.25);
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.4);
}

.workspace-output {
  font-size: 8pt;
  color: $subtext0;
  margin-right: 8px;
  opacity: 0.5;
}

.workspace-strip {
  margin-left: 0px;
}

/* Flat buttons with subtle borders */
.workspace-button {
  background: rgba(30, 30, 46, 0.3);
  padding: 3px 6px;
  border-radius: 4px;
  border: 1px solid rgba(108, 112, 134, 0.3);
  box-shadow: none;
  min-width: 0;
  transition: all 0.2s;
}

button {
  box-shadow: none;
  background-image: none;
  outline: none;
}

.workspace-button:hover {
  background: rgba(137, 180, 250, 0.15);
  border: 1px solid rgba(137, 180, 250, 0.4);
}

/* Focused: Flat blue accent */
.workspace-button.focused {
  background: rgba(137, 180, 250, 0.3);
  border: 1px solid rgba(137, 180, 250, 0.6);
}

/* Visible on other monitor */
.workspace-button.visible:not(.focused) {
  background: rgba(137, 180, 250, 0.12);
  border: 1px solid rgba(137, 180, 250, 0.35);
}

.workspace-button.urgent {
  background: rgba(243, 139, 168, 0.25);
  border: 1px solid rgba(243, 139, 168, 0.5);
}

.workspace-button.empty {
  opacity: 0.3;
}

.workspace-button.empty:hover {
  opacity: 0.6;
}

/* Feature 058: Pending workspace highlight (User Story 1) */
.workspace-button.pending {
  background: rgba(249, 226, 175, 0.25);  /* Catppuccin Mocha Yellow */
  border: 1px solid rgba(249, 226, 175, 0.7);
  transition: all 0.2s;  /* Smooth transitions (T018) */
}

.workspace-button.pending .workspace-icon-image {
  -gtk-icon-shadow: 0 0 8px rgba(249, 226, 175, 0.8);  /* Icon glow */
}

.workspace-button.pending .workspace-number {
  color: $yellow;
  font-weight: 600;
}

/* T019: Pending overrides focused (mutual exclusion) */
.workspace-button.pending.focused {
  background: rgba(249, 226, 175, 0.25);  /* Pending takes priority */
  border: 1px solid rgba(249, 226, 175, 0.7);
}

.workspace-button.pending.focused .workspace-icon-image {
  -gtk-icon-shadow: 0 0 8px rgba(249, 226, 175, 0.8);  /* Pending icon glow */
}

.workspace-button.pending.focused .workspace-number {
  color: $yellow;  /* Pending color overrides blue focused color */
  font-weight: 600;
}

.workspace-pill {
  margin: 0;
  padding: 0;
}

.workspace-icon-image {
  opacity: 1.0;
  min-width: 16px;
  min-height: 16px;
}

.workspace-button.focused .workspace-icon-image {
  -gtk-icon-shadow: 0 0 8px rgba(137, 180, 250, 0.8);
}

.workspace-button.urgent .workspace-icon-image {
  -gtk-icon-shadow: 0 0 6px rgba(243, 139, 168, 0.5);
}

/* Hide icon when no icon path */
.workspace-button.no-icon .workspace-icon-image {
  opacity: 0;
}

/* Workspace number always visible */
.workspace-number {
  font-size: 9pt;
  font-weight: 500;
  color: $subtext0;
  min-width: 12px;
}

.workspace-button.focused .workspace-number {
  color: $blue;
  font-weight: 600;
}

.workspace-button.urgent .workspace-number {
  color: $red;
  font-weight: 600;
}

.workspace-button.empty .workspace-number {
  color: $overlay0;
}

/* Feature 058: Notification badge (User Story 3) */
.notification-badge-container {
  margin: 2px 2px 0 0;  /* T032: Position in top-right corner with slight offset */
}

.notification-badge {
  min-width: 8px;  /* T033: 8px diameter circle */
  min-height: 8px;
  padding: 0;  /* No padding to keep size tight */
  font-size: 0;  /* Hide any text content */
  background: $red;  /* Catppuccin Mocha Red (#f38ba8) */
  border: 1px solid white;  /* Thinner border for smaller size */
  border-radius: 50%;  /* Perfect circle */
  opacity: 1;
  transition: opacity 0.2s;  /* T035: Smooth fade-out when urgent clears */
}

/* T036: Badge coexists with pending highlight (both can be visible) */
.workspace-button.pending .notification-badge {
  /* No style override needed - badge renders on top via overlay widget */
  /* Pending affects button background, badge is independent overlay */
}

/* Feature 058: SwayNC notification indicator (enhancement) */
.swaync-button {
  background: rgba(30, 30, 46, 0.3);
  padding: 3px 8px;
  margin-left: 8px;
  border-radius: 4px;
  border: 1px solid rgba(108, 112, 134, 0.3);
  transition: all 0.2s;
}

.swaync-button:hover {
  background: rgba(137, 180, 250, 0.15);
  border: 1px solid rgba(137, 180, 250, 0.4);
}

.swaync-button.has-notifications {
  background: rgba(137, 180, 250, 0.25);
  border: 1px solid rgba(137, 180, 250, 0.5);
}

.swaync-button.dnd-active {
  background: rgba(249, 226, 175, 0.25);  /* Yellow for DND */
  border: 1px solid rgba(249, 226, 175, 0.6);
}

.swaync-pill {
  margin: 0;
  padding: 0;
}

.swaync-icon {
  font-size: 11pt;
}

.swaync-count {
  font-size: 9pt;
  font-weight: 600;
  color: $blue;
  min-width: 12px;
}

.swaync-button.dnd-active .swaync-count {
  color: $yellow;
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

# DEPRECATED: Feature 116 - This module is superseded by eww-device-controls
# Device controls (brightness, volume, bluetooth) are now handled by the unified
# eww-device-controls module. This module is kept for backwards compatibility
# but is disabled by default.
#
# Migration: Enable programs.eww-device-controls instead of this module.
# The new device controls provide:
# - Hardware-adaptive controls (only shows available hardware)
# - Expandable top bar panels
# - Comprehensive Devices tab in monitoring panel
#
# See: specs/116-use-eww-device/quickstart.md
{ config, lib, pkgs, osConfig ? null, ... }:

let
  cfg = config.programs.eww-quick-panel;
  hostname = osConfig.networking.hostName or "";
  isHeadless = hostname == "hetzner";
  isRyzen = hostname == "ryzen";

  ewwConfigDir = "eww-quick-panel";
  ewwConfigPath = "%h/.config/${ewwConfigDir}";

  arinAssets = builtins.path { path = ../../assets/swaync/arin; name = "eww-arin-assets"; };
  dashboardAssets = builtins.path { path = ../../assets/swaync/dashboard/images; name = "eww-dashboard-assets"; };

  assetsHome = "${config.home.homeDirectory}/.config/${ewwConfigDir}/assets";
  arinIconBase = "${assetsHome}/arin/icons";
  dashboardIconBase = "${assetsHome}/dashboard/icons";

  icons = {
    wifi = "${arinIconBase}/system/wifi.png";
    bluetooth = "${arinIconBase}/system/sys-reboot.png";
    volume = "${arinIconBase}/volume/volume.png";
    tailscale = "${arinIconBase}/apps/terminal.png";
    firefox = "${dashboardIconBase}/firefox.svg";
    terminal = "${dashboardIconBase}/terminal.svg";
    code = "${dashboardIconBase}/code.svg";
    files = "${dashboardIconBase}/files.svg";
    screenshot = "${arinIconBase}/dashboard.svg";
    lock = "${arinIconBase}/system/sys-lock.png";
    suspend = "${arinIconBase}/system/sys-sleep.png";
  };

  brightnessDevice = "apple-panel-bl";
  keyboardDevice = "kbd_backlight";

  ewwYuck = ''
(defpoll display_brightness :interval "4s"
  `brightnessctl -d ${brightnessDevice} -P | tr -d '%' || echo 0`)

(defpoll keyboard_brightness :interval "4s"
  `brightnessctl -d ${keyboardDevice} -P | tr -d '%' || echo 0`)

(defwidget brightness-card [label value down_cmd up_cmd]
  (box :class "metric-card"
       :orientation "v"
    (label :class "metric-title" :text label)
    (label :class "metric-value" :text {value + "%"})
    (box :class "metric-buttons"
         :spacing 6
      (button :class "metric-btn" :onclick down_cmd "−")
      (button :class "metric-btn" :onclick up_cmd "+"))))

(defwidget quick-action-button [label icon command]
  (button :class "quick-action" :onclick command
    (box :class "quick-action-inner" :spacing 8 :orientation "h"
      (image :path icon :image-width 28 :image-height 28)
      (label :class "quick-action-label" :text label))))

(defwidget quick-panel []
  (box :class "quick-panel"
       :orientation "v"
       :spacing 16
    (label :class "panel-title" :text "Quick Controls")

    (box :class "metrics-row" :spacing 12
      (brightness-card :label "Display Brightness"
                       :value display_brightness
                       :down_cmd "brightnessctl -d ${brightnessDevice} set 5%-"
                       :up_cmd "brightnessctl -d ${brightnessDevice} set +5%")
      (brightness-card :label "Keyboard Backlight"
                       :value keyboard_brightness
                       :down_cmd "brightnessctl -d ${keyboardDevice} set 10%-"
                       :up_cmd "brightnessctl -d ${keyboardDevice} set +10%"))

    (box :class "actions-grid" :spacing 10 :orientation "v"
      (box :spacing 10
        (quick-action-button :label "Network" :icon "${icons.wifi}" :command "nm-connection-editor")
        (quick-action-button :label "Bluetooth" :icon "${icons.bluetooth}" :command "blueman-manager"))
      (box :spacing 10
        (quick-action-button :label "Volume" :icon "${icons.volume}" :command "pavucontrol")
        (quick-action-button :label "VPN Status" :icon "${icons.tailscale}" :command "ghostty -e tailscale status"))
      (box :spacing 10
        (quick-action-button :label "Firefox" :icon "${icons.firefox}" :command "firefox")
        (quick-action-button :label "Ghostty" :icon "${icons.terminal}" :command "ghostty"))
      (box :spacing 10
        (quick-action-button :label "VS Code" :icon "${icons.code}" :command "code")
        (quick-action-button :label "Files" :icon "${icons.files}" :command "xdg-open ~"))
      (box :spacing 10
        (quick-action-button :label "Screenshot" :icon "${icons.screenshot}"
                              :command "capture-region-to-clipboard")
        (quick-action-button :label "Lock" :icon "${icons.lock}" :command "swaylock -f"))
      (box :spacing 10
        (quick-action-button :label "Suspend" :icon "${icons.suspend}" :command "systemctl suspend")
        (quick-action-button :label "Close Panel" :icon "${icons.lock}" :command "toggle-quick-panel"))))

(defwindow quick-panel
  :monitor "${if isHeadless then "HEADLESS-1" else if isRyzen then "DP-1" else "eDP-1"}"
  :geometry (geometry :x "50%"
                      :y "5%"
                      :width "420px"
                      :height "auto"
                      :anchor "top center")
  :stacking "overlay"
  :focusable true
  :exclusive false
  (quick-panel))
'';

  ewwScss = ''
$base: #1e1e2e;
$surface: rgba(49, 50, 68, 0.85);
$text: #cdd6f4;
$accent: #89b4fa;

* {
  font-family: "JetBrainsMono Nerd Font", sans-serif;
  color: $text;
}

window {
  background: transparent;
}

.quick-panel {
  background: rgba(30, 30, 46, 0.95);
  padding: 18px;
  border-radius: 16px;
  border: 1px solid rgba(203, 166, 247, 0.35);
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.55);
}

.panel-title {
  font-size: 18pt;
  font-weight: 600;
}

.metrics-row {
  spacing: 12px;
}

.metric-card {
  background: $surface;
  padding: 12px;
  border-radius: 12px;
  border: 1px solid rgba(68, 71, 90, 0.8);
  min-width: 180px;
}

.metric-title {
  font-size: 10pt;
  text-transform: uppercase;
  color: rgba(205, 214, 244, 0.7);
}

.metric-value {
  font-size: 20pt;
  font-weight: 700;
  margin: 6px 0;
}

.metric-buttons {
  spacing: 6px;
}

.metric-btn {
  background: rgba(137, 180, 250, 0.15);
  border: 1px solid rgba(137, 180, 250, 0.4);
  border-radius: 6px;
  padding: 4px 10px;
  font-size: 12pt;
}

.metric-btn:hover {
  background: rgba(137, 180, 250, 0.35);
}

.actions-grid {
  margin-top: 6px;
}

.quick-action {
  background: rgba(49, 50, 68, 0.65);
  border-radius: 12px;
  border: 1px solid rgba(68, 71, 90, 0.7);
  padding: 10px 14px;
  min-width: 180px;
}

.quick-action-inner {
  align-items: center;
}

.quick-action-label {
  font-size: 11pt;
}

.quick-action:hover {
  border-color: rgba(137, 180, 250, 0.7);
}
'';

  toggleScript = pkgs.writeShellScriptBin "toggle-quick-panel" ''
CFG="${config.home.homeDirectory}/.config/${ewwConfigDir}"
WINDOWS="$(${pkgs.eww}/bin/eww --config "$CFG" list-windows || true)"
if echo "$WINDOWS" | grep -qx quick-panel; then
  ${pkgs.eww}/bin/eww --config "$CFG" close quick-panel
else
  ${pkgs.eww}/bin/eww --config "$CFG" open quick-panel
fi
'';

  screenshotScript = pkgs.writeShellScriptBin "capture-region-to-clipboard" ''
grim -g "$(slurp)" - | wl-copy
'';

in {
  options.programs.eww-quick-panel.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;  # DEPRECATED: Feature 116 - Disabled by default, use eww-device-controls instead
    description = ''
      DEPRECATED: Enable Quick settings Eww panel.

      This module is superseded by programs.eww-device-controls which provides:
      - Hardware-adaptive controls (only shows available hardware)
      - Expandable top bar panels for volume, brightness, bluetooth, battery
      - Comprehensive Devices tab in monitoring panel (Alt+7)

      Migration: Set programs.eww-device-controls.enable = true instead.
    '';
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.eww toggleScript screenshotScript ];

    xdg.configFile."${ewwConfigDir}/eww.yuck".text = ewwYuck;
    xdg.configFile."${ewwConfigDir}/eww.scss".text = ewwScss;
    xdg.configFile."${ewwConfigDir}/assets/arin".source = arinAssets;
    xdg.configFile."${ewwConfigDir}/assets/dashboard".source = dashboardAssets;

    systemd.user.services.eww-quick-panel = {
      Unit = {
        Description = "Eww quick settings panel";
        After = [ "graphical-session.target" "sway-session.target" ];
        PartOf = [ "sway-session.target" ];
      };
      Service = {
        Type = "simple";
        # Pre-start: kill any orphan daemon for this config and clean stale socket
        ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.eww}/bin/eww --config ${ewwConfigPath} kill 2>/dev/null || true'";
        ExecStart = "${pkgs.eww}/bin/eww --config ${ewwConfigPath} daemon --no-daemonize";
        # Use 'eww kill' to properly terminate daemon (not just close windows)
        ExecStopPost = "${pkgs.eww}/bin/eww --config ${ewwConfigPath} kill 2>/dev/null || true";
        Restart = "on-failure";
        RestartSec = 2;
        # Kill all child processes when service stops
        KillMode = "control-group";
      };
      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}

{ config, lib, pkgs, osConfig ? null, ... }:

# Eww widget definitions (Yuck syntax) for top bar
# Feature 060: System metrics display with Catppuccin Mocha colors

let
  cfg = config.programs.eww-top-bar;

  # Catppuccin Mocha colors (imported from unified-bar-theme.nix via main module)
  mocha = {
    text = "#cdd6f4";
    subtext0 = "#a6adc8";
    blue = "#89b4fa";      # CPU
    sapphire = "#74c7ec";  # Memory
    sky = "#89dceb";       # Disk
    teal = "#94e2d5";      # Network
    peach = "#fab387";     # Temperature
    green = "#a6e3a1";     # Success
    red = "#f38ba8";       # Critical
  };

  # Script paths
  systemMetricsScript = "${config.xdg.configHome}/eww/eww-top-bar/scripts/system-metrics.py";
  hardwareDetectScript = "${config.xdg.configHome}/eww/eww-top-bar/scripts/hardware-detect.py";

  # Detect headless Sway configuration
  isHeadless = osConfig != null && (osConfig.networking.hostName or "") == "nixos-hetzner-sway";

  # Multi-monitor output configuration
  topBarOutputs =
    if isHeadless then [
      { name = "HEADLESS-1"; showTray = true; }
      { name = "HEADLESS-2"; showTray = false; }
      { name = "HEADLESS-3"; showTray = false; }
    ] else [
      { name = "eDP-1"; showTray = true; }
      { name = "HDMI-A-1"; showTray = false; }
    ];

  # Sanitize output names for Eww window IDs
  sanitizeOutputName = name:
    lib.toLower (lib.replaceStrings [" " ":" "/" "_" "-"] ["" "" "" "" ""] name);

in
''
;; Eww Top Bar - System Metrics Display
;; Feature 060: Catppuccin Mocha themed status bar

;; ============================================================================
;; Variables (defpoll for periodic updates)
;; ============================================================================

;; System metrics: CPU, memory, disk, network, temperature
;; Updates every ${toString cfg.updateIntervals.systemMetrics}s
(defpoll system_metrics
  :interval "${toString cfg.updateIntervals.systemMetrics}s"
  :initial '{"cpu_load":"0.00","mem_used_pct":"0","disk_used_pct":"0","net_rx_mbps":"0.0","net_tx_mbps":"0.0","temp_celsius":"0","temp_available":false}'
  `${pkgs.python3}/bin/python3 ${systemMetricsScript}`)

;; Date/time updates every ${toString cfg.updateIntervals.dateTime}s
(defpoll datetime
  :interval "${toString cfg.updateIntervals.dateTime}s"
  :initial "..."
  `${pkgs.coreutils}/bin/date '+%a %b %d  %H:%M:%S'`)

;; Volume monitoring (real-time via deflisten)
(deflisten volume
  :initial '{\"volume_pct\":\"0\",\"muted\":true}'
  `${pkgs.python3}/bin/python3 ${config.xdg.configHome}/eww/eww-top-bar/scripts/volume-monitor.py`)

;; Battery monitoring (real-time via deflisten)
(deflisten battery
  :initial '{\"percentage\":0,\"charging\":false,\"level\":\"unknown\"}'
  `${pkgs.python3}/bin/python3 ${config.xdg.configHome}/eww/eww-top-bar/scripts/battery-monitor.py`)

;; Bluetooth monitoring (real-time via deflisten)
(deflisten bluetooth
  :initial '{\"state\":\"disabled\",\"device_count\":0}'
  `${pkgs.python3}/bin/python3 ${config.xdg.configHome}/eww/eww-top-bar/scripts/bluetooth-monitor.py`)

;; Active i3pm project monitoring (polling via deflisten)
(deflisten active_project
  :initial '{\"project\":\"Global\",\"active\":false}'
  `${pkgs.python3}/bin/python3 ${config.xdg.configHome}/eww/eww-top-bar/scripts/active-project.py`)

;; Hardware capabilities (run once at startup)
(defpoll hardware
  :interval "0"
  :run-while false
  :initial '{"battery":false,"bluetooth":false,"thermal":false}'
  `${pkgs.python3}/bin/python3 ${hardwareDetectScript}`)

;; i3pm daemon health check (every ${toString cfg.updateIntervals.daemonHealth}s)
(defpoll daemon_health
  :interval "${toString cfg.updateIntervals.daemonHealth}s"
  :initial '{"status":"unknown","response_ms":0}'
  `${pkgs.bash}/bin/bash ${config.xdg.configHome}/eww/eww-top-bar/scripts/i3pm-health.sh`)

;; ============================================================================
;; Widgets
;; ============================================================================

;; CPU Load Average widget
(defwidget cpu-widget []
  (box :class "metric-block"
       :spacing 6
       (label :class "icon cpu-icon"
              :text "")
       (label :class "value cpu-value"
              :text {system_metrics.cpu_load ?: "0.00"})))

;; Memory Usage widget
(defwidget memory-widget []
  (box :class "metric-block"
       :spacing 6
       (label :class "icon memory-icon"
              :text "")
       (label :class "value memory-value"
              :text "''${system_metrics.mem_used_gb ?: '0.0'}G / ''${system_metrics.mem_total_gb ?: '0'}G (''${system_metrics.mem_used_pct ?: '0'}%)")))

;; Disk Usage widget
(defwidget disk-widget []
  (box :class "metric-block"
       :spacing 6
       (label :class "icon disk-icon"
              :text "")
       (label :class "value disk-value"
              :text "''${system_metrics.disk_used_gb ?: '0'}G / ''${system_metrics.disk_total_gb ?: '0'}G (''${system_metrics.disk_used_pct ?: '0'}%)")))

;; Network Traffic widget (with click handler to open network settings)
(defwidget network-widget []
  (eventbox :onclick "${pkgs.gnome.gnome-control-center}/bin/gnome-control-center wifi &"
    (box :class "metric-block"
         :spacing 6
         (label :class "icon network-icon"
                :text "")
         (label :class "value network-value"
                :text "↓''${system_metrics.net_rx_mbps ?: '0.0'} ↑''${system_metrics.net_tx_mbps ?: '0.0'} Mbps"))))

;; Temperature widget (conditional - only shown if thermal sensors available)
(defwidget temperature-widget []
  (box :class "metric-block"
       :spacing 6
       :visible {system_metrics.temp_available ?: false}
       (label :class "icon temp-icon"
              :text "")
       (label :class "value temp-value"
              :text "''${system_metrics.temp_celsius ?: '0'}°C")))

;; Date/Time widget (with click handler to open calendar)
(defwidget datetime-widget []
  (eventbox :onclick "${pkgs.gnome-calendar}/bin/gnome-calendar &"
    (box :class "metric-block"
         :spacing 6
         (label :class "icon datetime-icon"
                :text "")
         (label :class "value datetime-value"
                :text {datetime ?: "..."}))))

;; Volume widget (with click handler to open pavucontrol)
(defwidget volume-widget []
  (eventbox :onclick "${pkgs.pavucontrol}/bin/pavucontrol &"
    (box :class "metric-block"
         :spacing 6
         (label :class "icon volume-icon"
                :text {volume.muted ? "" : ""})
         (label :class "value volume-value"
                :text "''${volume.volume_pct ?: '0'}%"))))

;; Battery widget (conditional - only shown if battery hardware present)
(defwidget battery-widget []
  (box :class "metric-block"
       :spacing 6
       :visible {hardware.battery ?: false}
       (label :class {battery.level == "critical" ? "icon battery-icon battery-critical" :
                      battery.level == "low" ? "icon battery-icon battery-low" :
                      "icon battery-icon battery-normal"}
              :text {battery.charging ? "" : ""})
       (label :class "value battery-value"
              :text "''${battery.percentage ?: '0'}%")))

;; Bluetooth widget (conditional - only shown if bluetooth hardware present, with click handler)
(defwidget bluetooth-widget []
  (eventbox :onclick "${pkgs.blueman}/bin/blueman-manager &"
    (box :class "metric-block"
         :spacing 6
         :visible {hardware.bluetooth ?: false}
         (label :class {bluetooth.state == "connected" ? "icon bluetooth-icon bluetooth-connected" :
                        bluetooth.state == "enabled" ? "icon bluetooth-icon bluetooth-enabled" :
                        "icon bluetooth-icon bluetooth-disabled"}
                :text {bluetooth.state == "connected" ? "" : ""})
         (label :class "value bluetooth-value"
                :text {bluetooth.device_count > 0 ? "''${bluetooth.device_count ?: '0'}" : ""}))))

;; Active Project widget (with click handler to open project switcher)
(defwidget project-widget []
  (eventbox :onclick "${pkgs.i3pm-deno}/bin/i3pm project switch &"
    (box :class "metric-block"
         :spacing 6
         (label :class "icon project-icon"
                :text "")
         (label :class "value project-value"
                :text {active_project.project ?: "Global"}))))

;; Daemon Health widget (with click handler to open diagnostics)
(defwidget daemon-health-widget []
  (eventbox :onclick "${pkgs.ghostty}/bin/ghostty -e ${pkgs.i3pm-deno}/bin/i3pm diagnose health &"
    (box :class "metric-block"
         :spacing 6
         (label :class {daemon_health.status == "healthy" ? "icon daemon-icon daemon-healthy" :
                        daemon_health.status == "slow" ? "icon daemon-icon daemon-slow" :
                        "icon daemon-icon daemon-unhealthy"}
                :text {daemon_health.status == "healthy" ? "✓" :
                       daemon_health.status == "slow" ? "⚠" :
                       "❌"})
         (label :class "value daemon-value"
                :text "''${daemon_health.response_ms ?: '0'}ms"))))

;; Separator between blocks
(defwidget separator []
  (label :class "separator"
         :text "|"))

;; Main bar layout (horizontal)
(defwidget main-bar []
  (centerbox :class "top-bar"
    ;; Left: System metrics
    (box :class "left-block"
         :halign "start"
         :spacing 12
         (cpu-widget)
         (separator)
         (memory-widget)
         (separator)
         (disk-widget)
         (separator)
         (network-widget)
         (separator)
         (temperature-widget)
         (separator)
         (volume-widget))

    ;; Center: Active Project and Daemon Health
    (box :class "center-block"
         :halign "center"
         :spacing 12
         (project-widget)
         (separator)
         (daemon-health-widget))

    ;; Right: Hardware status and Date/Time
    (box :class "right-block"
         :halign "end"
         :spacing 12
         (battery-widget)
         (separator)
         (bluetooth-widget)
         (separator)
         (datetime-widget))))

;; ============================================================================
;; Windows (per-monitor instances)
;; ============================================================================

'' + (lib.concatMapStringsSep "\n" (output: ''
(defwindow top-bar-${sanitizeOutputName output.name}
  :monitor "${output.name}"
  :geometry (geometry
    :x "0px"
    :y "0px"
    :width "100%"
    :height "32px"
    :anchor "top center")
  :stacking "fg"
  :exclusive true
  :focusable false
  :namespace "eww-top-bar"
  :reserve (struts :distance "36px" :side "top")
  :windowtype "dock"
  (main-bar))
'') topBarOutputs)

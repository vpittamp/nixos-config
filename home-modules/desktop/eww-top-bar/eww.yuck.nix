{ config, lib, pkgs, topBarOutputs ? [], sanitizeOutputName ? (x: x), ... }:

# Feature 061: Eww Top Bar - Enhanced widget definitions
# Adds: System tray, WiFi widget, enhanced volume control with popup
# Now with dynamic monitor-based window generation (fixes Hetzner/M1 mismatch)

let
  # Generate Eww window definition for a monitor
  mkWindowDef = output: let
    windowId = sanitizeOutputName output.name;
    isPrimary = output.showTray;
  in ''
    ;; ${output.name} display (${if isPrimary then "primary" else "secondary"})
    (defwindow top-bar-${windowId}
      :monitor "${output.name}"
      :geometry (geometry
        :x "0px"
        :y "0px"
        :width "100%"
        :height "26px"
        :anchor "top center")
      :stacking "fg"
      :exclusive true
      :focusable false
      :namespace "eww-top-bar"
      :reserve (struts :distance "30px" :side "top")
      :windowtype "dock"
      (main-bar :is_primary ${if isPrimary then "true" else "false"}))
  '';

  # Only add fallback window when no generated output covers eDP-1
  hasEDP1 = builtins.any (o: o.name == "eDP-1") topBarOutputs;
  fallbackWindow = lib.optionalString (!hasEDP1) ''
;; Fallback primary window
(defwindow top-bar-edp1
  :monitor "eDP-1"
  :geometry (geometry
    :x "0px"
    :y "0px"
    :width "100%"
    :height "26px"
    :anchor "top center")
  :stacking "fg"
  :exclusive true
  :focusable false
  :namespace "eww-top-bar"
  :reserve (struts :distance "30px" :side "top")
  :windowtype "dock"
  (main-bar :is_primary true))
'';

  # Generate volume popup window for first monitor
  firstMonitor = if topBarOutputs != [] then (builtins.head topBarOutputs).name else "eDP-1";
in
''
;; Eww Top Bar - System Metrics Display
;; Feature 060: Core functionality
;; Feature 061: Added system tray, WiFi, volume popup, calendar

;; ============================================================================
;; Variables (defpoll for periodic updates)
;; ============================================================================

;; System metrics: CPU, memory, disk, network, temperature
;; Updates every 2s
(defpoll system_metrics
  :interval "2s"
  :initial '{"cpu_load":"0.00","mem_used_pct":"0","mem_used_gb":"0.0","mem_total_gb":"0","disk_used_pct":"0","disk_used_gb":"0","disk_total_gb":"0","net_rx_mbps":"0.0","net_tx_mbps":"0.0","temp_celsius":"0","temp_available":false}'
  `python3 ~/.config/eww/eww-top-bar/scripts/system-metrics.py`)

;; Date/time updates every 1s (12-hour format)
(defpoll datetime
  :interval "1s"
  :initial "..."
  `date '+%a %b %d | %I:%M:%S %p'`)

;; Feature 061: WiFi status monitoring (US2)
(defpoll wifi_status
  :interval "2s"
  :initial '{"connected":false,"ssid":null,"signal":null,"color":"#6c7086","icon":""}'
  `bash ~/.config/eww/eww-top-bar/scripts/wifi-status.sh`)

;; Feature 061: Volume status monitoring (US3)
(defpoll volume_status
  :interval "2s"
  :initial '{"volume":0,"muted":false,"icon":"🔇"}'
  `bash ~/.config/eww/eww-top-bar/scripts/volume-status.sh`)

;; Volume monitoring (real-time via deflisten) - kept for compatibility
(deflisten volume
  :initial '{\"volume_pct\":\"0\",\"muted\":true}'
  `python3 ~/.config/eww/eww-top-bar/scripts/volume-monitor.py`)

;; Battery monitoring (real-time via deflisten)
(deflisten battery
  :initial '{\"percentage\":0,\"charging\":false,\"level\":\"unknown\"}'
  `python3 ~/.config/eww/eww-top-bar/scripts/battery-monitor.py`)

;; Bluetooth monitoring (real-time via deflisten)
(deflisten bluetooth
  :initial '{\"state\":\"disabled\",\"device_count\":0}'
  `python3 ~/.config/eww/eww-top-bar/scripts/bluetooth-monitor.py`)

;; Active i3pm project monitoring (polling via deflisten)
(deflisten active_project
  :initial '{\"project\":\"Global\",\"active\":false}'
  `python3 ~/.config/eww/eww-top-bar/scripts/active-project.py`)

;; Hardware capabilities (run once at startup)
(defpoll hardware
  :interval "0"
  :run-while false
  :initial '{"battery":false,"bluetooth":false,"thermal":false}'
  `python3 ~/.config/eww/eww-top-bar/scripts/hardware-detect.py`)

;; Build health poll - uses nixos-build-status for OS & HM generations / errors
(defpoll build_health
  :interval "10s"
  :initial '{"status":"unknown","os_generation":"--","hm_generation":"--","error_count":0,"details":"..."}'
  `bash ~/.config/eww/eww-top-bar/scripts/build-health.sh`)

;; Interactions / popups
(defvar volume_popup_visible false)
(defvar show_wifi_details false)
(defvar show_volume_peek false)
(defvar show_metrics false)

;; ============================================================================
;; Widgets
;; ============================================================================

;; CPU Load Average widget (pill-style)
(defwidget cpu-widget []
  (box :class "pill metric-pill cpu"
       :spacing 2
       :tooltip "CPU load (1m average)"
       (label :class "icon cpu-icon" :text "")
       (label :class "value" :text {system_metrics.cpu_load ?: "0.00"})))

;; Memory Usage widget
(defwidget memory-widget []
  (box :class "pill metric-pill mem"
       :spacing 2
       :tooltip "Memory in use"
        (label :class "icon mem-icon"
               :text "")
       (label :class "value mem-value"
              :text "''${system_metrics.mem_used_pct ?: 0}%")))

;; Disk Usage widget
(defwidget disk-widget []
  (box :class "pill metric-pill disk"
       :spacing 2
       :tooltip "Root disk usage"
        (label :class "icon disk-icon"
               :text "")
       (label :class "value disk-value"
              :text "''${system_metrics.disk_used_pct ?: 0}%")))

;; Temperature widget (conditional)
(defwidget temperature-widget []
  (box :class "pill metric-pill temp"
       :spacing 2
       :visible {system_metrics.temp_available ?: false}
       :tooltip "Average CPU temperature"
        (label :class "icon temp-icon"
               :text "")
       (label :class "value temp-value"
              :text "''${system_metrics.temp_celsius ?: 0}°C")))

;; Network Traffic widget (with click handler to open network settings)
(defwidget network-widget []
  (eventbox :onclick "nm-connection-editor &"
    (box :class "pill metric-pill net"
         :spacing 2
         :tooltip "Network throughput (Mbps)"
         (label :class "icon network-icon" :text "")
         (label :class "value network-value"
                :text "↓''${system_metrics.net_rx_mbps ?: '0.0'} ↑''${system_metrics.net_tx_mbps ?: '0.0'}"))))

;; WiFi widget (icon + hover reveal strength bar)
(defwidget wifi-widget []
  (eventbox :onclick "nm-connection-editor &"
            :onhover "eww update show_wifi_details=true"
            :onhoverlost "eww update show_wifi_details=false"
    (box :class {wifi_status.connected ? "pill metric-pill wifi" : "pill metric-pill wifi wifi-disconnected"}
         :spacing 2
         :tooltip {wifi_status.connected ? (wifi_status.ssid ?: "WiFi") : "Not connected"}
         (label :class "icon wifi-icon"
                :style "color: ''${wifi_status.color ?: '#6c7086'}"
                :text "")
         (label :class "value wifi-value"
                :text {wifi_status.connected ? "''${wifi_status.signal ?: 0}%" : "--"}))))

;; Date/Time widget
(defwidget datetime-widget []
  (eventbox :onclick "gnome-calendar &"
    (box :class "pill time-pill"
         :spacing 3
         (label :class "icon time-icon"
                :text "")
         (label :class "value time-value"
                :text {datetime}))))

;; Volume widget (icon + hover slider)
(defwidget volume-widget-enhanced []
  (eventbox :onclick ""
            :onhover "eww update show_volume_peek=true"
            :onhoverlost "eww update show_volume_peek=false"
    (box :class "pill metric-pill volume"
         :spacing 2
         :tooltip "Volume"
         (label :class "icon volume-icon"
                :text {volume_status.icon ?: "🔇"})
         (label :class "value volume-value"
                :text "''${volume_status.volume ?: 0}%")
         (revealer :transition "slideleft"
                   :reveal show_volume_peek
                   (scale :class "meter meter-volume"
                          :min 0
                          :max 100
                          :value {volume_status.volume ?: 0})))))

;; Legacy volume widget (kept for compatibility)
(defwidget volume-widget []
  (eventbox :onclick "pavucontrol &"
    (box :class "pill metric-pill volume"
         :spacing 2
         (label :class "icon volume-icon"
                :text {volume.muted ? "" : ""})
         (scale :class "meter meter-volume"
                :min 0
                :max 100
                :value {volume.volume_pct ?: 0}))))

;; Battery widget (conditional - only shown if battery hardware present)
(defwidget battery-widget []
  (box :class "pill metric-pill battery"
       :spacing 3
       :tooltip "Battery status"
       (label :class {battery.level == "critical" ? "icon battery-icon battery-critical" :
                      battery.level == "low" ? "icon battery-icon battery-low" :
                      "icon battery-icon battery-normal"}
              :text {battery.charging ? "" : ""})
       (scale :class "meter meter-battery"
              :min 0
              :max 100
              :value {battery.percentage ?: 0})
       (label :class "value battery-value"
              :text "''${battery.percentage ?: '0'}%")))

;; Bluetooth widget (conditional - only shown if bluetooth hardware present, with click handler)
(defwidget bluetooth-widget []
  (eventbox :onclick "blueman-manager &"
    (box :class {bluetooth.state == "connected" ? "pill metric-pill bluetooth bluetooth-connected" :
                 bluetooth.state == "enabled" ? "pill metric-pill bluetooth bluetooth-enabled" :
                 "pill metric-pill bluetooth bluetooth-disabled"}
         :spacing 3
         :visible {hardware.bluetooth ?: false}
         :tooltip {bluetooth.state == "connected"
                    ? "Bluetooth: ''${bluetooth.device_count ?: 0} device(s) connected"
                    : bluetooth.state == "enabled" ? "Bluetooth: on, not connected"
                    : "Bluetooth: off"}
         (label :class "icon bluetooth-icon" :text "")
         (label :class "value bluetooth-count"
                :visible {bluetooth.device_count > 0}
                :text "''${bluetooth.device_count ?: 0}"))))

;; Active Project widget (with click handler to open project switcher)
;; Feature 079: US7 - T052/T053 - Enhanced with icon and branch number
(defwidget project-widget []
  (eventbox :onclick "i3pm project switch &"
    (box :class {active_project.is_worktree == true ? "pill project-pill-worktree" : "pill project-pill"}
         :spacing 2
         ;; T052: Project icon from metadata
         (label :class "icon project-icon"
                :text {active_project.icon ?: ""})
         (label :class "value project-value"
                :text {active_project.formatted_label ?: "Global"}))))

;; Build health widget (shows generations + status)
(defwidget build-health-widget []
  (eventbox :onclick "nixos-build-status --verbose | less"
    (box :class "pill metric-pill build-health"
         :spacing 3
         (label :class {build_health.status == "healthy" ? "icon health-icon health-healthy" :
                        build_health.status == "warning" ? "icon health-icon health-warning" :
                        "icon health-icon health-error"}
                :text "●")
         (label :class "value health-os"
                :text {build_health.os_generation ?: "--"})
         (label :class "value health-hm"
                :text {build_health.hm_generation ?: "--"})
         (label :class "value health-status"
                :text {build_health.status ?: "unknown"}))))

;; Separator between blocks
;; Visual separator between widget groups
(defwidget separator []
  (label :class "separator"
         :text "│"))

;; Feature 061: System Tray widget (US1) - conditional on is_primary
(defwidget systray-widget [is_primary]
  (box :class "metric-block"
       :visible is_primary
       (systray :spacing 4
                :icon-size 14
                :orientation "horizontal"
                :prepend-new false)))

;; Main bar layout - upgraded pill layout with reveals/hover states

(defwidget main-bar [is_primary]
  (centerbox :orientation "h"
             :class "bar"
    ;; Left: Collapsible system metrics (click or hover to open); build health always visible
    (eventbox :onhover "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update show_metrics=true"
              :onhoverlost "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update show_metrics=false"
      (box :class "left"
           :orientation "h"
           :space-evenly false
           :halign "start"
           :spacing 3
           ;; Compact trigger keeps footprint small when collapsed
           (eventbox
             :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update show_metrics=$( [ $(${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar get show_metrics) = true ] && echo false || echo true )"
             (button :class "pill compact-trigger"
                     :tooltip "Click to toggle system metrics"
                     (label :class "icon compact-icon" :text "")))
           ;; Expandable metrics
           (revealer :class "metrics-revealer"
                     :transition "slideleft"
                     :reveal show_metrics
             (box :class "metrics-expanded"
                  :orientation "h"
                  :space-evenly false
                  :halign "start"
                  :spacing 3
                  (cpu-widget)
                  (memory-widget)
                  (disk-widget)
                  (temperature-widget)
                  (network-widget)
                  (wifi-widget)))

           ;; Always-visible controls
           (volume-widget-enhanced)
           (battery-widget)
           (bluetooth-widget)

           ;; Health widget stays visible with text
           (build-health-widget)))

    ;; Center: Active Project
    (box :class "center"
         :orientation "h"
         :space-evenly false
         :halign "center"
         :spacing 4
         (project-widget))

    ;; Right: Date/Time and System Tray
    (box :class "right"
         :orientation "h"
         :space-evenly false
         :halign "end"
         :spacing 4
          (datetime-widget)
          (systray-widget :is_primary is_primary))))

;; ============================================================================
;; Windows (per-monitor instances)
;; Generated dynamically based on detected monitors (Hetzner: HEADLESS-*, M1: eDP-1/HDMI-A-1)
;; ============================================================================

${lib.concatMapStrings mkWindowDef topBarOutputs}
${fallbackWindow}

''

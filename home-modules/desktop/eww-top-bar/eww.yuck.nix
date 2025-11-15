{ config, lib, pkgs, ... }:

# Feature 061: Eww Top Bar - Enhanced widget definitions
# Adds: System tray, WiFi widget, enhanced volume control with popup

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
  :initial '{"cpu_load":"0.00","mem_used_pct":"0","disk_used_pct":"0","net_rx_mbps":"0.0","net_tx_mbps":"0.0","temp_celsius":"0","temp_available":false}'
  `python3 ~/.config/eww/eww-top-bar/scripts/system-metrics.py`)

;; Date/time updates every 1s
(defpoll datetime
  :interval "1s"
  :initial "..."
  `date '+%a %b %d | %H:%M:%S'`)

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

;; Feature 061: i3pm daemon health check - FIXED exit code 0 (US6)
(defpoll daemon_health
  :interval "5s"
  :initial '{"status":"unknown","response_ms":0}'
  `bash ~/.config/eww/eww-top-bar/scripts/i3pm-health.sh`)

;; Feature 061: Volume popup visibility state (US3)
(defvar volume_popup_visible false)

;; ============================================================================
;; Widgets
;; ============================================================================

;; CPU Load Average widget
(defwidget cpu-widget []
  (box :class "metric-block"
       :spacing 4
       (label :class "icon cpu-icon"
              :text "")
       (label :class "value cpu-value"
              :text {system_metrics.cpu_load ?: "0.00"})))

;; Memory Usage widget (compact - percentage only)
(defwidget memory-widget []
  (box :class "metric-block"
       :spacing 4
       (label :class "icon memory-icon"
              :text "")
       (label :class "value memory-value"
              :text "''${system_metrics.mem_used_pct ?: '0'}%")))

;; Disk Usage widget (compact - percentage only)
(defwidget disk-widget []
  (box :class "metric-block"
       :spacing 4
       (label :class "icon disk-icon"
              :text "")
       (label :class "value disk-value"
              :text "''${system_metrics.disk_used_pct ?: '0'}%")))

;; Network Traffic widget (with click handler to open network settings)
(defwidget network-widget []
  (eventbox :onclick "nm-connection-editor &"
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

;; Feature 061: WiFi widget (US2 - compact)
(defwidget wifi-widget []
  (eventbox :onclick "nm-connection-editor &"
    (box :class "metric-block wifi-widget"
         :spacing 4
         (label :class {wifi_status.connected ? "icon wifi-icon signal-strong" : "icon wifi-icon disconnected"}
                :style "color: ''${wifi_status.color ?: '#6c7086'}"
                :text {wifi_status.icon ?: ""})
         (label :class "value wifi-value"
                :visible {wifi_status.connected ?: false}
                :text "''${wifi_status.ssid ?: 'N/A'}"))))

;; Date/Time widget (with click handler to open calendar)
(defwidget datetime-widget []
  (eventbox :onclick "gnome-calendar &"
    (box :class "metric-block"
         :spacing 4
         (label :class "icon datetime-icon"
                :text "")
         (label :class "value datetime-value"
                :text {datetime ?: "..."}))))

;; Feature 061: Enhanced Volume widget with popup (US3)
(defwidget volume-widget-enhanced []
  (eventbox :onclick "eww update volume_popup_visible=''${!volume_popup_visible}"
    (box :class "metric-block volume-widget"
         :spacing 4
         (label :class "icon volume-icon"
                :text {volume_status.icon ?: "🔇"})
         (label :class "value volume-value"
                :text "''${volume_status.volume ?: '0'}%"))))

;; Legacy volume widget (kept for compatibility)
(defwidget volume-widget []
  (eventbox :onclick "pavucontrol &"
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
  (eventbox :onclick "blueman-manager &"
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
  (eventbox :onclick "i3pm project switch &"
    (box :class "metric-block"
         :spacing 6
         (label :class "icon project-icon"
                :text "")
         (label :class "value project-value"
                :text {active_project.project ?: "Global"}))))

;; Daemon Health widget (with click handler to open diagnostics)
(defwidget daemon-health-widget []
  (eventbox :onclick "ghostty -e i3pm diagnose health &"
    (box :class "metric-block daemon-health"
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

;; Feature 061: System Tray widget (US1) - conditional on is_primary
(defwidget systray-widget [is_primary]
  (box :class "metric-block"
       :visible is_primary
       (systray :spacing 4
                :icon-size 16
                :orientation "horizontal"
                :prepend-new false)))

;; Feature 061: Volume popup with slider (US3)
(defwidget volume-popup-content []
  (box :class "volume-popup"
       :orientation "v"
       :spacing 8
    (box :class "volume-slider"
         :orientation "v"
         (scale :min 0
                :max 100
                :value {volume_status.volume ?: 0}
                :timeout "100ms"
                :onchange "wpctl set-volume @DEFAULT_AUDIO_SINK@ {}% || pactl set-sink-volume @DEFAULT_SINK@ {}%"))
    (button :class "volume-mute-button"
            :onclick "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle || pactl set-sink-mute @DEFAULT_SINK@ toggle"
            {volume_status.muted ? "Unmute" : "Mute"})))

;; Main bar layout (horizontal) - with is_primary parameter
(defwidget main-bar [is_primary]
  (centerbox :class "top-bar"
    ;; Left: System metrics (compact)
    (box :class "left-block"
         :halign "start"
         :spacing 4
         (cpu-widget)
         (separator)
         (memory-widget)
         (separator)
         (disk-widget)
         (separator)
         (wifi-widget)
         (separator)
         (volume-widget-enhanced))

    ;; Center: Active Project and Daemon Health
    (box :class "center-block"
         :halign "center"
         :spacing 8
         (project-widget)
         (separator)
         (daemon-health-widget))

    ;; Right: Hardware status, Date/Time, and System Tray
    (box :class "right-block"
         :halign "end"
         :spacing 4
         (battery-widget)
         (separator)
         (bluetooth-widget)
         (separator)
         (datetime-widget)
         (separator)
         (systray-widget :is_primary is_primary))))

;; ============================================================================
;; Windows (per-monitor instances)
;; ============================================================================

;; Built-in display (primary)
(defwindow top-bar-edp1
  :monitor "eDP-1"
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
  (main-bar :is_primary true))

;; External display (secondary)
(defwindow top-bar-hdmia1
  :monitor "HDMI-A-1"
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
  (main-bar :is_primary false))

;; Feature 061: Volume popup window (US3)
(defwindow volume-popup
  :monitor "eDP-1"
  :geometry (geometry
    :anchor "top right"
    :x "-10px"
    :y "40px")
  :stacking "overlay"
  :focusable true
  :namespace "eww-volume-popup"
  (revealer :transition "slidedown"
            :reveal volume_popup_visible
            :duration "200ms"
    (volume-popup-content)))
''

{ config, lib, pkgs, topBarOutputs ? [], sanitizeOutputName ? (x: x), topbarSpinnerScript ? null, topbarSpinnerOpacityScript ? null, isLaptop ? false, ... }:

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
	      (main-bar
	        :is_primary ${if isPrimary then "true" else "false"}
	        :monitor_id "${windowId}"))
	  '';

  # Generate Powermenu overlay window definition for a monitor
  mkPowermenuWindowDef = output: let
    windowId = sanitizeOutputName output.name;
  in ''
    ;; Powermenu overlay (${output.name})
    (defwindow powermenu-${windowId}
      :monitor "${output.name}"
      :geometry (geometry
        :anchor "top left"
        :x "0px"
        :y "0px"
        :width "100%"
        :height "100%")
      :stacking "overlay"
      :exclusive false
      :focusable "ondemand"
      :namespace "eww-top-bar"
      :windowtype "dialog"
      (powermenu-overlay))
  '';

  # Generate badge shelf overlay window definition for a monitor
  mkBadgeShelfWindowDef = output: let
    windowId = sanitizeOutputName output.name;
  in ''
    ;; Badge shelf overlay (${output.name})
    (defwindow badge-shelf-${windowId}
      :monitor "${output.name}"
      :geometry (geometry
        :anchor "top center"
        :x "0px"
        :y "25px"
        :width "100%"
        :height "44px")
      :stacking "overlay"
      :exclusive false
      :focusable "ondemand"
      :namespace "eww-top-bar"
      :windowtype "dialog"
      (badge-shelf-window :monitor_id "${windowId}"))
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
  (main-bar :is_primary true :monitor_id "edp1"))
'';

  fallbackPowermenuWindow = lib.optionalString (!hasEDP1) ''
;; Fallback powermenu overlay window (eDP-1)
(defwindow powermenu-edp1
  :monitor "eDP-1"
  :geometry (geometry
    :anchor "top left"
    :x "0px"
    :y "0px"
    :width "100%"
    :height "100%")
  :stacking "overlay"
  :exclusive false
  :focusable "ondemand"
  :namespace "eww-top-bar"
  :windowtype "dialog"
  (powermenu-overlay))
'';

  fallbackBadgeShelfWindow = lib.optionalString (!hasEDP1) ''
;; Fallback badge shelf overlay window (eDP-1)
(defwindow badge-shelf-edp1
  :monitor "eDP-1"
  :geometry (geometry
    :anchor "top center"
    :x "0px"
    :y "25px"
    :width "100%"
    :height "44px")
  :stacking "overlay"
  :exclusive false
  :focusable "ondemand"
  :namespace "eww-top-bar"
  :windowtype "dialog"
  (badge-shelf-window :monitor_id "edp1"))
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

${if isLaptop then ''
;; Brightness status monitoring (laptop only)
;; Uses device-backend.py from eww-device-controls module
(defpoll brightness_state
  :interval "2s"
  :initial '{"display":50,"keyboard":null,"error":false}'
  `~/.config/eww/eww-device-controls/scripts/device-backend.py --mode brightness 2>/dev/null || echo '{"display":50,"keyboard":null,"error":true}'`)
'' else ""}

;; Volume monitoring (real-time via deflisten) - kept for compatibility
(deflisten volume
  :initial '{\"volume_pct\":\"0\",\"muted\":true}'
  `python3 ~/.config/eww/eww-top-bar/scripts/volume-monitor.py`)

;; Battery monitoring (real-time via deflisten)
(deflisten battery
  :initial '{\"percentage\":0,\"charging\":false,\"level\":\"unknown\",\"time_remaining\":0,\"time_formatted\":\"--\",\"energy_rate\":0,\"energy\":0,\"energy_full\":0}'
  `python3 ~/.config/eww/eww-top-bar/scripts/battery-monitor.py`)

;; Bluetooth monitoring (real-time via deflisten)
(deflisten bluetooth
  :initial '{\"state\":\"disabled\",\"device_count\":0}'
  `python3 ~/.config/eww/eww-top-bar/scripts/bluetooth-monitor.py`)

;; Feature 110: Notification data (real-time via deflisten)
;; Streams count, dnd, visible status from SwayNC for badge display
(deflisten notification_data
  :initial '{\"count\":0,\"dnd\":false,\"visible\":false,\"inhibited\":false,\"has_unread\":false,\"display_count\":\"0\",\"error\":false}'
  `python3 ~/.config/eww/eww-top-bar/scripts/notification-monitor.py`)

;; Active outputs (poll swaymsg) - controls and reflects monitor state
(defpoll active_outputs
  :interval "2s"
  ;; Include a per-output map so the monitor pills render meaningful defaults
  :initial '{"active":[],"enabled":[],"all":[],"active_count":0,"map":{"HEADLESS-1":false,"HEADLESS-2":false,"HEADLESS-3":false}}'
  `/run/current-system/sw/bin/bash -lc '$HOME/.config/eww/eww-top-bar/scripts/active-outputs-status.sh'`)

;; Feature 083: Event-driven monitor state (pushed via eww update, <100ms latency)
;; This replaces polling for profile switches - daemon pushes updates immediately
(defvar monitor_state '{"profile_name":"unknown","outputs":[]}')

;; Active i3pm project monitoring (polling via deflisten)
(deflisten active_project
  :initial '{\"project\":\"Global\",\"active\":false}'
  `python3 ~/.config/eww/eww-top-bar/scripts/active-project.py`)

;; Hardware capabilities (run once at startup)
;; Uses timeout to prevent hanging if D-Bus or other checks are slow
(defpoll hardware
  :interval "0"
  :run-while false
  :initial '{"battery":false,"bluetooth":false,"thermal":false}'
  `timeout 5s python3 ~/.config/eww/eww-top-bar/scripts/hardware-detect.py || echo '{"battery":false,"bluetooth":false,"thermal":false}'`)

;; Build health poll - uses nixos-build-status for OS & HM generations / errors
;; Feature 123: Increased from 10s to 30s (build status rarely changes, saves ~1.5s/cycle)
(defpoll build_health
  :interval "30s"
  :initial '{"status":"unknown","os_generation":"--","hm_generation":"--","error_count":0,"details":"..."}'
  `bash ~/.config/eww/eww-top-bar/scripts/build-health.sh`)

;; Monitoring panel visibility status (Feature 085)
;; Increased to 3s to reduce process spawning overhead
(defpoll monitoring_panel_visible
  :interval "3s"
  :initial "false"
  `bash -c '${pkgs.systemd}/bin/systemctl --user is-active --quiet eww-monitoring-panel.service && echo true || echo false'`)

;; Feature 110: Notification center visibility now provided by notification_data.visible
;; (deflisten via notification-monitor.py replaces the old polling approach)

;; Feature 123: AI sessions data via OpenTelemetry
;; Feature 136: DISABLED - AI indicators moved to monitoring panel only
;; Uses deflisten to consume JSON stream from otel-ai-monitor service (event-driven, no polling)
;; Falls back to error state (visible in UI) if pipe doesn't exist - avoids silent failures
;; (deflisten ai_sessions_data
;;   :initial '{"type":"session_list","sessions":[],"timestamp":0}'
;;   `cat $XDG_RUNTIME_DIR/otel-ai-monitor.pipe 2>/dev/null || echo '{"type":"error","error":"pipe_missing","sessions":[],"timestamp":0}'`)

;; Feature 123: Pulsating circle for working AI sessions
;; Feature 136: DISABLED - AI indicators moved to monitoring panel only
;; Static circle character - animation via opacity only (saves 1 defpoll)
;; (defpoll topbar_spinner_frame
;;   :interval "10s"
;;   :run-while false
;;   :initial "⬤"
;;   `echo "⬤"`)

;; Feature 123: Opacity for pulsating fade effect
;; Feature 136: DISABLED - AI indicators moved to monitoring panel only
;; Cycles: 0.4 → 0.6 → 0.8 → 1.0 → 1.0 → 0.8 → 0.6 → 0.4
;; (defpoll topbar_spinner_opacity
;;   :interval "120ms"
;;   :run-while {ai_sessions_data.has_working ?: false}
;;   :initial "1.0"
;;   `${topbarSpinnerOpacityScript}/bin/eww-topbar-spinner-opacity`)

;; Interactions / popups
(defvar show_volume_peek false)
(defvar show_brightness_peek false)
(defvar powermenu_confirm_action "")

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

;; WiFi widget (click to open network settings)
(defwidget wifi-widget []
  (eventbox :onclick "nm-connection-editor &"
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
            :onhover "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update show_volume_peek=true"
            :onhoverlost "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update show_volume_peek=false"
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

${if isLaptop then ''
;; Brightness widget (laptop only - requires backlight hardware)
;; Icon + hover reveal slider, scroll to adjust
(defwidget brightness-widget []
  (eventbox :onclick ""
            :onhover "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update show_brightness_peek=true"
            :onhoverlost "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update show_brightness_peek=false"
            :onscroll "~/.config/eww/eww-device-controls/scripts/brightness-control.sh {}"
    (box :class "pill metric-pill brightness"
         :spacing 2
         :tooltip "Brightness: ''${brightness_state.display ?: 50}%"
         (label :class "icon brightness-icon"
                :text "󰃟")
         (label :class "value brightness-value"
                :text "''${brightness_state.display ?: 50}%")
         (revealer :transition "slideleft"
                   :reveal show_brightness_peek
           (scale :class "meter meter-brightness"
                  :min 5
                  :max 100
                  :value {brightness_state.display ?: 50}
                  :onchange "~/.config/eww/eww-device-controls/scripts/brightness-control.sh set {}")))))
'' else ""}

;; Battery widget (conditional - only shown if battery hardware present)
(defwidget battery-widget []
  (box :class "pill metric-pill battery"
       :spacing 3
       :visible {hardware.battery ?: false}
       :tooltip {battery.charging
                  ? "Charging: ''${battery.percentage ?: 0}% (''${battery.time_formatted ?: '--'} to full)"
                  : "Battery: ''${battery.percentage ?: 0}% (''${battery.time_formatted ?: '--'} remaining)"}
       (label :class {battery.level == "critical" ? "icon battery-icon battery-icon-critical" :
                      battery.level == "very_low" ? "icon battery-icon battery-icon-very-low" :
                      battery.level == "low" ? "icon battery-icon battery-icon-low" :
                      "icon battery-icon"}
              :text {battery.charging ? "" : ""})
       (scale :class "meter meter-battery"
              :min 0
              :max 100
              :value {battery.percentage ?: 0})
       (label :class "value battery-value"
              :text "''${battery.percentage ?: '0'}%")
       ;; Time remaining (compact display)
       (label :class "value battery-time"
              :text {battery.time_formatted ?: "--"})))

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
  (eventbox :onclick "swaymsg mode '→ WS' && i3pm-workspace-mode char ':' &"
            :tooltip {(active_project.remote_enabled ?: false)
                      ? ((active_project.formatted_label ?: "Global") + "\nSSH: " + (active_project.remote_target ?: "") +
                         ((active_project.remote_directory_display ?: "") != "" ? "\n" + (active_project.remote_directory_display ?: "") : ""))
                      : (active_project.formatted_label ?: "Global")}
    (box :class {(active_project.is_worktree == true ? "pill project-pill-worktree" : "pill project-pill") + ((active_project.remote_enabled ?: false) ? " project-pill-ssh" : "")}
         :spacing 2
         ;; T052: Project icon from metadata
         (label :class "icon project-icon"
                :text {active_project.icon ?: ""})
         (label :class "project-ssh-indicator"
                :visible {active_project.remote_enabled ?: false}
                :text "󰣀 SSH")
         (label :class "project-ssh-target"
                :visible {active_project.remote_enabled ?: false}
                :limit-width 16
                :truncate true
                :text {active_project.remote_target_short ?: active_project.remote_target ?: ""})
         ;; Truncate long project names to prevent top bar overflow
         (label :class "value project-value"
                :limit-width 30
                :truncate true
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

;; Compact build health indicator for always-on top bar view
(defwidget build-health-dot-widget [monitor_id]
  (eventbox :onclick {"toggle-topbar-badge-shelf toggle " + monitor_id + " &"}
    (box :class {build_health.status == "healthy" ? "pill metric-pill health-dot-pill health-dot-healthy" :
                 build_health.status == "warning" ? "pill metric-pill health-dot-pill health-dot-warning" :
                 build_health.status == "error" ? "pill metric-pill health-dot-pill health-dot-error" :
                 "pill metric-pill health-dot-pill health-dot-unknown"}
         :tooltip {"Build health: " + (build_health.status ?: "unknown") +
                   " | OS " + (build_health.os_generation ?: "--") +
                   " HM " + (build_health.hm_generation ?: "--")}
         (label :class "icon health-dot-icon" :text "●"))))

;; Opens the secondary badge shelf (CPU/mem/disk/net/etc.)
(defwidget status-shelf-toggle [monitor_id]
  (eventbox
    :onclick {"toggle-topbar-badge-shelf toggle " + monitor_id + " &"}
    (box :class {(build_health.status ?: "unknown") == "warning" ||
                 (build_health.status ?: "unknown") == "error" ||
                 (battery.level ?: "unknown") == "critical" ||
                 (battery.level ?: "unknown") == "very_low"
                 ? "pill metric-pill status-shelf-toggle status-shelf-alert"
                 : "pill metric-pill status-shelf-toggle"}
         :tooltip "System badges"
         (label :class "icon status-shelf-icon" :text "󰖷"))))

;; Secondary badge shelf: moved metrics and status badges
(defwidget badge-shelf-window [monitor_id]
  (box :class "badge-shelf-window"
       :orientation "h"
       :space-evenly false
       :halign "end"
    (box :class "badge-shelf-card"
         :orientation "h"
         :space-evenly false
         :spacing 4
         (cpu-widget)
         (memory-widget)
         (disk-widget)
         (temperature-widget)
         (network-widget)
         (wifi-widget)
         ${if isLaptop then "(brightness-widget)" else ""}
         (bluetooth-widget)
         (build-health-widget)
         (button :class "badge-shelf-close"
                 :onclick {"toggle-topbar-badge-shelf close " + monitor_id + " &"}
                 ""))))

;; Separator between blocks
;; Visual separator between widget groups
(defwidget separator []
  (label :class "separator"
         :text "│"))

;; Powermenu toggle button (opens fullscreen overlay)
;; Only visible on the primary bar to avoid multi-monitor clutter; keybinding still works everywhere.
(defwidget powermenu-toggle [is_primary monitor_id]
  (eventbox
    :visible is_primary
    :cursor "pointer"
    :onclick {"toggle-topbar-powermenu " + monitor_id + " &"}
    (box :class "pill metric-pill powermenu-toggle"
         :tooltip "Power menu (Mod+Shift+E)"
         (label :class "icon powermenu-icon" :text ""))))

;; Powermenu action button (icon + label)
(defwidget powermenu-action [label icon class onclick]
  (button
    :class {"pm-action " + class}
    :onclick onclick
    (box :class "pm-action-inner"
         :orientation "v"
         :spacing 6
         :halign "center"
         :valign "center"
      (label :class "pm-action-icon" :text icon)
      (label :class "pm-action-label" :text label))))

;; Powermenu confirmation strip (shown for reboot/shutdown)
(defwidget powermenu-confirm-bar []
  (revealer
    :transition "slideup"
    :duration "160ms"
    :reveal {powermenu_confirm_action != ""}
    (box :class "pm-confirm"
         :orientation "h"
         :space-evenly false
         :spacing 10
      (label :class "pm-confirm-text"
             :hexpand true
             :halign "start"
             :text {powermenu_confirm_action == "shutdown" ? "Power off the system?" : "Reboot the system?"})
      (button :class "pm-confirm-btn pm-confirm-cancel"
              :onclick "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update powermenu_confirm_action=\"\""
              "Cancel")
      (button :class {powermenu_confirm_action == "shutdown"
                       ? "pm-confirm-btn pm-confirm-danger"
                       : "pm-confirm-btn pm-confirm-warn"}
              :onclick {powermenu_confirm_action == "shutdown"
                         ? "toggle-topbar-powermenu; systemctl poweroff"
                         : "toggle-topbar-powermenu; systemctl reboot"}
              {powermenu_confirm_action == "shutdown" ? "Power Off" : "Reboot"}))))

;; Powermenu overlay widget (fullscreen modal)
(defwidget powermenu-overlay []
  ;; Important: don't wrap the card in a clickable eventbox, or it can steal
  ;; pointer events from the buttons (GTK event handling).
  (box :class "powermenu-overlay"
       :orientation "v"
       :space-evenly false
       :hexpand true
       :vexpand true
    ;; Top dismiss area
    (eventbox :onclick "toggle-topbar-powermenu"
      (box :class "powermenu-overlay-dismiss" :hexpand true :vexpand true))

    ;; Middle row: left dismiss, card, right dismiss
    (box :orientation "h" :space-evenly false :hexpand true
      (eventbox :onclick "toggle-topbar-powermenu"
        (box :class "powermenu-overlay-dismiss" :hexpand true :vexpand true))

      (box :class "powermenu-overlay-inner"
           :orientation "v"
           :space-evenly false
           :halign "center"
           :valign "center"
        (box :class "powermenu-card"
             :orientation "v"
             :space-evenly false
             :spacing 12
          (box :class "powermenu-header"
               :orientation "h"
               :space-evenly false
               :spacing 10
            (label :class "powermenu-title" :text "Power")
            (label :class "powermenu-subtitle"
                   :hexpand true
                   :halign "start"
                   :text "Lock • Suspend • Logout • Reboot • Shutdown")
            (button :class "powermenu-close"
                    :onclick "toggle-topbar-powermenu"
                    ""))

          (box :class "powermenu-grid"
               :orientation "v"
               :space-evenly false
               :spacing 10
            (box :class "powermenu-row"
                 :orientation "h"
                 :space-evenly false
                 :spacing 10
              (powermenu-action
                :label "Lock"
                :icon ""
                :class "lock"
                :onclick "toggle-topbar-powermenu; swaylock -f &")
              (powermenu-action
                :label "Suspend"
                :icon ""
                :class "suspend"
                :onclick "toggle-topbar-powermenu; systemctl suspend")
              (powermenu-action
                :label "Logout"
                :icon ""
                :class "logout"
                :onclick "toggle-topbar-powermenu; swaymsg exit"))
            (box :class "powermenu-row"
                 :orientation "h"
                 :space-evenly false
                 :spacing 10
              (powermenu-action
                :label "Reboot"
                :icon ""
                :class {powermenu_confirm_action == "reboot" ? "reboot selected" : "reboot"}
                :onclick {powermenu_confirm_action == "reboot"
                           ? "toggle-topbar-powermenu; systemctl reboot"
                           : "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update powermenu_confirm_action='reboot'"})
              (powermenu-action
                :label "Shutdown"
                :icon ""
                :class {powermenu_confirm_action == "shutdown" ? "shutdown selected" : "shutdown"}
                :onclick {powermenu_confirm_action == "shutdown"
                           ? "toggle-topbar-powermenu; systemctl poweroff"
                           : "${pkgs.eww}/bin/eww --config $HOME/.config/eww/eww-top-bar update powermenu_confirm_action='shutdown'"})
              (powermenu-action
                :label "Cancel"
                :icon ""
                :class "cancel"
                :onclick "toggle-topbar-powermenu")))

          (powermenu-confirm-bar)))

      (eventbox :onclick "toggle-topbar-powermenu"
        (box :class "powermenu-overlay-dismiss" :hexpand true :vexpand true)))

    ;; Bottom dismiss area
    (eventbox :onclick "toggle-topbar-powermenu"
      (box :class "powermenu-overlay-dismiss" :hexpand true :vexpand true))))

;; Feature 061: System Tray widget (US1) - conditional on is_primary
(defwidget systray-widget [is_primary]
  (box :class "metric-block"
       :visible is_primary
       (systray :spacing 4
                :icon-size 14
                :orientation "horizontal"
                :prepend-new false)))

;; Feature 083: Consolidated monitor profile widget
;; Shows profile name + visual output indicators (dots)
;; Clicking opens Walker with ;m prefix for profile switching
(defwidget monitor-profile-widget []
  (eventbox :onclick "elephant --prefix ';m ' &"
    (box :class "pill metric-pill monitor-profile"
         :spacing 4
         :tooltip "Click to switch monitor profile (;m)"
         ;; Profile icon
         (label :class "icon monitor-profile-icon" :text "󰍹")
         ;; Profile name
         (label :class "value monitor-profile-name"
                :text {monitor_state.profile_name ?: "unknown"})
         ;; Output indicators - visual dots for each output
         (box :class "monitor-indicators"
              :orientation "h"
              :spacing 2
              ;; Use for-loop to iterate outputs and show indicator per output
              (for output in {monitor_state.outputs ?: []}
                (label :class {output.active ? "monitor-dot monitor-dot-active" : "monitor-dot monitor-dot-inactive"}
                       :tooltip {output.active ? "''${output.short_name} active" : "''${output.short_name} inactive"}
                       :text "●"))))))

;; Feature 085: Monitoring panel toggle widget
;; Shows current panel visibility and allows clicking to toggle
(defwidget monitoring-panel-toggle []
  (eventbox :onclick "toggle-monitoring-panel &"
    (box :class {monitoring_panel_visible == "true" ? "pill metric-pill monitoring-toggle monitoring-toggle-active" : "pill metric-pill monitoring-toggle"}
         :spacing 2
         :tooltip {monitoring_panel_visible == "true" ? "Hide monitoring panel (Mod+M)" : "Show monitoring panel (Mod+M)"}
         (label :class "icon monitoring-toggle-icon"
                :text {monitoring_panel_visible == "true" ? "󰍉" : "󰍜"}))))

;; Feature 110: Notification badge widget (SwayNC integration)
;; Shows notification count badge with real-time updates via deflisten
;; Clicking toggles SwayNC control center via toggle-swaync wrapper
(defwidget notification-badge []
  (eventbox :onclick "toggle-swaync &"
    (box :class {notification_data.visible == true ? "pill metric-pill notification-toggle notification-toggle-active" :
                 notification_data.has_unread == true ? "pill metric-pill notification-toggle notification-has-unread" :
                 notification_data.dnd == true ? "pill metric-pill notification-toggle notification-dnd" :
                 "pill metric-pill notification-toggle"}
         :spacing 2
         :tooltip {notification_data.dnd == true ? "Do Not Disturb enabled (Mod+Shift+I)" :
                   notification_data.count == 0 ? "No notifications (Mod+Shift+I)" :
                   "''${notification_data.count} unread notification(s) (Mod+Shift+I)"}
         ;; Icon: changes based on dnd/count state
         (label :class {notification_data.dnd == true ? "icon notification-toggle-icon notification-icon-dnd" :
                        notification_data.has_unread == true ? "icon notification-toggle-icon notification-icon-active" :
                        "icon notification-toggle-icon notification-icon-empty"}
                :text {notification_data.dnd == true ? "󰂛" :
                       notification_data.has_unread == true ? "󰂚" : "󰂜"})
         ;; Badge: only visible when count > 0 and not in DND mode
         (label :class "notification-badge-count"
                :visible {notification_data.has_unread == true && notification_data.dnd == false}
                :text {notification_data.display_count}))))

;; Feature 123: AI Sessions widget for top bar (OTEL-based)
;; Feature 136: DISABLED - AI indicators moved to monitoring panel only
;; Compact chips showing active AI assistants (Claude Code, Codex)
;; Three states: working (pulsating), completed/attention (bell), idle (muted)
;; Error state: shows red indicator when pipe is missing (visible failure, not silent)
;; Data comes from otel-ai-monitor service via deflisten (event-driven)
;; Feature 123 Enhancement: Project badge shows branch number (worktrees) or abbreviation
;; (defwidget ai-sessions-widget []
;;   (box :class "ai-sessions-container"
;;        :visible {(ai_sessions_data.type ?: "") == "error" || arraylength(ai_sessions_data.sessions ?: []) > 0}
;;        :orientation "h"
;;        :space-evenly false
;;        :spacing 4
;;        ;; Error indicator when pipe is missing
;;        (box :class "ai-chip error"
;;             :visible {(ai_sessions_data.type ?: "") == "error"}
;;             :tooltip {"AI Monitor Error: " + (ai_sessions_data.error ?: "unknown")}
;;             (label :class "ai-chip-indicator" :text "󰅙"))
;;        ;; Normal session chips
;;        ;; Adds "focused" class when this session matches the active project
;;        (for session in {ai_sessions_data.sessions ?: []}
;;          (eventbox :onclick {"focus-window-action '" + (session.project ?: "Global") + "' '" + (session.window_id ?: "0") + "' &"}
;;                    :cursor "pointer"
;;                    :tooltip {session.tool == "claude-code" ? "Claude Code" : (session.tool == "codex" ? "Codex" : session.tool) + " - " + (session.state == "working" ? "Working" : (session.state == "completed" ? "Needs attention" : "Ready")) + " [" + (session.project ?: "Global") + "]" + ((session.project ?: "") == (active_project.project ?: "") ? " (Active)" : "")}
;;            (box :class {"ai-chip" + (session.state == "working" ? " working" : (session.state == "completed" ? " attention" : " idle")) + ((session.project ?: "") == (active_project.project ?: "") ? " focused" : "")}
;;                 :orientation "h"
;;                 :space-evenly false
;;                 :spacing 4
;;                 ;; State indicator (nerd font icons)
;;                 (label :class {"ai-chip-indicator" + (session.state == "working" ? " ai-opacity-" + (topbar_spinner_opacity == "0.4" ? "04" : (topbar_spinner_opacity == "0.6" ? "06" : (topbar_spinner_opacity == "0.8" ? "08" : "10"))) : "")}
;;                        :text {session.state == "working" ? topbar_spinner_frame : (session.state == "completed" ? "󰂞" : "󰤄")})
;;                 ;; Project badge - extracts feature number from branch name
;;                 ;; Format: "owner/repo:branch" (e.g., "vpittamp/nixos-config:123-otel-tracing" → "123")
;;                 ;; Uses captures() to extract digits after colon; fallback: first 3 chars of branch
;;                 (label :class "ai-chip-project-badge"
;;                        :halign "center"
;;                        :visible {(session.project ?: "") != "" && (session.project ?: "") != "Global"}
;;                        :text {arraylength(captures(session.project ?: "", ":([0-9]+)")) > 1
;;                               ? captures(session.project ?: "", ":([0-9]+)")[1]
;;                               : substring(replace(session.project ?: "???", ".*:", ""), 0, 3)})
;;                 ;; Tool icon (SVG images for claude and codex)
;;                 (image
;;                   :class "ai-chip-source-icon"
;;                   :path {session.tool == "claude-code" ? "/etc/nixos/assets/icons/claude.svg" : (session.tool == "codex" ? "/etc/nixos/assets/icons/chatgpt.svg" : "/etc/nixos/assets/icons/anthropic.svg")}
;;                   :image-width 16
;;                   :image-height 16))))))

;; Main bar layout - static left metrics with compact interactive controls

(defwidget main-bar [is_primary monitor_id]
  (centerbox :orientation "h"
             :class "bar"
    ;; Left: Minimal always-on controls; extended badges move to shelf popup
    ;; Wrapped in an expanding side container to keep the center group truly centered.
    (box :class "bar-side bar-side-left"
         :orientation "h"
         :space-evenly false
         :halign "start"
         :hexpand true
      (box :class "left"
           :orientation "h"
           :space-evenly false
           :halign "start"
           :spacing 5
           (status-shelf-toggle :monitor_id monitor_id)
           (volume-widget-enhanced)
           (memory-widget)
           (battery-widget)
           (build-health-dot-widget :monitor_id monitor_id)))

    ;; Center: Active Project + AI Sessions
    (box :class "center"
         :orientation "h"
         :space-evenly false
         :halign "center"
         :spacing 5
         (project-widget)
         ;; Feature 136: AI sessions widget disabled - functionality moved to monitoring panel
         ;; (ai-sessions-widget)
         )

    ;; Right: Date/Time, Monitor Profile, Monitoring Panel Toggle, Notification Badge, and System Tray
    ;; Wrapped in an expanding side container to mirror left-side expansion.
    (box :class "bar-side bar-side-right"
         :orientation "h"
         :space-evenly false
         :halign "end"
         :hexpand true
      (box :class "right"
           :orientation "h"
           :space-evenly false
           :halign "end"
           :spacing 5
            (monitor-profile-widget)
            (monitoring-panel-toggle)
            (notification-badge)
            (datetime-widget)
            (systray-widget :is_primary is_primary)
            (powermenu-toggle :is_primary is_primary :monitor_id monitor_id)))))

;; ============================================================================
;; Windows (per-monitor instances)
;; Generated dynamically based on detected monitors (Hetzner: HEADLESS-*, M1: eDP-1/HDMI-A-1)
;; ============================================================================

${lib.concatMapStrings mkWindowDef topBarOutputs}
${fallbackWindow}

;; ============================================================================
;; Overlay Windows (per-monitor instances)
;; ============================================================================

${lib.concatMapStrings mkBadgeShelfWindowDef topBarOutputs}
${fallbackBadgeShelfWindow}

${lib.concatMapStrings mkPowermenuWindowDef topBarOutputs}
${fallbackPowermenuWindow}
''

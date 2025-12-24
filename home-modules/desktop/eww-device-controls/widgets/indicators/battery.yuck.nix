# Battery Indicator Widget (Laptop Only)
# Feature 116: Top bar battery status with expandable panel
{ scriptsDir, ... }:

''
; =============================================================================
; Battery Indicator (Top Bar, Laptop Only)
; =============================================================================

(defwidget battery-indicator []
  (eventbox
    :onclick {battery_expanded ? "" : "eww update battery_expanded=true"}
    :class "device-indicator battery-indicator ''${battery_state.level}''${battery_state.state == "charging" ? " charging" : ""}"
    :tooltip "Battery: ''${battery_state.percentage}%''${battery_state.time_remaining != "null" && battery_state.time_remaining != null ? " (" + battery_state.time_remaining + ")" : ""}"
    (box :class "indicator-box"
      (box :class "battery-overview" :orientation "v" :spacing 2
        (box :class "battery-summary" :spacing 4 :valign "center"
          (label :class "indicator-icon battery-icon ''${battery_state.level}''${battery_state.state == "charging" ? " charging" : ""}"
                 :text {battery_state.icon})
          (label :class "battery-percent" :text "''${battery_state.percentage}%"))
        (revealer :reveal {(battery_state.state != "charging") && (battery_state.level == "low" || battery_state.level == "critical")}
                  :transition "slidedown"
                  :duration "150ms"
          (box :class "battery-warning-chip" :spacing 4
            (label :class "warning-icon" :text {battery_state.level == "critical" ? "󰂃" : "󰂆"})
            (label :class "warning-text" :text {battery_state.level == "critical" ? "Plug in now" : "Low battery"}))))
      (revealer :reveal {battery_expanded}
                :transition "slideright"
                :duration "150ms"
        (box :class "expanded-panel battery-panel" :orientation "v" :spacing 4
          ; Battery status
          (box :class "panel-row status-row" :spacing 8
            (label :class "status-label" :text {battery_state.state == "charging" ? "󰂄 Charging" : battery_state.state == "discharging" ? "󰁹 On Battery" : "󰁹 Full"})
            (label :class "status-value" :text "''${battery_state.percentage}%"))
          ; Time remaining
          (revealer :reveal {battery_state.time_remaining != "null" && battery_state.time_remaining != null}
                    :transition "slidedown"
            (box :class "panel-row" :spacing 8
              (label :class "panel-label" :text "Time")
              (label :class "panel-value" :text {battery_state.time_remaining ?: ""})))
          ; Close button
          (button :class "panel-button close-btn"
                  :onclick "eww update battery_expanded=false"
            (label :text "󰅖")))))))
''

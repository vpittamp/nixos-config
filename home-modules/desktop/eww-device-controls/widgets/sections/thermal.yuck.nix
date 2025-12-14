# Thermal Section Widget (Devices Tab)
# Feature 116: Temperature and fan monitoring for monitoring panel
{ scriptsDir, ... }:

''
; =============================================================================
; Thermal Section (Devices Tab)
; =============================================================================

(defwidget devices-thermal-section []
  (box :class "devices-section thermal-section" :orientation "v" :spacing 8
    (label :class "section-title" :text "󰔐 Thermal")
    (box :class "section-content" :orientation "v" :spacing 8
      ; CPU temperature
      (box :class "thermal-row" :spacing 8
        (label :class "thermal-icon ''${device_state.thermal.level ?: "cool"}"
               :text {device_state.thermal.icon ?: "󰔐"})
        (box :class "thermal-info" :orientation "v"
          (label :class "thermal-label" :text "CPU")
          (label :class "thermal-value ''${device_state.thermal.level ?: "cool"}"
                 :text "''${device_state.thermal.cpu_temp ?: 0}C"))
        (progress :class "thermal-bar ''${device_state.thermal.level ?: "cool"}"
                  :value {device_state.thermal.cpu_temp ?: 0}
                  :min 0
                  :max {device_state.thermal.cpu_temp_max ?: 100}))
      ; Fan speed (if available)
      (revealer :reveal {device_state.thermal.fan_speed != "null" && device_state.thermal.fan_speed != null}
                :transition "slidedown"
        (box :class "fan-row" :spacing 8
          (label :class "fan-icon" :text "󰈐")
          (label :class "fan-label" :text "Fan")
          (label :class "fan-value" :text "''${device_state.thermal.fan_speed ?: 0} RPM"))))))
''

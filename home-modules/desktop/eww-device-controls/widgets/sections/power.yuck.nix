# Power Section Widget (Devices Tab, Laptop Only)
# Feature 116: Battery and power profile controls for monitoring panel
{ scriptsDir, ... }:

''
; =============================================================================
; Power Section (Devices Tab, Laptop Only)
; =============================================================================

(defwidget devices-power-section []
  (box :class "devices-section power-section" :orientation "v" :spacing 8
    (label :class "section-title" :text "󰂄 Power")
    (box :class "section-content" :orientation "v" :spacing 8
      ; Battery status
      (box :class "battery-status" :spacing 12
        (label :class "battery-icon ''${device_state.battery.level ?: "normal"}''${device_state.battery.state == "charging" ? " charging" : ""}"
               :text {device_state.battery.icon ?: "󰁹"})
        (box :class "battery-info" :orientation "v"
          (label :class "battery-percent-large" :text "''${device_state.battery.percentage ?: 100}%")
          (label :class "battery-state" :text {device_state.battery.state == "charging" ? "Charging" : device_state.battery.state == "discharging" ? "Discharging" : "Full"}))
        (revealer :reveal {device_state.battery.time_remaining != "null" && device_state.battery.time_remaining != null}
                  :transition "slideleft"
          (box :class "time-remaining"
            (label :text {device_state.battery.time_remaining ?: ""}))))
      ; Battery health (detailed info)
      (revealer :reveal {device_state.battery.health != "null" && device_state.battery.health != null}
                :transition "slidedown"
        (box :class "battery-details" :spacing 16
          (box :class "detail-item"
            (label :class "detail-label" :text "Health")
            (label :class "detail-value" :text "''${device_state.battery.health ?: 100}%"))
          (revealer :reveal {device_state.battery.cycles != "null" && device_state.battery.cycles != null}
                    :transition "slideleft"
            (box :class "detail-item"
              (label :class "detail-label" :text "Cycles")
              (label :class "detail-value" :text "''${device_state.battery.cycles ?: 0}")))
          (revealer :reveal {device_state.battery.power_draw != "null" && device_state.battery.power_draw != null}
                    :transition "slideleft"
            (box :class "detail-item"
              (label :class "detail-label" :text "Power")
              (label :class "detail-value" :text "''${device_state.battery.power_draw ?: 0}W")))))
      ; Power profile selector
      (revealer :reveal {device_state.power_profile != "null" && device_state.power_profile != null}
                :transition "slidedown"
        (box :class "power-profiles" :spacing 8
          (for profile in {device_state.power_profile.available ?: ["balanced"]}
            (button :class "profile-btn''${device_state.power_profile.current == profile ? " active" : ""}"
                    :onclick "${scriptsDir}/power-profile-control.sh set ''${profile}"
              (label :text {profile == "performance" ? "󱐋 Performance" : profile == "balanced" ? "󰾅 Balanced" : "󰾆 Power Saver"}))))))))
''

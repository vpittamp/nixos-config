# Display Section Widget (Devices Tab, Laptop Only)
# Feature 116: Brightness controls for monitoring panel
{ scriptsDir, ... }:

''
; =============================================================================
; Display Section (Devices Tab, Laptop Only)
; =============================================================================

(defwidget devices-display-section []
  (box :class "devices-section display-section" :orientation "v" :spacing 8
    (label :class "section-title" :text "󰛨 Display")
    (box :class "section-content" :orientation "v" :spacing 8
      ; Display brightness
      (box :class "slider-row" :spacing 8
        (label :class "slider-label" :text "Screen")
        (scale :class "device-slider"
               :value {device_state.brightness.display ?: 50}
               :min 5 :max 100
               :onchange "${scriptsDir}/brightness-control.sh set {}")
        (label :class "slider-value" :text "''${device_state.brightness.display ?: 50}%"))
      ; Keyboard backlight
      (revealer :reveal {device_state.brightness.keyboard != "null" && device_state.brightness.keyboard != null}
                :transition "slidedown"
        (box :class "slider-row" :spacing 8
          (label :class "slider-label" :text "Keyboard")
          (scale :class "device-slider"
                 :value {device_state.brightness.keyboard ?: 0}
                 :min 0 :max 100
                 :onchange "${scriptsDir}/brightness-control.sh set {} --device keyboard")
          (label :class "slider-value" :text "''${device_state.brightness.keyboard ?: 0}%"))))))
''

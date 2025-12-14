# Brightness Indicator Widget (Laptop Only)
# Feature 116: Top bar brightness control with expandable panel
{ scriptsDir, ... }:

''
; =============================================================================
; Brightness Indicator (Top Bar, Laptop Only)
; =============================================================================

(defwidget brightness-indicator []
  (eventbox
    :onclick {brightness_expanded ? "" : "eww update brightness_expanded=true"}
    :onscroll "${scriptsDir}/brightness-control.sh {}"
    :class "device-indicator"
    :tooltip "Brightness: ''${brightness_state.display}%"
    (box :class "indicator-box"
      (label :class "indicator-icon" :text "󰃟")
      (revealer :reveal {brightness_expanded}
                :transition "slideright"
                :duration "150ms"
        (box :class "expanded-panel brightness-panel" :orientation "v" :spacing 8
          ; Display brightness
          (box :class "slider-row" :spacing 8
            (label :class "slider-label" :text "󰛨")
            (scale :class "device-slider brightness-slider"
                   :value {brightness_state.display}
                   :min 5 :max 100
                   :onchange "${scriptsDir}/brightness-control.sh set {}"))
          ; Keyboard backlight (if available)
          (revealer :reveal {brightness_state.keyboard != "null" && brightness_state.keyboard != null}
                    :transition "slidedown"
            (box :class "slider-row" :spacing 8
              (label :class "slider-label" :text "󰌌")
              (scale :class "device-slider keyboard-slider"
                     :value {brightness_state.keyboard ?: 0}
                     :min 0 :max 100
                     :onchange "${scriptsDir}/brightness-control.sh set {} --device keyboard")))
          ; Close button
          (button :class "panel-button close-btn"
                  :onclick "eww update brightness_expanded=false"
            (label :text "󰅖")))))))
''

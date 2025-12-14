# Volume Indicator Widget
# Feature 116: Top bar volume control with expandable panel
{ scriptsDir, ... }:

''
; =============================================================================
; Volume Indicator (Top Bar)
; =============================================================================

(defwidget volume-indicator []
  (eventbox
    :onclick {volume_expanded ? "" : "eww update volume_expanded=true"}
    :onscroll "${scriptsDir}/volume-control.sh {}"
    :class "device-indicator"
    :tooltip "Volume: ''${volume_state.volume}%''${volume_state.muted ? " (Muted)" : ""}"
    (box :class "indicator-box"
      (label :class "indicator-icon''${volume_state.muted ? " muted" : ""}"
             :text {volume_state.icon})
      (revealer :reveal {volume_expanded}
                :transition "slideright"
                :duration "150ms"
        (box :class "expanded-panel volume-panel" :spacing 8
          ; Volume slider
          (scale :class "device-slider volume-slider"
                 :value {volume_state.volume}
                 :min 0 :max 100
                 :onchange "${scriptsDir}/volume-control.sh set {}")
          ; Mute toggle
          (button :class "panel-button mute-toggle''${volume_state.muted ? " active" : ""}"
                  :onclick "${scriptsDir}/volume-control.sh mute"
                  :tooltip "Toggle Mute"
            (label :text {volume_state.muted ? "󰝟" : "󰕾"}))
          ; Close button
          (button :class "panel-button close-btn"
                  :onclick "eww update volume_expanded=false"
            (label :text "󰅖")))))))
''

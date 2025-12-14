# Audio Section Widget (Devices Tab)
# Feature 116: Comprehensive audio controls for monitoring panel
{ scriptsDir, ... }:

''
; =============================================================================
; Audio Section (Devices Tab)
; =============================================================================

(defwidget devices-audio-section []
  (box :class "devices-section audio-section" :orientation "v" :spacing 8
    (label :class "section-title" :text "󰕾 Audio")
    (box :class "section-content" :orientation "v" :spacing 8
      ; Current output device
      (box :class "device-row" :spacing 8
        (label :class "device-label" :text "Output")
        (label :class "device-value" :text {device_state.volume.current_device ?: "Unknown"}))
      ; Volume slider
      (box :class "slider-row" :spacing 8
        (label :class "slider-icon" :text {device_state.volume.icon ?: "󰕾"})
        (scale :class "device-slider"
               :value {device_state.volume.volume ?: 50}
               :min 0 :max 100
               :onchange "${scriptsDir}/volume-control.sh set {}")
        (label :class "slider-value" :text "''${device_state.volume.volume ?: 50}%")
        (button :class "mute-btn''${device_state.volume.muted ?: false ? " muted" : ""}"
                :onclick "${scriptsDir}/volume-control.sh mute"
          (label :text {device_state.volume.muted ?: false ? "󰝟" : "󰕾"})))
      ; Output device selector
      (revealer :reveal {arraylength(device_state.volume.devices ?: []) > 1}
                :transition "slidedown"
        (box :class "device-selector" :orientation "v" :spacing 4
          (for device in {device_state.volume.devices ?: []}
            (button :class "device-option''${device.active ? " active" : ""}"
                    :onclick "${scriptsDir}/volume-control.sh device ''${device.id}"
              (box :spacing 8
                (label :class "device-type-icon"
                       :text {device.type == "speaker" ? "󰓃" : device.type == "headphones" ? "󰋋" : "󰂰"})
                (label :text {device.name})))))))))
''

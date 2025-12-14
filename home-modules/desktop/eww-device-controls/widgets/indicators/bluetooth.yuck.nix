# Bluetooth Indicator Widget
# Feature 116: Top bar bluetooth control with expandable panel
{ scriptsDir, ... }:

''
; =============================================================================
; Bluetooth Indicator (Top Bar)
; =============================================================================

(defwidget bluetooth-indicator []
  (eventbox
    :onclick {bluetooth_expanded ? "" : "eww update bluetooth_expanded=true"}
    :class "device-indicator"
    :tooltip "Bluetooth: ''${bluetooth_state.enabled ? "On" : "Off"}"
    (box :class "indicator-box"
      (label :class "indicator-icon''${bluetooth_state.enabled ? " connected" : " disabled"}"
             :text {bluetooth_state.enabled ? "󰂯" : "󰂲"})
      (revealer :reveal {bluetooth_expanded}
                :transition "slideright"
                :duration "150ms"
        (box :class "expanded-panel bluetooth-panel" :orientation "v" :spacing 4
          ; Toggle switch
          (box :class "panel-row" :spacing 8
            (label :class "panel-label" :text "Bluetooth")
            (button :class "toggle-switch''${bluetooth_state.enabled ? " active" : ""}"
                    :onclick "${scriptsDir}/bluetooth-control.sh power toggle"
              (box :class "toggle-track"
                (box :class "toggle-thumb"))))
          ; Device list (if enabled)
          (revealer :reveal {bluetooth_state.enabled && arraylength(bluetooth_state.devices) > 0}
                    :transition "slidedown"
            (box :class "device-list" :orientation "v" :spacing 2
              (for device in {bluetooth_state.devices}
                (button :class "device-item''${device.connected ? " connected" : ""}"
                        :onclick "${scriptsDir}/bluetooth-control.sh ''${device.connected ? "disconnect" : "connect"} ''${device.mac}"
                  (box :spacing 8
                    (label :class "device-icon" :text {device.icon})
                    (label :class "device-name" :text {device.name})
                    (label :class "device-status"
                           :text {device.connected ? "Connected" : ""}))))))
          ; Close button
          (button :class "panel-button close-btn"
                  :onclick "eww update bluetooth_expanded=false"
            (label :text "󰅖")))))))
''

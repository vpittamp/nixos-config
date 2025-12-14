# Bluetooth Section Widget (Devices Tab)
# Feature 116: Comprehensive bluetooth controls for monitoring panel
{ scriptsDir, ... }:

''
; =============================================================================
; Bluetooth Section (Devices Tab)
; =============================================================================

(defwidget devices-bluetooth-section []
  (box :class "devices-section bluetooth-section" :orientation "v" :spacing 8
    (label :class "section-title" :text "󰂯 Bluetooth")
    (box :class "section-content" :orientation "v" :spacing 8
      ; Adapter toggle
      (box :class "toggle-row" :spacing 8
        (label :class "toggle-label" :text "Bluetooth")
        (button :class "toggle-switch''${device_state.bluetooth.enabled ?: false ? " active" : ""}"
                :onclick "${scriptsDir}/bluetooth-control.sh power toggle"
          (box :class "toggle-track"
            (box :class "toggle-thumb"))))
      ; Paired devices list
      (revealer :reveal {device_state.bluetooth.enabled ?: false}
                :transition "slidedown"
        (box :class "device-list" :orientation "v" :spacing 4
          (for device in {device_state.bluetooth.devices ?: []}
            (box :class "device-item''${device.connected ? " connected" : ""}" :spacing 8
              (label :class "device-icon" :text {device.icon})
              (box :class "device-info" :orientation "v"
                (label :class "device-name" :text {device.name})
                (label :class "device-mac" :text {device.mac}))
              (revealer :reveal {device.battery != "null" && device.battery != null}
                        :transition "slideleft"
                (label :class "device-battery" :text "󰁹 ''${device.battery}%"))
              (button :class "connect-btn"
                      :onclick "${scriptsDir}/bluetooth-control.sh ''${device.connected ? "disconnect" : "connect"} ''${device.mac}"
                (label :text {device.connected ? "Disconnect" : "Connect"})))))))))
''

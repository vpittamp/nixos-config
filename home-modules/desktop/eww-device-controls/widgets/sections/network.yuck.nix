# Network Section Widget (Devices Tab)
# Feature 116: WiFi and Tailscale status for monitoring panel
{ scriptsDir, ... }:

''
; =============================================================================
; Network Section (Devices Tab)
; =============================================================================

(defwidget devices-network-section []
  (box :class "devices-section network-section" :orientation "v" :spacing 8
    (label :class "section-title" :text "󰖩 Network")
    (box :class "section-content" :orientation "v" :spacing 8
      ; WiFi status
      (revealer :reveal {device_state.network.wifi_enabled ?: false}
                :transition "slidedown"
        (box :class "network-row wifi-row" :spacing 8
          (label :class "network-icon" :text {device_state.network.wifi_icon ?: "󰤭"})
          (box :class "network-info" :orientation "v"
            (label :class "network-type" :text "WiFi")
            (label :class "network-value" :text {device_state.network.wifi_ssid ?: "Not connected"}))
          (revealer :reveal {device_state.network.wifi_signal != "null" && device_state.network.wifi_signal != null}
                    :transition "slideleft"
            (label :class "signal-strength" :text "''${device_state.network.wifi_signal ?: 0}%"))))
      ; Tailscale status
      (box :class "network-row tailscale-row" :spacing 8
        (label :class "network-icon''${device_state.network.tailscale_connected ?: false ? " connected" : " disconnected"}"
               :text "󰖂")
        (box :class "network-info" :orientation "v"
          (label :class "network-type" :text "Tailscale")
          (label :class "network-value"
                 :text {device_state.network.tailscale_connected ?: false ? device_state.network.tailscale_ip ?: "Connected" : "Disconnected"}))))))
''

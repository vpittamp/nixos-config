# Eww Variables and Polling Definitions
# Feature 116: Device control state management
{ cfg, scriptsDir, isLaptop, ... }:

''
; =============================================================================
; Variables and State Definitions
; =============================================================================

; Hardware capabilities - detected at runtime by device-backend.py
(defvar hardware_caps '{"has_battery": false, "has_brightness": false, "has_bluetooth": true, "has_wifi": true, "has_thermal_sensors": true}')

; Panel expansion state (for top bar indicators)
(defvar volume_expanded false)
(defvar brightness_expanded false)
(defvar bluetooth_expanded false)
(defvar battery_expanded false)

; Devices tab visibility flag (controls full state polling)
(defvar devices_tab_visible false)

; Keyboard navigation state (for focus mode)
(defvar devices_selected_section 0)
(defvar devices_selected_item 0)

; =============================================================================
; Polling Definitions
; =============================================================================

; Volume state (1s interval for responsive control)
(defpoll volume_state :interval "${cfg.volumeInterval}"
  `${scriptsDir}/device-backend.py --mode volume 2>/dev/null || echo '{"volume": 50, "muted": false, "icon": "󰕾", "current_device": "Unknown", "devices": []}'`)

; Bluetooth state (3s interval)
(defpoll bluetooth_state :interval "${cfg.bluetoothInterval}"
  `${scriptsDir}/device-backend.py --mode bluetooth 2>/dev/null || echo '{"enabled": false, "scanning": false, "devices": []}'`)

${if isLaptop then ''
; Brightness state (2s interval, laptop only)
(defpoll brightness_state :interval "${cfg.brightnessInterval}"
  `${scriptsDir}/device-backend.py --mode brightness 2>/dev/null || echo '{"display": 50, "display_device": "", "keyboard": null, "keyboard_device": null}'`)

; Battery state (5s interval, laptop only)
(defpoll battery_state :interval "${cfg.batteryInterval}"
  `${scriptsDir}/device-backend.py --mode battery 2>/dev/null || echo '{"percentage": 100, "state": "full", "time_remaining": null, "icon": "󰁹", "level": "full"}'`)
'' else ""}

; Full device state for Devices tab (only poll when tab visible)
(defpoll device_state :interval "${cfg.fullStateInterval}"
  :run-while {devices_tab_visible}
  `${scriptsDir}/device-backend.py 2>/dev/null || echo '{}'`)
''

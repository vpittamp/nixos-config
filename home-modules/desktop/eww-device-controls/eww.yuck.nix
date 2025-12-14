# Eww Widget Definitions for Device Controls
# Feature 116: Unified device control widgets
#
# This file composes modular widget definitions from:
# - widgets/variables.yuck.nix - State and polling definitions
# - widgets/indicators/*.yuck.nix - Top bar indicator widgets
# - widgets/sections/*.yuck.nix - Devices tab section widgets
#
{ config, lib, pkgs, mocha, isLaptop, isRyzen, isThinkPad, isM1, isHeadless, scriptsDir, ... }:

let
  cfg = config.programs.eww-device-controls;

  # Common arguments passed to all widget modules
  widgetArgs = { inherit cfg scriptsDir; };

  # Import modular widget definitions
  variablesYuck = import ./widgets/variables.yuck.nix (widgetArgs // { inherit isLaptop; });

  # Top bar indicators
  volumeIndicator = import ./widgets/indicators/volume.yuck.nix widgetArgs;
  bluetoothIndicator = import ./widgets/indicators/bluetooth.yuck.nix widgetArgs;
  brightnessIndicator = import ./widgets/indicators/brightness.yuck.nix widgetArgs;
  batteryIndicator = import ./widgets/indicators/battery.yuck.nix widgetArgs;

  # Devices tab sections
  audioSection = import ./widgets/sections/audio.yuck.nix widgetArgs;
  displaySection = import ./widgets/sections/display.yuck.nix widgetArgs;
  bluetoothSection = import ./widgets/sections/bluetooth.yuck.nix widgetArgs;
  powerSection = import ./widgets/sections/power.yuck.nix widgetArgs;
  thermalSection = import ./widgets/sections/thermal.yuck.nix widgetArgs;
  networkSection = import ./widgets/sections/network.yuck.nix widgetArgs;

in
''
; =============================================================================
; Feature 116: Eww Device Controls
; =============================================================================
; Modular device control system with:
; - Top bar indicators with expandable panels (volume, brightness, bluetooth, battery)
; - Devices tab for monitoring panel (comprehensive dashboard)
;
; Structure:
; - Variables/polling from widgets/variables.yuck.nix
; - Indicators from widgets/indicators/*.yuck.nix
; - Sections from widgets/sections/*.yuck.nix
; =============================================================================

${variablesYuck}

; =============================================================================
; Top Bar Indicators (Tier 1: Quick Access)
; =============================================================================

${volumeIndicator}

${bluetoothIndicator}

${if isLaptop then brightnessIndicator else ""}

${if isLaptop then batteryIndicator else ""}

; -----------------------------------------------------------------------------
; Combined Device Controls Widget (for top bar integration)
; -----------------------------------------------------------------------------

(defwidget device-controls []
  (box :class "device-controls" :spacing 4
    (volume-indicator)
    ${if cfg.showBluetooth then "(bluetooth-indicator)" else ""}
    ${if isLaptop then "(brightness-indicator)" else ""}
    ${if isLaptop then "(battery-indicator)" else ""}))

; -----------------------------------------------------------------------------
; Click-Outside Handler
; -----------------------------------------------------------------------------
; Closes all expanded panels when clicking outside

(defwidget device-controls-wrapper []
  (eventbox
    :onclick "eww update volume_expanded=false brightness_expanded=false bluetooth_expanded=false battery_expanded=false"
    :class "device-controls-wrapper"
    (device-controls)))

; =============================================================================
; Devices Tab Sections (Tier 2: Comprehensive Dashboard for Monitoring Panel)
; =============================================================================

${audioSection}

${if isLaptop then displaySection else ""}

${bluetoothSection}

${if isLaptop then powerSection else ""}

${thermalSection}

${if cfg.showNetwork then networkSection else ""}

; -----------------------------------------------------------------------------
; Main Devices Tab Widget
; -----------------------------------------------------------------------------

(defwidget devices-tab []
  (scroll :class "devices-tab" :vscroll true :hscroll false
    (box :class "devices-content" :orientation "v" :spacing 16
      (devices-audio-section)
      ${if isLaptop then "(devices-display-section)" else ""}
      (devices-bluetooth-section)
      ${if isLaptop then "(devices-power-section)" else ""}
      (devices-thermal-section)
      ${if cfg.showNetwork then "(devices-network-section)" else ""})))

; -----------------------------------------------------------------------------
; Section List for Navigation
; -----------------------------------------------------------------------------

(defvar devices_sections [${if isLaptop then ''
  "audio" "display" "bluetooth" "power" "thermal"${if cfg.showNetwork then '' "network"'' else ""}
'' else ''
  "audio" "bluetooth" "thermal"${if cfg.showNetwork then '' "network"'' else ""}
''}])
''

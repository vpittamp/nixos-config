# Eww Styles for Device Controls
# Feature 116: Catppuccin Mocha theme for device control widgets
{ config, lib, pkgs, mocha, ... }:

''
// =============================================================================
// Feature 116: Device Controls Styles
// Catppuccin Mocha theme
// =============================================================================

// -----------------------------------------------------------------------------
// Theme Variables
// -----------------------------------------------------------------------------

$base: ${mocha.base};
$mantle: ${mocha.mantle};
$surface0: ${mocha.surface0};
$surface1: ${mocha.surface1};
$overlay0: ${mocha.overlay0};
$text: ${mocha.text};
$subtext0: ${mocha.subtext0};
$blue: ${mocha.blue};
$sapphire: ${mocha.sapphire};
$sky: ${mocha.sky};
$teal: ${mocha.teal};
$green: ${mocha.green};
$yellow: ${mocha.yellow};
$peach: ${mocha.peach};
$red: ${mocha.red};
$mauve: ${mocha.mauve};

// -----------------------------------------------------------------------------
// Common Styles
// -----------------------------------------------------------------------------

* {
  font-family: "JetBrainsMono Nerd Font", "Symbols Nerd Font", sans-serif;
  font-size: 13px;
  color: $text;
}

// -----------------------------------------------------------------------------
// Top Bar Indicators
// -----------------------------------------------------------------------------

.device-indicator {
  padding: 0 4px;
  margin: 0 2px;
  border-radius: 6px;
  transition: all 150ms ease;

  &:hover {
    background: rgba($surface0, 0.5);
  }
}

.indicator-box {
  padding: 4px 6px;
}

.indicator-icon {
  font-size: 16px;
  min-width: 20px;

  &.muted {
    color: $subtext0;
  }

  &.connected {
    color: $teal;
  }

  &.disabled {
    color: $overlay0;
  }
}

// -----------------------------------------------------------------------------
// Expanded Panels
// -----------------------------------------------------------------------------

.expanded-panel {
  background: rgba($surface0, 0.95);
  border: 1px solid rgba($mauve, 0.3);
  border-radius: 12px;
  padding: 12px;
  margin-left: 8px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
}

.volume-panel {
  min-width: 200px;
}

.bluetooth-panel {
  min-width: 220px;
}

.brightness-panel {
  min-width: 200px;
}

.battery-panel {
  min-width: 180px;
}

// -----------------------------------------------------------------------------
// Sliders
// -----------------------------------------------------------------------------

.device-slider {
  min-width: 120px;

  trough {
    background: rgba($overlay0, 0.3);
    border-radius: 4px;
    min-height: 6px;

    highlight {
      background: $blue;
      border-radius: 4px;
    }
  }

  slider {
    background: $text;
    border-radius: 50%;
    min-width: 14px;
    min-height: 14px;
    margin: -4px 0;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);

    &:hover {
      background: $mauve;
    }
  }
}

.brightness-slider trough highlight {
  background: $yellow;
}

.keyboard-slider trough highlight {
  background: $peach;
}

.volume-slider trough highlight {
  background: $blue;
}

// -----------------------------------------------------------------------------
// Buttons
// -----------------------------------------------------------------------------

.panel-button {
  background: rgba($surface1, 0.5);
  border: 1px solid rgba($overlay0, 0.3);
  border-radius: 6px;
  padding: 4px 8px;
  min-width: 28px;
  min-height: 28px;
  transition: all 150ms ease;

  &:hover {
    background: rgba($blue, 0.2);
    border-color: $blue;
  }
}

.close-btn {
  color: $subtext0;

  &:hover {
    color: $red;
    background: rgba($red, 0.15);
    border-color: $red;
  }
}

.mute-toggle {
  &.active {
    background: rgba($red, 0.2);
    border-color: $red;
    color: $red;
  }
}

// -----------------------------------------------------------------------------
// Toggle Switch
// -----------------------------------------------------------------------------

.toggle-switch {
  background: transparent;
  border: none;
  padding: 0;
}

.toggle-track {
  background: rgba($overlay0, 0.4);
  border-radius: 12px;
  min-width: 44px;
  min-height: 24px;
  padding: 2px;
  transition: all 200ms ease;
}

.toggle-thumb {
  background: $text;
  border-radius: 50%;
  min-width: 20px;
  min-height: 20px;
  margin-left: 0;
  transition: all 200ms ease;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
}

.toggle-switch.active {
  .toggle-track {
    background: rgba($teal, 0.6);
  }

  .toggle-thumb {
    margin-left: 20px;
    background: $teal;
  }
}

// -----------------------------------------------------------------------------
// Device List
// -----------------------------------------------------------------------------

.device-list {
  margin-top: 8px;
}

.device-item {
  background: rgba($surface1, 0.3);
  border: 1px solid transparent;
  border-radius: 8px;
  padding: 8px 10px;
  transition: all 150ms ease;

  &:hover {
    background: rgba($surface1, 0.6);
    border-color: rgba($blue, 0.3);
  }

  &.connected {
    border-color: rgba($teal, 0.5);
    background: rgba($teal, 0.1);
  }
}

.device-icon {
  font-size: 18px;
  min-width: 24px;
  color: $subtext0;

  .connected & {
    color: $teal;
  }
}

.device-name {
  font-weight: 500;
}

.device-mac {
  font-size: 10px;
  color: $subtext0;
}

.device-status {
  font-size: 11px;
  color: $teal;
  margin-left: auto;
}

.device-battery {
  font-size: 11px;
  color: $green;
}

// -----------------------------------------------------------------------------
// Battery Indicator
// -----------------------------------------------------------------------------

.battery-indicator {
  .battery-percent {
    font-size: 11px;
    color: $subtext0;
    margin-left: 4px;
  }
}

.battery-icon {
  &.critical { color: $red; }
  &.low { color: $yellow; }
  &.normal { color: $text; }
  &.full { color: $green; }
  &.charging { color: $teal; }
}

// -----------------------------------------------------------------------------
// Panel Rows
// -----------------------------------------------------------------------------

.panel-row {
  padding: 4px 0;
}

.panel-label {
  color: $subtext0;
  min-width: 60px;
}

.panel-value {
  font-weight: 500;
}

.slider-row {
  padding: 4px 0;
}

.slider-label {
  color: $subtext0;
  min-width: 24px;
  font-size: 16px;
}

.slider-value {
  color: $subtext0;
  font-size: 11px;
  min-width: 36px;
  text-align: right;
}

// -----------------------------------------------------------------------------
// Devices Tab (Monitoring Panel)
// -----------------------------------------------------------------------------

.devices-tab {
  padding: 16px;
}

.devices-content {
  padding: 0;
}

.devices-section {
  background: rgba($surface0, 0.6);
  border: 1px solid rgba($overlay0, 0.3);
  border-radius: 12px;
  padding: 12px 16px;
}

.section-title {
  font-size: 14px;
  font-weight: 600;
  color: $blue;
  margin-bottom: 8px;
  padding-bottom: 8px;
  border-bottom: 1px solid rgba($overlay0, 0.2);
}

.section-content {
  padding: 4px 0;
}

// Section-specific colors
.audio-section .section-title { color: $blue; }
.display-section .section-title { color: $yellow; }
.bluetooth-section .section-title { color: $sapphire; }
.power-section .section-title { color: $green; }
.thermal-section .section-title { color: $peach; }
.network-section .section-title { color: $teal; }

// -----------------------------------------------------------------------------
// Device Selector
// -----------------------------------------------------------------------------

.device-selector {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid rgba($overlay0, 0.2);
}

.device-option {
  background: rgba($surface1, 0.3);
  border: 1px solid transparent;
  border-radius: 8px;
  padding: 8px 12px;
  text-align: left;
  transition: all 150ms ease;

  &:hover {
    background: rgba($surface1, 0.6);
    border-color: rgba($blue, 0.3);
  }

  &.active {
    border-color: $blue;
    background: rgba($blue, 0.15);
  }
}

.device-type-icon {
  font-size: 16px;
  color: $subtext0;
  min-width: 24px;
}

// -----------------------------------------------------------------------------
// Battery Section (Devices Tab)
// -----------------------------------------------------------------------------

.battery-status {
  padding: 8px 0;
}

.battery-icon {
  font-size: 32px;
}

.battery-info {
  margin-left: 4px;
}

.battery-percent-large {
  font-size: 24px;
  font-weight: 700;
}

.battery-state {
  font-size: 12px;
  color: $subtext0;
}

.time-remaining {
  font-size: 14px;
  color: $subtext0;
  padding: 4px 12px;
  background: rgba($surface1, 0.4);
  border-radius: 8px;
}

.battery-details {
  margin-top: 8px;
  padding: 8px 12px;
  background: rgba($surface1, 0.3);
  border-radius: 8px;
}

.detail-item {
  flex-direction: column;
}

.detail-label {
  font-size: 10px;
  color: $subtext0;
  text-transform: uppercase;
}

.detail-value {
  font-size: 14px;
  font-weight: 500;
}

// -----------------------------------------------------------------------------
// Power Profiles
// -----------------------------------------------------------------------------

.power-profiles {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid rgba($overlay0, 0.2);
}

.profile-btn {
  background: rgba($surface1, 0.3);
  border: 1px solid transparent;
  border-radius: 8px;
  padding: 8px 12px;
  flex: 1;
  transition: all 150ms ease;

  &:hover {
    background: rgba($surface1, 0.6);
    border-color: rgba($mauve, 0.3);
  }

  &.active {
    border-color: $mauve;
    background: rgba($mauve, 0.15);
  }
}

// -----------------------------------------------------------------------------
// Thermal Section
// -----------------------------------------------------------------------------

.thermal-row {
  padding: 8px 0;
}

.thermal-icon {
  font-size: 28px;

  &.cool { color: $teal; }
  &.warm { color: $yellow; }
  &.hot { color: $peach; }
  &.critical { color: $red; }
}

.thermal-info {
  margin-left: 4px;
}

.thermal-label {
  font-size: 12px;
  color: $subtext0;
}

.thermal-value {
  font-size: 18px;
  font-weight: 600;

  &.cool { color: $teal; }
  &.warm { color: $yellow; }
  &.hot { color: $peach; }
  &.critical { color: $red; }
}

.thermal-bar {
  min-width: 100px;
  margin-left: auto;

  trough {
    background: rgba($overlay0, 0.3);
    border-radius: 4px;
    min-height: 8px;

    progress {
      border-radius: 4px;
    }
  }

  &.cool trough progress { background: $teal; }
  &.warm trough progress { background: $yellow; }
  &.hot trough progress { background: $peach; }
  &.critical trough progress { background: $red; }
}

.fan-row {
  padding: 4px 0;
  margin-top: 4px;
}

.fan-icon {
  font-size: 16px;
  color: $subtext0;
}

.fan-label {
  color: $subtext0;
  font-size: 12px;
}

.fan-value {
  font-size: 14px;
  margin-left: auto;
}

// -----------------------------------------------------------------------------
// Network Section
// -----------------------------------------------------------------------------

.network-row {
  padding: 8px 0;

  &:not(:last-child) {
    border-bottom: 1px solid rgba($overlay0, 0.15);
  }
}

.network-icon {
  font-size: 20px;
  color: $subtext0;
  min-width: 28px;

  &.connected {
    color: $teal;
  }

  &.disconnected {
    color: $overlay0;
  }
}

.network-info {
  margin-left: 4px;
}

.network-type {
  font-size: 11px;
  color: $subtext0;
  text-transform: uppercase;
}

.network-value {
  font-size: 14px;
  font-weight: 500;
}

.signal-strength {
  font-size: 12px;
  color: $teal;
  margin-left: auto;
}

// -----------------------------------------------------------------------------
// Connect Button
// -----------------------------------------------------------------------------

.connect-btn {
  background: rgba($blue, 0.15);
  border: 1px solid rgba($blue, 0.3);
  border-radius: 6px;
  padding: 4px 12px;
  font-size: 11px;
  margin-left: auto;
  transition: all 150ms ease;

  &:hover {
    background: rgba($blue, 0.3);
    border-color: $blue;
  }

  .connected & {
    background: rgba($red, 0.15);
    border-color: rgba($red, 0.3);
    color: $red;

    &:hover {
      background: rgba($red, 0.3);
      border-color: $red;
    }
  }
}

// -----------------------------------------------------------------------------
// Mute Button (Devices Tab)
// -----------------------------------------------------------------------------

.mute-btn {
  background: rgba($surface1, 0.5);
  border: 1px solid rgba($overlay0, 0.3);
  border-radius: 6px;
  padding: 4px 8px;
  min-width: 28px;
  transition: all 150ms ease;

  &:hover {
    background: rgba($blue, 0.2);
    border-color: $blue;
  }

  &.muted {
    background: rgba($red, 0.2);
    border-color: $red;
    color: $red;
  }
}
''

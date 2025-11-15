{ config, lib, pkgs, ... }:

# Feature 061: Eww Top Bar - GTK CSS Styling
# Catppuccin Mocha theme colors from Feature 057

''
  /* Feature 061: Eww Top Bar Polish & Completion */
  /* GTK CSS Styling with Catppuccin Mocha Theme */

  /* ========================================================================== */
  /* Color Palette - Catppuccin Mocha (from Feature 057) */
  /* ========================================================================== */

  * {
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 11px;
  }

  label {
    all: unset;
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 11px;
  }

  /* Top Bar Container */
  .top-bar {
    background-color: #1e1e2e; /* base */
    color: #cdd6f4; /* text */
    padding: 2px 6px;
  }

  /* Block sections */
  .left-block,
  .center-block,
  .right-block {
    min-width: 0;
  }

  /* Metric Blocks (widgets) */
  .metric-block {
    padding: 2px 4px;
    margin: 0;
    border-radius: 2px;
    transition: background-color 0.15s ease-in-out;
  }

  .metric-block:hover {
    background-color: rgba(69, 71, 90, 0.6); /* surface1 */
  }

  .metric-block:active {
    background-color: rgba(69, 71, 90, 0.8); /* surface1 darker */
    transition: background-color 0.1s ease-in-out;
  }

  /* Widget Labels */
  .widget-label {
    color: #cdd6f4; /* text */
    margin-right: 4px;
  }

  .widget-value {
    color: #89b4fa; /* blue */
    font-weight: bold;
  }

  /* System Tray Styling */
  .systray {
    padding: 0 4px;
  }

  /* WiFi Widget Styling */
  .wifi-widget {
    padding: 4px 8px;
  }

  .wifi-icon {
    margin-right: 4px;
    transition: color 0.3s ease-in-out;
  }

  .wifi-icon.signal-strong {
    color: #a6e3a1; /* green */
  }

  .wifi-icon.signal-medium {
    color: #f9e2af; /* yellow */
  }

  .wifi-icon.signal-weak {
    color: #fab387; /* orange */
  }

  .wifi-icon.disconnected {
    color: #6c7086; /* overlay0 / gray */
  }

  /* Volume Widget Styling */
  .volume-widget {
    padding: 4px 8px;
  }

  .volume-icon {
    margin-right: 4px;
    transition: color 0.3s ease-in-out;
  }

  /* Volume Slider Popup */
  .volume-popup {
    background-color: #313244; /* surface0 */
    border: 1px solid #45475a; /* surface1 */
    border-radius: 8px;
    padding: 12px;
  }

  .volume-slider scale trough {
    background-color: rgba(108, 112, 134, 0.3); /* overlay0 */
    border-radius: 4px;
    min-height: 6px;
    min-width: 200px;
  }

  .volume-slider scale highlight {
    background-color: #89b4fa; /* blue */
    border-radius: 4px;
    transition: all 0.3s ease-in-out;
  }

  .volume-slider scale slider {
    background-color: #cdd6f4; /* text */
    border-radius: 50%;
    min-height: 16px;
    min-width: 16px;
  }

  .volume-mute-button {
    margin-top: 8px;
    padding: 6px 12px;
    background-color: #45475a; /* surface1 */
    border-radius: 4px;
    transition: background-color 0.15s ease-in-out;
  }

  .volume-mute-button:hover {
    background-color: #585b70; /* surface2 */
  }

  /* Calendar Popup */
  .calendar-popup {
    background-color: #313244; /* surface0 */
    border: 1px solid #45475a; /* surface1 */
    border-radius: 8px;
    padding: 12px;
  }

  .calendar-widget {
    color: #cdd6f4; /* text */
  }

  .calendar-widget:selected {
    background-color: #89b4fa; /* blue */
    color: #1e1e2e; /* base */
    border-radius: 4px;
  }

  /* Daemon Health Widget */
  .daemon-health {
    padding: 4px 8px;
  }

  .daemon-health.healthy {
    color: #a6e3a1; /* green */
  }

  .daemon-health.slow {
    color: #f9e2af; /* yellow */
  }

  .daemon-health.unhealthy {
    color: #f38ba8; /* red */
  }

  /* Date/Time Widget */
  .datetime-widget {
    padding: 4px 12px;
    font-weight: 500;
  }

  /* Icon Transitions */
  .widget-icon {
    transition: color 0.3s ease-in-out;
  }

  /* Popup Animations (handled by Eww revealer widget) */
  revealer {
    transition: all 0.2s ease-in-out;
  }
''

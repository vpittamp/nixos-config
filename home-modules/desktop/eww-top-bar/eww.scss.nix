{ config, lib, pkgs, ... }:

# Feature 061: Eww Top Bar - GTK CSS Styling
# Catppuccin Mocha theme colors from Feature 057

''
  /* Eww Top Bar - Modeled after successful eww bars */
  /* Catppuccin Mocha theme */

  * {
    all: unset;
    font-family: "JetBrainsMono Nerd Font", monospace;
  }

  /* Bar container */
  .bar {
    background-color: #1e1e2e;
    color: #cdd6f4;
    padding: 5px;
    font-size: 11px;
  }

  /* Sections */
  .left,
  .center,
  .right {
    margin: 0 10px;
  }

  /* Metric widgets */
  .metric {
    padding: 0 5px;
  }

  .metric .icon {
    color: #89b4fa;
    margin-right: 5px;
  }

  .metric .value {
    color: #cdd6f4;
  }

  .metric:hover {
    background-color: rgba(69, 71, 90, 0.5);
    border-radius: 4px;
  }

  /* System tray */
  .systray {
    padding: 0 5px;
  }

  /* Volume popup */
  .volume-popup {
    background-color: #313244;
    border: 1px solid #45475a;
    border-radius: 8px;
    padding: 12px;
  }

  .volume-slider scale trough {
    background-color: rgba(108, 112, 134, 0.3);
    border-radius: 4px;
    min-height: 6px;
    min-width: 200px;
  }

  .volume-slider scale highlight {
    background-color: #89b4fa;
    border-radius: 4px;
  }

  .volume-slider scale slider {
    background-color: #cdd6f4;
    border-radius: 50%;
    min-height: 16px;
    min-width: 16px;
  }

  .volume-mute-button {
    margin-top: 8px;
    padding: 6px 12px;
    background-color: #45475a;
    border-radius: 4px;
  }

  .volume-mute-button:hover {
    background-color: #585b70;
  }
''

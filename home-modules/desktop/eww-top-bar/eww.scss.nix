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

  /* Feature 079: US7 - T054/T055 - Project block styling with accent colors */
  .project-block {
    padding: 2px 8px;
    border-radius: 6px;
    background-color: rgba(69, 71, 90, 0.3);
    transition: all 0.2s;
  }

  .project-block:hover {
    background-color: rgba(69, 71, 90, 0.6);
  }

  /* Worktree projects with Catppuccin Mocha peach accent (#fab387) */
  .project-block-worktree {
    padding: 2px 8px;
    border-radius: 6px;
    background-color: rgba(250, 179, 135, 0.15);
    border: 1px solid rgba(250, 179, 135, 0.3);
    transition: all 0.2s;
  }

  .project-block-worktree:hover {
    background-color: rgba(250, 179, 135, 0.25);
    border: 1px solid rgba(250, 179, 135, 0.5);
  }

  .project-block-worktree .project-value {
    color: #fab387;
    font-weight: 600;
  }

  .project-block-worktree .project-icon {
    color: #fab387;
  }
''

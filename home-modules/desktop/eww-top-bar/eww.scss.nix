{ config, lib, pkgs, ... }:

# Feature 061: Eww Top Bar - GTK CSS Styling (refreshed)
# Catppuccin Mocha palette + glassy pills inspired by saimoomedits widgets

''
  * {
    all: unset;
    font-family: "JetBrainsMono Nerd Font", "Inter", monospace;
  }

  /* Bar container */
  .bar {
    background-color: rgba(30, 30, 46, 0.9);
    color: #cdd6f4;
    padding: 2px 3px;
    font-size: 10px;
    border: 1px solid #313244;
    border-radius: 6px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.25), 0 0 0 1px rgba(203, 166, 247, 0.06);
  }

  .left, .center, .right {
    margin: 0 3px;
  }

  /* Pill foundation */
  .pill {
    background: rgba(49, 50, 68, 0.65);
    border: 1px solid rgba(108, 112, 134, 0.45);
    border-radius: 7px;
    padding: 1px 4px;
    min-height: 13px;
    transition: background 120ms ease, border 120ms ease;
  }

  .pill:hover {
    background: rgba(69, 71, 90, 0.65);
    border-color: #cba6f7;
  }

  .metric-pill {
    color: #cdd6f4;
  }

  .icon {
    font-size: 10px;
    margin-right: 1px;
    color: #cba6f7;
  }

  /* Reintroduce minimal text so styling shows, but tiny to keep height low */
  .value {
    font-size: 9px;
    font-weight: 600;
    margin-left: 1px;
  }
  .subtext { color: #a6adc8; font-size: 7px; }

  .separator {
    color: #585b70;
    margin: 0 4px;
    font-weight: 700;
  }

  /* Meters and progress fills */
  .meter scale {
    min-width: 44px;
    min-height: 3px;
  }

  .meter scale trough {
    background: rgba(49, 50, 68, 0.9);
    border-radius: 10px;
  }

  .meter scale highlight {
    border-radius: 10px;
    background: #89b4fa;
  }

  .meter-mem scale highlight { background: linear-gradient(90deg, #74c7ec, #89dceb); }
  .meter-disk scale highlight { background: linear-gradient(90deg, #fab387, #f9e2af); }
  .meter-temp scale highlight { background: linear-gradient(90deg, #fab387, #f38ba8); }
  .meter-net scale highlight { background: linear-gradient(90deg, #94e2d5, #89dceb); }
  .meter-wifi scale highlight { background: linear-gradient(90deg, #a6e3a1, #74c7ec); }
  .meter-volume scale highlight { background: linear-gradient(90deg, #cba6f7, #89b4fa); }
  .meter-battery scale highlight { background: linear-gradient(90deg, #a6e3a1, #f9e2af); }

  /* Color accents per metric */
  .cpu .icon { color: #89b4fa; }
  .mem .icon { color: #74c7ec; }
  .disk .icon { color: #fab387; }
  .temp .icon { color: #f38ba8; }
  .net .icon { color: #94e2d5; }
  .wifi .icon { color: #a6e3a1; }
  .volume .icon { color: #cba6f7; }
  .battery-normal .icon, .battery .icon { color: #a6e3a1; }
  .battery-low { color: #f9e2af; }
  .battery-critical { color: #f38ba8; }
  .bluetooth-icon { color: #89b4fa; }
  .daemon-healthy { color: #a6e3a1; }
  .daemon-slow { color: #f9e2af; }
  .daemon-unhealthy { color: #f38ba8; }

  .wifi-disconnected .icon { color: #6c7086; }

  /* Project pill accents */
  .project-pill {
    background: rgba(250, 179, 135, 0.12);
    border: 1px solid rgba(250, 179, 135, 0.28);
  }

  .project-pill:hover {
    background: rgba(250, 179, 135, 0.18);
    border-color: rgba(250, 179, 135, 0.4);
  }

  .project-pill .value,
  .project-pill .icon { color: #fab387; }

  .project-pill-worktree {
    background: rgba(148, 226, 213, 0.14);
    border: 1px solid rgba(148, 226, 213, 0.35);
  }

  .project-pill-worktree .value,
  .project-pill-worktree .icon { color: #94e2d5; }

  /* Time pill */
  .time-pill {
    background: rgba(69, 71, 90, 0.35);
    border: 1px solid rgba(203, 166, 247, 0.35);
    padding-right: 10px;
  }

  .time-pill .icon { color: #cba6f7; }
  .time-value { color: #cdd6f4; }

  /* Volume popup styling */
  .volume-popup {
    background-color: #313244;
    border: 1px solid #45475a;
    border-radius: 12px;
    padding: 12px;
    box-shadow: 0 12px 30px rgba(0, 0, 0, 0.4);
  }

  .volume-slider scale trough {
    background-color: rgba(108, 112, 134, 0.3);
    border-radius: 6px;
    min-height: 6px;
    min-width: 140px;
  }

  .volume-slider scale highlight {
    background-color: #89b4fa;
    border-radius: 6px;
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
    border-radius: 6px;
  }

  .volume-mute-button:hover {
    background-color: #585b70;
  }

  /* Systray */
  .metric-block systray {
    padding: 0 4px;
  }

  /* Fallback container for legacy metric blocks (systray) */
  .metric-block {
    padding: 0 4px;
  }
''

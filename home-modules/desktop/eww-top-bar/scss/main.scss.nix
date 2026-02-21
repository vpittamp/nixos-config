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
    padding: 3px 6px;
    font-size: 11px;
    border: 1px solid #313244;
    border-radius: 7px;
    box-shadow: 0 8px 22px rgba(0, 0, 0, 0.22), 0 0 0 1px rgba(203, 166, 247, 0.05);
  }

  .left, .center, .right {
    margin: 0 4px;
  }

  /* Pill foundation */
  .pill {
    background: rgba(49, 50, 68, 0.65);
    border: 1px solid rgba(108, 112, 134, 0.45);
    border-radius: 8px;
    padding: 2px 6px;
    min-height: 14px;
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
    margin-right: 2px;
    color: #cba6f7;
  }

  /* Reintroduce minimal text so styling shows, but tiny to keep height low */
  .value {
    font-size: 9px;
    font-weight: 600;
    margin-left: 0;
  }
  .subtext { color: #a6adc8; font-size: 7px; }

  .separator {
    color: #585b70;
    margin: 0 4px;
    font-weight: 700;
  }

  /* Meters and progress fills */
  .meter scale {
    min-width: 40px;
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
  .meter-brightness scale highlight { background: linear-gradient(90deg, #f9e2af, #fab387); }
  .meter-battery scale highlight { background: linear-gradient(90deg, #a6e3a1, #f9e2af); }

  /* Color accents per metric */
  .cpu .icon { color: #89b4fa; }
  .mem .icon { color: #74c7ec; }
  .disk .icon { color: #fab387; }
  .temp .icon { color: #f38ba8; }
  .net .icon { color: #94e2d5; }
  .wifi .icon { color: #a6e3a1; }
  .volume .icon { color: #cba6f7; }
  .brightness .icon { color: #f9e2af; }
  .battery-normal .icon, .battery .icon { color: #a6e3a1; }
  .battery-icon-low { color: #f9e2af; }
  .battery-icon-very-low { color: #fab387; }
  .battery-icon-critical { color: #f38ba8; font-weight: bold; }
  .battery-time { color: #a6adc8; font-size: 0.85em; margin-left: 2px; }
  .bluetooth-icon { color: #89b4fa; }

  /* Battery level state backgrounds */
  .battery-low {
    background: rgba(249, 226, 175, 0.12);
    border-color: rgba(249, 226, 175, 0.4);
  }
  .battery-very-low {
    background: rgba(250, 179, 135, 0.15);
    border-color: rgba(250, 179, 135, 0.5);
  }
  .battery-critical {
    background: rgba(243, 139, 168, 0.25);
    border-color: rgba(243, 139, 168, 0.7);
  }

  .health-healthy { color: #a6e3a1; }
  .health-warning { color: #f9e2af; }
  .health-error { color: #f38ba8; }

  /* Bluetooth states */
  .bluetooth-connected {
    background: rgba(137, 180, 250, 0.16);
    border-color: rgba(137, 180, 250, 0.55);
  }

  .bluetooth-connected .icon,
  .bluetooth-connected .bluetooth-count { color: #89b4fa; }

  .bluetooth-enabled {
    background: rgba(108, 112, 134, 0.16);
    border-color: rgba(108, 112, 134, 0.45);
  }

  .bluetooth-enabled .icon,
  .bluetooth-enabled .bluetooth-count { color: #a6adc8; }

  .bluetooth-disabled {
    background: rgba(69, 71, 90, 0.24);
    border-color: rgba(69, 71, 90, 0.45);
  }

  .bluetooth-disabled .icon { color: #6c7086; }

  .bluetooth-count {
    padding: 0 4px;
    margin-left: 1px;
    border-radius: 6px;
    background: rgba(137, 180, 250, 0.12);
    font-weight: 700;
  }

  .bluetooth-enabled .bluetooth-count,
  .bluetooth-disabled .bluetooth-count { background: transparent; }

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

  .project-pill-worktree:hover {
    background: rgba(148, 226, 213, 0.2);
    border-color: rgba(148, 226, 213, 0.55);
  }

  .project-pill-worktree .value,
  .project-pill-worktree .icon { color: #94e2d5; }

  .project-pill-local {
    background: linear-gradient(135deg, rgba(137, 180, 250, 0.2), rgba(148, 226, 213, 0.16));
    border: 1px solid rgba(137, 180, 250, 0.62);
    box-shadow: inset 0 0 8px rgba(137, 180, 250, 0.15);
  }

  .project-pill-local:hover {
    background: linear-gradient(135deg, rgba(137, 180, 250, 0.3), rgba(148, 226, 213, 0.24));
    border-color: rgba(137, 180, 250, 0.85);
    box-shadow: 0 0 14px rgba(137, 180, 250, 0.26);
  }

  .project-pill-local .project-value,
  .project-pill-local .project-icon {
    color: #89b4fa;
    font-weight: 700;
  }

  .project-pill-ssh {
    background: linear-gradient(135deg, rgba(166, 227, 161, 0.26), rgba(249, 226, 175, 0.2));
    border: 1px solid rgba(166, 227, 161, 0.75);
    box-shadow: 0 0 12px rgba(166, 227, 161, 0.26),
                inset 0 0 10px rgba(249, 226, 175, 0.16);
  }

  .project-pill-ssh:hover {
    background: linear-gradient(135deg, rgba(166, 227, 161, 0.34), rgba(249, 226, 175, 0.28));
    border-color: rgba(249, 226, 175, 0.92);
    box-shadow: 0 0 16px rgba(166, 227, 161, 0.42),
                0 4px 14px rgba(249, 226, 175, 0.24);
  }

  .project-pill-ssh .project-value,
  .project-pill-ssh .project-icon {
    color: #a6e3a1;
    font-weight: 700;
  }

  .project-connection-chip {
    font-size: 12px;
    font-weight: 800;
    letter-spacing: 0;
    border-radius: 7px;
    padding: 1px 5px;
    min-width: 18px;
  }

  .project-connection-chip-ssh {
    color: #a6e3a1;
    background: rgba(22, 32, 22, 0.84);
    border: 1px solid rgba(166, 227, 161, 0.78);
    box-shadow: 0 0 8px rgba(166, 227, 161, 0.24);
  }

  .project-connection-chip-local {
    color: #89b4fa;
    background: rgba(20, 34, 50, 0.82);
    border: 1px solid rgba(137, 180, 250, 0.72);
    box-shadow: 0 0 8px rgba(137, 180, 250, 0.24);
  }

  .project-ssh-target {
    font-size: 9px;
    font-weight: 700;
    font-family: "JetBrainsMono Nerd Font", monospace;
    color: #f9e2af;
    background: rgba(34, 33, 21, 0.78);
    border-radius: 6px;
    padding: 1px 6px;
    border: 1px solid rgba(249, 226, 175, 0.45);
  }

  /* Time pill */
  .time-pill {
    background: rgba(69, 71, 90, 0.35);
    border: 1px solid rgba(203, 166, 247, 0.35);
    padding-right: 8px;
  }

  .time-pill .icon { color: #cba6f7; }
  .time-value { color: #cdd6f4; }

  /* Status shelf trigger for secondary badges */
  .status-shelf-toggle {
    background: linear-gradient(135deg, rgba(69, 71, 90, 0.6), rgba(49, 50, 68, 0.75));
    border-color: rgba(108, 112, 134, 0.58);
    padding-left: 7px;
    padding-right: 7px;
  }

  .status-shelf-toggle:hover {
    border-color: rgba(148, 226, 213, 0.75);
    box-shadow: 0 2px 8px rgba(148, 226, 213, 0.25);
  }

  .status-shelf-icon {
    color: #94e2d5;
    font-size: 11px;
  }

  .status-shelf-alert {
    background: linear-gradient(135deg, rgba(243, 139, 168, 0.2), rgba(250, 179, 135, 0.18));
    border-color: rgba(243, 139, 168, 0.65);
    box-shadow: 0 0 12px rgba(243, 139, 168, 0.24);
  }

  /* Compact always-visible health indicator */
  .health-dot-pill {
    min-width: 12px;
    padding: 2px 5px;
  }

  .health-dot-icon {
    font-size: 10px;
    margin-right: 0;
  }

  .health-dot-healthy .health-dot-icon { color: #a6e3a1; }
  .health-dot-warning .health-dot-icon { color: #f9e2af; }
  .health-dot-error .health-dot-icon { color: #f38ba8; }
  .health-dot-unknown .health-dot-icon { color: #6c7086; }

  /* Popup badge shelf */
  .badge-shelf-window {
    background: transparent;
    padding: 0;
  }

  .badge-shelf-card {
    background: linear-gradient(180deg, rgba(24, 24, 37, 0.97), rgba(30, 30, 46, 0.95));
    border: 1px solid rgba(108, 112, 134, 0.45);
    border-top: 0;
    border-radius: 0 0 12px 12px;
    padding: 4px 7px;
    margin-left: 6px;
    margin-right: 6px;
    min-width: 960px;
    box-shadow: 0 12px 26px rgba(0, 0, 0, 0.42), 0 1px 0 rgba(203, 166, 247, 0.04) inset;
  }

  .badge-shelf-header {
    padding: 1px 2px 3px 2px;
  }

  .badge-shelf-title {
    font-size: 12px;
    font-weight: 800;
    color: #cdd6f4;
  }

  .badge-shelf-subtitle {
    font-size: 10px;
    color: #a6adc8;
  }

  .badge-shelf-group-title {
    font-size: 10px;
    font-weight: 800;
    color: #89b4fa;
    letter-spacing: 0.2px;
    margin-left: 2px;
    min-width: 86px;
    margin-top: 2px;
  }

  .badge-shelf-group-items {
    margin-right: 4px;
    min-height: 18px;
  }

  .badge-shelf-card .pill {
    border-radius: 7px;
    min-height: 13px;
    padding: 1px 4px;
  }

  .badge-shelf-close {
    background: rgba(69, 71, 90, 0.55);
    border: 1px solid rgba(108, 112, 134, 0.45);
    border-radius: 7px;
    padding: 1px 7px;
    font-size: 11px;
    font-weight: 800;
    color: #a6adc8;
    margin-left: 4px;
  }

  .badge-shelf-close:hover {
    border-color: rgba(203, 166, 247, 0.75);
    color: #cba6f7;
  }

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

  /* Monitor toggle styling */
  .metric-block.monitor-toggle {
    padding: 4px 6px;
    .icon { margin-right: 6px; color: #89b4fa; }
    .pill {
      background: rgba(137, 180, 250, 0.15);
      color: #cdd6f4;
      border: 1px solid rgba(137, 180, 250, 0.35);
      border-radius: 8px;
      padding: 3px 10px;
      min-width: 40px;
      font-weight: 700;
      transition: background 0.15s ease, border 0.15s ease;
      &:hover { background: rgba(137, 180, 250, 0.25); }
    }
    .pill + .pill { margin-left: 4px; }
    .pill-text {
      color: #cdd6f4;
      font-weight: 800;
      font-size: 11px;
      letter-spacing: 0.5px;
    }
    .pill-text.dim {
      color: #6c7086;
      opacity: 0.85;
    }
  }

  /* Feature 083: Consolidated monitor profile widget styling */
  .monitor-profile {
    background: rgba(148, 226, 213, 0.12);
    border: 1px solid rgba(148, 226, 213, 0.35);
  }

  .monitor-profile:hover {
    background: rgba(148, 226, 213, 0.18);
    border-color: rgba(148, 226, 213, 0.5);
  }

  .monitor-profile .icon,
  .monitor-profile-icon {
    color: #94e2d5;
    font-size: 10px;
  }

  .monitor-profile-name {
    color: #94e2d5;
    font-weight: 700;
  }

  /* Monitor output indicators */
  .monitor-indicators {
    margin-left: 4px;
  }

  .monitor-dot {
    font-size: 8px;
    transition: color 150ms ease;
  }

  .monitor-dot-active {
    color: #89b4fa;
    text-shadow: 0 0 4px rgba(137, 180, 250, 0.6);
  }

  .monitor-dot-inactive {
    color: #45475a;
    opacity: 0.6;
  }

  /* Feature 085: Monitoring panel toggle button styling */
  .monitoring-toggle {
    background: linear-gradient(135deg, rgba(69, 71, 90, 0.5), rgba(49, 50, 68, 0.6));
    border: 1px solid rgba(108, 112, 134, 0.4);
    padding: 2px 6px;
    transition: all 200ms ease;
  }

  .monitoring-toggle:hover {
    background: linear-gradient(135deg, rgba(203, 166, 247, 0.15), rgba(137, 180, 250, 0.12));
    border-color: rgba(203, 166, 247, 0.6);
    box-shadow: 0 2px 8px rgba(203, 166, 247, 0.3);
  }

  .monitoring-toggle-active {
    background: linear-gradient(135deg, rgba(203, 166, 247, 0.35), rgba(137, 180, 250, 0.25));
    border: 1px solid rgba(203, 166, 247, 0.8);
    box-shadow: 0 0 12px rgba(203, 166, 247, 0.5),
                inset 0 0 8px rgba(203, 166, 247, 0.2);
    /* Animation disabled for CPU savings */
  }

  .monitoring-toggle-active:hover {
    background: linear-gradient(135deg, rgba(203, 166, 247, 0.45), rgba(137, 180, 250, 0.35));
    border-color: rgba(203, 166, 247, 0.95);
    box-shadow: 0 0 16px rgba(203, 166, 247, 0.7),
                0 4px 12px rgba(203, 166, 247, 0.4),
                inset 0 0 12px rgba(203, 166, 247, 0.3);
  }

  .monitoring-toggle-icon {
    color: #a6adc8;
    font-size: 12px;
    transition: all 200ms ease;
  }

  .monitoring-toggle:hover .monitoring-toggle-icon {
    color: #cba6f7;
  }

  .monitoring-toggle-active .monitoring-toggle-icon {
    color: #cba6f7;
    text-shadow: 0 0 8px rgba(203, 166, 247, 0.9),
                 0 0 4px rgba(203, 166, 247, 0.6);
  }

  /* Notification center toggle button styling (SwayNC) */
  .notification-toggle {
    background: linear-gradient(135deg, rgba(69, 71, 90, 0.5), rgba(49, 50, 68, 0.6));
    border: 1px solid rgba(108, 112, 134, 0.4);
    padding: 2px 6px;
    transition: all 200ms ease;
  }

  .notification-toggle:hover {
    background: linear-gradient(135deg, rgba(137, 180, 250, 0.15), rgba(166, 227, 161, 0.12));
    border-color: rgba(137, 180, 250, 0.6);
    box-shadow: 0 2px 8px rgba(137, 180, 250, 0.3);
  }

  .notification-toggle-active {
    background: linear-gradient(135deg, rgba(137, 180, 250, 0.35), rgba(166, 227, 161, 0.25));
    border: 1px solid rgba(137, 180, 250, 0.8);
    box-shadow: 0 0 12px rgba(137, 180, 250, 0.5),
                inset 0 0 8px rgba(137, 180, 250, 0.2);
    /* Animation disabled for CPU savings */
  }

  .notification-toggle-active:hover {
    background: linear-gradient(135deg, rgba(137, 180, 250, 0.45), rgba(166, 227, 161, 0.35));
    border-color: rgba(137, 180, 250, 0.95);
    box-shadow: 0 0 16px rgba(137, 180, 250, 0.7),
                0 4px 12px rgba(137, 180, 250, 0.4),
                inset 0 0 12px rgba(137, 180, 250, 0.3);
  }

  .notification-toggle-icon {
    color: #a6adc8;
    font-size: 12px;
    transition: all 200ms ease;
  }

  .notification-toggle:hover .notification-toggle-icon {
    color: #89b4fa;
  }

  .notification-toggle-active .notification-toggle-icon {
    color: #89b4fa;
    text-shadow: 0 0 8px rgba(137, 180, 250, 0.9),
                 0 0 4px rgba(137, 180, 250, 0.6);
  }

  /* Feature 110: Notification badge styling */

  /* Has unread notifications - red/peach gradient glow (no animation for CPU savings) */
  .notification-has-unread {
    background: linear-gradient(135deg, rgba(243, 139, 168, 0.25), rgba(250, 179, 135, 0.2));
    border: 1px solid rgba(243, 139, 168, 0.7);
    box-shadow: 0 0 12px rgba(243, 139, 168, 0.4),
                inset 0 0 8px rgba(243, 139, 168, 0.15);
    /* Animation disabled for CPU savings - static glow is sufficient */
  }

  .notification-has-unread:hover {
    background: linear-gradient(135deg, rgba(243, 139, 168, 0.35), rgba(250, 179, 135, 0.3));
    border-color: rgba(243, 139, 168, 0.9);
    box-shadow: 0 0 16px rgba(243, 139, 168, 0.6),
                0 4px 12px rgba(243, 139, 168, 0.3),
                inset 0 0 12px rgba(243, 139, 168, 0.2);
  }

  .notification-has-unread .notification-toggle-icon {
    color: #f38ba8;
    text-shadow: 0 0 8px rgba(243, 139, 168, 0.8),
                 0 0 4px rgba(243, 139, 168, 0.5);
  }

  /* DND mode styling - muted gray */
  .notification-dnd {
    background: linear-gradient(135deg, rgba(69, 71, 90, 0.4), rgba(49, 50, 68, 0.5));
    border: 1px solid rgba(108, 112, 134, 0.5);
  }

  .notification-dnd:hover {
    background: linear-gradient(135deg, rgba(69, 71, 90, 0.5), rgba(49, 50, 68, 0.6));
    border-color: rgba(108, 112, 134, 0.7);
  }

  .notification-icon-dnd {
    color: #6c7086;
  }

  .notification-icon-empty {
    color: #a6adc8;
  }

  .notification-icon-active {
    color: #f38ba8;
  }

  /* Badge count styling - red/peach gradient pill */
  .notification-badge-count {
    background: linear-gradient(135deg, #f38ba8, #fab387);
    color: #1e1e2e;
    font-size: 8px;
    font-weight: 800;
    padding: 0 4px;
    margin-left: 2px;
    border-radius: 6px;
    min-width: 12px;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
  }

  /* Feature 117: AI Sessions widget styling */
  .ai-sessions-container {
    margin-left: 8px;
  }

  /* AI chip base styling */
  .ai-chip {
    background: rgba(49, 50, 68, 0.65);
    border: 1px solid rgba(108, 112, 134, 0.45);
    border-radius: 12px;
    padding: 3px 8px;
    min-height: 20px;
    transition: all 150ms ease;
  }

  .ai-chip:hover {
    background: rgba(69, 71, 90, 0.7);
    border-color: rgba(148, 226, 213, 0.6);
    box-shadow: 0 2px 8px rgba(148, 226, 213, 0.3);
  }

  /* Working state - teal glow (animation disabled for CPU savings) */
  .ai-chip.working {
    background: linear-gradient(135deg, rgba(148, 226, 213, 0.2), rgba(137, 180, 250, 0.15));
    border: 1px solid rgba(148, 226, 213, 0.6);
    box-shadow: 0 0 10px rgba(148, 226, 213, 0.4),
                inset 0 0 6px rgba(148, 226, 213, 0.15);
    /* animation: ai-working-pulse 2s ease-in-out infinite; - disabled for CPU */
  }

  .ai-chip.working:hover {
    background: linear-gradient(135deg, rgba(148, 226, 213, 0.3), rgba(137, 180, 250, 0.2));
    box-shadow: 0 0 14px rgba(148, 226, 213, 0.6);
  }

  /* Attention state - peach/red highlight (no animation for CPU savings) */
  .ai-chip.attention {
    background: linear-gradient(135deg, rgba(250, 179, 135, 0.25), rgba(243, 139, 168, 0.2));
    border: 1px solid rgba(250, 179, 135, 0.7);
    box-shadow: 0 0 10px rgba(250, 179, 135, 0.4),
                inset 0 0 6px rgba(250, 179, 135, 0.15);
    /* Animation disabled for CPU savings */
  }

  .ai-chip.attention:hover {
    background: linear-gradient(135deg, rgba(250, 179, 135, 0.35), rgba(243, 139, 168, 0.3));
    box-shadow: 0 0 14px rgba(250, 179, 135, 0.6);
  }

  /* Idle state - muted/dimmed */
  .ai-chip.idle {
    background: rgba(49, 50, 68, 0.4);
    border: 1px solid rgba(108, 112, 134, 0.35);
    opacity: 0.7;
  }

  .ai-chip.idle:hover {
    opacity: 1;
    background: rgba(69, 71, 90, 0.5);
  }

  /* Focused state - highlight when this AI session's window is currently focused */
  /* Adds bright lavender border and subtle glow to indicate "you are here" */
  .ai-chip.focused {
    border-width: 2px;
    border-style: solid;
    border-color: rgba(203, 166, 247, 0.9);
    box-shadow: 0 0 12px rgba(203, 166, 247, 0.6),
                0 0 4px rgba(203, 166, 247, 0.8),
                inset 0 0 8px rgba(203, 166, 247, 0.15);
  }

  /* Focused + working: combine teal working glow with lavender focus ring */
  .ai-chip.focused.working {
    border-width: 2px;
    border-style: solid;
    border-color: rgba(203, 166, 247, 0.9);
    box-shadow: 0 0 12px rgba(203, 166, 247, 0.6),
                0 0 10px rgba(148, 226, 213, 0.4),
                inset 0 0 6px rgba(148, 226, 213, 0.15);
  }

  /* Focused + idle: make idle chip more visible when focused */
  .ai-chip.focused.idle {
    opacity: 1;
    background: rgba(69, 71, 90, 0.6);
  }

  /* Error state - red indicator for pipe/service failures (no animation for CPU savings) */
  .ai-chip.error {
    background: linear-gradient(135deg, rgba(243, 139, 168, 0.3), rgba(235, 160, 172, 0.25));
    border: 1px solid rgba(243, 139, 168, 0.8);
    box-shadow: 0 0 10px rgba(243, 139, 168, 0.5);
    /* Animation disabled for CPU savings */
  }

  .ai-chip.error .ai-chip-indicator {
    color: #f38ba8;
    font-size: 12px;
  }

  /* Indicator icon styling */
  .ai-chip-indicator {
    font-size: 12px;
    color: #94e2d5;
    transition: opacity 120ms ease;
  }

  .ai-chip.working .ai-chip-indicator {
    color: #94e2d5;
  }

  .ai-chip.attention .ai-chip-indicator {
    color: #fab387;
  }

  .ai-chip.idle .ai-chip-indicator {
    color: #6c7086;
  }

  /* Opacity classes for pulsating fade effect */
  .ai-opacity-04 { opacity: 0.4; }
  .ai-opacity-06 { opacity: 0.6; }
  .ai-opacity-08 { opacity: 0.8; }
  .ai-opacity-10 { opacity: 1.0; }

  /* Source icon styling (SVG images) */
  .ai-chip-source-icon {
    min-width: 16px;
    min-height: 16px;
  }

  .ai-chip.idle .ai-chip-source-icon {
    opacity: 0.6;
  }

  /* Project badge - feature number prominently displayed */
  .ai-chip-project-badge {
    font-size: 10px;
    font-weight: 700;
    font-family: "JetBrainsMono Nerd Font", monospace;
    padding: 1px 6px;
    margin: 0 3px;
    border-radius: 6px;
    background: rgba(30, 30, 46, 0.9);
    border: 1px solid rgba(148, 226, 213, 0.5);
    color: #94e2d5;
    min-width: 18px;
    /* Note: GTK CSS doesn't support text-align; use :halign in widget */
  }

  .ai-chip.working .ai-chip-project-badge {
    background: rgba(30, 30, 46, 0.95);
    border-color: rgba(148, 226, 213, 0.7);
    color: #94e2d5;
    box-shadow: 0 0 4px rgba(148, 226, 213, 0.3);
  }

  .ai-chip.attention .ai-chip-project-badge {
    background: rgba(30, 30, 46, 0.95);
    border-color: rgba(250, 179, 135, 0.7);
    color: #fab387;
    box-shadow: 0 0 4px rgba(250, 179, 135, 0.3);
  }

  .ai-chip.idle .ai-chip-project-badge {
    background: rgba(49, 50, 68, 0.7);
    border-color: rgba(108, 112, 134, 0.4);
    color: #a6adc8;
  }

  /* Focused state - highlight when this AI session's window is currently focused */
  /* Adds bright lavender border and subtle glow to indicate "you are here" */
  .ai-chip.focused {
    border-width: 2px;
    border-style: solid;
    border-color: rgba(203, 166, 247, 0.9);
    box-shadow: 0 0 12px rgba(203, 166, 247, 0.6),
                0 0 4px rgba(203, 166, 247, 0.8),
                inset 0 0 8px rgba(203, 166, 247, 0.15);
  }

  /* Focused + working: combine teal working glow with lavender focus ring */
  .ai-chip.focused.working {
    border-width: 2px;
    border-style: solid;
    border-color: rgba(203, 166, 247, 0.9);
    box-shadow: 0 0 12px rgba(203, 166, 247, 0.6),
                0 0 10px rgba(148, 226, 213, 0.4),
                inset 0 0 6px rgba(148, 226, 213, 0.15);
  }

  /* Focused + idle: make idle chip more visible when focused */
  .ai-chip.focused.idle {
    opacity: 1;
    background: rgba(69, 71, 90, 0.6);
  }

  .ai-chip.focused .ai-chip-project-badge {
    border-color: rgba(203, 166, 247, 0.8);
    color: #cba6f7;
    box-shadow: 0 0 4px rgba(203, 166, 247, 0.3);
  }

  /* Project name - revealed on hover */
  /* Note: GTK CSS doesn't support overflow/text-overflow; use :limit-width in widget */
  .ai-chip-project-name {
    font-size: 8px;
    font-weight: 600;
    color: #a6adc8;
    margin-left: 4px;
    padding: 0 4px;
    background: rgba(49, 50, 68, 0.8);
    border-radius: 4px;
  }

  .ai-chip.working .ai-chip-project-name {
    color: #94e2d5;
  }

  .ai-chip.attention .ai-chip-project-name {
    color: #fab387;
  }

  /* ==========================================================================
   * Powermenu (Feature 127)
   * Fullscreen overlay opened from the top bar (right side)
   * ========================================================================== */

  .powermenu-toggle {
    background: rgba(243, 139, 168, 0.10);
    border: 1px solid rgba(243, 139, 168, 0.35);
    padding: 2px 6px;
  }

  .powermenu-toggle:hover {
    background: rgba(243, 139, 168, 0.16);
    border-color: rgba(243, 139, 168, 0.70);
    box-shadow: 0 0 10px rgba(243, 139, 168, 0.25);
  }

  .powermenu-icon { color: #f38ba8; }

  .powermenu-overlay {
    background: rgba(24, 24, 37, 0.58);
  }

  .powermenu-overlay-inner {
    padding: 24px;
  }

  .powermenu-card {
    background: rgba(30, 30, 46, 0.96);
    border: 1px solid rgba(203, 166, 247, 0.35);
    border-radius: 18px;
    padding: 16px 18px 14px;
    min-width: 420px;
    box-shadow: 0 18px 60px rgba(0, 0, 0, 0.55),
                0 0 0 1px rgba(203, 166, 247, 0.08);
  }

  .powermenu-title {
    font-size: 14px;
    font-weight: 900;
    color: #cdd6f4;
  }

  .powermenu-subtitle {
    font-size: 9px;
    color: #a6adc8;
    opacity: 0.95;
  }

  .powermenu-close {
    background: rgba(69, 71, 90, 0.35);
    border: 1px solid rgba(108, 112, 134, 0.45);
    border-radius: 10px;
    padding: 6px 10px;
    font-size: 11px;
  }

  .powermenu-close:hover {
    background: rgba(243, 139, 168, 0.14);
    border-color: rgba(243, 139, 168, 0.75);
  }

  .pm-action {
    background: rgba(49, 50, 68, 0.65);
    border: 1px solid rgba(108, 112, 134, 0.45);
    border-radius: 14px;
    padding: 10px 12px;
    min-width: 110px;
    min-height: 72px;
    transition: background 120ms ease, border 120ms ease, box-shadow 120ms ease;
  }

  .pm-action:hover {
    background: rgba(69, 71, 90, 0.55);
    box-shadow: 0 10px 26px rgba(0, 0, 0, 0.35);
  }

  .pm-action.selected {
    border-color: rgba(203, 166, 247, 0.90);
    box-shadow: 0 0 0 1px rgba(203, 166, 247, 0.18),
                0 12px 30px rgba(0, 0, 0, 0.45);
  }

  .pm-action-icon {
    font-size: 20px;
    margin-bottom: 1px;
  }

  .pm-action-label {
    font-size: 9px;
    font-weight: 900;
    color: #a6adc8;
  }

  /* Action accents */
  .pm-action.lock:hover { border-color: rgba(137, 180, 250, 0.75); }
  .pm-action.suspend:hover { border-color: rgba(249, 226, 175, 0.75); }
  .pm-action.logout:hover { border-color: rgba(203, 166, 247, 0.75); }
  .pm-action.reboot:hover { border-color: rgba(148, 226, 213, 0.75); }
  .pm-action.shutdown:hover { border-color: rgba(243, 139, 168, 0.80); }
  .pm-action.cancel:hover { border-color: rgba(166, 173, 200, 0.70); }

  .pm-action.lock .pm-action-icon { color: #89b4fa; }
  .pm-action.suspend .pm-action-icon { color: #f9e2af; }
  .pm-action.logout .pm-action-icon { color: #cba6f7; }
  .pm-action.reboot .pm-action-icon { color: #94e2d5; }
  .pm-action.shutdown .pm-action-icon { color: #f38ba8; }
  .pm-action.cancel .pm-action-icon { color: #a6adc8; }

  .pm-confirm {
    background: rgba(49, 50, 68, 0.75);
    border: 1px solid rgba(108, 112, 134, 0.50);
    border-radius: 14px;
    padding: 10px 12px;
  }

  .pm-confirm-text {
    color: #cdd6f4;
    font-size: 10px;
    font-weight: 800;
  }

  .pm-confirm-btn {
    background: rgba(69, 71, 90, 0.35);
    border: 1px solid rgba(108, 112, 134, 0.45);
    border-radius: 12px;
    padding: 6px 10px;
    font-size: 10px;
    font-weight: 900;
    transition: background 120ms ease, border 120ms ease, box-shadow 120ms ease;
  }

  .pm-confirm-btn:hover {
    background: rgba(69, 71, 90, 0.55);
    border-color: rgba(203, 166, 247, 0.65);
  }

  .pm-confirm-danger {
    background: rgba(243, 139, 168, 0.16);
    border-color: rgba(243, 139, 168, 0.60);
    color: #f38ba8;
  }

  .pm-confirm-danger:hover {
    background: rgba(243, 139, 168, 0.22);
    border-color: rgba(243, 139, 168, 0.80);
    box-shadow: 0 0 14px rgba(243, 139, 168, 0.35);
  }

  .pm-confirm-warn {
    background: rgba(148, 226, 213, 0.14);
    border-color: rgba(148, 226, 213, 0.55);
    color: #94e2d5;
  }

  .pm-confirm-warn:hover {
    background: rgba(148, 226, 213, 0.20);
    border-color: rgba(148, 226, 213, 0.75);
    box-shadow: 0 0 14px rgba(148, 226, 213, 0.28);
  }
''

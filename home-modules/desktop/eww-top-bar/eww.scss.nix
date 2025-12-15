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

  /* Compact metrics trigger (always visible) */
  .compact-trigger {
    background: rgba(69, 71, 90, 0.35);
    border: 1px solid rgba(108, 112, 134, 0.45);
    padding: 2px 6px;
    border-radius: 7px;
    min-width: 14px;
    min-height: 14px;
    margin-right: 2px;
  }

  .compact-trigger .compact-icon {
    color: #a6adc8;
    font-size: 10px;
  }

  .metrics-revealer {
    transition: all 180ms ease;
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
    animation: pulse-glow 3s ease-in-out infinite;
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

  @keyframes pulse-glow {
    0% {
      box-shadow: 0 0 12px rgba(203, 166, 247, 0.5),
                  inset 0 0 8px rgba(203, 166, 247, 0.2);
    }
    50% {
      box-shadow: 0 0 18px rgba(203, 166, 247, 0.7),
                  inset 0 0 12px rgba(203, 166, 247, 0.3);
    }
    100% {
      box-shadow: 0 0 12px rgba(203, 166, 247, 0.5),
                  inset 0 0 8px rgba(203, 166, 247, 0.2);
    }
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
    animation: pulse-notification 3s ease-in-out infinite;
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

  @keyframes pulse-notification {
    0% {
      box-shadow: 0 0 12px rgba(137, 180, 250, 0.5),
                  inset 0 0 8px rgba(137, 180, 250, 0.2);
    }
    50% {
      box-shadow: 0 0 18px rgba(137, 180, 250, 0.7),
                  inset 0 0 12px rgba(137, 180, 250, 0.3);
    }
    100% {
      box-shadow: 0 0 12px rgba(137, 180, 250, 0.5),
                  inset 0 0 8px rgba(137, 180, 250, 0.2);
    }
  }

  /* Feature 110: Notification badge styling */

  /* Has unread notifications - red/peach gradient glow */
  .notification-has-unread {
    background: linear-gradient(135deg, rgba(243, 139, 168, 0.25), rgba(250, 179, 135, 0.2));
    border: 1px solid rgba(243, 139, 168, 0.7);
    box-shadow: 0 0 12px rgba(243, 139, 168, 0.4),
                inset 0 0 8px rgba(243, 139, 168, 0.15);
    animation: pulse-unread 2s ease-in-out infinite;
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

  /* Pulsing glow animation for unread notifications */
  @keyframes pulse-unread {
    0% {
      box-shadow: 0 0 12px rgba(243, 139, 168, 0.4),
                  inset 0 0 8px rgba(243, 139, 168, 0.15);
    }
    50% {
      box-shadow: 0 0 18px rgba(243, 139, 168, 0.6),
                  inset 0 0 12px rgba(243, 139, 168, 0.25);
    }
    100% {
      box-shadow: 0 0 12px rgba(243, 139, 168, 0.4),
                  inset 0 0 8px rgba(243, 139, 168, 0.15);
    }
  }

  /* Feature 117: AI Sessions widget styling */
  .ai-sessions-container {
    margin-left: 8px;
  }

  /* AI chip base styling */
  .ai-chip {
    background: rgba(49, 50, 68, 0.65);
    border: 1px solid rgba(108, 112, 134, 0.45);
    border-radius: 10px;
    padding: 2px 6px;
    min-height: 16px;
    transition: all 150ms ease;
  }

  .ai-chip:hover {
    background: rgba(69, 71, 90, 0.7);
    border-color: rgba(148, 226, 213, 0.6);
    box-shadow: 0 2px 8px rgba(148, 226, 213, 0.3);
  }

  /* Working state - teal pulsating glow */
  .ai-chip.working {
    background: linear-gradient(135deg, rgba(148, 226, 213, 0.2), rgba(137, 180, 250, 0.15));
    border: 1px solid rgba(148, 226, 213, 0.6);
    box-shadow: 0 0 10px rgba(148, 226, 213, 0.4),
                inset 0 0 6px rgba(148, 226, 213, 0.15);
    animation: ai-working-pulse 2s ease-in-out infinite;
  }

  .ai-chip.working:hover {
    background: linear-gradient(135deg, rgba(148, 226, 213, 0.3), rgba(137, 180, 250, 0.2));
    box-shadow: 0 0 14px rgba(148, 226, 213, 0.6);
  }

  /* Attention state - peach/red highlight */
  .ai-chip.attention {
    background: linear-gradient(135deg, rgba(250, 179, 135, 0.25), rgba(243, 139, 168, 0.2));
    border: 1px solid rgba(250, 179, 135, 0.7);
    box-shadow: 0 0 10px rgba(250, 179, 135, 0.4),
                inset 0 0 6px rgba(250, 179, 135, 0.15);
    animation: ai-attention-pulse 2s ease-in-out infinite;
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

  /* Indicator icon styling */
  .ai-chip-indicator {
    font-size: 10px;
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
    min-width: 14px;
    min-height: 14px;
  }

  .ai-chip.idle .ai-chip-source-icon {
    opacity: 0.6;
  }

  /* AI working pulse animation */
  @keyframes ai-working-pulse {
    0% {
      box-shadow: 0 0 10px rgba(148, 226, 213, 0.4),
                  inset 0 0 6px rgba(148, 226, 213, 0.15);
    }
    50% {
      box-shadow: 0 0 16px rgba(148, 226, 213, 0.6),
                  inset 0 0 10px rgba(148, 226, 213, 0.25);
    }
    100% {
      box-shadow: 0 0 10px rgba(148, 226, 213, 0.4),
                  inset 0 0 6px rgba(148, 226, 213, 0.15);
    }
  }

  /* AI attention pulse animation */
  @keyframes ai-attention-pulse {
    0% {
      box-shadow: 0 0 10px rgba(250, 179, 135, 0.4),
                  inset 0 0 6px rgba(250, 179, 135, 0.15);
    }
    50% {
      box-shadow: 0 0 16px rgba(250, 179, 135, 0.6),
                  inset 0 0 10px rgba(250, 179, 135, 0.25);
    }
    100% {
      box-shadow: 0 0 10px rgba(250, 179, 135, 0.4),
                  inset 0 0 6px rgba(250, 179, 135, 0.15);
    }
  }
''

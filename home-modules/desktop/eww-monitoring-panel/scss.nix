{ mocha, ... }:

''
  /* Feature 085: Sway Monitoring Widget - Catppuccin Mocha Theme */
  /* Direct color interpolation from Nix - Eww doesn't support CSS variables */

  /* Window base - must be transparent for see-through effect on Wayland */
  * {
    margin: 0;
    padding: 0;
    color: ${mocha.text};
  }

  window {
    background-color: transparent;
  }

  label, box, button {
    color: ${mocha.text};
    background-color: transparent;
    background-image: none;
  }

  button {
    background-image: none;
  }

  .panel-container {
    border-radius: 12px;
    padding: 6px;
    margin: 4px;
    border: 2px solid rgba(137, 180, 250, 0.2);
  }

  .panel-container * {
    min-width: 0;
  }

  .panel-container.focused {
    border: 2px solid ${mocha.mauve};
    box-shadow: 0 0 20px rgba(203, 166, 247, 0.4),
                0 0 40px rgba(203, 166, 247, 0.2),
                inset 0 0 15px rgba(203, 166, 247, 0.05);
  }

  .mode-toggle {
    font-size: 14px;
    padding: 4px 6px;
    border-radius: 4px;
    border: 1px solid rgba(255, 255, 255, 0.08);
    background: rgba(255, 255, 255, 0.04);
    color: ${mocha.subtext0};
    min-width: 22px;
  }

  .mode-toggle:hover {
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.15);
    color: ${mocha.text};
  }

  .mode-toggle.docked {
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.12);
    color: ${mocha.subtext0};
  }

  .mode-toggle.docked:hover {
    background: rgba(255, 255, 255, 0.14);
    color: ${mocha.text};
  }

  .mode-toggle.overlay {
    background: rgba(255, 255, 255, 0.04);
    color: ${mocha.subtext0};
  }

  .mode-toggle.overlay:hover {
    background: rgba(255, 255, 255, 0.1);
    color: ${mocha.text};
  }

  .panel-header {
    background-color: rgba(24, 24, 37, 0.4);
    border-bottom: 1px solid ${mocha.overlay0};
    border-radius: 8px;
    padding: 8px 12px;
    margin-bottom: 8px;
  }

  .panel-title {
    font-size: 14px;
    font-weight: bold;
    color: ${mocha.text};
    margin-bottom: 4px;
  }

  .summary-counts {
    font-size: 11px;
    color: ${mocha.subtext0};
  }

  .count-badge {
    font-size: 10px;
    color: ${mocha.teal};
    background-color: rgba(148, 226, 213, 0.15);
    padding: 2px 6px;
    border-radius: 3px;
  }

  .debug-toggle {
    font-size: 14px;
    color: ${mocha.subtext0};
    padding: 2px 6px;
    margin-left: 8px;
    border-radius: 4px;
    background-color: rgba(49, 50, 68, 0.3);
    transition: all 150ms ease;
  }

  .debug-toggle:hover {
    color: ${mocha.text};
    background-color: rgba(49, 50, 68, 0.5);
  }

  .debug-toggle.active {
    color: ${mocha.yellow};
    background-color: rgba(249, 226, 175, 0.2);
  }

  .workspace-pills-scroll {
    margin-top: 6px;
  }

  .workspace-pills {
    padding: 2px 0;
  }

  .workspace-pill {
    font-size: 11px;
    padding: 4px 10px;
    margin-right: 4px;
    border-radius: 12px;
    background-color: rgba(49, 50, 68, 0.5);
    color: ${mocha.subtext0};
    border: 1px solid ${mocha.surface0};
  }

  .workspace-pill:hover {
    background-color: rgba(69, 71, 90, 0.6);
    color: ${mocha.text};
    border-color: ${mocha.overlay0};
  }

  .workspace-pill.focused {
    background-color: rgba(137, 180, 250, 0.3);
    color: ${mocha.blue};
    border-color: ${mocha.blue};
    font-weight: bold;
    box-shadow: 0 0 6px rgba(137, 180, 250, 0.4);
  }

  .workspace-pill.urgent {
    background-color: rgba(243, 139, 168, 0.3);
    color: ${mocha.red};
    border-color: ${mocha.red};
    box-shadow: 0 0 6px rgba(243, 139, 168, 0.4);
  }

  .tabs {
    margin-bottom: 8px;
  }

  .tab {
    font-size: 16px;
    padding: 8px 16px;
    min-width: 60px;
    background-color: rgba(49, 50, 68, 0.4);
    background-image: none;
    color: ${mocha.subtext0};
    border: 1px solid ${mocha.overlay0};
    border-radius: 6px;
  }

  .tab label {
    color: ${mocha.subtext0};
  }

  .tab:hover {
    background-color: rgba(69, 71, 90, 0.5);
    background-image: none;
    color: ${mocha.text};
    border-color: ${mocha.overlay0};
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
  }

  .tab:hover label {
    color: ${mocha.text};
  }

  .tab.active {
    background-color: rgba(137, 180, 250, 0.6);
    background-image: none;
    color: ${mocha.base};
    border-color: ${mocha.blue};
    font-weight: bold;
    box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
  }

  .tab.active label {
    color: ${mocha.base};
  }

  .tab.active:hover {
    background-color: rgba(137, 180, 250, 0.7);
    background-image: none;
    box-shadow: 0 0 12px rgba(137, 180, 250, 0.6);
  }

  .tab.active:hover label {
    color: ${mocha.base};
  }

  .panel-body {
    background-color: transparent;
    padding: 4px;
    min-height: 0;
    min-width: 0;
  }

  .view-container {
    background-color: transparent;
    min-width: 0;
  }

  .content-container {
    padding: 8px 24px 8px 12px;
  }

  .projects-list {
    min-width: 0;
  }

  .project {
    margin-bottom: 12px;
    padding: 8px;
    background-color: rgba(49, 50, 68, 0.15);
    border-radius: 8px;
    border: 1px solid rgba(108, 112, 134, 0.3);
  }

  .scoped-project {
    border-left: 3px solid ${mocha.teal};
  }

  .global-project {
    border-left: 3px solid ${mocha.mauve};
  }

  .project-active {
    background-color: rgba(137, 180, 250, 0.1);
    border-left-color: ${mocha.blue};
  }

  .project-active .project-header {
    background-color: rgba(137, 180, 250, 0.15);
  }

  .project-active .project-name {
    color: ${mocha.blue};
  }

  .active-indicator {
    font-size: 9px;
    font-weight: bold;
    color: ${mocha.blue};
    background-color: rgba(137, 180, 250, 0.2);
    padding: 1px 6px;
    border-radius: 3px;
    margin-left: 6px;
  }

  .project-header {
    padding: 6px 8px;
    border-bottom: 1px solid ${mocha.overlay0};
    margin-bottom: 6px;
    border-radius: 4px 4px 0 0;
    transition: background-color 0.15s ease;
  }

  .project-header:hover {
    background-color: rgba(137, 180, 250, 0.1);
  }

  .project-action-bar {
    padding: 4px 8px;
    background-color: rgba(24, 24, 37, 0.95);
    border-radius: 4px;
    margin-top: 4px;
    margin-bottom: 4px;
  }

  .project-action-bar .action-btn {
    font-size: 14px;
    padding: 4px 8px;
    margin: 0 2px;
    border-radius: 4px;
    transition: background-color 0.15s ease;
  }

  .project-action-bar .action-btn:hover {
    background-color: rgba(137, 180, 250, 0.2);
  }

  .action-switch {
    color: ${mocha.teal};
  }

  .action-close-project {
    color: ${mocha.red};
  }

  .action-dismiss {
    color: ${mocha.subtext0};
  }

  .windows-actions-row {
    padding: 4px 8px;
    margin-bottom: 8px;
  }

  .expand-all-btn {
    padding: 4px 10px;
    background-color: rgba(137, 180, 250, 0.15);
    border: 1px solid ${mocha.blue};
    border-radius: 4px;
    transition: background-color 0.15s ease;
  }

  .expand-all-btn:hover {
    background-color: rgba(137, 180, 250, 0.3);
  }

  .expand-all-icon {
    color: ${mocha.blue};
    font-size: 12px;
  }

  .expand-all-text {
    color: ${mocha.text};
    font-size: 11px;
    font-weight: 500;
  }

  .close-all-btn {
    padding: 4px 10px;
    background-color: rgba(243, 139, 168, 0.15);
    border: 1px solid ${mocha.red};
    border-radius: 4px;
    transition: background-color 0.15s ease;
  }

  .close-all-btn:hover {
    background-color: rgba(243, 139, 168, 0.3);
  }

  .close-all-icon {
    color: ${mocha.red};
    font-size: 12px;
  }

  .close-all-text {
    color: ${mocha.text};
    font-size: 11px;
    font-weight: 500;
  }

  .project-name {
    font-size: 13px;
    font-weight: bold;
    color: ${mocha.text};
    min-width: 0;
  }

  .window-count-badge {
    font-size: 10px;
    color: ${mocha.teal};
    background-color: rgba(148, 226, 213, 0.2);
    padding: 1px 5px;
    border-radius: 3px;
    min-width: 18px;
  }

  .windows-container {
    margin-left: 8px;
    margin-top: 2px;
  }

  .window {
    padding: 4px 8px;
    margin-bottom: 1px;
    border-radius: 2px;
    background-color: transparent;
    border-left: 2px solid transparent;
  }

  .window-focused {
    background-color: rgba(137, 180, 250, 0.1);
    border-left-color: ${mocha.blue};
  }

  .window-floating {
    border-right: 2px solid ${mocha.yellow};
  }

  .window-hidden {
    opacity: 0.5;
    font-style: italic;
  }

  .scoped-window {
    border-left-color: ${mocha.teal};
  }

  .global-window {
    border-left-color: ${mocha.overlay0};
  }

  .window:hover {
    background-color: rgba(137, 180, 250, 0.15);
    border-left-width: 3px;
  }

  .window.clicked {
    background-color: rgba(137, 180, 250, 0.25);
    border-left-color: ${mocha.blue};
    border-left-width: 4px;
  }

  .window-icon-container {
    min-width: 24px;
    min-height: 24px;
    margin-right: 6px;
  }

  .window-icon-image {
    min-width: 20px;
    min-height: 20px;
  }

  .window-app-name {
    font-size: 11px;
    font-weight: 500;
    color: ${mocha.text};
    margin-left: 6px;
  }

  .window-badges {
    margin-left: 4px;
  }

  .badge {
    font-size: 9px;
    font-weight: 600;
    padding: 1px 4px;
    border-radius: 2px;
    margin-left: 4px;
  }

  .badge-pwa {
    color: ${mocha.mauve};
    background-color: rgba(203, 166, 247, 0.2);
  }

  .badge-project {
    color: ${mocha.teal};
    background-color: rgba(148, 226, 213, 0.15);
  }

  .badge-notification {
    font-weight: bold;
    padding: 2px 6px;
    border-radius: 4px;
    margin-left: 6px;
    font-size: 10px;
  }

  .badge-stopped {
    color: ${mocha.base};
    background: linear-gradient(135deg, ${mocha.peach}, ${mocha.red});
    border: 1px solid ${mocha.peach};
    box-shadow: 0 0 8px rgba(250, 179, 135, 0.6),
                0 0 16px rgba(250, 179, 135, 0.3),
                inset 0 1px 0 rgba(255, 255, 255, 0.2);
  }

  .badge-working {
    color: ${mocha.teal};
    background: rgba(148, 226, 213, 0.15);
    border: 1px solid rgba(148, 226, 213, 0.4);
    box-shadow: 0 0 6px rgba(148, 226, 213, 0.4);
    font-size: 12px;
    font-weight: bold;
    padding: 2px 6px;
    border-radius: 8px;
    transition: opacity 500ms ease-in-out;
    opacity: 0.5;
  }

  .badge-working.pulse-bright {
    opacity: 1;
  }

  .badge-attention {
    color: ${mocha.peach};
    background: rgba(250, 179, 135, 0.15);
    border: 1px solid rgba(250, 179, 135, 0.4);
    box-shadow: 0 0 8px rgba(250, 179, 135, 0.4);
    font-size: 14px;
    padding: 2px 6px;
    border-radius: 8px;
  }

  .ai-badge-icon {
    margin-left: 4px;
    margin-right: 2px;
    min-width: 16px;
    min-height: 16px;
    opacity: 1.0;
  }

  .ai-badge-icon.working {
    opacity: 1.0;
    transition: opacity 500ms ease-in-out;
  }

  .ai-badge-icon.working.rotate-phase {
    opacity: 0.4;
  }

  .ai-badge-icon.attention {
    opacity: 1.0;
  }

  .ai-badge-icon.completed {
    opacity: 0.5;
  }

  .ai-badge-icon.idle {
    opacity: 0.5;
  }

  /* AI badge hover effect with PID tooltip */
  .ai-badge-hover {
    padding: 2px;
    margin: 0 1px;
    border-radius: 6px;
    transition: all 200ms ease-out;
    background: transparent;
  }

  .ai-badge-hover:hover {
    background: rgba(137, 180, 250, 0.15);
  }

  .ai-badge-hover:hover .ai-badge-icon {
    opacity: 1.0;
  }

  .ai-badge-hover:hover .ai-badge-icon.working {
    opacity: 1.0;
  }

  .ai-badge-hover:hover .ai-badge-icon.idle,
  .ai-badge-hover:hover .ai-badge-icon.completed {
    opacity: 1.0;
  }

  /* Global AI session chip wrapper hover effect */
  .ai-badge-hover.ai-session-chip-wrapper {
    padding: 0;
    border-radius: 12px;
  }

  .ai-badge-hover.ai-session-chip-wrapper:hover {
    background: transparent;
  }

  .ai-badge-hover.ai-session-chip-wrapper:hover .ai-session-chip {
    background: rgba(137, 180, 250, 0.2);
  }

  /* Feature 136: Overflow badge for multiple AI indicators */
  .badge-overflow {
    color: ${mocha.text};
    background-color: rgba(127, 132, 156, 0.3);
    border-radius: 4px;
    font-size: 10px;
    font-weight: 600;
    padding: 2px 4px;
    margin-left: 2px;
  }

  .badge-focused-window {
    opacity: 0.4;
    box-shadow: none;
  }

  .ai-sessions-bar {
    padding: 4px 0;
    margin-bottom: 8px;
  }

  // Feature 136: Global AI Sessions section for orphaned sessions
  .global-ai-sessions {
    margin-top: 12px;
    padding: 8px;
    background: rgba(49, 50, 68, 0.3);
    border-radius: 8px;
    border: 1px solid rgba(137, 180, 250, 0.2);
  }

  .global-ai-header {
    margin-bottom: 8px;
    color: ${mocha.subtext0};
  }

  .global-ai-icon {
    font-size: 14px;
    margin-right: 6px;
    color: ${mocha.blue};
  }

  .global-ai-title {
    font-size: 12px;
    font-weight: 600;
    color: ${mocha.subtext0};
  }

  .global-ai-count {
    font-size: 11px;
    color: ${mocha.overlay0};
    margin-left: 4px;
  }

  // Note: .global-ai-sessions-container wrapping handled by EWW box widget (GTK3 doesn't support flex-wrap)

  .ai-session-label {
    font-size: 11px;
    color: ${mocha.subtext0};
  }

  .ai-session-chip {
    background: rgba(49, 50, 68, 0.5);
    border-radius: 12px;
    padding: 3px 8px;
    border: none;
    transition: all 150ms ease;
  }

  .ai-session-chip:hover {
    background: rgba(69, 71, 90, 0.7);
  }

  .ai-session-chip.working {
    background: rgba(243, 139, 168, 0.12);
  }

  .ai-session-chip.working:hover {
    background: rgba(243, 139, 168, 0.2);
  }

  .ai-session-chip.working .ai-session-indicator {
    color: ${mocha.red};
  }

  .ai-session-chip.attention {
    background: linear-gradient(135deg, rgba(250, 179, 135, 0.15), rgba(249, 226, 175, 0.1));
  }

  .ai-session-chip.attention:hover {
    background: linear-gradient(135deg, rgba(250, 179, 135, 0.25), rgba(249, 226, 175, 0.15));
  }

  .ai-session-chip.attention .ai-session-indicator {
    color: ${mocha.peach};
  }

  .ai-session-chip.idle {
    background: rgba(49, 50, 68, 0.3);
  }

  .ai-session-chip.idle:hover {
    background: rgba(69, 71, 90, 0.5);
  }

  .ai-session-chip.idle .ai-session-indicator {
    color: ${mocha.overlay0};
  }

  .ai-session-chip.completed {
    background: rgba(49, 50, 68, 0.3);
  }

  .ai-session-chip.completed:hover {
    background: rgba(69, 71, 90, 0.5);
  }

  .ai-session-chip.completed .ai-session-indicator {
    color: ${mocha.overlay0};
  }

  .ai-session-status-icon {
    font-size: 8px;
    margin-left: 2px;
    opacity: 0.8;
  }

  .ai-session-status-icon.completed {
    color: ${mocha.teal};
  }

  .ai-session-status-icon.working {
    color: ${mocha.red};
  }

  .ai-session-status-icon.attention {
    color: ${mocha.peach};
  }

  .ai-session-indicator {
    font-size: 12px;
    font-weight: bold;
  }

  .ai-session-source-icon {
    opacity: 0.7;
    margin-top: 1px;
  }

  .ai-session-chip.working .ai-session-source-icon {
    opacity: 1.0;
  }

  .ai-session-chip.attention .ai-session-source-icon {
    opacity: 1.0;
  }

  .env-expand-trigger {
    padding: 2px 6px;
    margin: 0 2px;
    border-radius: 4px;
    background-color: transparent;
  }

  .env-expand-trigger:hover {
    background-color: rgba(148, 226, 213, 0.15);
  }

  .env-expand-trigger.expanded {
    background-color: rgba(148, 226, 213, 0.25);
  }

  .env-expand-icon {
    font-size: 12px;
    color: ${mocha.teal};
  }

  .env-expand-trigger:hover .env-expand-icon {
    color: ${mocha.green};
  }

  .window-env-panel {
    background-color: rgba(24, 24, 37, 0.98);
    border: 2px solid ${mocha.teal};
    border-radius: 8px;
    padding: 0;
    margin: 4px 0 8px 0;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6),
                0 0 0 1px rgba(148, 226, 213, 0.3);
  }

  .env-panel-header {
    background-color: rgba(148, 226, 213, 0.15);
    border-bottom: 1px solid ${mocha.teal};
    padding: 8px 12px;
    border-radius: 6px 6px 0 0;
  }

  .env-panel-title {
    font-size: 11px;
    font-weight: bold;
    color: ${mocha.teal};
  }

  .env-close-btn {
    font-size: 14px;
    padding: 4px 8px;
    background-color: rgba(243, 139, 168, 0.2);
    color: ${mocha.red};
    border: 1px solid ${mocha.red};
    border-radius: 4px;
    min-width: 24px;
  }

  .env-close-btn:hover {
    background-color: rgba(243, 139, 168, 0.4);
    box-shadow: 0 0 8px rgba(243, 139, 168, 0.4);
  }

  .env-filter-box {
    background-color: rgba(30, 30, 46, 0.6);
    border: 1px solid ${mocha.surface1};
    border-radius: 4px;
    padding: 4px 8px;
    margin: 8px 12px;
  }

  .env-filter-box:focus-within {
    border-color: ${mocha.teal};
    background-color: rgba(30, 30, 46, 0.8);
  }

  .env-filter-icon {
    font-size: 12px;
    color: ${mocha.subtext0};
    padding-right: 6px;
  }

  .env-filter-input {
    background-color: transparent;
    border: none;
    outline: none;
    font-family: "JetBrains Mono", "Fira Code", monospace;
    font-size: 11px;
    color: ${mocha.text};
    min-width: 150px;
  }

  .env-filter-input:focus {
    border: none;
    outline: none;
  }

  .env-filter-clear {
    font-size: 12px;
    padding: 2px 4px;
    color: ${mocha.overlay0};
    border-radius: 3px;
  }

  .env-filter-clear:hover {
    color: ${mocha.red};
    background-color: rgba(243, 139, 168, 0.2);
  }

  .env-loading {
    padding: 16px;
    color: ${mocha.subtext0};
    font-size: 12px;
    font-style: italic;
  }

  .env-error {
    padding: 12px;
    color: ${mocha.red};
    font-size: 11px;
    background-color: rgba(243, 139, 168, 0.1);
    border-radius: 0 0 6px 6px;
  }

  .env-section {
    padding: 8px 12px;
  }

  .env-section-i3pm {
    background-color: rgba(148, 226, 213, 0.05);
    border-bottom: 1px solid rgba(148, 226, 213, 0.2);
  }

  .env-section-other {
    background-color: rgba(30, 30, 46, 0.4);
  }

  .env-section-title {
    font-size: 10px;
    font-weight: bold;
    color: ${mocha.teal};
    margin-bottom: 6px;
  }

  .env-section-other .env-section-title {
    color: ${mocha.subtext0};
  }

  .env-vars-list {
    padding: 0;
  }

  .env-var-row {
    padding: 3px 0;
    border-bottom: 1px solid rgba(108, 112, 134, 0.1);
  }

  .env-var-row:last-child {
    border-bottom: none;
  }

  .env-var-key {
    font-family: "JetBrains Mono", "Fira Code", monospace;
    font-size: 10px;
    font-weight: bold;
    color: ${mocha.green};
    min-width: 180px;
    padding-right: 8px;
  }

  .env-var-key-other {
    color: ${mocha.overlay0};
    font-weight: normal;
  }

  .env-var-value {
    font-family: "JetBrains Mono", "Fira Code", monospace;
    font-size: 10px;
    color: ${mocha.peach};
  }

  .env-var-value-other {
    color: ${mocha.subtext0};
  }

  .error-state {
    padding: 32px;
  }

  .error-icon {
    font-size: 48px;
    color: ${mocha.red};
    margin-bottom: 16px;
  }

  .error-message {
    font-size: 14px;
    color: ${mocha.text};
  }

  .empty-state {
    padding: 32px;
  }

  .empty-icon {
    font-size: 48px;
    color: ${mocha.subtext0};
    margin-bottom: 16px;
  }

  .empty-title {
    font-size: 16px;
    font-weight: bold;
    color: ${mocha.text};
    margin-bottom: 8px;
  }

  .empty-message {
    font-size: 14px;
    color: ${mocha.subtext0};
  }

  .empty-action-button {
    background-color: ${mocha.blue};
    color: ${mocha.mantle};
    border: none;
    border-radius: 6px;
    padding: 8px 16px;
    margin-top: 16px;
    font-size: 13px;
    font-weight: 500;
  }

  .empty-action-button:hover {
    background-color: ${mocha.sapphire};
  }

  .panel-footer {
    background-color: rgba(24, 24, 37, 0.4);
    border-top: 1px solid ${mocha.overlay0};
    border-radius: 8px;
    padding: 6px 8px;
    margin-top: 8px;
  }

  .timestamp {
    font-size: 10px;
    color: ${mocha.subtext0};
    font-style: italic;
  }

  scrollbar {
    background-color: transparent;
    border-radius: 4px;
  }

  scrollbar slider {
    background-color: ${mocha.overlay0};
    border-radius: 4px;
    min-width: 6px;
  }

  scrollbar slider:hover {
    background-color: ${mocha.surface1};
  }

  .project-card {
    background-color: rgba(49, 50, 68, 0.3);
    border-left: 2px solid ${mocha.surface1};
    border-radius: 2px;
    padding: 8px 10px;
    margin-bottom: 4px;
    min-width: 0;
  }

  .project-card:hover {
    background-color: rgba(49, 50, 68, 0.5);
    border-left-color: ${mocha.overlay0};
  }

  .project-card.active-project {
    border-left-color: ${mocha.teal};
    background-color: rgba(148, 226, 213, 0.12);
  }

  .project-card-header {
    min-width: 0;
  }

  .project-main-content {
    min-width: 0;
  }

  .git-branch-row {
    margin-top: 4px;
    padding-top: 4px;
    border-top: 1px solid rgba(69, 71, 90, 0.3);
  }

  .project-card-meta {
    margin-top: 4px;
  }

  .git-branch-container {
    margin-right: 6px;
    min-width: 0;
  }

  .git-branch-icon {
    font-family: "JetBrainsMono Nerd Font", monospace;
    color: ${mocha.teal};
    font-size: 12px;
    margin-right: 4px;
  }

  .git-branch-text {
    color: ${mocha.subtext0};
    font-size: 11px;
    min-width: 0;
  }

  .git-dirty {
    color: ${mocha.red};
    font-size: 11px;
    margin-left: 4px;
  }

  .git-sync-ahead {
    color: ${mocha.green};
    font-size: 10px;
    margin-left: 6px;
    font-weight: bold;
  }

  .git-sync-behind {
    color: ${mocha.yellow};
    font-size: 10px;
    margin-left: 4px;
    font-weight: bold;
  }

  .badge-merged {
    color: ${mocha.teal};
    font-size: 10px;
    margin-left: 4px;
    font-weight: bold;
  }

  .git-conflict {
    color: ${mocha.red};
    font-size: 11px;
    margin-left: 4px;
    font-weight: bold;
  }

  .badge-stale {
    color: ${mocha.overlay0};
    font-size: 10px;
    margin-left: 4px;
    opacity: 0.8;
  }

  .project-icon-container {
    background-color: rgba(137, 180, 250, 0.1);
    border-radius: 6px;
    padding: 4px 6px;
    margin-right: 8px;
    min-width: 28px;
  }

  .project-icon {
    font-size: 16px;
  }

  .project-info {
    min-width: 0;
  }

  .project-card-name {
    font-size: 12px;
    font-weight: bold;
    color: ${mocha.text};
  }

  .project-card-path {
    font-size: 9px;
    color: ${mocha.subtext0};
    font-family: "JetBrainsMono Nerd Font", monospace;
    margin-top: 1px;
  }

  .project-badges {
    margin-left: 6px;
  }

  .badge {
    font-size: 9px;
    padding: 1px 5px;
    border-radius: 8px;
    margin-left: 3px;
    font-weight: 500;
  }

  .badge-active {
    color: ${mocha.green};
    font-size: 8px;
  }

  .badge-scope {
    font-size: 10px;
    padding: 1px 4px;
    color: ${mocha.teal};
    background-color: rgba(148, 226, 213, 0.15);
    border-radius: 4px;
  }

  .badge-scoped {
    color: ${mocha.teal};
  }

  .badge-global {
    color: ${mocha.peach};
    background-color: rgba(250, 179, 135, 0.15);
  }

  .badge-remote {
    color: ${mocha.mauve};
    background-color: rgba(203, 166, 247, 0.15);
    font-size: 10px;
    padding: 1px 4px;
  }

  .project-git-status {
    padding: 2px 6px;
    background-color: rgba(69, 71, 90, 0.3);
    border-radius: 4px;
    font-size: 10px;
  }

  .git-branch-name {
    color: ${mocha.subtext0};
    font-size: 10px;
  }

  .git-dirty-indicator {
    color: ${mocha.yellow};
    font-size: 10px;
    margin-left: 4px;
    font-weight: bold;
  }

  .git-sync-status {
    color: ${mocha.sapphire};
    font-size: 10px;
    margin-left: 4px;
  }

  .expand-toggle {
    padding: 2px 6px;
    margin-right: 4px;
    border-radius: 4px;
    background-color: rgba(69, 71, 90, 0.3);
  }

  .expand-toggle:hover {
    background-color: rgba(69, 71, 90, 0.5);
  }

  .expand-icon {
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 12px;
    color: ${mocha.subtext0};
  }

  .worktree-count-badge {
    font-size: 9px;
    color: ${mocha.green};
    background-color: rgba(166, 227, 161, 0.15);
    padding: 1px 5px;
    border-radius: 8px;
    margin-left: 6px;
  }

  .badge-dirty {
    color: ${mocha.peach};
    font-size: 8px;
  }

  .worktrees-container {
    margin-left: 20px;
    padding-left: 8px;
    border-left: 1px solid rgba(69, 71, 90, 0.5);
  }

  .orphaned-section {
    margin-top: 12px;
    padding-top: 8px;
    border-top: 1px dashed ${mocha.peach};
  }

  .orphaned-header {
    font-size: 11px;
    color: ${mocha.peach};
    font-weight: bold;
    margin-bottom: 8px;
  }

  .orphaned-worktree-card {
    background-color: rgba(250, 179, 135, 0.1);
    border-left: 2px solid ${mocha.peach};
    border-radius: 2px;
    padding: 6px 8px;
    margin-bottom: 4px;
  }

  .orphaned-icon {
    margin-right: 6px;
    font-size: 14px;
  }

  .orphaned-info {
    min-width: 0;
  }

  .orphaned-name {
    font-size: 11px;
    color: ${mocha.text};
  }

  .orphaned-path {
    font-size: 9px;
    color: ${mocha.subtext0};
    font-family: "JetBrainsMono Nerd Font", monospace;
  }

  .action-recover {
    color: ${mocha.green};
  }

  .action-add {
    color: ${mocha.green};
  }

  .badge-missing {
    color: ${mocha.yellow};
    font-size: 12px;
    margin-right: 4px;
  }

  .badge-source-type {
    font-size: 10px;
    padding: 1px 3px;
    border-radius: 4px;
    margin-right: 2px;
  }

  .badge-source-local {
    color: ${mocha.blue};
  }

  .badge-source-worktree {
    color: ${mocha.green};
  }

  .badge-source-remote {
    color: ${mocha.mauve};
  }

  .project-action-bar {
    margin-left: 6px;
    background-color: rgba(30, 30, 46, 0.8);
    border-radius: 6px;
    padding: 2px 4px;
  }

  .action-btn {
    font-size: 12px;
    padding: 3px 6px;
    border-radius: 4px;
    min-width: 20px;
  }

  .action-edit {
    color: ${mocha.blue};
  }

  .action-edit:hover {
    background-color: rgba(137, 180, 250, 0.2);
    color: ${mocha.sapphire};
  }

  .action-delete {
    color: ${mocha.overlay0};
  }

  .action-delete:hover {
    background-color: rgba(243, 139, 168, 0.2);
    color: ${mocha.red};
  }

  .action-json {
    color: ${mocha.overlay0};
  }

  .action-json:hover,
  .action-json.expanded {
    background-color: rgba(137, 180, 250, 0.2);
    color: ${mocha.blue};
  }

  .project-json-tooltip {
    background-color: rgba(24, 24, 37, 0.98);
    border: 2px solid ${mocha.teal};
    border-radius: 8px;
    padding: 0;
    margin: 4px 0 8px 0;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6),
                0 0 0 1px rgba(148, 226, 213, 0.3);
  }

  .project-json-tooltip .json-tooltip-header {
    background-color: rgba(148, 226, 213, 0.15);
    border-bottom: 1px solid ${mocha.teal};
  }

  .project-json-tooltip .json-tooltip-title {
    color: ${mocha.teal};
  }

  .remote-indicator {
    color: ${mocha.peach};
    font-size: 10px;
    margin-left: 6px;
  }

  .project-name-row {
    margin-bottom: 2px;
  }

  .project-detail-tooltip {
    background-color: rgba(24, 24, 37, 0.95);
    border: 1px solid ${mocha.overlay0};
    border-radius: 6px;
    padding: 10px;
    margin-top: 8px;
  }

  .json-detail {
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 9px;
    color: ${mocha.text};
  }

  .worktree-card-wrapper {
    margin-left: 16px;
    margin-bottom: 2px;
    padding-bottom: 2px;
  }

  .worktree-action-bar {
    opacity: 0;
    transition: opacity 150ms ease-in-out;
    padding-left: 8px;
  }

  .worktree-action-bar.visible {
    opacity: 1;
  }

  .worktree-action-bar .action-btn {
    font-size: 14px;
    padding: 4px 8px;
    margin: 0 2px;
    border-radius: 4px;
    transition: background-color 0.15s ease;
  }

  .worktree-action-bar .action-btn:hover {
    background-color: rgba(137, 180, 250, 0.2);
  }

  .worktree-action-bar .action-delete {
    color: ${mocha.red};
  }

  .worktree-action-bar .action-delete:hover {
    background-color: rgba(243, 139, 168, 0.2);
  }

  .worktree-action-bar .action-terminal {
    color: ${mocha.green};
  }

  .worktree-action-bar .action-terminal:hover {
    background-color: rgba(166, 227, 161, 0.2);
  }

  .worktree-action-bar .action-editor {
    color: ${mocha.blue};
  }

  .worktree-action-bar .action-editor:hover {
    background-color: rgba(137, 180, 250, 0.2);
  }

  .worktree-action-bar .action-files {
    color: ${mocha.yellow};
  }

  .worktree-action-bar .action-files:hover {
    background-color: rgba(249, 226, 175, 0.2);
  }

  .worktree-action-bar .action-git {
    color: ${mocha.peach};
  }

  .worktree-action-bar .action-git:hover {
    background-color: rgba(250, 179, 135, 0.2);
  }

  .worktree-action-bar .action-copy {
    color: ${mocha.lavender};
  }

  .worktree-action-bar .action-copy:hover {
    background-color: rgba(180, 190, 254, 0.2);
  }

  .worktree-card {
    background-color: rgba(49, 50, 68, 0.3);
    border: 1px solid ${mocha.overlay0};
    border-radius: 6px;
    padding: 6px 8px;
  }

  .worktree-tree {
    color: ${mocha.overlay0};
    font-size: 11px;
    margin-right: 4px;
    font-family: monospace;
    min-width: 16px;
  }

  .worktree-icon {
    font-size: 14px;
  }

  .worktree-name {
    font-size: 11px;
    color: ${mocha.subtext0};
  }

  .worktree-badges {
    margin-left: 4px;
  }

  .branch-number-badge-container {
    margin-right: 6px;
  }

  .branch-number-badge {
    font-size: 9px;
    font-weight: bold;
    font-family: monospace;
    color: ${mocha.mantle};
    background: linear-gradient(135deg, ${mocha.mauve} 0%, ${mocha.pink} 100%);
    padding: 1px 4px;
    border-radius: 3px;
    min-width: 20px;
  }

  .branch-number-badge:hover {
    background: linear-gradient(135deg, ${mocha.pink} 0%, ${mocha.mauve} 100%);
    opacity: 0.9;
  }

  .branch-main-badge {
    font-size: 10px;
    font-weight: bold;
    padding: 1px 4px;
    border-radius: 3px;
    min-width: 20px;
    color: ${mocha.mantle};
    background: linear-gradient(135deg, ${mocha.blue} 0%, ${mocha.sapphire} 100%);
  }

  .branch-feature-badge {
    font-size: 10px;
    font-weight: bold;
    padding: 1px 4px;
    border-radius: 3px;
    min-width: 20px;
    color: ${mocha.mantle};
    background: linear-gradient(135deg, ${mocha.green} 0%, ${mocha.teal} 100%);
  }

  .worktree-path-row {
    margin-top: 2px;
  }

  .copy-btn-container {
    opacity: 0;
    transition: opacity 150ms ease-in-out;
    margin-left: 4px;
  }

  .copy-btn-container.visible {
    opacity: 1;
  }

  .copy-btn {
    font-size: 10px;
    color: ${mocha.subtext0};
    padding: 2px 4px;
    border-radius: 3px;
  }

  .copy-btn:hover {
    color: ${mocha.teal};
    background-color: rgba(148, 226, 213, 0.15);
  }

  .badge-branch {
    font-size: 9px;
    color: ${mocha.teal};
    background-color: rgba(148, 226, 213, 0.15);
    padding: 1px 4px;
    border-radius: 4px;
    font-family: monospace;
  }

  .worktree-actions {
    margin-left: 4px;
    background-color: rgba(30, 30, 46, 0.8);
    border-radius: 4px;
    padding: 1px 3px;
  }

  .worktree-action-btn {
    background-color: transparent;
    border: none;
    padding: 2px 4px;
    border-radius: 4px;
    font-size: 11px;
    min-width: 20px;
  }

  .worktree-action-btn.edit-btn {
    color: ${mocha.blue};
  }

  .worktree-action-btn.edit-btn:hover {
    background-color: rgba(137, 180, 250, 0.2);
  }

  .worktree-action-btn.delete-btn {
    color: ${mocha.red};
  }

  .worktree-action-btn.delete-btn:hover {
    background-color: rgba(243, 139, 168, 0.2);
  }

  .worktree-action-btn.delete-btn.confirm {
    background-color: rgba(243, 139, 168, 0.4);
    border: 2px solid ${mocha.red};
    font-weight: bold;
  }

  .worktree-edit-form {
    border-color: ${mocha.teal};
  }

  .worktree-create-form {
    border-color: ${mocha.green};
  }

  .discovered-repos-section {
    margin-top: 12px;
    padding-top: 8px;
    border-top: 1px solid ${mocha.surface0};
  }

  .discovered-repos-header {
    font-size: 12px;
    font-weight: bold;
    color: ${mocha.teal};
    margin-bottom: 8px;
    padding-left: 4px;
  }

  .discovered-repo {
    border-left-color: ${mocha.teal};
  }

  .discovered-repo:hover {
    background-color: rgba(148, 226, 213, 0.08);
  }

  .worktree-indent {
    min-width: 16px;
    color: ${mocha.overlay0};
  }

  .worktree-info {
    min-width: 0;
  }

  .worktree-branch {
    font-size: 11px;
    font-weight: 500;
    color: ${mocha.text};
    min-width: 0;
  }

  .worktree-commit {
    font-size: 10px;
    color: ${mocha.overlay0};
    font-family: "JetBrainsMono Nerd Font", monospace;
  }

  .worktree-path {
    font-size: 9px;
    color: ${mocha.subtext0};
    min-width: 0;
  }

  .worktree-last-commit {
    font-size: 9px;
    font-style: italic;
    color: ${mocha.overlay0};
    margin-top: 2px;
  }

  .active-worktree {
    background-color: rgba(148, 226, 213, 0.15);
    border: 1px solid ${mocha.teal};
  }

  .active-indicator {
    color: ${mocha.teal};
    font-size: 8px;
    margin-right: 4px;
  }

  .active-indicator-placeholder {
    color: transparent;
    font-size: 8px;
    margin-right: 4px;
  }

  .dirty-worktree {
    border-left-color: ${mocha.peach};
  }

  .git-dirty {
    color: ${mocha.peach};
    font-weight: bold;
  }

  .git-sync {
    font-size: 10px;
    color: ${mocha.blue};
    margin-left: 4px;
  }

  .badge-main {
    font-size: 8px;
    color: ${mocha.green};
    background-color: rgba(166, 227, 161, 0.15);
    padding: 1px 4px;
    border-radius: 3px;
    margin-left: 4px;
  }

  .projects-header-container {
    background-color: rgba(30, 30, 46, 0.4);
    border-bottom: 1px solid ${mocha.surface0};
    margin-bottom: 8px;
  }

  .projects-header {
    padding: 8px 12px;
  }

  .projects-header-title {
    font-size: 14px;
    font-weight: bold;
    color: ${mocha.text};
  }

  .header-icon-button {
    background-color: transparent;
    color: ${mocha.subtext0};
    padding: 4px 8px;
    border-radius: 6px;
    font-size: 16px;
    border: none;
    margin-left: 4px;
  }

  .header-icon-button:hover {
    background-color: ${mocha.surface0};
    color: ${mocha.blue};
  }

  .expand-collapse-btn:hover {
    color: ${mocha.teal};
  }

  .new-project-btn:hover {
    color: ${mocha.green};
  }

  .projects-filter-row {
    padding: 4px 12px 8px 12px;
  }

  .filter-input-container {
    background-color: ${mocha.mantle};
    border: 1px solid ${mocha.surface1};
    border-radius: 6px;
    padding: 6px 10px;
    min-height: 28px;
  }

  .filter-input-container:focus-within {
    border-color: ${mocha.blue};
    background-color: ${mocha.base};
  }

  .filter-icon {
    color: ${mocha.subtext0};
    font-size: 14px;
    margin-right: 8px;
  }

  .project-filter-input {
    background-color: transparent;
    color: ${mocha.text};
    font-size: 12px;
    border: none;
    outline: none;
    min-width: 120px;
  }

  .filter-clear-button {
    background-color: transparent;
    color: ${mocha.subtext0};
    padding: 2px 4px;
    border: none;
    font-size: 12px;
    border-radius: 4px;
  }

  .filter-clear-button:hover {
    color: ${mocha.red};
    background-color: rgba(243, 139, 168, 0.2);
  }

  .filter-count {
    color: ${mocha.subtext0};
    font-size: 11px;
    margin-left: 8px;
    padding: 2px 6px;
    background-color: rgba(137, 180, 250, 0.15);
    border-radius: 4px;
  }

  .action-copy {
    color: ${mocha.blue};
  }

  .action-copy:hover {
    color: ${mocha.sapphire};
  }

  .project-card.selected,
  .repository-card.selected,
  .worktree-card.selected {
    background-color: rgba(137, 180, 250, 0.15);
    border-color: ${mocha.blue};
    box-shadow: 0 0 8px rgba(137, 180, 250, 0.3);
  }

  .project-card.selected .project-card-name,
  .repository-card.selected .project-card-name,
  .worktree-card.selected .worktree-name {
    color: ${mocha.blue};
  }

  .keyboard-hints {
    padding: 6px 12px;
    background-color: rgba(49, 50, 68, 0.8);
    border-top: 1px solid ${mocha.surface1};
    font-size: 10px;
    color: ${mocha.subtext0};
  }

  .keyboard-hint {
    margin-right: 12px;
  }

  .keyboard-hint-key {
    background-color: ${mocha.surface1};
    color: ${mocha.text};
    padding: 2px 5px;
    border-radius: 3px;
    font-family: monospace;
    font-weight: bold;
    margin-right: 4px;
  }

  .project-create-form {
    border-color: ${mocha.green};
    background-color: rgba(30, 30, 46, 0.95);
    margin: 8px;
    border-radius: 8px;
  }

  .project-create-form .edit-form-header {
    color: ${mocha.green};
  }

  .apps-header {
    padding: 8px 12px;
    background-color: rgba(30, 30, 46, 0.4);
    border-bottom: 1px solid ${mocha.surface0};
    margin-bottom: 8px;
  }

  .apps-header-title {
    font-size: 14px;
    font-weight: bold;
    color: ${mocha.text};
  }

  .new-app-button {
    background-color: ${mocha.sapphire};
    color: ${mocha.base};
    padding: 4px 12px;
    border-radius: 6px;
    font-size: 12px;
    font-weight: bold;
    border: none;
  }

  .new-app-button:hover {
    background-color: ${mocha.sky};
  }

  .app-create-form {
    border-color: ${mocha.sapphire};
    background-color: rgba(30, 30, 46, 0.95);
    margin: 8px;
    border-radius: 8px;
  }

  .app-create-form .edit-form-header {
    color: ${mocha.sapphire};
  }

  .app-type-selector {
    margin-bottom: 12px;
  }

  .type-buttons {
    padding: 4px 0;
  }

  .type-btn {
    background-color: rgba(49, 50, 68, 0.5);
    color: ${mocha.subtext0};
    padding: 8px 16px;
    border: 1px solid ${mocha.surface0};
    border-radius: 6px;
    font-size: 12px;
    margin-right: 8px;
  }

  .type-btn:hover {
    background-color: rgba(49, 50, 68, 0.8);
    color: ${mocha.text};
  }

  .type-btn.active {
    background-color: ${mocha.sapphire};
    color: ${mocha.base};
    border-color: ${mocha.sapphire};
    font-weight: bold;
  }

  .terminal-command-select {
    padding: 4px 0;
  }

  .term-btn {
    background-color: rgba(49, 50, 68, 0.5);
    color: ${mocha.subtext0};
    padding: 6px 12px;
    border: 1px solid ${mocha.surface0};
    border-radius: 4px;
    font-size: 11px;
    margin-right: 6px;
  }

  .term-btn:hover {
    background-color: rgba(49, 50, 68, 0.8);
    color: ${mocha.text};
  }

  .term-btn.active {
    background-color: ${mocha.teal};
    color: ${mocha.base};
    border-color: ${mocha.teal};
    font-weight: bold;
  }

  .pwa-fields {
    padding: 12px;
    background-color: rgba(137, 180, 250, 0.1);
    border-radius: 6px;
    border: 1px solid ${mocha.sapphire};
    margin-top: 8px;
  }

  .pwa-workspace-note {
    color: ${mocha.peach};
    font-style: italic;
  }

  .pwa-create-success {
    background-color: rgba(166, 227, 161, 0.2);
    border: 1px solid ${mocha.green};
    border-radius: 6px;
    padding: 12px;
    margin-top: 8px;
  }

  .pwa-create-success .success-message {
    color: ${mocha.green};
    font-weight: bold;
    margin-bottom: 8px;
  }

  .ulid-display {
    font-family: monospace;
  }

  .ulid-label {
    color: ${mocha.subtext0};
  }

  .ulid-value {
    color: ${mocha.sapphire};
    font-weight: bold;
  }

  .workspace-input {
    min-width: 80px;
  }

  .scope-buttons {
    margin-top: 4px;
    background-color: #313244;
    border-radius: 6px;
    padding: 2px;
  }

  .scope-btn {
    padding: 4px 12px;
    border-radius: 4px;
    color: #cdd6f4;
    background-color: transparent;
  }

  .scope-btn.active {
    background-color: #89b4fa;
    color: #11111b;
    font-weight: bold;
  }

  .agent-buttons {
    margin-top: 4px;
    background-color: #313244;
    border-radius: 6px;
    padding: 2px;
  }

  .agent-btn {
    padding: 4px 12px;
    border-radius: 4px;
    color: #cdd6f4;
    background-color: transparent;
  }

  .agent-btn.active {
    font-weight: bold;
    color: #11111b;
  }

  .agent-btn.claude.active {
    background-color: #89b4fa;
  }

  .agent-btn.gemini.active {
    background-color: #cba6f7;
  }

  .remote-toggle {
    padding: 8px 0;
    margin-top: 8px;
  }

  .remote-toggle checkbox {
    margin-right: 8px;
  }

  .remote-fields {
    padding: 12px;
    background-color: rgba(49, 50, 68, 0.3);
    border-radius: 6px;
    border: 1px solid ${mocha.surface1};
    margin-top: 8px;
  }

  .icon-input {
    min-width: 60px;
  }

  .port-input {
    min-width: 80px;
  }

  .readonly-field .field-readonly {
    color: ${mocha.subtext0};
    background-color: rgba(49, 50, 68, 0.5);
    padding: 8px 12px;
    border-radius: 6px;
    border: 1px solid ${mocha.surface0};
    font-family: monospace;
    font-size: 12px;
  }

  .readonly-field .field-label {
    color: ${mocha.overlay0};
  }

  .field-hint {
    font-size: 10px;
    color: ${mocha.overlay0};
    margin-top: 4px;
    font-style: italic;
  }

  .edit-button {
    background-color: transparent;
    border: none;
    color: ${mocha.blue};
    padding: 3px 6px;
    border-radius: 4px;
    font-size: 11px;
    margin-left: 6px;
  }

  .edit-button label {
    color: ${mocha.blue};
  }

  .edit-button:hover {
    background-color: rgba(137, 180, 250, 0.2);
  }

  .edit-button:hover label {
    color: ${mocha.blue};
  }

  .delete-button {
    background-color: transparent;
    border: none;
    color: ${mocha.red};
    padding: 3px 6px;
    border-radius: 4px;
    font-size: 11px;
    margin-left: 4px;
  }

  .delete-button:hover {
    background-color: rgba(243, 139, 168, 0.2);
  }

  .delete-confirmation-dialog {
    background-color: rgba(24, 24, 37, 0.98);
    border: 2px solid ${mocha.red};
    border-radius: 8px;
    padding: 16px;
    margin: 8px 0;
  }

  .delete-confirmation-dialog .dialog-header {
    margin-bottom: 12px;
  }

  .delete-confirmation-dialog .dialog-icon {
    font-size: 18px;
    margin-right: 8px;
  }

  .delete-confirmation-dialog .dialog-icon.warning {
    color: ${mocha.peach};
  }

  .delete-confirmation-dialog .dialog-title {
    font-size: 16px;
    font-weight: bold;
    color: ${mocha.red};
  }

  .delete-confirmation-dialog .project-name-display {
    font-size: 14px;
    font-weight: bold;
    color: ${mocha.text};
    margin-bottom: 12px;
    padding: 8px 12px;
    background-color: rgba(243, 139, 168, 0.1);
    border-radius: 4px;
    border-left: 3px solid ${mocha.red};
  }

  .delete-confirmation-dialog .warning-message {
    font-size: 12px;
    color: ${mocha.subtext0};
    margin-bottom: 12px;
  }

  .delete-confirmation-dialog .worktree-warning {
    background-color: rgba(250, 179, 135, 0.15);
    border: 1px solid ${mocha.peach};
    border-radius: 6px;
    padding: 12px;
    margin-bottom: 12px;
  }

  .delete-confirmation-dialog .warning-icon {
    font-size: 12px;
    color: ${mocha.peach};
    font-weight: bold;
    margin-bottom: 6px;
  }

  .delete-confirmation-dialog .warning-detail {
    font-size: 11px;
    color: ${mocha.subtext0};
    margin-bottom: 8px;
  }

  .delete-confirmation-dialog .force-delete-option {
    margin-top: 8px;
    padding: 6px 0;
  }

  .delete-confirmation-dialog .force-delete-checkbox {
    margin-right: 8px;
  }

  .delete-confirmation-dialog .force-delete-label {
    font-size: 12px;
    color: ${mocha.peach};
  }

  .delete-confirmation-dialog .error-message {
    color: ${mocha.red};
    font-size: 12px;
    padding: 8px 12px;
    background-color: rgba(243, 139, 168, 0.15);
    border-radius: 4px;
    margin-bottom: 12px;
  }

  .delete-confirmation-dialog .dialog-actions {
    margin-top: 16px;
  }

  .delete-confirmation-dialog .cancel-delete-button {
    background-color: rgba(49, 50, 68, 0.8);
    color: ${mocha.subtext0};
    padding: 8px 16px;
    border: 1px solid ${mocha.surface1};
    border-radius: 6px;
    font-size: 12px;
    margin-right: 8px;
  }

  .delete-confirmation-dialog .cancel-delete-button:hover {
    background-color: ${mocha.surface0};
    color: ${mocha.text};
  }

  .delete-confirmation-dialog .confirm-delete-button {
    background-color: ${mocha.red};
    color: ${mocha.base};
    padding: 8px 16px;
    border: none;
    border-radius: 6px;
    font-size: 12px;
    font-weight: bold;
  }

  .delete-confirmation-dialog .confirm-delete-button:hover {
    background-color: rgba(243, 139, 168, 0.85);
  }

  .delete-confirmation-dialog .confirm-delete-button.disabled {
    background-color: ${mocha.surface1};
    color: ${mocha.overlay0};
  }

  .delete-confirmation-dialog .confirm-delete-button.disabled:hover {
    background-color: ${mocha.surface1};
  }

  .app-delete-confirmation-dialog {
    background-color: rgba(24, 24, 37, 0.98);
    border: 2px solid rgba(243, 139, 168, 0.7);
    border-radius: 8px;
    padding: 16px;
    margin-top: 8px;
    margin-bottom: 8px;
  }

  .app-delete-confirmation-dialog .dialog-header {
    margin-bottom: 12px;
  }

  .app-delete-confirmation-dialog .dialog-icon {
    font-size: 20px;
    margin-right: 8px;
  }

  .app-delete-confirmation-dialog .dialog-icon.warning {
    color: ${mocha.yellow};
  }

  .app-delete-confirmation-dialog .dialog-title {
    font-size: 14px;
    font-weight: bold;
    color: rgba(243, 139, 168, 0.95);
  }

  .app-delete-confirmation-dialog .app-name-display {
    font-size: 16px;
    font-weight: bold;
    color: ${mocha.text};
    padding: 8px 12px;
    background-color: ${mocha.surface0};
    border-radius: 4px;
    margin-bottom: 12px;
  }

  .app-delete-confirmation-dialog .warning-message {
    font-size: 12px;
    color: ${mocha.subtext0};
    margin-bottom: 12px;
  }

  .app-delete-confirmation-dialog .pwa-warning {
    background-color: rgba(249, 226, 175, 0.15);
    border: 1px solid ${mocha.yellow};
    border-radius: 6px;
    padding: 10px;
    margin-bottom: 12px;
  }

  .app-delete-confirmation-dialog .pwa-warning .warning-icon {
    font-size: 12px;
    font-weight: bold;
    color: ${mocha.yellow};
    margin-bottom: 4px;
  }

  .app-delete-confirmation-dialog .pwa-warning .warning-detail {
    font-size: 11px;
    color: ${mocha.subtext0};
  }

  .app-delete-confirmation-dialog .error-message {
    background-color: rgba(243, 139, 168, 0.2);
    border: 1px solid rgba(243, 139, 168, 0.5);
    border-radius: 4px;
    padding: 8px;
    margin-bottom: 12px;
    font-size: 12px;
    color: rgba(243, 139, 168, 1);
  }

  .app-delete-confirmation-dialog .dialog-actions {
    margin-top: 8px;
  }

  .app-delete-confirmation-dialog .cancel-delete-app-button {
    background-color: ${mocha.surface0};
    color: ${mocha.text};
    border: 1px solid ${mocha.overlay0};
    border-radius: 4px;
    padding: 6px 12px;
    font-size: 12px;
  }

  .app-delete-confirmation-dialog .cancel-delete-app-button:hover {
    background-color: ${mocha.surface1};
    border-color: ${mocha.overlay0};
  }

  .app-delete-confirmation-dialog .confirm-delete-app-button {
    background-color: rgba(243, 139, 168, 0.85);
    color: ${mocha.mantle};
    border: none;
    border-radius: 4px;
    padding: 6px 12px;
    font-size: 12px;
    font-weight: bold;
  }

  .app-delete-confirmation-dialog .confirm-delete-app-button:hover {
    background-color: rgba(243, 139, 168, 1);
  }

  .delete-app-button {
    background-color: transparent;
    border: none;
    font-size: 12px;
    padding: 2px 6px;
    border-radius: 3px;
    opacity: 0.6;
    margin-left: 4px;
  }

  .delete-app-button:hover {
    background-color: rgba(243, 139, 168, 0.2);
    opacity: 1;
  }

  .rebuild-required-notice {
    background-color: rgba(166, 227, 161, 0.15);
    border: 1px solid ${mocha.green};
    border-radius: 6px;
    padding: 12px;
    margin: 8px 0;
    font-size: 12px;
    color: ${mocha.green};
  }

  .success-notification-toast {
    background-color: rgba(166, 227, 161, 0.95);
    border: 1px solid ${mocha.green};
    border-radius: 8px;
    padding: 10px 16px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
    margin-top: 10px;
  }

  .success-notification-toast .success-icon {
    font-size: 16px;
    color: ${mocha.mantle};
    font-weight: bold;
  }

  .success-notification-toast .success-message {
    font-size: 13px;
    color: ${mocha.mantle};
    font-weight: 500;
  }

  .success-notification-toast .success-dismiss {
    background-color: transparent;
    border: none;
    font-size: 12px;
    color: ${mocha.mantle};
    opacity: 0.7;
    padding: 2px 6px;
    margin-left: 8px;
  }

  .success-notification-toast .success-dismiss:hover {
    opacity: 1;
  }

  .error-notification-toast {
    background-color: rgba(243, 139, 168, 0.95);
    border: 1px solid ${mocha.red};
    border-radius: 8px;
    padding: 10px 16px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
    margin-top: 10px;
  }

  .error-notification-toast .error-icon {
    font-size: 16px;
    color: ${mocha.mantle};
    font-weight: bold;
  }

  .error-notification-toast .error-message {
    font-size: 13px;
    color: ${mocha.mantle};
    font-weight: 500;
  }

  .error-notification-toast .error-dismiss {
    background-color: transparent;
    border: none;
    font-size: 12px;
    color: ${mocha.mantle};
    opacity: 0.7;
    padding: 2px 6px;
    margin-left: 8px;
  }

  .error-notification-toast .error-dismiss:hover {
    opacity: 1;
  }

  .warning-notification-toast {
    background-color: rgba(249, 226, 175, 0.95);
    border: 1px solid ${mocha.yellow};
    border-radius: 8px;
    padding: 10px 16px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
    margin-top: 10px;
  }

  .warning-notification-toast .warning-icon {
    font-size: 16px;
    color: ${mocha.mantle};
    font-weight: bold;
  }

  .warning-notification-toast .warning-message {
    font-size: 13px;
    color: ${mocha.mantle};
    font-weight: 500;
  }

  .warning-notification-toast .warning-dismiss {
    background-color: transparent;
    border: none;
    font-size: 12px;
    color: ${mocha.mantle};
    opacity: 0.7;
    padding: 2px 6px;
    margin-left: 8px;
  }

  .warning-notification-toast .warning-dismiss:hover {
    opacity: 1;
  }

  .context-menu-overlay {
    background-color: rgba(0, 0, 0, 0.5);
    padding: 20px;
  }

  .context-menu {
    background-color: ${mocha.base};
    border: 1px solid ${mocha.overlay0};
    border-radius: 8px;
    padding: 8px 0;
    min-width: 150px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
  }

  .context-menu-header {
    padding: 8px 12px;
    border-bottom: 1px solid ${mocha.surface0};
    margin-bottom: 4px;
  }

  .context-menu-title {
    font-size: 12px;
    font-weight: bold;
    color: ${mocha.subtext0};
  }

  .context-menu-close {
    padding: 2px 6px;
    border-radius: 4px;
  }

  .context-menu-close:hover {
    background-color: ${mocha.surface0};
  }

  .context-menu-item {
    padding: 8px 12px;
  }

  .context-menu-item:hover {
    background-color: ${mocha.surface0};
  }

  .context-menu-item.danger:hover {
    background-color: rgba(243, 139, 168, 0.2);
  }

  .context-menu-item.danger .menu-label {
    color: ${mocha.red};
  }

  .menu-icon {
    font-size: 14px;
    color: ${mocha.subtext0};
    min-width: 24px;
  }

  .menu-label {
    font-size: 13px;
    color: ${mocha.text};
  }

  .window-action-bar {
    background-color: ${mocha.surface0};
    border-radius: 0 0 6px 6px;
    padding: 4px 8px;
    margin-top: 2px;
  }

  .action-btn {
    font-size: 16px;
    padding: 6px 10px;
    border-radius: 4px;
    color: ${mocha.subtext0};
    margin: 0 2px;
  }

  .action-btn:hover {
    background-color: ${mocha.surface1};
    color: ${mocha.text};
  }

  .action-focus:hover {
    color: ${mocha.blue};
  }

  .action-float:hover {
    color: ${mocha.yellow};
  }

  .action-fullscreen:hover {
    color: ${mocha.green};
  }

  .action-scratchpad:hover {
    color: ${mocha.mauve};
  }

  .action-trace {
    color: ${mocha.overlay0};
  }

  .action-trace:hover {
    background-color: rgba(180, 190, 254, 0.2);
    color: ${mocha.lavender};
  }

  .action-close {
    color: ${mocha.overlay0};
  }

  .action-close:hover {
    background-color: rgba(243, 139, 168, 0.2);
    color: ${mocha.red};
  }

  .hover-close-btn {
    opacity: 0;
    padding: 4px 8px;
    margin-left: 4px;
    border-radius: 6px;
    background-color: transparent;
    transition: opacity 150ms ease-in-out, background-color 150ms ease-in-out;
  }

  .hover-close-icon {
    font-size: 14px;
    color: ${mocha.overlay0};
    transition: color 150ms ease-in-out;
  }

  .window-row:hover .hover-close-btn {
    opacity: 1;
  }

  .project-header:hover .hover-close-btn {
    opacity: 1;
  }

  .hover-close-btn:hover {
    background-color: rgba(243, 139, 168, 0.2);
  }

  .hover-close-btn:hover .hover-close-icon {
    color: ${mocha.red};
  }

  .project-hover-close {
    padding: 2px 6px;
  }

  .project-hover-close .hover-close-icon {
    font-size: 12px;
  }

  .save-in-progress {
    opacity: 0.6;
  }

  .loading-spinner {
    font-size: 14px;
  }

  .edit-form {
    background-color: rgba(24, 24, 37, 0.95);
    border: 1px solid ${mocha.blue};
    border-radius: 8px;
    padding: 16px;
    margin-top: 8px;
  }

  .edit-form-header {
    font-size: 14px;
    font-weight: bold;
    color: ${mocha.blue};
    margin-bottom: 12px;
  }

  .form-field {
    margin-bottom: 12px;
  }

  .form-field-checkbox {
    margin-top: 8px;
    margin-bottom: 8px;

    checkbox {
      min-width: 18px;
      min-height: 18px;
    }

    .checkbox-label {
      margin-left: 8px;
      color: ${mocha.subtext0};
      font-size: 12px;
    }
  }

  .field-label {
    font-size: 11px;
    color: ${mocha.subtext0};
    margin-bottom: 4px;
  }

  .field-input {
    background-color: ${mocha.surface0};
    border: 1px solid ${mocha.overlay0};
    border-radius: 4px;
    padding: 6px 8px;
    font-size: 12px;
    color: ${mocha.text};
  }

  .field-input:focus {
    border-color: ${mocha.blue};
    outline: none;
  }

  .field-value-readonly {
    font-size: 11px;
    color: ${mocha.subtext0};
    padding: 6px 8px;
    background-color: ${mocha.mantle};
    border-radius: 4px;
    font-family: "JetBrainsMono Nerd Font", monospace;
  }

  .conflict-dialog-overlay {
    background-color: rgba(0, 0, 0, 0.7);
    padding: 20px;
  }

  .conflict-dialog {
    background-color: ${mocha.base};
    border: 2px solid ${mocha.yellow};
    border-radius: 12px;
    padding: 20px;
  }

  .conflict-header {
    padding-bottom: 12px;
    border-bottom: 1px solid ${mocha.overlay0};
    margin-bottom: 16px;
  }

  .conflict-title {
    font-size: 16px;
    font-weight: bold;
    color: ${mocha.yellow};
  }

  .conflict-close-button {
    background-color: transparent;
    border: none;
    color: ${mocha.overlay0};
    font-size: 18px;
    padding: 4px 8px;
  }

  .conflict-close-button:hover {
    color: ${mocha.text};
    background-color: ${mocha.surface0};
    border-radius: 4px;
  }

  .conflict-message {
    font-size: 13px;
    color: ${mocha.text};
    margin-bottom: 16px;
  }

  .conflict-diff-container {
    margin: 16px 0;
  }

  .conflict-diff-pane {
    border: 1px solid ${mocha.overlay0};
    border-radius: 8px;
    padding: 8px;
    background-color: ${mocha.mantle};
  }

  .conflict-pane-header {
    font-size: 12px;
    font-weight: bold;
    color: ${mocha.blue};
    margin-bottom: 8px;
  }

  .conflict-content {
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 11px;
    color: ${mocha.text};
  }

  .conflict-actions {
    margin-top: 16px;
    padding-top: 12px;
    border-top: 1px solid ${mocha.overlay0};
  }

  .conflict-button {
    padding: 8px 16px;
    border-radius: 6px;
    font-size: 12px;
    font-weight: bold;
    margin: 0 4px;
  }

  .conflict-keep-file {
    background-color: ${mocha.surface0};
    border: 1px solid ${mocha.overlay0};
    color: ${mocha.text};
  }

  .conflict-keep-file:hover {
    background-color: ${mocha.surface1};
    border-color: ${mocha.overlay0};
  }

  .conflict-keep-ui {
    background-color: ${mocha.green};
    border: 1px solid ${mocha.green};
    color: ${mocha.base};
  }

  .conflict-keep-ui:hover {
    background-color: ${mocha.teal};
    border-color: ${mocha.teal};
  }

  .conflict-merge {
    background-color: ${mocha.yellow};
    border: 1px solid ${mocha.yellow};
    color: ${mocha.base};
  }

  .conflict-merge:hover {
    background-color: ${mocha.peach};
    border-color: ${mocha.peach};
  }

  .radio-button {
    background-color: ${mocha.surface0};
    border: 1px solid ${mocha.overlay0};
    border-radius: 4px;
    padding: 6px 12px;
    font-size: 11px;
    color: ${mocha.text};
    margin-right: 8px;
  }

  .radio-button.selected {
    background-color: ${mocha.blue};
    border-color: ${mocha.blue};
    color: ${mocha.base};
  }

  .radio-button:hover {
    border-color: ${mocha.blue};
  }

  .form-section {
    margin-top: 16px;
    padding-top: 16px;
    border-top: 1px solid ${mocha.overlay0};
  }

  .remote-fields {
    margin-left: 24px;
    margin-top: 8px;
  }

  .form-actions {
    margin-top: 16px;
  }

  .cancel-button {
    background-color: rgba(49, 50, 68, 0.6);
    border: 1px solid ${mocha.surface1};
    border-radius: 8px;
    padding: 8px 18px;
    margin-right: 10px;
    font-size: 12px;
    font-weight: 500;
    color: ${mocha.subtext0};
  }

  .cancel-button:hover {
    background-color: rgba(69, 71, 90, 0.8);
    border-color: ${mocha.overlay0};
    color: ${mocha.text};
  }

  .save-button {
    background-color: ${mocha.blue};
    border: none;
    border-radius: 8px;
    padding: 8px 20px;
    font-size: 12px;
    color: ${mocha.base};
    font-weight: bold;
    box-shadow: 0 2px 8px rgba(137, 180, 250, 0.3);
  }

  .save-button:hover {
    background-color: ${mocha.sapphire};
    box-shadow: 0 4px 12px rgba(116, 199, 236, 0.4);
  }

  .save-button-disabled {
    background-color: ${mocha.surface0};
    border: 1px solid ${mocha.surface1};
    border-radius: 8px;
    padding: 8px 20px;
    font-size: 12px;
    color: ${mocha.overlay0};
    font-weight: bold;
    opacity: 0.6;
  }

  .save-button-loading {
    background-color: rgba(137, 180, 250, 0.2);
    border: 1px solid ${mocha.blue};
    border-radius: 8px;
    padding: 8px 20px;
    font-size: 12px;
    color: ${mocha.blue};
    font-weight: bold;
    font-style: italic;
  }

  .field-error {
    font-size: 11px;
    color: ${mocha.red};
    margin-top: 4px;
    padding: 4px 0;
  }

  .error-message {
    background-color: rgba(243, 139, 168, 0.15);
    border-left: 3px solid ${mocha.red};
    padding: 12px;
    margin: 8px 0;
    font-size: 12px;
    color: ${mocha.red};
    border-radius: 4px;
  }

  .app-card {
    background-color: rgba(49, 50, 68, 0.4);
    border: 1px solid ${mocha.overlay0};
    border-radius: 8px;
    padding: 12px;
    margin-bottom: 8px;
  }

  .app-card-header {
    margin-bottom: 4px;
  }

  .app-icon {
    font-size: 18px;
    margin-right: 8px;
  }

  .app-card-name {
    font-size: 13px;
    font-weight: bold;
    color: ${mocha.text};
    margin-bottom: 2px;
  }

  .app-card-details {
    font-size: 10px;
    color: ${mocha.subtext0};
  }

  .app-running-indicator {
    color: ${mocha.green};
    font-size: 14px;
  }

  .app-section {
    margin-bottom: 16px;
  }

  .section-header {
    font-size: 12px;
    font-weight: bold;
    color: ${mocha.subtext0};
    margin-bottom: 8px;
    margin-left: 4px;
  }

  .app-icon-container {
    margin-right: 10px;
  }

  .app-type-icon {
    font-size: 24px;
  }

  .app-name-row {
    margin-bottom: 2px;
  }

  .app-card-command {
    font-size: 9px;
    color: ${mocha.subtext0};
    font-family: "JetBrainsMono Nerd Font", monospace;
  }

  .terminal-indicator {
    color: ${mocha.mauve};
    font-size: 12px;
    margin-left: 6px;
  }

  .app-status-container {
    margin-left: 8px;
  }

  .app-card-details-row {
    margin-top: 6px;
    padding-top: 6px;
    border-top: 1px solid rgba(108, 112, 134, 0.2);
  }

  .app-edit-button {
    background-color: transparent;
    color: ${mocha.blue};
    border: none;
    font-size: 14px;
    padding: 2px 6px;
    border-radius: 4px;
  }

  .app-edit-button:hover {
    background-color: rgba(137, 180, 250, 0.15);
    color: ${mocha.sapphire};
  }

  .health-cards {
    padding: 4px;
  }

  .health-card {
    background-color: rgba(49, 50, 68, 0.4);
    border: 1px solid ${mocha.overlay0};
    border-radius: 6px;
    padding: 10px 12px;
    margin-bottom: 6px;
  }

  .health-card.health-ok {
    border-left: 3px solid ${mocha.green};
  }

  .health-card.health-error {
    border-left: 3px solid ${mocha.red};
  }

  .health-card-title {
    font-size: 12px;
    color: ${mocha.subtext0};
  }

  .health-card-value {
    font-size: 13px;
    font-weight: bold;
    color: ${mocha.text};
  }

  .health-summary {
    background-color: rgba(49, 50, 68, 0.3);
    border: 1px solid ${mocha.overlay0};
    border-radius: 6px;
    padding: 8px 12px;
    margin-bottom: 8px;
  }

  .health-summary-title {
    font-size: 14px;
    font-weight: bold;
    color: ${mocha.text};
    margin-bottom: 4px;
  }

  .health-summary-counts {
    font-size: 11px;
    color: ${mocha.subtext0};
  }

  .health-categories {
    padding: 4px;
  }

  .service-category {
    margin-bottom: 12px;
  }

  .category-header {
    background-color: rgba(69, 71, 90, 0.5);
    border-radius: 4px;
    padding: 6px 10px;
    margin-bottom: 6px;
  }

  .category-title {
    font-size: 13px;
    font-weight: bold;
    color: ${mocha.text};
  }

  .category-counts {
    font-size: 11px;
    color: ${mocha.subtext0};
  }

  .service-list {
    padding-left: 4px;
  }

  .service-health-card {
    background-color: rgba(49, 50, 68, 0.4);
    border: 1px solid ${mocha.overlay0};
    border-radius: 6px;
    padding: 8px 10px;
    margin-bottom: 4px;
  }

  .service-health-card:hover {
    background-color: rgba(69, 71, 90, 0.6);
  }

  .service-health-card.health-healthy {
    border-left: 3px solid ${mocha.green};
  }

  .service-health-card.health-degraded {
    border-left: 3px solid ${mocha.yellow};
    background-color: rgba(249, 226, 175, 0.1);
  }

  .service-health-card.health-degraded .service-icon {
    color: ${mocha.yellow};
  }

  .service-health-card.health-critical {
    border-left: 4px solid ${mocha.red};
    border: 1px solid ${mocha.red};
    background-color: rgba(243, 139, 168, 0.15);
    box-shadow: 0 0 8px rgba(243, 139, 168, 0.3);
  }

  .service-health-card.health-critical .service-name {
    color: ${mocha.red};
    font-weight: 600;
  }

  .service-health-card.health-critical .service-icon {
    color: ${mocha.red};
  }

  .service-health-card.health-disabled {
    border-left: 3px solid ${mocha.overlay0};
    opacity: 0.7;
  }

  .service-health-card.health-unknown {
    border-left: 3px solid ${mocha.peach};
  }

  .service-icon {
    font-size: 16px;
    min-width: 24px;
    margin-right: 8px;
  }

  .service-name {
    font-size: 12px;
    font-weight: 500;
    color: ${mocha.text};
  }

  .service-status {
    font-size: 10px;
    color: ${mocha.subtext0};
    margin-top: 2px;
  }

  .service-uptime {
    font-size: 9px;
    color: ${mocha.green};
    margin-top: 2px;
  }

  .service-memory {
    font-size: 9px;
    color: ${mocha.blue};
    margin-top: 2px;
  }

  .service-last-active {
    font-size: 9px;
    color: ${mocha.red};
    margin-top: 2px;
    font-style: italic;
  }

  .health-indicator-box {
    min-width: 80px;
  }

  .health-indicator {
    font-size: 10px;
    color: ${mocha.subtext0};
    padding: 2px 6px;
    border-radius: 3px;
    background-color: rgba(69, 71, 90, 0.5);
  }

  .restart-count {
    font-size: 9px;
    color: ${mocha.yellow};
    margin-top: 2px;
    font-weight: bold;
  }

  .restart-count.restart-warning {
    color: ${mocha.red};
    font-size: 10px;
  }

  .restart-button {
    background-color: ${mocha.blue};
    color: ${mocha.base};
    border: none;
    border-radius: 4px;
    padding: 4px 8px;
    margin-top: 4px;
    font-size: 14px;
    font-weight: bold;
  }

  .restart-button:hover {
    background-color: ${mocha.sapphire};
  }

  .restart-button:active {
    background-color: ${mocha.sky};
  }

  .detail-view {
    background-color: transparent;
    padding: 8px;
  }

  .detail-header {
    background-color: rgba(49, 50, 68, 0.4);
    border-radius: 8px;
    padding: 8px 12px;
    margin-bottom: 8px;
  }

  .detail-back-btn {
    font-size: 12px;
    padding: 6px 12px;
    background-color: rgba(69, 71, 90, 0.5);
    color: ${mocha.text};
    border: 1px solid ${mocha.overlay0};
    border-radius: 4px;
  }

  .detail-back-btn:hover {
    background-color: rgba(137, 180, 250, 0.6);
    color: ${mocha.base};
    border-color: ${mocha.blue};
  }

  .detail-title {
    font-size: 14px;
    font-weight: bold;
    color: ${mocha.text};
  }

  .detail-content {
    padding: 4px;
  }

  .detail-section {
    background-color: rgba(49, 50, 68, 0.4);
    border: 1px solid ${mocha.overlay0};
    border-radius: 8px;
    padding: 10px 12px;
    margin-bottom: 8px;
  }

  .detail-section-title {
    font-size: 12px;
    font-weight: bold;
    color: ${mocha.teal};
    margin-bottom: 8px;
  }

  .detail-row {
    padding: 4px 0;
    border-bottom: 1px solid rgba(108, 112, 134, 0.2);
  }

  .detail-row:last-child {
    border-bottom: none;
  }

  .detail-label {
    font-size: 11px;
    color: ${mocha.subtext0};
    min-width: 80px;
  }

  .detail-value {
    font-size: 11px;
    color: ${mocha.text};
    font-family: monospace;
  }

  .detail-full-title {
    font-size: 12px;
    color: ${mocha.text};
  }

  .detail-marks {
    font-size: 10px;
    color: ${mocha.subtext0};
    font-family: monospace;
  }

  .window-info {
    margin-left: 6px;
    min-width: 0;
  }

  .window-app-name {
    min-width: 0;
  }

  .window-title {
    font-size: 10px;
    color: ${mocha.subtext0};
    min-width: 0;
  }

  .events-view-container {
    padding: 0 8px 8px 8px;
  }

  .events-list {
    padding: 4px;
    margin-top: 4px;
  }

  .burst-indicator {
    padding: 6px 12px;
    margin: 4px 8px;
    border-radius: 4px;
    background-color: rgba(249, 226, 175, 0.1);
    border: 1px solid rgba(249, 226, 175, 0.3);
  }

  .burst-badge {
    font-size: 12px;
    color: ${mocha.yellow};
    font-weight: bold;
  }

  .burst-badge.burst-active {
    color: ${mocha.red};
  }

  .burst-badge.burst-inactive {
    color: ${mocha.subtext0};
  }

  .event-card {
    background-color: ${mocha.surface0};
    border-left: 3px solid ${mocha.overlay0};
    border-radius: 4px;
    padding: 8px;
    margin-bottom: 6px;
  }

  .event-card:hover {
    background-color: ${mocha.surface1};
  }

  .event-card.event-category-window {
    border-left-color: ${mocha.blue};
  }

  .event-card.event-category-workspace {
    border-left-color: ${mocha.teal};
  }

  .event-card.event-category-output {
    border-left-color: ${mocha.mauve};
  }

  .event-card.event-category-binding {
    border-left-color: ${mocha.yellow};
  }

  .event-card.event-category-mode {
    border-left-color: ${mocha.sky};
  }

  .event-card.event-category-system {
    border-left-color: ${mocha.red};
  }

  .event-card.event-category-project {
    border-left-color: ${mocha.peach};
  }

  .event-card.event-category-visibility {
    border-left-color: ${mocha.mauve};
  }

  .event-card.event-category-scratchpad {
    border-left-color: ${mocha.pink};
  }

  .event-card.event-category-launch {
    border-left-color: ${mocha.green};
  }

  .event-card.event-category-state {
    border-left-color: ${mocha.sapphire};
  }

  .event-card.event-category-command {
    border-left-color: ${mocha.sky};
  }

  .event-card.event-category-trace {
    border-left-color: ${mocha.lavender};
  }

  .event-source-badge {
    font-size: 14px;
    margin-right: 8px;
    min-width: 18px;
    padding: 2px;
    border-radius: 3px;
  }

  .event-source-badge.source-i3pm {
    color: ${mocha.peach};
    background-color: rgba(250, 179, 135, 0.15);
  }

  .event-source-badge.source-sway {
    color: ${mocha.blue};
    background-color: rgba(137, 180, 250, 0.1);
  }

  .event-card.event-source-i3pm {
    background-color: rgba(250, 179, 135, 0.05);
  }

  .event-card.event-source-i3pm:hover {
    background-color: rgba(250, 179, 135, 0.1);
  }

  .event-trace-indicator {
    font-size: 14px;
    margin-right: 6px;
    color: ${mocha.mauve};
    min-width: 16px;
    opacity: 0.9;
  }

  .event-trace-indicator.trace-evicted {
    color: ${mocha.overlay0};
    opacity: 0.6;
  }

  .event-orphaned-indicator {
    font-size: 12px;
    margin-right: 6px;
    color: ${mocha.yellow};
    opacity: 0.8;
  }

  .event-duration-badge {
    font-size: 10px;
    font-weight: 600;
    margin-right: 6px;
    padding: 2px 6px;
    border-radius: 8px;
    min-width: 40px;
  }

  .event-duration-badge.duration-slow {
    color: ${mocha.yellow};
    background-color: rgba(249, 226, 175, 0.2);
  }

  .event-duration-badge.duration-critical {
    color: ${mocha.red};
    background-color: rgba(243, 139, 168, 0.2);
  }

  .event-card.event-has-trace {
    border-left: 2px solid ${mocha.mauve};
  }

  .event-chain-indicator {
    background-color: ${mocha.lavender};
    border-radius: 1px;
    margin-right: 8px;
    min-height: 20px;
  }

  .event-card.event-in-chain {
    border-left: 2px solid ${mocha.lavender};
  }

  .event-card.event-in-chain:hover {
    background-color: rgba(180, 190, 254, 0.15);
  }

  .event-card.event-child-depth-1 {
    border-left-color: ${mocha.sapphire};
  }
  .event-card.event-child-depth-2 {
    border-left-color: ${mocha.sky};
  }
  .event-card.event-child-depth-3 {
    border-left-color: ${mocha.teal};
  }

  .event-icon {
    font-size: 20px;
    margin-right: 12px;
    min-width: 28px;
  }

  .event-header {
    margin-bottom: 4px;
  }

  .event-type {
    font-size: 11px;
    font-weight: 600;
    color: ${mocha.text};
    font-family: monospace;
  }

  .event-timestamp {
    font-size: 10px;
    color: ${mocha.subtext0};
    font-style: italic;
  }

  .event-payload {
    font-size: 10px;
    color: ${mocha.subtext0};
  }

  .filter-panel {
    background-color: transparent;
    padding: 0;
    margin: 0 4px 0 4px;
  }

  .filter-header {
    padding: 6px 8px;
    background-color: ${mocha.surface0};
    border-radius: 4px;
    border: 1px solid ${mocha.overlay0};
    margin-bottom: 0;
  }

  .filter-header:hover {
    background-color: ${mocha.surface1};
    border-color: ${mocha.blue};
  }

  .filter-title {
    font-size: 11px;
    font-weight: 600;
    color: ${mocha.blue};
  }

  .filter-toggle {
    font-size: 9px;
    color: ${mocha.subtext0};
    margin-left: 8px;
  }

  .filter-controls {
    padding: 8px 4px;
    background-color: ${mocha.mantle};
    border-radius: 6px;
    margin-top: 4px;
    border: 1px solid ${mocha.overlay0};
  }

  .filter-global-controls {
    padding: 6px 4px;
    margin-bottom: 8px;
  }

  .filter-button {
    background-color: ${mocha.surface0};
    color: ${mocha.text};
    border: 1px solid ${mocha.overlay0};
    border-radius: 3px;
    padding: 4px 10px;
    margin-right: 6px;
    font-size: 10px;
    font-weight: 500;
  }

  .filter-button:hover {
    background-color: ${mocha.surface1};
    border-color: ${mocha.blue};
  }

  .sort-controls {
    padding-left: 12px;
  }

  .sort-label {
    font-size: 10px;
    color: ${mocha.subtext0};
    margin-right: 6px;
  }

  .sort-button {
    background-color: ${mocha.surface0};
    color: ${mocha.subtext0};
    border: 1px solid ${mocha.surface1};
    border-radius: 3px;
    padding: 3px 8px;
    margin-left: 4px;
    font-size: 10px;
  }

  .sort-button:hover {
    background-color: ${mocha.surface1};
    color: ${mocha.text};
  }

  .sort-button.active {
    background-color: ${mocha.blue};
    color: ${mocha.base};
    border-color: ${mocha.blue};
  }

  .filter-category-group {
    background-color: ${mocha.base};
    border-radius: 4px;
    padding: 6px;
    margin-bottom: 6px;
    border: 1px solid ${mocha.surface0};
  }

  .filter-category-title {
    font-size: 10px;
    font-weight: 600;
    color: ${mocha.teal};
    margin-bottom: 4px;
    padding: 2px 0;
    border-bottom: 1px solid ${mocha.surface0};
  }

  .filter-checkboxes {
    padding: 2px 0;
  }

  .filter-checkbox-item {
    padding: 2px 6px;
    margin-right: 8px;
    border-radius: 3px;
    background-color: transparent;
  }

  .filter-checkbox-item:hover {
    background-color: ${mocha.surface0};
  }

  .filter-checkbox-icon {
    font-size: 12px;
    color: ${mocha.blue};
    margin-right: 3px;
  }

  .filter-checkbox-label {
    font-size: 9px;
    color: ${mocha.text};
    font-family: monospace;
  }

  .i3pm-events-category {
    border-color: ${mocha.peach};
    background-color: rgba(250, 179, 135, 0.05);
  }

  .i3pm-title {
    color: ${mocha.peach};
  }

  .filter-subcategory {
    padding-left: 8px;
    margin-top: 4px;
    border-left: 2px solid ${mocha.surface1};
  }

  .filter-subcategory-title {
    font-size: 9px;
    font-weight: 500;
    color: ${mocha.subtext0};
    margin-bottom: 2px;
    margin-top: 4px;
  }

  .traces-summary {
    padding: 8px 12px;
    background-color: ${mocha.surface0};
    border-radius: 6px;
    margin-bottom: 8px;
  }

  .traces-count {
    font-size: 12px;
    font-weight: 600;
    color: ${mocha.teal};
  }

  .traces-help {
    font-size: 12px;
    color: ${mocha.subtext0};
  }

  .template-selector-container {
    margin-right: 8px;
  }

  .template-add-button {
    background-color: ${mocha.surface0};
    color: ${mocha.text};
    border: 1px solid ${mocha.overlay0};
    border-radius: 4px;
    padding: 4px 10px;
    font-size: 11px;
    font-weight: 500;
  }

  .template-add-button:hover {
    background-color: ${mocha.surface1};
    border-color: ${mocha.blue};
  }

  .template-add-button.active {
    background-color: ${mocha.blue};
    color: ${mocha.base};
    border-color: ${mocha.blue};
  }

  .template-dropdown {
    margin-top: 4px;
    background-color: ${mocha.surface0};
    border: 1px solid ${mocha.overlay0};
    border-radius: 6px;
    padding: 4px;
    min-width: 180px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
  }

  .template-item {
    padding: 8px 10px;
    border-radius: 4px;
    margin: 2px 0;
  }

  .template-item:hover {
    background-color: ${mocha.surface1};
  }

  .template-icon {
    font-size: 18px;
    color: ${mocha.teal};
    margin-right: 10px;
    min-width: 24px;
  }

  .template-name {
    font-size: 12px;
    font-weight: 600;
    color: ${mocha.text};
    margin-bottom: 2px;
  }

  .template-description {
    font-size: 10px;
    color: ${mocha.subtext0};
  }

  .traces-empty {
    padding: 40px 20px;
  }

  .traces-empty .empty-icon {
    font-size: 48px;
    color: ${mocha.overlay0};
    margin-bottom: 12px;
  }

  .traces-empty .empty-title {
    font-size: 14px;
    font-weight: 600;
    color: ${mocha.subtext0};
    margin-bottom: 8px;
  }

  .traces-empty .empty-hint {
    font-size: 11px;
    color: ${mocha.subtext0};
    margin-bottom: 4px;
  }

  .traces-empty .empty-command {
    font-size: 11px;
    color: ${mocha.peach};
    font-family: monospace;
    background-color: ${mocha.surface0};
    padding: 4px 8px;
    border-radius: 4px;
  }

  .traces-list {
    padding: 0 4px;
  }

  .trace-card {
    background-color: ${mocha.surface0};
    border-radius: 6px;
    padding: 10px 12px;
    margin-bottom: 6px;
    border-left: 3px solid ${mocha.overlay0};
  }

  .trace-card:hover {
    background-color: ${mocha.surface1};
  }

  .trace-card.trace-active {
    border-left-color: ${mocha.red};
    background-color: rgba(243, 139, 168, 0.1);
  }

  .trace-card.trace-stopped {
    border-left-color: ${mocha.overlay0};
    opacity: 0.8;
  }

  .trace-status-icon {
    font-size: 18px;
    margin-right: 10px;
    min-width: 24px;
  }

  .trace-header {
    margin-bottom: 4px;
  }

  .trace-id {
    font-size: 11px;
    font-family: monospace;
    color: ${mocha.blue};
    font-weight: 600;
  }

  .trace-status-label {
    font-size: 9px;
    font-weight: 700;
    padding: 2px 6px;
    border-radius: 3px;
    background-color: ${mocha.surface1};
    color: ${mocha.text};
  }

  .trace-active .trace-status-label {
    background-color: ${mocha.red};
    color: ${mocha.base};
  }

  .trace-stopped .trace-status-label {
    background-color: ${mocha.surface1};
    color: ${mocha.subtext0};
  }

  .trace-matcher {
    font-size: 10px;
    color: ${mocha.subtext0};
    font-family: monospace;
    margin-bottom: 4px;
  }

  .trace-stats {
    font-size: 10px;
    color: ${mocha.subtext0};
  }

  .trace-events {
    color: ${mocha.green};
  }

  .trace-separator {
    color: ${mocha.overlay0};
  }

  .trace-duration {
    color: ${mocha.yellow};
  }

  .trace-window-id {
    color: ${mocha.mauve};
    font-family: monospace;
  }

  .trace-actions {
    margin-left: 10px;
  }

  .trace-action-btn {
    background-color: ${mocha.surface1};
    color: ${mocha.text};
    border: 1px solid ${mocha.overlay0};
    border-radius: 4px;
    padding: 4px 8px;
    font-size: 12px;
    margin-bottom: 4px;
    min-width: 28px;
  }

  .trace-action-btn:hover {
    background-color: ${mocha.surface1};
    border-color: ${mocha.blue};
  }

  .trace-stop-btn:hover {
    background-color: ${mocha.red};
    border-color: ${mocha.red};
    color: ${mocha.base};
  }

  .trace-copy-btn {
    font-size: 14px;
    padding: 4px 8px;
    background-color: rgba(137, 180, 250, 0.2);
    color: ${mocha.blue};
    border: 1px solid ${mocha.blue};
    border-radius: 4px;
    min-width: 28px;
    margin-right: 4px;
  }

  .trace-copy-btn:hover {
    background-color: rgba(137, 180, 250, 0.3);
    box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
  }

  .trace-copy-btn:active {
    background-color: rgba(137, 180, 250, 0.5);
    box-shadow: 0 0 12px rgba(137, 180, 250, 0.6);
  }

  .trace-copy-btn.copied {
    background-color: rgba(166, 227, 161, 0.3);
    color: ${mocha.green};
    border: 1px solid ${mocha.green};
    box-shadow: 0 0 12px rgba(166, 227, 161, 0.5),
                inset 0 0 8px rgba(166, 227, 161, 0.2);
    font-weight: bold;
  }

  .trace-copy-btn.copied:hover {
    background-color: rgba(166, 227, 161, 0.4);
    box-shadow: 0 0 16px rgba(166, 227, 161, 0.6);
  }

  .trace-card.trace-expanded {
    border-left-color: ${mocha.lavender};
    background-color: rgba(180, 190, 254, 0.1);
  }

  .trace-card-header {
    padding: 4px 0;
  }

  .trace-expand-icon {
    font-size: 12px;
    color: ${mocha.overlay0};
    margin-right: 6px;
    min-width: 16px;
  }

  .trace-expanded .trace-expand-icon {
    color: ${mocha.lavender};
  }

  .trace-card.trace-highlight {
    border: 2px solid ${mocha.mauve};
    background-color: rgba(203, 166, 247, 0.15);
  }

  .trace-events-panel {
    margin-top: 8px;
    padding-top: 8px;
    border-top: 1px solid ${mocha.surface1};
  }

  .trace-events-loading {
    padding: 12px;
    color: ${mocha.subtext0};
    font-size: 11px;
    font-style: italic;
  }

  .trace-events-list {
    padding: 0;
  }

  .trace-event-row {
    padding: 6px 8px;
    margin-bottom: 2px;
    background-color: ${mocha.base};
    border-radius: 4px;
    border-left: 2px solid ${mocha.overlay0};
  }

  .trace-event-row:hover {
    background-color: ${mocha.surface0};
  }

  .trace-event-row.trace\:\:start {
    border-left-color: ${mocha.green};
  }

  .trace-event-row.trace\:\:stop {
    border-left-color: ${mocha.red};
  }

  .trace-event-row.window\:\:new {
    border-left-color: ${mocha.blue};
  }

  .trace-event-row.window\:\:focus {
    border-left-color: ${mocha.yellow};
  }

  .trace-event-row.window\:\:move {
    border-left-color: ${mocha.peach};
  }

  .trace-event-row.mark\:\:added {
    border-left-color: ${mocha.mauve};
  }

  .event-time {
    font-family: monospace;
    font-size: 10px;
    color: ${mocha.subtext0};
    min-width: 60px;
    margin-right: 8px;
  }

  .event-type-badge {
    font-size: 9px;
    font-weight: 600;
    padding: 2px 6px;
    border-radius: 3px;
    background-color: ${mocha.surface1};
    color: ${mocha.text};
    margin-right: 8px;
    min-width: 80px;
  }

  .event-type-badge.trace\:\:start {
    background-color: rgba(166, 227, 161, 0.2);
    color: ${mocha.green};
  }

  .event-type-badge.trace\:\:stop {
    background-color: rgba(243, 139, 168, 0.2);
    color: ${mocha.red};
  }

  .event-type-badge.window\:\:new {
    background-color: rgba(137, 180, 250, 0.2);
    color: ${mocha.blue};
  }

  .event-type-badge.window\:\:focus {
    background-color: rgba(249, 226, 175, 0.2);
    color: ${mocha.yellow};
  }

  .event-type-badge.window\:\:move {
    background-color: rgba(250, 179, 135, 0.2);
    color: ${mocha.peach};
  }

  .event-type-badge.mark\:\:added {
    background-color: rgba(203, 166, 247, 0.2);
    color: ${mocha.mauve};
  }

  .event-content {
    padding-left: 4px;
  }

  .event-description {
    font-size: 10px;
    color: ${mocha.text};
  }

  .event-changes {
    font-size: 9px;
    color: ${mocha.subtext0};
    font-family: monospace;
    margin-top: 2px;
  }

  .devices-content {
    padding: 10px;
  }

  .devices-section {
    background-color: ${mocha.surface0};
    border-radius: 8px;
    padding: 10px 12px;
    margin-bottom: 8px;
    border: 1px solid ${mocha.surface1};

    .section-title {
      font-size: 11px;
      font-weight: 600;
      color: ${mocha.blue};
      margin-bottom: 8px;
      padding-bottom: 6px;
      border-bottom: 1px solid ${mocha.surface1};
      letter-spacing: 0.5px;
    }

    .section-content {
      padding: 2px 0;
    }
  }

  .device-row {
    padding: 4px 6px;
    background-color: ${mocha.mantle};
    border-radius: 6px;
    margin-bottom: 6px;

    .device-label {
      font-size: 10px;
      color: ${mocha.subtext0};
      min-width: 45px;
    }

    .device-value {
      font-size: 10px;
      color: ${mocha.text};
    }
  }

  .slider-row {
    padding: 4px 2px;

    .slider-icon {
      font-size: 14px;
      color: ${mocha.blue};
      min-width: 20px;
    }

    .device-slider {
      min-width: 100px;
      margin: 0 6px;

      trough {
        background-color: ${mocha.surface1};
        border-radius: 3px;
        min-height: 4px;
      }

      highlight {
        background-color: ${mocha.blue};
        border-radius: 3px;
      }

      slider {
        background-color: ${mocha.text};
        border-radius: 50%;
        min-width: 10px;
        min-height: 10px;
        margin: -3px;
      }
    }

    .slider-value {
      font-size: 10px;
      font-weight: 600;
      color: ${mocha.text};
      min-width: 28px;
      margin-right: 4px;
    }

    .mute-btn {
      font-size: 12px;
      color: ${mocha.subtext0};
      padding: 3px 6px;
      border-radius: 4px;
      background-color: ${mocha.surface1};

      &:hover {
        background-color: ${mocha.overlay0};
        color: ${mocha.text};
      }

      &.muted {
        color: ${mocha.red};
        background-color: shade(${mocha.red}, 0.3);
      }
    }
  }

  .toggle-row {
    padding: 4px 2px;

    .toggle-icon {
      font-size: 14px;
      color: ${mocha.blue};
      min-width: 20px;
    }

    .toggle-label {
      font-size: 11px;
      font-weight: 500;
      color: ${mocha.text};
    }

    .toggle-btn {
      min-width: 32px;
      min-height: 20px;
      border-radius: 10px;
      border: none;
      padding: 2px 8px;

      label {
        font-size: 11px;
      }

      &.on {
        background-color: ${mocha.green};
        color: ${mocha.base};
      }

      &.off {
        background-color: ${mocha.surface1};
        color: ${mocha.overlay0};
      }

      &:hover {
        opacity: 0.9;
      }
    }
  }

  .device-list {
    padding-top: 4px;
    margin-top: 2px;

    .device-item {
      background-color: ${mocha.mantle};
      border-radius: 5px;
      padding: 6px 8px;
      margin-bottom: 4px;

      &.connected {
        border-left: 2px solid ${mocha.green};
        background-color: shade(${mocha.green}, 0.2);
      }

      .device-icon {
        font-size: 12px;
        color: ${mocha.subtext0};
        min-width: 18px;
      }

      .device-name {
        font-size: 10px;
        color: ${mocha.text};
      }

      .connect-btn {
        font-size: 9px;
        font-weight: 500;
        color: ${mocha.blue};
        padding: 3px 6px;
        background-color: ${mocha.surface1};
        border-radius: 4px;

        &:hover {
          background-color: ${mocha.blue};
          color: ${mocha.base};
        }
      }
    }
  }

  .battery-row {
    padding: 6px;
    background-color: ${mocha.mantle};
    border-radius: 6px;
    margin-bottom: 6px;

    .battery-icon {
      font-size: 18px;
      color: ${mocha.green};
      min-width: 26px;

      &.low {
        color: ${mocha.yellow};
      }

      &.critical {
        color: ${mocha.red};
      }

      &.charging {
        color: ${mocha.teal};
      }
    }

    .battery-info {
      .battery-percent {
        font-size: 14px;
        font-weight: 600;
        color: ${mocha.text};
      }

      .battery-state {
        font-size: 10px;
        color: ${mocha.subtext0};
      }

      .battery-time {
        font-size: 9px;
        color: ${mocha.subtext0};
        margin-top: 2px;
      }
    }
  }

  .battery-details {
    padding: 6px;
    background-color: ${mocha.mantle};
    border-radius: 6px;
    margin-bottom: 6px;

    .detail-item {
      .detail-label {
        font-size: 9px;
        color: ${mocha.subtext0};
      }

      .detail-value {
        font-size: 11px;
        font-weight: 600;
        color: ${mocha.text};
      }
    }
  }

  .power-profiles {
    padding: 4px;
    background-color: ${mocha.mantle};
    border-radius: 6px;

    .profile-btn {
      padding: 6px 12px;
      border-radius: 5px;
      border: none;
      background-image: none;

      label {
        font-size: 14px;
      }
    }

    .profile-btn.profile-saver {
      background-color: ${mocha.surface0};
      background-image: none;

      label {
        color: ${mocha.green};
      }
    }

    .profile-btn.profile-saver:hover {
      background-color: ${mocha.surface1};
      background-image: none;
    }

    .profile-btn.profile-saver.active {
      background-color: ${mocha.green};
      background-image: none;

      label {
        color: ${mocha.base};
      }
    }

    .profile-btn.profile-balanced {
      background-color: ${mocha.surface0};
      background-image: none;

      label {
        color: ${mocha.blue};
      }
    }

    .profile-btn.profile-balanced:hover {
      background-color: ${mocha.surface1};
      background-image: none;
    }

    .profile-btn.profile-balanced.active {
      background-color: ${mocha.blue};
      background-image: none;

      label {
        color: ${mocha.base};
      }
    }

    .profile-btn.profile-performance {
      background-color: ${mocha.surface0};
      background-image: none;

      label {
        color: ${mocha.peach};
      }
    }

    .profile-btn.profile-performance:hover {
      background-color: ${mocha.surface1};
      background-image: none;
    }

    .profile-btn.profile-performance.active {
      background-color: ${mocha.peach};
      background-image: none;

      label {
        color: ${mocha.base};
      }
    }
  }

  .slider-label {
    font-size: 10px;
    color: ${mocha.subtext0};
    min-width: 50px;
  }

  .thermal-row {
    padding: 6px;
    background-color: ${mocha.mantle};
    border-radius: 6px;
    margin-bottom: 6px;

    .thermal-icon {
      font-size: 16px;
      color: ${mocha.peach};
      min-width: 22px;
    }

    .thermal-info {
      min-width: 50px;
      margin-right: 8px;

      .thermal-label {
        font-size: 9px;
        color: ${mocha.subtext0};
      }

      .thermal-value {
        font-size: 12px;
        font-weight: 600;
        color: ${mocha.text};
      }
    }

    .thermal-bar {
      min-height: 6px;
      border-radius: 3px;

      trough {
        background-color: ${mocha.surface1};
        border-radius: 3px;
        min-height: 6px;
      }

      progress {
        background-color: ${mocha.peach};
        border-radius: 3px;
      }
    }
  }

  .fan-row {
    padding: 6px;
    background-color: ${mocha.mantle};
    border-radius: 6px;

    .fan-icon {
      font-size: 14px;
      color: ${mocha.sapphire};
      min-width: 22px;
    }

    .fan-label {
      font-size: 10px;
      color: ${mocha.subtext0};
      min-width: 30px;
    }

    .fan-value {
      font-size: 11px;
      font-weight: 500;
      color: ${mocha.text};
    }
  }

  .network-row {
    padding: 6px;
    background-color: ${mocha.mantle};
    border-radius: 6px;
    margin-bottom: 6px;

    .network-icon {
      font-size: 16px;
      min-width: 22px;

      &.connected {
        color: ${mocha.green};
      }

      &.disconnected {
        color: ${mocha.overlay0};
      }
    }

    .network-info {
      .network-type {
        font-size: 9px;
        color: ${mocha.subtext0};
      }

      .network-value {
        font-size: 11px;
        font-weight: 500;
        color: ${mocha.text};
      }
    }
  }
''

{ mocha, ... }:

''
  /* Feature 057: Unified theme colors from unified-bar-theme.nix */
  /* Catppuccin Mocha color palette */
  $base: ${mocha.base};
  $mantle: ${mocha.mantle};
  $surface0: ${mocha.surface0};
  $surface1: ${mocha.surface1};
  $overlay0: ${mocha.overlay0};
  $text: ${mocha.text};
  $subtext0: ${mocha.subtext0};
  $mauve: ${mocha.mauve};
  $blue: ${mocha.blue};
  $teal: ${mocha.teal};
  $red: ${mocha.red};
  $yellow: ${mocha.yellow};
  $green: ${mocha.green};

  * {
    font-family: sans-serif;
    font-size: 11pt;
    color: $text;
    background-color: transparent;
  }

  window {
    background-color: transparent;
  }

  .workspace-bar {
    background: rgba(30, 30, 46, 0.85);
    padding: 4px 8px;
    margin: 6px;
    border-radius: 6px;
    border: 1px solid rgba(203, 166, 247, 0.25);
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.4);
  }

  .workspace-output {
    font-size: 8pt;
    color: $subtext0;
    margin-right: 8px;
    opacity: 0.5;
  }

  .workspace-strip {
    margin-left: 0px;
  }

  .workspace-button {
    background: rgba(30, 30, 46, 0.3);
    padding: 3px 6px;
    border-radius: 4px;
    border: 1px solid rgba(108, 112, 134, 0.3);
    box-shadow: none;
    min-width: 0;
    transition: all 0.2s;
  }

  button {
    box-shadow: none;
    background-image: none;
    outline: none;
  }

  .workspace-button:hover {
    background: rgba(137, 180, 250, 0.15);
    border: 1px solid rgba(137, 180, 250, 0.4);
  }

  .workspace-button.focused {
    background: rgba(137, 180, 250, 0.3);
    border: 1px solid rgba(137, 180, 250, 0.6);
  }

  .workspace-button.visible:not(.focused) {
    background: rgba(137, 180, 250, 0.12);
    border: 1px solid rgba(137, 180, 250, 0.35);
  }

  .workspace-button.urgent {
    background: rgba(243, 139, 168, 0.25);
    border: 1px solid rgba(243, 139, 168, 0.5);
  }

  .workspace-button.empty {
    opacity: 0.3;
  }

  .workspace-button.empty:hover {
    opacity: 0.6;
  }

  .workspace-button.pending {
    background: rgba(249, 226, 175, 0.25);
    border: 1px solid rgba(249, 226, 175, 0.7);
    transition: all 0.2s;
  }

  .workspace-button.pending .workspace-icon-image {
    -gtk-icon-shadow: 0 0 8px rgba(249, 226, 175, 0.8);
  }

  .workspace-button.pending .workspace-number {
    color: $yellow;
    font-weight: 600;
  }

  .workspace-button.pending.focused {
    background: rgba(249, 226, 175, 0.25);
    border: 1px solid rgba(249, 226, 175, 0.7);
  }

  .workspace-button.pending.focused .workspace-icon-image {
    -gtk-icon-shadow: 0 0 8px rgba(249, 226, 175, 0.8);
  }

  .workspace-button.pending.focused .workspace-number {
    color: $yellow;
    font-weight: 600;
  }

  .workspace-pill {
    margin: 0;
    padding: 0;
  }

  .workspace-icon-image {
    opacity: 1.0;
    min-width: 16px;
    min-height: 16px;
  }

  .workspace-button.focused .workspace-icon-image {
    -gtk-icon-shadow: 0 0 8px rgba(137, 180, 250, 0.8);
  }

  .workspace-button.urgent .workspace-icon-image {
    -gtk-icon-shadow: 0 0 6px rgba(243, 139, 168, 0.5);
  }

  .workspace-button.no-icon .workspace-icon-image {
    opacity: 0;
  }

  .workspace-number {
    font-size: 9pt;
    font-weight: 500;
    color: $subtext0;
    min-width: 12px;
  }

  .workspace-button.focused .workspace-number {
    color: $blue;
    font-weight: 600;
  }

  .workspace-button.urgent .workspace-number {
    color: $red;
    font-weight: 600;
  }

  .workspace-button.empty .workspace-number {
    color: $overlay0;
  }

  .preview-wrapper {
    min-width: 600px;
    min-height: 800px;
  }

  .preview-card {
    background: rgba(30, 30, 46, 0.95);
    padding: 16px;
    border-radius: 8px;
    border: 2px solid rgba(203, 166, 247, 0.4);
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
    min-width: 400px;
    min-height: 150px;
  }

  .preview-header {
    margin-bottom: 12px;
    padding-bottom: 12px;
    border-bottom: 1px solid rgba(108, 112, 134, 0.3);
  }

  .preview-mode-digits {
    font-size: 28pt;
    font-weight: 700;
    color: $yellow;
    margin-bottom: 4px;
    letter-spacing: 0.5px;
    text-shadow: 0 0 12px rgba(249, 226, 175, 0.4);
  }

  .preview-subtitle {
    font-size: 10pt;
    font-weight: 400;
    color: $subtext0;
    opacity: 0.8;
  }

  .preview-body {
    padding: 20px 0;
  }

  .preview-empty {
    font-size: 10pt;
    color: $subtext0;
    font-style: italic;
  }

  .preview-apps {
    padding: 4px 0;
    min-height: 50px;
  }

  .preview-app {
    padding: 6px 8px;
    border-radius: 4px;
    background: rgba(49, 50, 68, 0.4);
    transition: all 0.2s;
  }

  .preview-app:hover {
    background: rgba(49, 50, 68, 0.6);
  }

  .preview-app.focused {
    background: rgba(137, 180, 250, 0.25);
    border: 1px solid rgba(137, 180, 250, 0.5);
  }

  .preview-app.selected {
    background: rgba(137, 180, 250, 0.2);
    border-left: 3px solid rgba(137, 180, 250, 0.8);
    transition: background 0.2s ease-in-out, border 0.2s ease-in-out;
  }

  .workspace-group-header.selected {
    background: rgba(137, 180, 250, 0.2);
    border-left: 3px solid rgba(137, 180, 250, 0.8);
    transition: background 0.2s ease-in-out, border 0.2s ease-in-out;
  }

  .preview-app.selected-move-mode {
    background: rgba(250, 179, 135, 0.2);
    border-left: 3px solid rgba(250, 179, 135, 0.8);
  }

  .workspace-group-header.selected-move-mode {
    background: rgba(250, 179, 135, 0.2);
    border-left: 3px solid rgba(250, 179, 135, 0.8);
  }

  .preview-app.selected .preview-app-name,
  .workspace-group-header.selected {
    color: #cdd6f4;
  }

  .project-item {
    padding: 10px 12px;
    border-radius: 8px;
    background: rgba(49, 50, 68, 0.6);
    border: 2px solid transparent;
    transition: all 0.15s ease-in-out;
  }

  .project-item:hover {
    background: rgba(69, 71, 90, 0.8);
  }

  .project-item.selected {
    background: rgba(166, 227, 161, 0.25);
    border: 2px solid rgba(166, 227, 161, 0.9);
    box-shadow: 0 0 12px rgba(166, 227, 161, 0.3), inset 0 0 8px rgba(166, 227, 161, 0.1);
    border-left: 6px solid rgba(166, 227, 161, 1);
  }

  .project-item.indent-1 {
    margin-left: 24px;
    border-left: 3px solid rgba(250, 179, 135, 0.5);
  }

  .project-item.indent-1.selected {
    border-left: 6px solid rgba(166, 227, 161, 1);
  }

  .project-icon {
    font-size: 16pt;
    min-width: 28px;
  }

  .project-name {
    font-size: 12pt;
    font-weight: 500;
    color: #cdd6f4;
  }

  .project-item.selected .project-name {
    color: rgba(166, 227, 161, 1);
    font-weight: 700;
    text-shadow: 0 0 8px rgba(166, 227, 161, 0.4);
  }

  .project-time {
    font-size: 9pt;
    color: #a6adc8;
  }

  .project-badge {
    font-size: 8pt;
    padding: 2px 6px;
    border-radius: 4px;
    background: rgba(108, 112, 134, 0.3);
    color: #bac2de;
  }

  .project-badge-worktree {
    font-size: 8pt;
    padding: 2px 6px;
    border-radius: 4px;
    background: rgba(137, 180, 250, 0.2);
    color: rgba(137, 180, 250, 0.9);
  }

  .project-badge-root {
    font-size: 8pt;
    padding: 2px 6px;
    border-radius: 4px;
    background: rgba(148, 226, 213, 0.2);
    color: rgba(148, 226, 213, 0.9);
  }

  .project-parent {
    font-size: 9pt;
    color: #7f849c;
    font-style: italic;
  }

  .project-git-clean {
    color: rgba(166, 227, 161, 0.9);
    font-size: 9pt;
  }

  .project-git-dirty {
    color: rgba(243, 139, 168, 0.9);
    font-size: 9pt;
  }

  .project-git-ahead {
    color: rgba(250, 179, 135, 0.9);
    font-size: 9pt;
  }

  .project-git-behind {
    color: rgba(245, 194, 231, 0.9);
    font-size: 9pt;
  }

  .project-warning {
    color: rgba(249, 226, 175, 0.9);
    font-size: 9pt;
    font-weight: bold;
  }

  .project-list-scroll {
    margin: 8px 0;
  }

  .project-item-metadata {
    margin-top: 4px;
    margin-left: 36px;
  }

  .preview-app-icon {
    min-width: 24px;
    min-height: 24px;
    opacity: 0.9;
  }

  .preview-app.focused .preview-app-icon {
    opacity: 1.0;
    -gtk-icon-shadow: 0 0 8px rgba(137, 180, 250, 0.6);
  }

  .preview-app-name {
    font-size: 10pt;
    color: $text;
  }

  .preview-app.focused .preview-app-name {
    color: $blue;
    font-weight: 500;
  }

  .preview-footer {
    margin-top: 12px;
    padding-top: 8px;
    border-top: 1px solid rgba(108, 112, 134, 0.3);
  }

  .preview-count {
    font-size: 9pt;
    color: $subtext0;
  }

  .keyboard-hints-footer {
    margin-top: 8px;
    padding-top: 8px;
    border-top: 1px solid rgba(108, 112, 134, 0.3);
  }

  .keyboard-hints {
    font-size: 9pt;
    color: $subtext0;
    font-family: monospace;
    opacity: 0.9;
  }
''

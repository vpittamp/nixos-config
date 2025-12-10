{ config, pkgs, lib, ... }:

let
  i3pmProjectBadgeScript = "/etc/nixos/scripts/i3pm-project-badge.sh";
in
{
  # Tmux configuration - force rebuild 2025-09-19
  programs.tmux = {
    enable = true;
    shell = "${pkgs.bash}/bin/bash";
    terminal = "tmux-256color";
    prefix = "`";
    baseIndex = 0;
    historyLimit = 10000;
    keyMode = "vi";
    mouse = true;
    aggressiveResize = true;  # Enable for better dynamic resizing with window-size latest

    plugins = with pkgs.tmuxPlugins; [
      # Removed sensible plugin as it overrides aggressive-resize setting
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-capture-pane-contents 'on'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
      pain-control
      prefix-highlight
      tmux-fzf
    ];

    extraConfig = ''
      # General settings
      set -g default-command "${pkgs.bash}/bin/bash"
      set -g default-terminal "tmux-256color"
      set -ga terminal-overrides ",xterm-256color:Tc"
      set -ga terminal-overrides ",screen-256color:Tc"
      set -ga terminal-overrides ",tmux-256color:Tc"
      set -sg escape-time 0
      set -g focus-events on
      set -g detach-on-destroy off
      set -g repeat-time 1000
      set -g set-clipboard on

      # Handle different terminal emulators properly
      # Use 'latest' window-size to track most recent active client
      # This fixes the issue where tmux limits to smallest client (VSCode)
      set -g window-size latest

      # Text wrapping settings
      setw -g wrap-search on
      setw -g automatic-rename on

      # Force UTF-8 (fixes wrapping with special characters)
      set -q -g utf8 on
      setw -q -g utf8 on

      # Force refresh on attach
      set-hook -g client-attached 'run-shell "tmux refresh-client -S"'

      # Bind key for manual window resize when needed
      bind R run-shell "tmux resize-window -A"

      # Terminal-specific overrides for proper rendering
      # Konsole-specific settings
      set -ga terminal-overrides ',konsole*:Tc'
      set -ga terminal-overrides ',konsole*:Ms@'

      # VSCode terminal settings - disable OSC queries that cause escape sequences
      set -ga terminal-overrides ',vscode*:Tc'
      set -ga terminal-overrides ',vscode*:Ms@:XT@'

      # General xterm settings
      set -ga terminal-overrides ',xterm*:Tc'
      set -ga terminal-overrides ',xterm-256color:Tc'

      # Ghostty terminal settings - modern terminal with excellent feature support
      set -ga terminal-overrides ',ghostty*:Tc'
      set -ga terminal-overrides ',ghostty*:RGB'

      # Allow passthrough for proper color handling, but disable for VSCode
      if-shell '[ -z "$VSCODE_TERMINAL" ]' \
        'set -g allow-passthrough on' \
        'set -g allow-passthrough off'

      # Handle Konsole-specific environment
      if-shell '[ -n "$KONSOLE_VERSION" ]' \
        'set -g window-size latest'

      # Basic terminal features
      set -as terminal-features ",*:RGB"

      # Cursor settings - enable blinking cursor for active pane visibility
      # Ss/Se enables cursor shape changes, blinking cursor makes active pane obvious
      set -ga terminal-overrides ',*:Ss=\E[%p1%d q:Se=\E[2 q'
      set -ga terminal-overrides ',*:Cs=\E]12;%p1%s\007:Cr=\E]112\007'

      # Pane settings
      set -g pane-base-index 0
      set -g renumber-windows on
      set -g pane-border-lines heavy  # Thicker lines create more spacing
      set -g pane-border-status top  # Add padding line at top of each pane
      set -g pane-border-format " "  # Empty padding space (invisible content)

      # Catppuccin Mocha theme - completely invisible borders with padding
      # Both active and inactive borders match their respective backgrounds
      # The border-status line adds padding around panes
      set -g pane-border-style "fg=#313244,bg=#313244"  # Match inactive pane background with bg for padding
      set -g pane-active-border-style "fg=#11111b,bg=#11111b"  # Match active pane background with bg for padding

      # Visual distinction between active and inactive panes
      # Active pane: DARKEST background with BRIGHTEST text (focus here!)
      # Inactive panes: LIGHTER greyish background with MUTED text (recedes into background)
      # The background contrast provides ALL the separation - no borders or arrows needed
      set -g window-active-style "fg=#cdd6f4,bg=#11111b"  # Bright white text on darkest Crust
      set -g window-style "fg=#6c7086,bg=#313244"  # Very muted text on lighter Surface0 (greyish)

      # Pane indicators - completely disabled, rely on contrast only
      set -g pane-border-indicators off  # No arrows or indicators
      set -g display-panes-colour "#6c7086"  # Muted gray for inactive pane numbers
      set -g display-panes-active-colour "#89b4fa"  # Bright blue for active pane number
      set -g display-panes-time 3000  # Show pane numbers for 3 seconds (increased visibility)

      # Status bar styling - Catppuccin Mocha theme
      set -g status-position top
      set -g status-justify left
      set -g status-style "bg=#11111b fg=#a6adc8"  # Catppuccin Crust bg, Subtext0 fg
      set -g status-left-length 40
      set -g status-right-length 60

      # Status left with Catppuccin colors - COPY in blue, PREFIX in red, ZOOM icon in yellow, normal in green
      set -g status-left "#{?pane_in_mode,#[fg=#11111b bg=#89b4fa bold] COPY ,#{?client_prefix,#[fg=#11111b bg=#f38ba8 bold] PREFIX ,#[fg=#11111b bg=#a6e3a1 bold] TMUX }}#{?window_zoomed_flag,#[fg=#11111b bg=#f9e2af bold] 🔍 ,}#[fg=#cdd6f4 bg=#313244] #S #[default] "

      # Status right - Catppuccin colors
      set -g status-right "#[fg=#cdd6f4 bg=#313244] #( ${i3pmProjectBadgeScript} --tmux ) #H | %H:%M #[default]"

      # Window status - inactive in muted colors, active in blue
      set -g window-status-format "#[fg=#a6adc8] #I:#W "
      set -g window-status-current-format "#[fg=#11111b bg=#89b4fa bold] #I:#W #[default]"  # Catppuccin Blue
      set -g window-status-separator ""

      # Message styling - Catppuccin Yellow for warnings/messages
      set -g message-style "fg=#11111b bg=#f9e2af bold"

      # Key bindings
      # Reload config (prefix + r) with native Wayland notification (transient, auto-dismisses)
      bind r source-file ~/.config/tmux/tmux.conf \; run-shell "notify-send -u low -t 2000 -h string:x-dunst-stack-tag:tmux 'Tmux' 'Configuration reloaded'" \; display-message "Config reloaded!"

      # Window and pane management
      bind c new-window -c "#{pane_current_path}"
      bind v split-window -v -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind h split-window -h -c "#{pane_current_path}"
      # Using backslash for horizontal split
      bind BSpace split-window -h -c "#{pane_current_path}"
      # Zoom: use default backtick + z (resize-pane -Z)
      bind x kill-pane
      bind X kill-window

      # Pane navigation (without prefix)
      bind -n C-h select-pane -L
      bind -n C-j select-pane -D
      bind -n C-k select-pane -U
      bind -n C-l select-pane -R

      # Pane resizing
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      # Quick window switching
      bind -n M-0 select-window -t 0
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4

      # Copy mode with KDE clipboard integration
      # Use prefix+[ for copy mode (default tmux behavior)
      # 'Enter' key remains default (execute command in normal mode, copy in copy mode)
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle

      # 'y' key copies to KDE clipboard and stays in copy mode (for multiple selections)
      bind -T copy-mode-vi y send-keys -X copy-pipe "/etc/nixos/scripts/clipboard-sync.sh"

      # 'Y' copies to clipboard and exits copy mode
      bind -T copy-mode-vi Y send-keys -X copy-pipe-and-cancel "/etc/nixos/scripts/clipboard-sync.sh"

      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi H send-keys -X start-of-line
      bind -T copy-mode-vi L send-keys -X end-of-line

      # Paste
      bind p paste-buffer
      bind B choose-buffer  # Changed from P to B to avoid conflict with popup

      # Paste from system clipboard (KDE Plasma clipboard)
      # Use Ctrl+Shift+V or prefix + V to paste from system clipboard
      bind V run-shell "/etc/nixos/scripts/clipboard-paste.sh | tmux load-buffer - && tmux paste-buffer"
      bind ] run-shell "/etc/nixos/scripts/clipboard-paste.sh | tmux load-buffer - && tmux paste-buffer"

      # Toggles
      bind S run-shell "tmux setw synchronize-panes && tmux display-message 'Synchronize panes: #{?pane_synchronized,ON,OFF}'"
      bind m run-shell "tmux set -g mouse && tmux display-message 'Mouse: #{?mouse,ON,OFF}'"

      # Keybinding cheatsheet (F1 or prefix + ?)
      bind -n F1 run-shell "/etc/nixos/scripts/keybindings-cheatsheet.sh"
      bind ? run-shell "/etc/nixos/scripts/keybindings-cheatsheet.sh"

      # Clipboard history (Meta + v for clipboard history)
      # Restore prefix + v for vertical split
      # Use -b flag to run in background and suppress "ok" message
      bind -n M-v run-shell -b "/etc/nixos/scripts/clipcat-fzf.sh"

      # File path scanner (prefix + u) - extract valid file paths from entire scrollback history
      # Only shows files that exist on filesystem, opens in nvim on workspace 4
      # Uses fzf with multi-select, bat preview, full-screen popup
      # -S - means capture from beginning of scrollback history (not just visible screen)
      bind u run-shell "tmux capture-pane -J -p -S - > /tmp/tmux-buffer-scan.txt && tmux display-popup -E -h 95% -w 95% tmux-url-scan"

      # URL opener (prefix + o) - extract URLs from scrollback and open in browser
      # Complementary to prefix + u (file paths), this extracts http/https URLs
      # Uses fzf for selection, xdg-open to launch in default browser (or PWA via pwa-url-router)
      bind o run-shell "tmux capture-pane -J -p -S - > /tmp/tmux-url-buffer.txt && tmux display-popup -E -h 95% -w 95% tmux-url-open"

      # Mouse scroll sensitivity - reduce scroll speed for precision
      # By default, tmux scrolls too fast (3 lines per wheel event)
      # Reduce to 1 line per event for more precise scrolling
      bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'select-pane -t=; copy-mode -e; send-keys -M'"
      bind -n WheelDownPane select-pane -t= \; send-keys -M

      # In copy mode, scroll 5 lines at a time for faster scrolling
      bind -T copy-mode-vi WheelUpPane send-keys -X -N 5 scroll-up
      bind -T copy-mode-vi WheelDownPane send-keys -X -N 5 scroll-down

      # Mouse behavior with KDE Plasma clipboard integration
      # Right-click paste enabled (use Shift+Right-click for terminal context menu)

      # Enhanced mouse copy that integrates with KDE clipboard
      # Mouse drag exits copy mode after copying (native terminal feel)
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "/etc/nixos/scripts/clipboard-sync.sh"

      # Double-click to select word and copy to clipboard (exits copy mode)
      bind -T copy-mode-vi DoubleClick1Pane \
        select-pane \; \
        send-keys -X select-word \; \
        send-keys -X copy-pipe-and-cancel "/etc/nixos/scripts/clipboard-sync.sh"

      # Triple-click to select line and copy to clipboard (exits copy mode)
      bind -T copy-mode-vi TripleClick1Pane \
        select-pane \; \
        send-keys -X select-line \; \
        send-keys -X copy-pipe-and-cancel "/etc/nixos/scripts/clipboard-sync.sh"

      # Sesh session management
      # Removed 'bind -n C-t' to allow bash's sesh_connect function to handle Ctrl+T
      # This enables the interactive sesh picker to work both inside and outside tmux
      bind l switch-client -l
      # Alternative sesh binding using prefix + T (backtick + T) if needed
      bind-key T new-window sesh

      # Tmux Popup Windows with Enhanced Copy Support
      # Using UPPERCASE to avoid conflicts
      # Tips: Use 'less' for scrollable output, mouse selection works in most popups

      # Terminal popup (backtick + P) - Simple bash shell with proper quoting
      bind-key P display-popup -E -h 70% -w 80% -d "#{pane_current_path}" 'bash --rcfile <(cat ~/.bashrc; echo "PS1=\"[popup] \\w $ \"")'

      # Alternative with script command (backtick + O) - Creates PTY boundary
      bind-key O display-popup -E -h 70% -w 80% -d "#{pane_current_path}" 'script -qc bash /dev/null'

      # Floating pane alternative (backtick + U) - True pane with selection
      bind-key U new-window -n float -c "#{pane_current_path}" bash

      # Git status popup (backtick + G) - Scrollable with less
      bind-key G display-popup -E -h 80% -w 90% 'bash -c "{ echo \"=== GIT STATUS ===\"; git status; echo; echo \"=== RECENT COMMITS ===\"; git log --oneline -20; } | less -R"'

      # File picker popup (backtick + F) - Auto-copies selected path
      bind-key F display-popup -E -h 80% -w 80% 'file=$(find . -type f 2>/dev/null | fzf --preview="head -50 {}"); \
        if [ -n "$file" ]; then \
          printf "%s" "$file" | /etc/nixos/scripts/clipboard-sync.sh; \
          echo "Copied: $file"; \
          sleep 1; \
        fi'

      # Note popup (backtick + N) - nvim has its own copy support
      bind-key N display-popup -E -h 60% -w 70% "nvim ~/notes/quick-$(date +%Y%m%d-%H%M%S).md"

      # System info popup (backtick + I) - Scrollable with less
      bind-key I display-popup -E -h 70% -w 80% 'bash -c "{ echo \"=== SYSTEM INFO ===\"; uname -a; echo; echo \"=== MEMORY ===\"; free -h; echo; echo \"=== DISK USAGE ===\"; df -h | head -10; echo; echo \"=== TOP PROCESSES ===\"; ps aux --sort=-%cpu | head -10; } | less"'

      # Docker status popup (backtick + D) - Table format, scrollable
      bind-key D display-popup -E -h 80% -w 90% 'bash -c "docker ps -a --format \"table {{.Names}}\t{{.Status}}\t{{.Image}}\" 2>/dev/null || echo \"Docker not running\"" | less'

      # Process viewer (backtick + H) - htop has built-in selection
      bind-key H display-popup -E -h 90% -w 90% 'htop || top'

      # Log viewer (backtick + L) - Scrollable, starts at end
      bind-key L display-popup -E -h 80% -w 90% 'journalctl -xe --no-pager | tail -500 | less +G'

      # Quick copy popup (backtick + C) - Show current tmux buffer
      bind-key C display-popup -E -h 60% -w 70% 'echo "=== TMUX BUFFER ==="; tmux show-buffer | less'

      # Clipboard history popup (backtick + Q) - Show clipcat clipboard items
      # Uses clipcat for unified clipboard history across all applications
      bind-key Q display-popup -E -h 70% -w 80% 'bash -c "\
        if command -v clipcatctl &>/dev/null 2>&1; then \
          echo \"=== CLIPBOARD HISTORY (clipcat) ===\"; \
          echo; \
          clipcatctl list | while IFS=: read -r hash content; do \
            echo \"Hash: $hash\"; \
            echo \"$content\" | head -3; \
            echo \"----------------------------------------\"; \
            echo; \
          done; \
        else \
          echo \"Clipcat not available\"; \
          if [ -n \"$WAYLAND_DISPLAY\" ]; then \
            echo \"Current clipboard:\"; wl-paste; \
          else \
            echo \"Current clipboard:\"; xclip -selection clipboard -o; \
          fi; \
        fi" | less'
    '';
  };
}

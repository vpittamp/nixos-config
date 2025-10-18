{ config, pkgs, lib, ... }:

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
      set -g focus-events off
      set -g detach-on-destroy off
      set -g repeat-time 1000

      # Handle different terminal emulators properly
      # Use 'latest' window-size to track most recent active client
      # This fixes the issue where tmux limits to smallest client (VSCode)
      set -g window-size latest

      # Enable aggressive-resize for better window handling
      setw -g aggressive-resize on

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

      # Allow passthrough for proper color handling, but disable for VSCode
      if-shell '[ -z "$VSCODE_TERMINAL" ]' \
        'set -g allow-passthrough on' \
        'set -g allow-passthrough off'

      # Handle Konsole-specific environment
      if-shell '[ -n "$KONSOLE_VERSION" ]' \
        'set -g aggressive-resize on; set -g window-size latest'

      # Basic terminal features
      set -as terminal-features ",*:RGB"

      # Pane settings
      set -g pane-base-index 0
      set -g renumber-windows on
      set -g pane-border-lines single  # Simple lines for cleaner look
      set -g pane-border-status off  # Remove pane status labels for cleaner appearance

      # Subtle pane borders - almost invisible
      set -g pane-border-style "fg=colour234"  # Very dark gray, almost invisible
      set -g pane-active-border-style "fg=colour236"  # Slightly lighter but still subtle

      # Visual distinction between active and inactive panes
      # DISABLED: Custom background colors cause invisible text in some terminals (XRDP/Alacritty)
      # Use terminal's default colors for maximum compatibility
      set -g window-active-style "default"
      set -g window-style "default"

      # Remove pane indicators for cleaner look
      set -g pane-border-indicators off
      set -g display-panes-colour "colour240"  # Subtle pane numbers
      set -g display-panes-active-colour "colour250"  # Slightly brighter for active

      # Status bar styling - simple and functional
      set -g status-position top
      set -g status-justify left
      set -g status-style "bg=colour235 fg=colour248"
      set -g status-left-length 40
      set -g status-right-length 60

      # Simple status left showing session name and mode
      set -g status-left "#{?client_prefix,#[fg=colour235 bg=colour203 bold] PREFIX ,#[fg=colour235 bg=colour40 bold] TMUX }#[fg=colour248 bg=colour237] #S #[default] "

      # Status right showing basic info
      set -g status-right "#[fg=colour248 bg=colour237] #H | %H:%M #[default]"

      # Window status - clean and simple
      set -g window-status-format "#[fg=colour248] #I:#W "
      set -g window-status-current-format "#[fg=colour235 bg=colour39 bold] #I:#W #[default]"
      set -g window-status-separator ""

      # Message styling
      set -g message-style "fg=colour235 bg=colour226 bold"

      # Key bindings
      # Reload config - removed due to Nix pure mode restrictions

      # Window and pane management
      bind c new-window -c "#{pane_current_path}"
      bind v split-window -v -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind h split-window -h -c "#{pane_current_path}"
      # Using backslash for horizontal split
      bind BSpace split-window -h -c "#{pane_current_path}"
      bind f resize-pane -Z
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
      bind Enter copy-mode
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle

      # 'y' key copies to KDE clipboard and exits copy mode
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "\
        if [ -n \"\$WAYLAND_DISPLAY\" ]; then \
          wl-copy; \
        else \
          xclip -selection clipboard -in; \
        fi"

      # 'Y' copies to clipboard but stays in copy mode (for multiple selections)
      bind -T copy-mode-vi Y send-keys -X copy-pipe "\
        if [ -n \"\$WAYLAND_DISPLAY\" ]; then \
          wl-copy; \
        else \
          xclip -selection clipboard -in; \
        fi"

      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi H send-keys -X start-of-line
      bind -T copy-mode-vi L send-keys -X end-of-line

      # Paste
      bind p paste-buffer
      bind B choose-buffer  # Changed from P to B to avoid conflict with popup

      # Paste from system clipboard (KDE Plasma clipboard)
      # Use Ctrl+Shift+V or prefix + V to paste from system clipboard
      bind V run-shell "\
        if [ -n \"\$WAYLAND_DISPLAY\" ]; then \
          wl-paste | tmux load-buffer - && tmux paste-buffer; \
        else \
          xclip -selection clipboard -out | tmux load-buffer - && tmux paste-buffer; \
        fi"

      # Toggles
      bind S run-shell "tmux setw synchronize-panes && tmux display-message 'Synchronize panes: #{?pane_synchronized,ON,OFF}'"
      bind m run-shell "tmux set -g mouse && tmux display-message 'Mouse: #{?mouse,ON,OFF}'"

      # Keybinding cheatsheet (F1 or prefix + ?)
      bind -n F1 run-shell "/etc/nixos/scripts/keybindings-cheatsheet.sh"
      bind ? run-shell "/etc/nixos/scripts/keybindings-cheatsheet.sh"


      # Mouse behavior with KDE Plasma clipboard integration
      unbind -n MouseDown3Pane
      unbind -T copy-mode-vi MouseDown3Pane

      # Enhanced mouse copy that integrates with KDE clipboard
      # This preserves the smooth selection experience while adding clipboard sync
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-no-clear "\
        if [ -n \"\$WAYLAND_DISPLAY\" ]; then \
          wl-copy; \
        else \
          xclip -selection clipboard -in; \
        fi"

      # Double-click to select word and copy to clipboard
      bind -T copy-mode-vi DoubleClick1Pane \
        select-pane \; \
        send-keys -X select-word \; \
        send-keys -X copy-pipe-no-clear "\
          if [ -n \"\$WAYLAND_DISPLAY\" ]; then \
            wl-copy; \
          else \
            xclip -selection clipboard -in; \
          fi"

      # Triple-click to select line and copy to clipboard
      bind -T copy-mode-vi TripleClick1Pane \
        select-pane \; \
        send-keys -X select-line \; \
        send-keys -X copy-pipe-no-clear "\
          if [ -n \"\$WAYLAND_DISPLAY\" ]; then \
            wl-copy; \
          else \
            xclip -selection clipboard -in; \
          fi"

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
          echo -n "$file" | if [ -n "$WAYLAND_DISPLAY" ]; then wl-copy; else xclip -selection clipboard; fi; \
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
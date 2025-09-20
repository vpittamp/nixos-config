{ config, pkgs, lib, ... }:

{
  # Tmux configuration - force rebuild 2025-09-19
  programs.tmux = {
    enable = true;
    shell = "${pkgs.bash}/bin/bash";
    terminal = "tmux-256color";
    prefix = "`";
    baseIndex = 1;
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

      # Force refresh on attach
      set-hook -g client-attached 'run-shell "tmux refresh-client -S"'

      # Bind key for manual window resize when needed
      bind R run-shell "tmux resize-window -A"

      # Terminal-specific overrides for proper rendering
      # Konsole-specific settings
      set -ga terminal-overrides ',konsole*:Tc'
      set -ga terminal-overrides ',konsole*:Ms@'

      # VSCode terminal settings
      set -ga terminal-overrides ',vscode*:Tc'

      # General xterm settings
      set -ga terminal-overrides ',xterm*:Tc'
      set -ga terminal-overrides ',xterm-256color:Tc'

      # Allow passthrough for proper color handling
      set -g allow-passthrough on

      # Handle Konsole-specific environment
      if-shell '[ -n "$KONSOLE_VERSION" ]' \
        'set -g aggressive-resize on; set -g window-size latest' \
        ''

      # Basic terminal features
      set -as terminal-features ",*:RGB"

      # Pane settings
      set -g pane-base-index 1
      set -g renumber-windows on
      set -g pane-border-lines single  # Simple lines for cleaner look
      set -g pane-border-status off  # Remove pane status labels for cleaner appearance

      # Subtle pane borders - almost invisible
      set -g pane-border-style "fg=colour234"  # Very dark gray, almost invisible
      set -g pane-active-border-style "fg=colour236"  # Slightly lighter but still subtle

      # Visual distinction between active and inactive panes
      # Active pane: pure black background with bright text
      set -g window-active-style "bg=colour16"  # Pure black background for active pane
      # Inactive panes: apply dim filter to all content including application colors
      set -g window-style "bg=colour234,dim"  # Dark gray background with dim attribute for all text

      # Alternative color settings for better inactive pane dimming
      # The 'dim' attribute affects all output including ANSI colors from applications
      set -g pane-border-dim true

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
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

      # Window and pane management
      bind c new-window -c "#{pane_current_path}"
      bind v split-window -v -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind h split-window -h -c "#{pane_current_path}"
      bind | split-window -h -c "#{pane_current_path}"
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
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5

      # Copy mode
      bind Enter copy-mode
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi H send-keys -X start-of-line
      bind -T copy-mode-vi L send-keys -X end-of-line

      # Paste
      bind ] paste-buffer
      bind p paste-buffer
      bind P choose-buffer

      # Toggles
      bind S setw synchronize-panes \; display-message "Synchronize panes: #{?pane_synchronized,ON,OFF}"
      bind m set -g mouse \; display-message "Mouse: #{?mouse,ON,OFF}"

      # Mouse behavior
      unbind -n MouseDown3Pane
      unbind -T copy-mode-vi MouseDown3Pane
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection

      # Sesh session management
      bind -n C-t run-shell "bash -ic 'sesh_connect'"
      bind -N "last-session (via sesh)" l run-shell "sesh last"
      bind-key "T" run-shell "sesh connect \"\$(sesh list --icons | fzf-tmux -p 80%,70% --no-sort --ansi --border-label ' sesh ' --prompt '⚡  ' --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' --bind 'tab:down,btab:up' --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)' --preview-window 'right:55%' --preview 'sesh preview {}')\""
    '';
  };
}
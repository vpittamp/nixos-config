{ config, pkgs, lib, ... }:

let
  # Catppuccin Mocha colors embedded directly
  colors = {
    base = "#1e1e2e";
    mantle = "#181825";
    crust = "#11111b";
    surface0 = "#313244";
    surface1 = "#45475a";
    surface2 = "#585b70";
    text = "#cdd6f4";
    subtext1 = "#bac2de";
    subtext0 = "#a6adc8";
    lavender = "#b4befe";
    blue = "#89b4fa";
    sapphire = "#74c7ec";
    sky = "#89dceb";
    teal = "#94e2d5";
    green = "#a6e3a1";
    yellow = "#f9e2af";
    peach = "#fab387";
    maroon = "#eba0ac";
    red = "#f38ba8";
    mauve = "#cba6f7";
    pink = "#f5c2e7";
    flamingo = "#f2cdcd";
    rosewater = "#f5e0dc";
  };
in
{
  # Tmux configuration
  programs.tmux = {
    enable = true;
    shell = "${pkgs.bash}/bin/bash";
    terminal = "tmux-256color";  # Better compatibility with modern terminals
    prefix = "`";
    baseIndex = 1;
    historyLimit = 10000;
    keyMode = "vi";
    mouse = true;  # Enable mouse for scrolling only (clicks disabled in config)
    aggressiveResize = true;  # Only resize when smaller client is actively viewing
    
    plugins = with pkgs.tmuxPlugins; [
      sensible
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
      # Prefix is set via programs.tmux.prefix

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

      # Handle VS Code terminal properly
      if-shell '[ -n "$VSCODE_TERMINAL" ]' {
        # Don't resize based on other clients when in VS Code
        set-window-option -g aggressive-resize off
        # Respect VS Code's terminal size
        set-window-option -g force-width 0
        set-window-option -g force-height 0
      }
      # Allow OSC sequences to pass through but filter problematic ones
      # Setting to 'on' allows color queries to be handled properly
      # Setting to 'off' can cause sequences to appear as text
      set -g allow-passthrough on

      # Strip OSC 11 sequences that query/set background color
      set -ag terminal-overrides ',*:Ms@'
      
      # Basic terminal features
      set -as terminal-features ',*:RGB'
      # Track alternate-screen state via user option (window-scoped)
      setw -g @altscreen on
      
      # Pane settings
      set -g pane-base-index 1
      set -g renumber-windows on
      set -g pane-border-lines double  # Use double lines for maximum visibility
      # Place per-pane pill at the bottom to avoid any conflict with the top status line
      set -g pane-border-status bottom
      # HIGH CONTRAST borders for dark theme visibility
      # Inactive panes: bright surface color for visibility
      set -g pane-border-style "fg=${colors.surface2}"
      # Active pane: BRIGHT cyan/sapphire border that pops on dark background
      set -g pane-active-border-style "fg=${colors.sapphire},bold"
      # Per-pane label with maximum contrast
      # Active: bright background with dark text; Inactive: visible but dimmer
      set -g pane-border-format "#{?pane_active,#[fg=${colors.crust},bg=${colors.sapphire},bold] ◆ #S:#I.#P #[default],#[fg=${colors.text},bg=${colors.surface1}] ○ #S:#I.#P #[default]}"
      
      # Status bar styling
      set -g status-position top
      set -g status-justify left
      set -g status-style "bg=${colors.crust} fg=${colors.text}"
      set -g status-left-length 80
      set -g status-right-length 150
      
      # Left status with session info (no session/window counts). Shows ⎇ only when alt-screen is OFF.
      set -g status-left "#{?client_prefix,#[fg=${colors.crust},bg=${colors.red},bold] PREFIX #[fg=${colors.red},bg=${colors.mauve}],#{?pane_in_mode,#[fg=${colors.crust},bg=${colors.yellow},bold] COPY #[fg=${colors.yellow},bg=${colors.mauve}],#{?window_zoomed_flag,#[fg=${colors.crust},bg=${colors.peach},bold] ZOOM #[fg=${colors.peach},bg=${colors.mauve}],#[fg=${colors.crust},bg=${colors.green},bold] TMUX #[fg=${colors.green},bg=${colors.mauve}]}}}#{?#{==:#{@altscreen},off},#[fg=${colors.crust},bg=${colors.sapphire},bold]  ⎇  #[fg=${colors.sapphire},bg=${colors.mauve}],}#[fg=${colors.crust},bg=${colors.mauve},bold]  #S #[fg=${colors.mauve},bg=${colors.surface1}]#[fg=${colors.surface1},bg=${colors.crust}] "
      
      # Right status: canonical pane target (session:window.pane)
      set -g status-right "#[fg=${colors.surface0},bg=${colors.crust}]#[fg=${colors.text},bg=${colors.surface0}]  #S:#I.#P "
      
      # Window status with enhanced visual separation
      set -g window-status-format "#[fg=${colors.surface1},bg=${colors.crust}]#[fg=${colors.subtext0},bg=${colors.surface1}] #I:#W #[fg=${colors.surface1},bg=${colors.crust}]"
      set -g window-status-current-format "#[fg=${colors.blue},bg=${colors.crust}]#[fg=${colors.crust},bg=${colors.blue},bold] #I:#W#F #[fg=${colors.blue},bg=${colors.crust}]"
      set -g window-status-separator ""
      
      # Pane borders handled above (ghost borders + per-pane pills)
      
      # Message styling
      set -g message-style "fg=${colors.crust} bg=${colors.yellow} bold"

      # Additional pane styling for better visual separation
      # Add padding and visual cues for active pane
      set -g pane-border-indicators both  # Show arrows pointing to active pane
      set -g display-panes-colour "${colors.yellow}"  # Bright color for pane numbers
      set -g display-panes-active-colour "${colors.sapphire}"  # Active pane number color
      set -g display-panes-time 2000  # Show pane numbers for 2 seconds

      # Make active pane background slightly lighter for visibility
      set -g window-style "fg=${colors.text},bg=${colors.crust}"
      set -g window-active-style "fg=${colors.text},bg=${colors.base}"
      
      # Key bindings
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"
      
      # Basic copy mode
      bind Enter copy-mode
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi H send-keys -X start-of-line
      bind -T copy-mode-vi L send-keys -X end-of-line
      
      # Basic paste
      bind ] paste-buffer
      bind p paste-buffer
      bind P choose-buffer
      
      # Window management
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
      bind -r L resize-pane -R 5
      
      # Quick window switching
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      
      # Toggles
      bind S setw synchronize-panes \; display-message "Synchronize panes: #{?pane_synchronized,ON,OFF}"
      bind m set -g mouse \; display-message "Mouse: #{?mouse,ON,OFF}"
      
      # Mouse behavior:
      # - Normal click/drag: tmux handles (selection, copy mode, scrolling)
      # - Shift + click/drag: native terminal selection (bypasses tmux)
      # Disable right-click context menu since we don't use it
      unbind -n MouseDown3Pane
      unbind -T copy-mode-vi MouseDown3Pane
      # Keep selection anchor when finishing a mouse drag in copy mode so the
      # view doesn't snap back to the live pane
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection

      # Sesh session management
      bind -n C-t run-shell "bash -ic 'sesh_connect'"
      bind -N "last-session (via sesh)" l run-shell "sesh last"
      bind-key "T" run-shell "sesh connect \"\$(sesh list --icons | fzf-tmux -p 80%,70% --no-sort --ansi --border-label ' sesh ' --prompt '⚡  ' --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' --bind 'tab:down,btab:up' --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)' --preview-window 'right:55%' --preview 'sesh preview {}')\""
      # Claude in scrollable windows (scoped alt-screen off)
      # - These bindings open Claude in a regular tmux window and disable
      #   the alternate screen only for that window, so tmux history/mouse
      #   scrolling works as expected.
      bind g new-window -n "Claude" "claude" \; setw alternate-screen off \; setw @altscreen off
      bind G new-window -n "Claude*" "claude --continue" \; setw alternate-screen off \; setw @altscreen off

      # Optional: launch in the current pane (no new window)
      # Use prefix + a / A to start Claude here with alt-screen disabled.
      bind a setw alternate-screen off \; setw @altscreen off \; send-keys -t ! "claude" C-m
      bind A setw alternate-screen off \; setw @altscreen off \; send-keys -t ! "claude --continue" C-m
      # Toggle alternate-screen for current window and update indicator
      bind M if -F '#{==:#{@altscreen},off}' \
        "setw alternate-screen on \; setw @altscreen on \; display-message \"ALT screen: ON\"" \
        "setw alternate-screen off \; setw @altscreen off \; display-message \"ALT screen: OFF\""
      # Help menu
      bind ? display-menu -T "Tmux Quick Help" -x C -y C \
        "Window Operations"  w "display-menu -T 'Window Operations' \
          'New Window (c)'           c 'new-window' \
          'Kill Window (X)'          X 'kill-window' \
          'Rename Window (,)'        , 'command-prompt -I \"#W\" \"rename-window %%\"' \
          'List Windows (w)'         w 'choose-window' \
          'Next Window (n)'          n 'next-window' \
          'Previous Window (p)'      p 'previous-window' \
          'Last Window (l)'          l 'last-window'" \
        "Pane Operations"    p "display-menu -T 'Pane Operations' \
          'Split Horizontal (|)'     | 'split-window -h' \
          'Split Vertical (-)'       - 'split-window -v' \
          'Kill Pane (x)'            x 'kill-pane' \
          'Zoom Pane (f)'            f 'resize-pane -Z' \
          'Rotate Panes (C-o)'       C-o 'rotate-window' \
          'Break Pane (!)'           ! 'break-pane' \
          'Swap Panes (})'           } 'swap-pane -D'" \
        "Session Operations" s "display-menu -T 'Session Operations' \
          'New Session'              N 'new-session' \
          'Choose Session (s)'       s 'choose-session' \
          'Detach (d)'               d 'detach-client' \
          'Rename Session ($)'       $ 'command-prompt -I \"#S\" \"rename-session %%\"' \
          'Kill Session'             K 'kill-session'" \
        "Copy Mode"          m "display-menu -T 'Copy Mode' \
          'Enter Copy Mode ([)'      [ 'copy-mode' \
          'Paste Buffer (])'         ] 'paste-buffer' \
          'List Buffers (=)'         = 'choose-buffer' \
          'Save Buffer'              S 'command-prompt -p \"Save to:\" \"save-buffer %%\"'" \
        "" \
        "Search Keys (/)"    / "command-prompt -p 'Search for command:' 'new-window -n \"Keys\" \"sh -lc \"tmux list-keys | grep -i %% | less\"\"'" \
        "List All Keys"      a "new-window -n 'Keys' 'sh -lc "tmux list-keys | less"'" \
        "Reload Config (r)"  r "source-file ~/.config/tmux/tmux.conf"
    '';
  };
}

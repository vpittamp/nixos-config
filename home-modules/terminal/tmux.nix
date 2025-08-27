{ config, pkgs, lib, ... }:

let
  # Custom tmux plugins not in nixpkgs
  tmux-mode-indicator = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-mode-indicator";
    version = "unstable-2024-01-01";
    rtpFilePath = "mode_indicator.tmux";
    src = pkgs.fetchFromGitHub {
      owner = "MunifTanjim";
      repo = "tmux-mode-indicator";
      rev = "11520829210a34dc9c7e5be9dead152eaf3a4423";
      sha256 = "sha256-hlhBKC6UzkpUrCanJehs2FxK5SoYBoiGiioXdx6trC4=";
    };
  };

  # tmux-sessionx for session management with preview
  tmux-sessionx = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-sessionx";
    version = "unstable-2024-12-01";
    rtpFilePath = "sessionx.tmux";
    src = pkgs.fetchFromGitHub {
      owner = "omerxx";
      repo = "tmux-sessionx";
      rev = "main";
      sha256 = "0yfxinx6bdddila3svszpky9776afjprn26c8agj6sqh8glhiz3b";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postInstall = ''
      substituteInPlace $out/share/tmux-plugins/tmux-sessionx/sessionx.tmux \
        --replace "fzf-tmux" "${pkgs.fzf}/bin/fzf-tmux" \
        --replace "fzf " "${pkgs.fzf}/bin/fzf "
    '';
  };

  # Color scheme access
  colors = config.colorScheme;
in
{
  # Tmux configuration
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";  # Better compatibility with modern terminals
    prefix = "`";
    baseIndex = 1;
    historyLimit = 10000;
    keyMode = "vi";
    mouse = true;
    
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      {
        plugin = tmux-mode-indicator;
        extraConfig = ''
          # Mode indicator configuration
          set -g @mode_indicator_prefix_prompt ' WAIT '
          set -g @mode_indicator_copy_prompt ' COPY '
          set -g @mode_indicator_sync_prompt ' SYNC '
          set -g @mode_indicator_empty_prompt ' TMUX '
          
          # Mode indicator styling
          set -g @mode_indicator_prefix_mode_style "bg=${colors.red},fg=${colors.crust}"
          set -g @mode_indicator_copy_mode_style "bg=${colors.yellow},fg=${colors.crust}"
          set -g @mode_indicator_sync_mode_style "bg=${colors.blue},fg=${colors.crust}"
          set -g @mode_indicator_empty_mode_style "bg=${colors.green},fg=${colors.crust}"
        '';
      }
      {
        plugin = tmux-sessionx;
        extraConfig = ''
          # Sessionx configuration
          set -g @sessionx-bind 'o'  # Prefix + o to open sessionx
          set -g @sessionx-x-path '${pkgs.coreutils}/bin'  # Path to coreutils
          set -g @sessionx-custom-paths '/etc/nixos'  # Add Nix config directory
          set -g @sessionx-custom-paths-subdirectories 'false'
          set -g @sessionx-filter-current 'false'  # Show current session in list
          set -g @sessionx-preview-location 'right'
          set -g @sessionx-preview-ratio '55%'
          set -g @sessionx-window-height '90%'
          set -g @sessionx-window-width '75%'
          set -g @sessionx-tmuxinator-mode 'off'
          set -g @sessionx-tree-mode 'off'
          set -g @sessionx-preview-enabled 'true'
        '';
      }
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
    ];
    
    extraConfig = ''
      # General settings
      set -g default-terminal "tmux-256color"
      set -ga terminal-overrides ",xterm-256color:Tc"
      set -ga terminal-overrides ",screen-256color:Tc"
      set -ga terminal-overrides ",tmux-256color:Tc"
      set -sg escape-time 0
      set -g focus-events off  # Disable to prevent [O[I escape sequences in VS Code
      set -g detach-on-destroy off  # don't exit from tmux when closing a session
      set -g repeat-time 1000
      
      # Enable passthrough for terminal escape sequences
      set -g allow-passthrough on
      
      # Fix for VS Code terminal - disable problematic features
      set -as terminal-overrides ',vscode*:Ms@'  # Disable OSC 52 clipboard for VS Code
      set -g set-clipboard off  # Disable clipboard integration
      set -as terminal-features ',*:RGB'  # Use RGB instead of OSC sequences
      
      # Pane settings
      set -g pane-base-index 1
      set -g renumber-windows on
      set -g pane-border-lines single
      set -g pane-border-status top
      
      # Status bar styling with enhanced contrast
      set -g status-position top
      set -g status-justify left
      set -g status-style "bg=${colors.crust} fg=${colors.text}"
      set -g status-left-length 80
      set -g status-right-length 150
      
      # Left status with powerline separators, session count and window count
      set -g status-left "#{?client_prefix,#[fg=${colors.crust}#,bg=${colors.red}#,bold] PREFIX #[fg=${colors.red}#,bg=${colors.mauve}],#{?pane_in_mode,#[fg=${colors.crust}#,bg=${colors.yellow}#,bold] COPY #[fg=${colors.yellow}#,bg=${colors.mauve}],#{?window_zoomed_flag,#[fg=${colors.crust}#,bg=${colors.peach}#,bold] ZOOM #[fg=${colors.peach}#,bg=${colors.mauve}],#[fg=${colors.crust}#,bg=${colors.green}#,bold] TMUX #[fg=${colors.green}#,bg=${colors.mauve}]}}}#[fg=${colors.crust},bg=${colors.mauve},bold]  #S #[fg=${colors.mauve},bg=${colors.surface1}]#[fg=${colors.text},bg=${colors.surface1}]  #(tmux ls | wc -l)S #{session_windows}W #[fg=${colors.surface1},bg=${colors.crust}] "
      
      # Right status - simplified with just pane info
      set -g status-right "#[fg=${colors.surface0},bg=${colors.crust}]#[fg=${colors.text},bg=${colors.surface0}]  #{window_panes} "
      
      # Window status with powerline styling
      set -g window-status-format "#[fg=${colors.crust},bg=${colors.surface0}]#[fg=${colors.text},bg=${colors.surface0}] #I:#W #[fg=${colors.surface0},bg=${colors.crust}]"
      set -g window-status-current-format "#[fg=${colors.crust},bg=#{?window_zoomed_flag,${colors.yellow},${colors.blue}}]#[fg=${colors.crust},bg=#{?window_zoomed_flag,${colors.yellow},${colors.blue}},bold]#{?window_zoomed_flag, 🔍,} #I:#W[#{window_panes}] #[fg=#{?window_zoomed_flag,${colors.yellow},${colors.blue}},bg=${colors.crust}]"
      set -g window-status-separator ""
      
      # Pane borders and titles
      set -g pane-border-style "fg=${colors.surface0}"
      set -g pane-active-border-style "fg=${colors.blue},bold"
      set -g pane-border-format " #[fg=${colors.text}]#{?pane_active,#[bg=${colors.surface1}],}[#P/#{window_panes}] #{pane_current_command} #{?window_zoomed_flag,#[fg=${colors.yellow}](ZOOMED) ,}#[default] "
      
      # Message styling
      set -g message-style "fg=${colors.crust} bg=${colors.yellow} bold"
      
      # Key bindings
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"
      
      # Split windows
      bind v split-window -v -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind h split-window -h -c "#{pane_current_path}"
      bind | split-window -h -c "#{pane_current_path}"
      
      # Pane navigation (without prefix)
      bind -n C-h select-pane -L
      bind -n C-j select-pane -D
      bind -n C-k select-pane -U
      bind -n C-l select-pane -R
      
      # Sesh session picker with Ctrl+T (no prefix needed) - calls bash's sesh_connect function
      bind -n C-t run-shell "bash -ic 'sesh_connect'"
      
      # Pane resizing
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r L resize-pane -R 5
      
      # Window management
      bind c new-window -c "#{pane_current_path}"
      bind f resize-pane -Z
      bind x kill-pane
      bind X kill-window
      
      # Quick window switching
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      
      # Synchronize panes toggle
      bind S setw synchronize-panes \; display-message "Synchronize panes: #{?pane_synchronized,ON,OFF}"
      
      # Sesh session management
      bind -N "last-session (via sesh)" l run-shell "sesh last"
      bind-key "T" run-shell "sesh connect \"\$(sesh list --icons | fzf-tmux -p 80%,70% --no-sort --ansi --border-label ' sesh ' --prompt '⚡  ' --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' --bind 'tab:down,btab:up' --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)' --preview-window 'right:55%' --preview 'sesh preview {}')\""
      # === Popup Windows ===
      
      # Ephemeral shell popup with full terminal features
      bind e display-popup -E \
        -w 80% -h 80% \
        -d "#{pane_current_path}" \
        -T " 🚀 Ephemeral Shell (ESC to close) " \
        -e TERM=xterm-256color \
        -e COLORTERM=truecolor \
        "exec bash --login"
      
      # Quick Claude commands
      bind C display-popup -E -w 80% -h 80% "claude"
      bind R display-popup -E -w 80% -h 80% "claude --continue"
      
      
      # Copy mode
      bind Enter copy-mode
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
      # Clipboard integration - try wl-copy first (Wayland/WSLg), fall back to clip.exe
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'wl-copy --type text/plain 2>/dev/null || /mnt/c/Windows/System32/clip.exe'
      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi H send-keys -X start-of-line
      bind -T copy-mode-vi L send-keys -X end-of-line
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'wl-copy --type text/plain 2>/dev/null || /mnt/c/Windows/System32/clip.exe'
    '';
  };
}
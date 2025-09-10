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
    mouse = true;  # Enable mouse support for proper scrolling
    
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
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
      better-mouse-mode
      tmux-fzf
      tmux-thumbs
    ];
    
    extraConfig = ''
      # Fix backtick prefix
      unbind -n '\`'
      bind '\`' send-prefix
      
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
      set -g allow-passthrough on
      
      # Clipboard integration
      set -g set-clipboard on
      set -as terminal-overrides ',vscode*:Ms@'
      set -as terminal-overrides ',vscode*:Cc@:Cr@:Cs@:Se@:Ss@'
      set -g @yank_selection 'clipboard'
      set -g @copy-command 'wl-copy'
      set -as terminal-features ',*:RGB'
      
      # Pane settings
      set -g pane-base-index 1
      set -g renumber-windows on
      set -g pane-border-lines single
      set -g pane-border-status top
      
      # Status bar styling
      set -g status-position top
      set -g status-justify left
      set -g status-style "bg=${colors.crust} fg=${colors.text}"
      set -g status-left-length 80
      set -g status-right-length 150
      
      # Left status with session info
      set -g status-left "#{?client_prefix,#[fg=${colors.crust}#,bg=${colors.red}#,bold] PREFIX #[fg=${colors.red}#,bg=${colors.mauve}],#{?pane_in_mode,#[fg=${colors.crust}#,bg=${colors.yellow}#,bold] COPY #[fg=${colors.yellow}#,bg=${colors.mauve}],#{?window_zoomed_flag,#[fg=${colors.crust}#,bg=${colors.peach}#,bold] ZOOM #[fg=${colors.peach}#,bg=${colors.mauve}],#[fg=${colors.crust}#,bg=${colors.green}#,bold] TMUX #[fg=${colors.green}#,bg=${colors.mauve}]}}}#[fg=${colors.crust},bg=${colors.mauve},bold]  #S #[fg=${colors.mauve},bg=${colors.surface1}]#[fg=${colors.text},bg=${colors.surface1}]  #(tmux ls | wc -l)S #{session_windows}W #[fg=${colors.surface1},bg=${colors.crust}] "
      
      # Right status
      set -g status-right "#[fg=${colors.surface0},bg=${colors.crust}]#[fg=${colors.text},bg=${colors.surface0}]  #{window_panes} "
      
      # Window status
      set -g window-status-format "#[fg=${colors.crust},bg=${colors.surface0}]#[fg=${colors.text},bg=${colors.surface0}] #I:#W #[fg=${colors.surface0},bg=${colors.crust}]"
      set -g window-status-current-format "#[fg=${colors.crust},bg=#{?window_zoomed_flag,${colors.yellow},${colors.blue}}]#[fg=${colors.crust},bg=#{?window_zoomed_flag,${colors.yellow},${colors.blue}},bold]#{?window_zoomed_flag, 🔍,} #I:#W[#{window_panes}] #[fg=#{?window_zoomed_flag,${colors.yellow},${colors.blue}},bg=${colors.crust}]"
      set -g window-status-separator ""
      
      # Pane borders
      set -g pane-border-style "fg=${colors.surface0}"
      set -g pane-active-border-style "fg=${colors.blue},bold"
      set -g pane-border-format " #[fg=${colors.text}]#{?pane_active,#[bg=${colors.surface1}],}[#P/#{window_panes}] #{pane_current_command} #{?window_zoomed_flag,#[fg=${colors.yellow}](ZOOMED) ,}#[default] "
      
      # Message styling
      set -g message-style "fg=${colors.crust} bg=${colors.yellow} bold"
      
      # Key bindings
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"
      
      # Copy mode
      bind Enter copy-mode
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'wl-copy'
      bind -T copy-mode-vi Y send-keys -X copy-pipe-and-cancel 'wl-copy'
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'wl-copy'
      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi H send-keys -X start-of-line
      bind -T copy-mode-vi L send-keys -X end-of-line
      
      # Paste from system clipboard
      bind ] run-shell "wl-paste | tmux load-buffer - && tmux paste-buffer"
      bind p run-shell "wl-paste | tmux load-buffer - && tmux paste-buffer"
      bind -n C-v run-shell "wl-paste | tmux load-buffer - && tmux paste-buffer"
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
      
      # Sesh session management
      bind -n C-t run-shell "bash -ic 'sesh_connect'"
      bind -N "last-session (via sesh)" l run-shell "sesh last"
      bind-key "T" run-shell "sesh connect \"\$(sesh list --icons | fzf-tmux -p 80%,70% --no-sort --ansi --border-label ' sesh ' --prompt '⚡  ' --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' --bind 'tab:down,btab:up' --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)' --preview-window 'right:55%' --preview 'sesh preview {}')\""
      
      # Popup windows
      bind e display-popup -E \
        -w 80% -h 80% \
        -d "#{pane_current_path}" \
        -T " 🚀 Ephemeral Shell (ESC to close) " \
        -e TERM=xterm-256color \
        -e COLORTERM=truecolor \
        "exec bash --login"
      
      bind C display-popup -E -w 80% -h 80% "claude"
      bind R display-popup -E -w 80% -h 80% "claude --continue"
      
      # Mouse scrolling
      bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'copy-mode -e'"
      bind -n WheelDownPane select-pane -t= \; send-keys -M
      
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
        "Search Keys (/)"    / "command-prompt -p 'Search for command:' 'display-popup -E \"tmux list-keys | grep -i %%\"'" \
        "List All Keys"      a "display-popup -E 'tmux list-keys | less'" \
        "Reload Config (r)"  r "source-file ~/.config/tmux/tmux.conf"
    '';
  };
}

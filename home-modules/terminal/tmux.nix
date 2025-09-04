{ config, pkgs, lib, ... }:

let
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
    mouse = true;  # Enable mouse support for proper scrolling
    
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      # Using only nixpkgs plugins to avoid build permission issues
      # Custom plugins (tmux-mode-indicator, tmux-sessionx) should be 
      # provided at system level if needed
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
      # Additional safe plugins from nixpkgs
      pain-control
      prefix-highlight
      better-mouse-mode
      tmux-fzf
      tmux-thumbs
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
      
      # Clipboard integration
      # Enable OSC 52 clipboard for terminals that support it (e.g. WezTerm/kitty)
      # Keep it disabled for VS Code specifically to avoid interference
      set -g set-clipboard on
      set -as terminal-overrides ',vscode*:Ms@'  # Disable OSC 52 clipboard for VS Code
      # Disable OSC 10/11 color queries for VSCode to prevent escape sequence artifacts
      set -as terminal-overrides ',vscode*:Cc@:Cr@:Cs@:Se@:Ss@'
      
      # Configure tmux-yank to use Windows clipboard in WSL
      # Falls back to wl-copy via explicit bindings below when available
      set -g @yank_selection 'clipboard'
      set -g @copy-command '/usr/local/bin/clip.exe'
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
      # Paste from Windows clipboard (helper: /usr/local/bin/wsl-paste)
      bind P run-shell "/usr/local/bin/wsl-paste | tmux load-buffer - && tmux paste-buffer -p" \; display-message 'Pasted from Windows clipboard'
      
      # Help and documentation with context-aware menus
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
      
      # Alternative simpler help binding
      bind h display-popup -E "printf 'Tmux Key Bindings (Prefix = backtick):\n\n\
      WINDOWS: c=new | X=kill | ,=rename | n/p=next/prev | 0-9=select\n\
      PANES:   |=split-h | -=split-v | x=kill | f=zoom | hjkl=navigate\n\
      SESSION: d=detach | s=list | \$=rename | o=sessionx\n\
      COPY:    [=copy-mode | ]=paste | v=select | y=yank\n\n\
      Press ? for interactive menu'"
      
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
      
      # Mouse mode toggle
      bind m set -g mouse \; display-message "Mouse: #{?mouse,ON,OFF}"
      
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
      # Mouse scrolling and selection
      # When mouse is enabled, scrolling enters copy mode automatically
      bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'copy-mode -e'"
      bind -n WheelDownPane select-pane -t= \; send-keys -M
      
      # Mouse selection in copy mode
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel '/usr/local/bin/wsl-clip-clean'
      
      # Clipboard integration
      # - y: copy cleaned (no emojis/private-use icons) to Windows clipboard
      # - Y: copy raw (full Unicode) to Windows clipboard
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel '/usr/local/bin/wsl-clip-clean' \; display-message 'Copied (clean)'
      bind -T copy-mode-vi Y send-keys -X copy-pipe-and-cancel '/usr/local/bin/clip.exe' \; display-message 'Copied (raw)'
      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi H send-keys -X start-of-line
      bind -T copy-mode-vi L send-keys -X end-of-line
    '';
  };
}

{ config, pkgs, lib, ... }:
{
  programs.bash = {
    enable = true;
    # Use the Nix-provided bash (version 5+) instead of system bash
    # This avoids compatibility issues with macOS's ancient bash 3.2
    package = pkgs.bashInteractive;
    
    historyControl = [ "ignoreboth" ];
    historySize = 10000;
    historyFileSize = 20000;
    
    # For macOS Terminal.app - it runs login shells by default
    # This ensures colors and configs load properly
    profileExtra = ''
      # macOS Terminal.app runs login shells, so source bashrc
      if [ -r ~/.bashrc ]; then
        source ~/.bashrc
      fi
      
      # Enable colors in macOS Terminal
      # CLICOLOR enables color output for BSD commands (ls on macOS)
      export CLICOLOR=1
      # LSCOLORS is for BSD ls (macOS native)
      export LSCOLORS=GxFxCxDxBxegedabagaced
      
      # Ensure terminal supports colors
      export TERM=${TERM:-xterm-256color}
      
      # Enable grep colors
      export GREP_OPTIONS='--color=auto'
      export GREP_COLOR='1;32'
      
      # Ensure LS_COLORS is set for GNU coreutils (from dircolors module)
      # This makes both BSD and GNU tools work with colors
      if [ -r ~/.dir_colors ]; then
        eval "$(dircolors -b ~/.dir_colors)"
      elif command -v dircolors >/dev/null 2>&1; then
        eval "$(dircolors -b)"
      fi
    '';
    
    shellOptions = [
      "histappend"
      "checkwinsize"
      "extglob"
      "globstar"
      "checkjobs"
    ];
    
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      PAGER = "less";
      LESS = "-R";
      # TERM is now set dynamically in bash initExtra to avoid conflicts
      # TERM = "screen-256color";
      DOCKER_HOST = "unix:///mnt/wsl/docker-desktop/shared-sockets/guest-services/docker.proxy.sock";
      # WSL-specific: Use Windows clipboard
      DISPLAY = ":0";
      # Disable OSC color queries
      NO_COLOR = "";  # Set to empty string so programs can check it exists
      
      # Nix single-user mode for containers (harmless on WSL)
      NIX_REMOTE = "";
      
      # SSL Certificate configuration
      NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
      
      # AI/LLM API Keys (set these in your environment or use a secrets manager)
      # AVANTE_ANTHROPIC_API_KEY = "your-api-key-here"; # Uncomment and set your Claude API key
      # Or use a command to retrieve from password manager:
      # AVANTE_ANTHROPIC_API_KEY = "$(op read 'op://Private/Anthropic API Key/api_key')"; # Example with 1Password
    };
    
    shellAliases = {
      # Navigation with zoxide
      cd = "z";  # Use zoxide for cd command
      cdd = "command cd";  # Original cd available as cdd
      zad = "ls -d */ 2>/dev/null | xargs -I {} zoxide add {}";  # Add all subdirectories to zoxide
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      
      # Better defaults
      ls = "eza --group-directories-first";
      ll = "eza -l --group-directories-first";
      la = "eza -la --group-directories-first";
      lt = "eza --tree";
      cat = "bat";
      grep = "rg";
      egrep = "rg";
      fgrep = "rg -F";
      
      # Git
      g = "git";
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline --graph --decorate";
      gd = "git diff";
      gco = "git checkout";
      gb = "git branch";
      
      # Docker alias to use Docker Desktop via wrapper
      docker = "/etc/nixos/docker-wrapper.sh";
      
      # Docker shortcuts
      d = "docker";
      dc = "docker-compose";
      dps = "docker ps";
      di = "docker images";
      
      # Tmux
      t = "tmux";
      ta = "tmux attach -t";
      ts = "tmux new-session -s";
      tl = "tmux list-sessions";
      
      # Kubernetes
      k = "kubectl";
      kgp = "kubectl get pods";
      kgs = "kubectl get svc";
      kgd = "kubectl get deployment";
      
      # System
      reload = "source ~/.bashrc";
      path = "echo $PATH | tr ':' '\n'";
      
      # File management
      y = "yazi";  # Quick file browser
      
      # Zoxide management
      zl = "zoxide query -l";  # List all database entries
      zr = "zoxide remove";     # Remove entry from database
      zs = "zoxide query -s";   # Show database statistics
      
      # WSL specific
      winhome = "cd /mnt/c/Users/VinodPittampalli/";
      
      # 1Password aliases
      ops = "eval $(op signin --account my)";
      opv = "op vault list";
      opi = "op item list";
      
      # ArgoCD with 1Password
      argo-login = "op plugin init argocd";
      
      # Claude aliases with initials
      cc = "claude --continue --dangerously-skip-permissions";
      cr = "claude --resume --dangerously-skip-permissions";
      cdsp = "claude --dangerously-skip-permissions";
      
      # Keep short aliases for convenience
      pbcopy = "pbcopy";
      pbpaste = "pbpaste";
    };
    
    initExtra = ''
      # Terminal configuration moved to TERM settings below
      
      # Fix terminal compatibility - detect VSCode terminal
      if [ "$TERM_PROGRAM" = "vscode" ]; then
        # VSCode terminal specific settings
        export TERM=xterm-256color
        # Disable COLORTERM in VSCode to avoid OSC issues
        unset COLORTERM
        # Disable problematic OSC sequences
        export STARSHIP_DISABLE_ANSI_INJECTION=1
        # Suppress OSC 10/11 color queries that cause the rgb: output
        printf '\033]10;?\007\033]11;?\007' 2>/dev/null | cat > /dev/null
        # Tell applications not to query terminal colors
        export VTE_VERSION="6003"  # Fake VTE version to disable color queries
      else
        # Regular terminal settings - use screen-256color to match tmux
        export TERM=screen-256color
        # Don't set COLORTERM to avoid OSC queries
        unset COLORTERM
      fi
      
      # Set up a colored prompt when Starship is not available
      # This ensures we always have colors even if Starship fails to load
      if ! command -v starship &> /dev/null; then
        PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
      fi
      
      # Add /usr/local/bin to PATH for Docker Desktop
      export PATH="/usr/local/bin:$PATH"
      
      # Terminal configuration handled by tmux settings
      
      # VSCode-specific: Suppress OSC sequences that cause visual artifacts
      if [ "$TERM_PROGRAM" = "vscode" ]; then
        # Disable OSC 10/11 (foreground/background color queries)
        # These cause the rgb: output you're seeing
        alias clear='printf "\033c"'
        # Suppress specific terminal query sequences
        stty -echoctl 2>/dev/null || true
      fi
      
      # Set up fzf key bindings (only if available)
      if command -v fzf &> /dev/null; then
        eval "$(fzf --bash)" 2>/dev/null || true
      fi
      
      # 1Password Shell Plugins
      if [ -f ~/.config/op/plugins.sh ]; then
        source ~/.config/op/plugins.sh
      fi
      
      # Enable direnv (only if available)
      if command -v direnv &> /dev/null; then
        eval "$(direnv hook bash)" 2>/dev/null || true
      fi
      
      # Better history search (avoid interfering with mouse wheel)
      # Use Ctrl+Up/Down for prefix-based search to prevent accidental triggers
      bind '"\e[1;5A": history-search-backward'  # Ctrl+Up
      bind '"\e[1;5B": history-search-forward'   # Ctrl+Down
      
      # Colored man pages
      export LESS_TERMCAP_mb=$'\e[1;32m'
      export LESS_TERMCAP_md=$'\e[1;32m'
      export LESS_TERMCAP_me=$'\e[0m'
      export LESS_TERMCAP_se=$'\e[0m'
      export LESS_TERMCAP_so=$'\e[01;33m'
      export LESS_TERMCAP_ue=$'\e[0m'
      export LESS_TERMCAP_us=$'\e[1;4;31m'
      
      # Sesh session manager keybinding - works both inside and outside tmux
      sesh_connect() {
        if [ -n "$TMUX" ]; then
          # Inside tmux: use fzf-tmux for popup overlay
          sesh connect "$(
            sesh list --icons | fzf-tmux -p 80%,70% \
              --no-sort \
              --ansi \
              --border-label ' sesh ' \
              --prompt '⚡  ' \
              --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' \
              --bind 'tab:down,btab:up' \
              --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' \
              --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' \
              --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' \
              --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' \
              --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
              --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)' \
              --preview-window 'right:55%' \
              --preview 'sesh preview {}'
          )"
        else
          # Outside tmux: use regular fzf
          sesh connect "$(
            sesh list --icons | fzf \
              --no-sort \
              --ansi \
              --border-label ' sesh ' \
              --prompt '⚡  ' \
              --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' \
              --bind 'tab:down,btab:up' \
              --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' \
              --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' \
              --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' \
              --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' \
              --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
              --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)' \
              --preview-window 'right:55%' \
              --preview 'sesh preview {}'
          )"
        fi
      }
      
      # Bind sesh_connect to Ctrl+T (works both inside and outside tmux)
      # Only bind if we're in an interactive shell with line editing enabled
      if [[ $- == *i* ]] && [[ -t 0 ]]; then
        bind -x '"\C-t": sesh_connect' 2>/dev/null || true
      fi
      
      # Yazi wrapper function with zoxide integration
      # This allows yazi to change the current directory and update zoxide's database
      function yazi() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
        command yazi "$@" --cwd-file="$tmp"
        if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
          cd -- "$cwd"
          # Update zoxide database when changing directories via yazi
          zoxide add "$PWD" 2>/dev/null || true
        fi
        rm -f -- "$tmp"
      }
      
      # Clipboard helper functions for robust WSL/WSLg behavior
      # pbcopy: reads from stdin (or args) and copies to clipboard
      # Prioritizes Wayland (wl-copy) for WSLg, falls back to Windows clipboard
      pbcopy() {
        local input
        if [ -t 0 ]; then
          input="$*"
        else
          input="$(cat)"
        fi
        # Try wl-copy first (Wayland/WSLg) with explicit text/plain MIME type
        if command -v wl-copy >/dev/null 2>&1; then
          printf "%s" "$input" | wl-copy --type text/plain 2>/dev/null
        # Fall back to Windows clipboard
        else
          printf "%s" "$input" | /mnt/c/Windows/System32/clip.exe
        fi
      }

      # pbpaste: prints clipboard contents
      # Prioritizes Wayland (wl-paste) for WSLg, falls back to Windows clipboard
      pbpaste() {
        # Try wl-paste first (Wayland/WSLg) with text output
        if command -v wl-paste >/dev/null 2>&1; then
          wl-paste --no-newline 2>/dev/null | sed 's/\r$//'
        # Fall back to Windows clipboard
        else
          /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -command 'Get-Clipboard' | sed 's/\r$//'
        fi
      }

      # Backwards-compatible helpers
      copy() { pbcopy "$@"; }
      clipaste() { pbpaste; }
      alias paste='pbpaste'
      
      # Initialize zoxide at the very end (only if available)
      if command -v zoxide &> /dev/null; then
        eval "$(zoxide init bash)" 2>/dev/null || true
        # Disable zoxide doctor warnings since we've properly initialized it
        export _ZO_DOCTOR=0
      fi
      
      # Preserve environment when using nix develop/shell
      # This ensures terminal customization is maintained
      if [ -n "$IN_NIX_SHELL" ]; then
        # Re-source starship if available
        if command -v starship &> /dev/null; then
          eval "$(starship init bash)" 2>/dev/null || true
        fi
        # Ensure our prompt is still active
        export STARSHIP_CONFIG="$HOME/.config/starship.toml"
      fi
    '';
  };
}

{ config, pkgs, lib, osConfig ? {}, ... }:
{
  programs.bash = {
    enable = true;
    # Use the Nix-provided bash (version 5+) instead of system bash
    # This avoids compatibility issues with macOS's ancient bash 3.2
    package = pkgs.bashInteractive;

    historyControl = [ "ignoreboth" ];
    historySize = 10000;
    historyFileSize = 20000;

    # Disable bash-completion on Darwin due to bash 3.2 incompatibility
    # The -v test operator in bash-completion doesn't work in bash 3.2
    # Users running Nix bash will get completion through initExtra
    enableCompletion = !pkgs.stdenv.isDarwin;
    
    # For macOS Terminal.app - it runs login shells by default
    # This ensures colors and configs load properly
    profileExtra = ''
      # On Darwin (macOS), set up the full nix-darwin PATH
      # This must match the PATH from nix-darwin's set-environment script
      if [[ "$OSTYPE" == "darwin"* ]]; then
        # nix-darwin system packages and home-manager packages
        export PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      else
        # On Linux, use standard Nix paths
        export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
      fi

      # CRITICAL: Source Nix daemon environment (sets up PATH)
      # This must come first to ensure nix packages are available
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi

      # CRITICAL: Source home-manager session variables for login shells
      # This ensures KDE terminals that start login shells get the environment
      if [ -e "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]; then
        . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
      fi
      
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
      export TERM=''${TERM:-xterm-256color}

      # Enable grep colors
      export GREP_OPTIONS='--color=auto'
      export GREP_COLOR='1;32'

      # Force colors for terminals (CRITICAL for Starship)
      export CLICOLOR_FORCE=1
      export FORCE_COLOR=1
      export COLORTERM=truecolor
      # Unset NO_COLOR if it's set (even if empty, it disables colors)
      unset NO_COLOR 2>/dev/null || true

      # Ensure LS_COLORS is set for GNU coreutils (from dircolors module)
      # This makes both BSD and GNU tools work with colors
      # Only run dircolors on Linux (it's not available on macOS)
      if command -v dircolors >/dev/null 2>&1; then
        if [ -r ~/.dir_colors ]; then
          eval "$(dircolors -b ~/.dir_colors)"
        else
          eval "$(dircolors -b)"
        fi
      fi
    '';
    
    # Shell options - globstar and checkjobs require bash 4+
    # On macOS, system bash is 3.2, so we conditionally enable these
    shellOptions = [
      "histappend"
      "checkwinsize"
      "extglob"
    ] ++ lib.optionals (!pkgs.stdenv.isDarwin) [
      # These options require bash 4+ and may not work with macOS system bash 3.2
      # They will work when using Nix bash 5.3+ (via ~/.nix-profile/bin/bash)
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
      # DOCKER_HOST is now set conditionally in WSL configuration only
      # Do not force DISPLAY here — let the desktop/remote session set it.
      # Forcing DISPLAY to :0 breaks apps like VS Code under XRDP or non-:0 seats.
      # Disable OSC color queries - commented out to allow colors
      # NO_COLOR = "";  # Don't set this as it disables colors in many programs

      # Nix single-user mode for containers (harmless on WSL)
      NIX_REMOTE = "";
    } // lib.optionalAttrs pkgs.stdenv.isLinux {
      # SSL Certificate configuration (Linux only)
      # macOS uses its own certificate store
      NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
    } // {

      # AI/LLM API Keys (set these in your environment or use a secrets manager)
      # AVANTE_ANTHROPIC_API_KEY = "your-api-key-here"; # Uncomment and set your Claude API key
      # Or use a command to retrieve from password manager:
      # AVANTE_ANTHROPIC_API_KEY = "$(op read 'op://Private/Anthropic API Key/api_key')"; # Example with 1Password

      # NOTE: BROWSER environment variable is configured in firefox.nix
      # to ensure proper OAuth flows for VSCode GitHub auth, Claude CLI, etc.
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

      # Session management
      klogout = "qdbus org.kde.Shutdown /Shutdown logout";
      session-logout = "qdbus org.kde.Shutdown /Shutdown logout";

      # System reboot with delay (gives time to disconnect from RDP)
      reboot-delayed = "echo 'System will reboot in 10 seconds...' && sleep 10 && sudo systemctl reboot";
      reboot-now = "sudo systemctl reboot";
      
      # Tmux pane information for LLM interaction
      tpane = "tmux display-message -p 'Current pane: #{session_name}:#{window_index}.#{pane_index} | Command: #{pane_current_command} | Path: #{pane_current_path}'";
      tpanes = "tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} → #{pane_current_command} (#{pane_current_path})'";
      tpinfo = "echo -e 'CURRENT PANE:\\n' && tmux display-message -p '  #{session_name}:#{window_index}.#{pane_index} (#{pane_current_command})\\n\\nALL PANES:' && tmux list-panes -a -F '  #{session_name}:#{window_index}.#{pane_index} → #{pane_current_command}'";
      
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
      
      # Platform-specific aliases moved to respective configurations
      
      # 1Password aliases (ops moved to onepassword-plugins.nix for service account)
      opv = "op vault list";
      opi = "op item list";

      # ArgoCD with 1Password
      argo-login = "op plugin init argocd";
      
      # Claude aliases handled by functions in initExtra (for tmux alt-screen)
      
      # Keep short aliases for convenience
      pbcopy = "pbcopy";
      pbpaste = "pbpaste";

      # Plasma config export with analysis
      plasma-export = "/etc/nixos/scripts/plasma-rc2nix.sh";
      plasma-diff = "/etc/nixos/scripts/plasma-diff.sh";
      plasma-diff-summary = "/etc/nixos/scripts/plasma-diff.sh --summary";
    };
    
    initExtra = ''
      # Source nix-darwin environment setup (must be first!)
      # This sets up PATH to include /run/current-system/sw/bin
      if [ -f /etc/bashrc ]; then
        . /etc/bashrc
      fi

      # Check bash version and warn if using old macOS bash
      if [[ "$OSTYPE" == "darwin"* ]] && [[ ''${BASH_VERSINFO[0]:-0} -lt 4 ]]; then
        echo "⚠️  Warning: You're using macOS system bash $BASH_VERSION (very old!)"
        echo "   For full features, use Nix bash: ~/.nix-profile/bin/bash"
        echo "   Or run: export PATH=\"\$HOME/.nix-profile/bin:\$PATH\""
        echo ""
      fi

      # Enable bash 4+ options if available (for old bash compatibility)
      if [[ ''${BASH_VERSINFO[0]:-0} -ge 4 ]]; then
        shopt -s globstar 2>/dev/null || true
        shopt -s checkjobs 2>/dev/null || true
      fi

      # CRITICAL: Source home-manager session variables
      # This is required for all home-manager configurations to work properly
      # especially in KDE where the display manager doesn't source these
      if [ -e "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]; then
        . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
      fi

      # Terminal configuration moved to TERM settings below
      
      # Native Linux Docker configuration (baseline)
      # Ensure we're using the local Docker socket if available
      if [[ -S /var/run/docker.sock ]]; then
        # Clear any incorrect Docker environment variables
        if [[ -n "''${DOCKER_HOST:-}" ]]; then
          unset DOCKER_HOST
        fi
        export DOCKER_HOST=""
      fi
      
      # Fix terminal compatibility - detect VSCode terminal
      if [ "$TERM_PROGRAM" = "vscode" ]; then
        # VSCode terminal specific settings
        export TERM=xterm-256color
        # Disable COLORTERM in VSCode to avoid OSC issues
        unset COLORTERM
        # Disable problematic OSC sequences
        export STARSHIP_DISABLE_ANSI_INJECTION=1
        # Tell applications not to query terminal colors
        export VTE_VERSION="6003"  # Fake VTE version to disable color queries
      elif [[ "$OSTYPE" == "darwin"* ]] && [ -n "$TMUX" ]; then
        # Darwin + tmux color configuration
        #
        # These environment variables prevent OSC color query sequences and
        # ensure proper dark theme detection for AI assistant TUIs:
        #
        # - VTE_VERSION=6003: Disables terminal color detection queries
        #   (prevents ]11;rgb:... sequences from appearing as literal text)
        # - COLORFGBG=15;0: Indicates dark terminal (white fg, black bg)
        #   (prevents yellow background distortion in AI TUIs like Gemini/Claude)
        # - STARSHIP_NO_COLOR_QUERY=1: Disables Starship's color detection
        # - COLORTERM=truecolor: Indicates 24-bit color support
        #
        # See: specs/003-incorporate-this-into/research.md for rationale

        export VTE_VERSION="6003"  # Fake VTE version to disable color queries
        export COLORFGBG="15;0"  # Dark terminal: white fg (15), black bg (0)
        export STARSHIP_NO_COLOR_QUERY=1  # Disable Starship color detection
        export COLORTERM="truecolor"  # 24-bit color support
      else
        # Regular terminal settings - let Konsole set its own TERM
        # Only set TERM if it's not already set properly
        if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
          export TERM=xterm-256color
        fi
        # Keep COLORTERM if set by the terminal
      fi
      
      # Set up a colored prompt when Starship is not available
      # This ensures we always have colors even if Starship fails to load
      if ! command -v starship &> /dev/null; then
        PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
      fi
      
      # Add /usr/local/bin to PATH for Docker Desktop
      export PATH="/usr/local/bin:$PATH"
      
      # Fix DISPLAY for SSH sessions with X11 forwarding
      if [ -n "$SSH_CONNECTION" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        # Check if we have the correct DISPLAY for X11 forwarding
        if xauth list 2>/dev/null | grep -q "unix:10"; then
          export DISPLAY=:10
        fi
      fi
      
      # Terminal configuration handled by tmux settings
      
      # VSCode-specific: reduce terminal artifacts without resetting colors
      if [ "$TERM_PROGRAM" = "vscode" ]; then
        # Avoid RIS (\033c) which can force a light default background
        # Keep control-character echo suppressed
        stty -echoctl 2>/dev/null || true
      fi

      # Claude wrappers: ensure scrollback in tmux by disabling alternate-screen per-window
      __claude_run() {
        local mode="$1"; shift || true
        if [ -n "$TMUX" ]; then
          tmux setw alternate-screen off >/dev/null 2>&1 || true
          tmux setw @altscreen off >/dev/null 2>&1 || true
        fi
        case "$mode" in
          continue) claude --continue --dangerously-skip-permissions "$@" ;;
          resume)   claude --resume   --dangerously-skip-permissions "$@" ;;
          *)        claude              --dangerously-skip-permissions "$@" ;;
        esac
      }
      cc()   { __claude_run continue  "$@"; }
      cr()   { __claude_run resume    "$@"; }
      cdsp() { __claude_run ""        "$@"; }

      # Set up fzf key bindings (only if available)
      if command -v fzf &> /dev/null; then
        eval "$(fzf --bash)" 2>/dev/null || true
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
      # Export the function so it's available in subshells (including tmux)
      export -f sesh_connect
      
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
      
      # Cross-platform clipboard functions (macOS, Wayland, X11)
      pbcopy() {
        local input
        if [ -t 0 ]; then
          input="$*"
        else
          input="$(cat)"
        fi
        # macOS native pbcopy
        if [[ "$OSTYPE" == "darwin"* ]] && command -v pbcopy >/dev/null 2>&1; then
          printf "%s" "$input" | command pbcopy
        # Try Wayland first (KDE Plasma on Hetzner)
        elif command -v wl-copy >/dev/null 2>&1 && [ -n "$WAYLAND_DISPLAY" ]; then
          printf "%s" "$input" | wl-copy --type text/plain 2>/dev/null
        # Fall back to X11
        elif command -v xclip >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
          printf "%s" "$input" | xclip -selection clipboard
        else
          echo "No clipboard utility available" >&2
          return 1
        fi
      }

      pbpaste() {
        # macOS native pbpaste
        if [[ "$OSTYPE" == "darwin"* ]] && command -v pbpaste >/dev/null 2>&1; then
          command pbpaste
        # Try Wayland first (KDE Plasma on Hetzner)
        elif command -v wl-paste >/dev/null 2>&1 && [ -n "$WAYLAND_DISPLAY" ]; then
          wl-paste --no-newline 2>/dev/null
        # Fall back to X11
        elif command -v xclip >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
          xclip -selection clipboard -o
        else
          echo "No clipboard utility available" >&2
          return 1
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
      
      # Initialize Starship prompt (should always be last to override PS1)
      if command -v starship &> /dev/null; then
        export STARSHIP_CONFIG="$HOME/.config/starship.toml"
        eval "$(starship init bash)" 2>/dev/null || true
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

      # Load tmux popup configuration if in tmux
      if [[ -n "$TMUX" ]] && [[ -f ~/.tmux-popups.conf ]]; then
        tmux source-file ~/.tmux-popups.conf 2>/dev/null
      fi
    '';
  };
}

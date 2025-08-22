{ config, pkgs, lib, inputs, ... }:

let
  # Custom package for claude-manager (fetchurl version for GitHub compatibility)
  claude-manager = pkgs.callPackage ./packages/claude-manager-fetchurl.nix { 
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  
  # Custom package for idpbuilder
  idpbuilder = pkgs.stdenv.mkDerivation rec {
    pname = "idpbuilder";
    version = "0.9.1";
    
    src = pkgs.fetchurl {
      url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${version}/idpbuilder-linux-amd64.tar.gz";
      sha256 = "a4f16943ec20c6ad41664ed7ae2986282368daf7827356516f9d6687b830aa09";
    };
    
    sourceRoot = ".";
    
    installPhase = ''
      mkdir -p $out/bin
      cp idpbuilder $out/bin/
      chmod +x $out/bin/idpbuilder
    '';
    
    meta = with lib; {
      description = "Tool for building Internal Developer Platforms with Kubernetes";
      homepage = "https://github.com/cnoe-io/idpbuilder";
      license = licenses.asl20;
      platforms = [ "x86_64-linux" ];
    };
  };
  
  # Modern color palette inspired by Catppuccin Mocha
  colors = {
    # Base colors
    base = "#1e1e2e";
    mantle = "#181825";
    crust = "#11111b";
    
    # Surface colors
    surface0 = "#313244";
    surface1 = "#45475a";
    surface2 = "#585b70";
    
    # Text colors
    text = "#cdd6f4";
    subtext1 = "#bac2de";
    subtext0 = "#a6adc8";
    
    # Main colors
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
  
  # Helper function to create hex color strings for tmux
  mkTmuxColor = color: "colour${color}";
  
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
in
{
  # Home Manager configuration
  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";
  home.stateVersion = "25.05";

  # Core packages
  home.packages = with pkgs; [
    # Core utilities
    tmux
    git
    stow
    fzf
    ripgrep
    fd
    bat  # Better cat with syntax highlighting
    eza  # Better ls with icons
    zoxide  # Smart cd
    sesh # Smart tmux session manager
    yazi # Fast terminal file manager
    
    # Claude Session Manager (local package)
    claude-manager
    
    # Development tools
    gh
    kubectl
    kubernetes-helm  # Kubernetes package manager
    k9s              # Terminal UI for Kubernetes
    kind             # Kubernetes in Docker
    vcluster         # Virtual Kubernetes clusters
    idpbuilder  # Custom package for IDP building
    argocd           # ArgoCD CLI for GitOps
    devspace         # DevSpace CLI for cloud-native development
    deno             # Secure JavaScript/TypeScript runtime
    direnv
    tree
    htop
    btop  # Better htop
    ncdu
    jq
    yq
    gum  # Charm's interactive shell script builder

    # System tools
    # xclip removed - using Windows clipboard via clip.exe in WSL
    file
    which
    curl
    wget
    ncurses  # Terminal utilities (clear, tput, reset, etc.)
  ];

  # Modern shell prompt with Starship - Pure ASCII configuration
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      format = "$username$hostname $directory$git_branch$git_status $kubernetes\n$character ";
      
      palette = "catppuccin_mocha";
      
      palettes.catppuccin_mocha = {
        rosewater = "${colors.rosewater}";
        flamingo = "${colors.flamingo}";
        pink = "${colors.pink}";
        mauve = "${colors.mauve}";
        red = "${colors.red}";
        maroon = "${colors.maroon}";
        peach = "${colors.peach}";
        yellow = "${colors.yellow}";
        green = "${colors.green}";
        teal = "${colors.teal}";
        sky = "${colors.sky}";
        sapphire = "${colors.sapphire}";
        blue = "${colors.blue}";
        lavender = "${colors.lavender}";
        text = "${colors.text}";
        subtext1 = "${colors.subtext1}";
        subtext0 = "${colors.subtext0}";
        overlay2 = "${colors.surface2}";
        overlay1 = "${colors.surface1}";
        overlay0 = "${colors.surface0}";
        surface2 = "${colors.surface2}";
        surface1 = "${colors.surface1}";
        surface0 = "${colors.surface0}";
        base = "${colors.base}";
        mantle = "${colors.mantle}";
        crust = "${colors.crust}";
      };
      
      os = {
        disabled = true;  # Disable OS to avoid encoding issues
        style = "fg:${colors.blue}";
        format = "[$symbol ]($style)";
      };
      
      os.symbols = {
        Ubuntu = "U";
        Debian = "D";
        Linux = "L";
        Arch = "A";
        Fedora = "F";
        Alpine = "Al";
        Amazon = "Am";
        Android = "An";
        Macos = "M";
        Windows = "W";
      };
      
      username = {
        show_always = true;
        style_user = "bold fg:${colors.mauve}";
        style_root = "bold fg:${colors.red}";
        format = "[$user]($style)";
      };
      
      hostname = {
        ssh_only = false;
        style = "fg:${colors.blue}";
        format = "@[$hostname]($style)";
        trim_at = "-";
      };
      
      directory = {
        style = "bold fg:${colors.green}";
        format = "[$path]($style)";
        truncation_length = 3;
        truncation_symbol = "…/";
        home_symbol = "~";
      };
      
      directory.substitutions = {
        "Documents" = "D";
        "Downloads" = "DL";
        "Music" = "M";
        "Pictures" = "P";
        "Developer" = "DEV";
      };
      
      git_branch = {
        symbol = "⎇";
        style = "fg:${colors.yellow}";
        format = " [$symbol $branch]($style)";
      };
      
      git_status = {
        style = "fg:${colors.yellow}";
        format = "[$all_status$ahead_behind]($style)";
        conflicted = "=";
        ahead = "⇡";
        behind = "⇣";
        diverged = "⇕";
        untracked = "?";
        modified = "!";
        renamed = "»";
        deleted = "✘";
        stashed = "\\$";
        staged = "+";
        typechanged = "±";
      };
      
      nodejs = {
        symbol = "⬢";
        style = "fg:${colors.green}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["js" "mjs" "cjs" "ts" "tsx"];
        detect_files = ["package.json" ".node-version"];
        detect_folders = ["node_modules"];
      };
      
      c = {
        symbol = "C";
        style = "fg:${colors.green}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["c" "h"];
      };
      
      rust = {
        symbol = "R";
        style = "fg:${colors.peach}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["rs"];
        detect_files = ["Cargo.toml" "Cargo.lock"];
      };
      
      golang = {
        symbol = "GO";
        style = "fg:${colors.sapphire}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["go"];
        detect_files = ["go.mod" "go.sum" "glide.yaml" "Gopkg.yml" "Gopkg.lock"];
      };
      
      php = {
        symbol = "PHP";
        style = "fg:${colors.lavender}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["php"];
        detect_files = ["composer.json" ".php-version"];
      };
      
      java = {
        symbol = "J";
        style = "fg:${colors.peach}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["java" "class" "jar"];
        detect_files = ["pom.xml" "build.gradle.kts" "build.sbt"];
      };
      
      kotlin = {
        symbol = "K";
        style = "fg:${colors.lavender}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["kt" "kts"];
      };
      
      haskell = {
        symbol = "λ";
        style = "fg:${colors.mauve}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["hs" "lhs"];
        detect_files = ["stack.yaml" "cabal.project"];
      };
      
      python = {
        symbol = "PY";
        style = "fg:${colors.yellow}";
        format = " [$symbol]($style)";
        disabled = false;
        detect_extensions = ["py"];
        detect_files = ["requirements.txt" "pyproject.toml" "Pipfile" "setup.py"];
        detect_folders = ["__pycache__" ".venv" "venv"];
      };
      
      docker_context = {
        symbol = "D";
        style = "fg:${colors.blue}";
        format = " [$symbol]($style)";
        only_with_files = true;
        detect_files = ["docker-compose.yml" "docker-compose.yaml" "Dockerfile"];
        disabled = false;
      };
      
      kubernetes = {
        symbol = "☸";
        style = "fg:${colors.sapphire}";
        format = " [$symbol $context]($style)";
        disabled = false;
        # Define shorter aliases for long context names
        contexts = [
          { context_pattern = "vcluster_.*_kind-localdev"; context_alias = "vcluster"; }
          { context_pattern = "arn:aws:eks:.*:cluster/(.*)"; context_alias = "$1"; }
          { context_pattern = "gke_.*_(?P<cluster>[\\w-]+)"; context_alias = "gke-$cluster"; }
          { context_pattern = "(.{15}).*"; context_alias = "$1..."; }  # Truncate to 15 chars
        ];
      };
      
      fill = {
        symbol = " ";
      };
      
      time = {
        disabled = true;
        time_format = "%H:%M";
        style = "fg:${colors.subtext0}";
        format = "[$time]($style)";
      };
      
      cmd_duration = {
        min_time = 2000;
        style = "fg:${colors.yellow}";
        format = "[took $duration]($style)";
      };
      
      character = {
        success_symbol = "[➜](bold fg:${colors.green})";
        error_symbol = "[➜](bold fg:${colors.red})";
        vimcmd_symbol = "[❮](bold fg:${colors.green})";
      };
    };
  };

  # Bash configuration
  programs.bash = {
    enable = true;
    historyControl = [ "ignoreboth" ];
    historySize = 10000;
    historyFileSize = 20000;
    
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
    };
    
    shellAliases = {
      # Navigation with zoxide
      cd = "z";  # Use zoxide for cd command
      cdd = "command cd";  # Original cd available as cdd
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
      
      # WSL clipboard helpers
      clip = "/mnt/c/Windows/System32/clip.exe";
      paste = "powershell.exe -command 'Get-Clipboard' | head -c -2";
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
      else
        # Regular terminal settings - use screen-256color to match tmux
        export TERM=screen-256color
        # Don't set COLORTERM to avoid OSC queries
        unset COLORTERM
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
      
      # Set up fzf key bindings
      if command -v fzf &> /dev/null; then
        eval "$(fzf --bash)"
      fi
      
      # 1Password Shell Plugins
      if [ -f ~/.config/op/plugins.sh ]; then
        source ~/.config/op/plugins.sh
      fi
      
      # Enable direnv
      eval "$(direnv hook bash)"
      
      # Better history search
      bind '"\e[A": history-search-backward'
      bind '"\e[B": history-search-forward'
      
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
      
      # Initialize zoxide at the very end to avoid configuration issues
      eval "$(zoxide init bash)"
      
      # Disable zoxide doctor warnings since we've properly initialized it
      export _ZO_DOCTOR=0
    '';
  };

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Vinod Pittampalli";
    userEmail = "vinod@pittampalli.com";
    
    aliases = {
      co = "checkout";
      ci = "commit";
      st = "status";
      br = "branch";
      hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";
      type = "cat-file -t";
      dump = "cat-file -p";
    };
    
    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "nvim";
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = false;
      
      credential = {
        "https://github.com" = {
          helper = "!gh auth git-credential";
        };
        "https://gist.github.com" = {
          helper = "!gh auth git-credential";
        };
        helper = "/mnt/c/Program\\ Files/Git/mingw64/bin/git-credential-manager.exe";
      };
      
    };
  };
  
  # SSH configuration with 1Password integration
  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host *
        IdentityAgent ~/.1password/agent.sock
    '';
  };
      
  # Tmux configuration
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
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
      set -g default-terminal "screen-256color"
      set -ga terminal-overrides ",*256col*:Tc"
      set -sg escape-time 0
      set -g focus-events off  # Disable to prevent [O[I escape sequences in WSL
      set -g detach-on-destroy off  # don't exit from tmux when closing a session
      set -g repeat-time 1000
      
      # Enable passthrough for terminal escape sequences
      set -g allow-passthrough on
      
      # Disable OSC sequences and bracketed paste to prevent escape sequence issues
      set -as terminal-overrides ',*:Ms@'  # Disable OSC 52 clipboard
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
      set -g status-left "#{?client_prefix,#[fg=${colors.crust}#,bg=${colors.red}#,bold] ⚡ PREFIX #[fg=${colors.red}#,bg=${colors.mauve}],#{?pane_in_mode,#[fg=${colors.crust}#,bg=${colors.yellow}#,bold]  COPY #[fg=${colors.yellow}#,bg=${colors.mauve}],#{?window_zoomed_flag,#[fg=${colors.crust}#,bg=${colors.peach}#,bold] 🔍 ZOOM #[fg=${colors.peach}#,bg=${colors.mauve}],#[fg=${colors.crust}#,bg=${colors.green}#,bold] ◉ TMUX #[fg=${colors.green}#,bg=${colors.mauve}]}}}#[fg=${colors.crust},bg=${colors.mauve},bold]  #S #[fg=${colors.mauve},bg=${colors.surface1}]#[fg=${colors.text},bg=${colors.surface1}]  #(tmux ls | wc -l)S \ue0b1 #{session_windows}W #[fg=${colors.surface1},bg=${colors.crust}] "
      
      # Right status with development info
      set -g status-right "#[fg=${colors.surface0},bg=${colors.crust}]#[fg=${colors.text},bg=${colors.surface0}]  #{window_panes} #[fg=${colors.surface1},bg=${colors.surface0}]#[fg=${colors.text},bg=${colors.surface1}]  #(git branch --show-current 2>/dev/null || echo 'no-git') #[fg=${colors.surface2},bg=${colors.surface1}]#[fg=${colors.text},bg=${colors.surface2}] ☸ #(kubectl config current-context 2>/dev/null | cut -d'/' -f2 | cut -c1-10 || echo 'none') #[fg=${colors.blue},bg=${colors.surface2}]#[fg=${colors.crust},bg=${colors.blue},bold] 🐳 #(docker ps -q 2>/dev/null | wc -l || echo '0') "
      
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
      
      # Claude session selector popup
      bind c display-popup -E \
        -w 90% -h 90% \
        -T " 🤖 Claude Session Selector (ESC to close) " \
        -d "#{pane_current_path}" \
        -e TERM=xterm-256color \
        -e COLORTERM=truecolor \
        "/home/vpittamp/claude-popup-selector.sh"
      
      # Quick Claude commands
      bind C display-popup -E -w 80% -h 80% "claude"
      bind R display-popup -E -w 80% -h 80% "claude --continue"
      
      
      # Copy mode
      bind Enter copy-mode
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
      # Use full path to clip.exe for WSL clipboard integration
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel '/mnt/c/Windows/System32/clip.exe'
      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi H send-keys -X start-of-line
      bind -T copy-mode-vi L send-keys -X end-of-line
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel '/mnt/c/Windows/System32/clip.exe'
      
      # Paste from Windows clipboard (Prefix + p)
      bind p run-shell 'powershell.exe -command "Get-Clipboard" | head -c -2 | tmux load-buffer - && tmux paste-buffer'
    '';
  };

  # Neovim configuration
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    
    extraConfig = ''
      set number relativenumber
      set expandtab
      set tabstop=2
      set shiftwidth=2
      set smartindent
      set termguicolors
      set signcolumn=yes
      set colorcolumn=80
      set scrolloff=8
      set updatetime=50
      
      " Better search
      set ignorecase
      set smartcase
      set incsearch
      set hlsearch
      
      " Key mappings
      let mapleader = " "
      nnoremap <leader>w :w<CR>
      nnoremap <leader>q :q<CR>
      nnoremap <leader>h :nohlsearch<CR>
      
      " Better navigation
      nnoremap <C-h> <C-w>h
      nnoremap <C-j> <C-w>j
      nnoremap <C-k> <C-w>k
      nnoremap <C-l> <C-w>l
    '';
    
    plugins = with pkgs.vimPlugins; [
      # Theme
      tokyonight-nvim
      
      # Essential
      plenary-nvim
      telescope-nvim
      nvim-treesitter.withAllGrammars
      
      # Telescope extensions and dependencies
      telescope-fzy-native-nvim
      telescope-live-grep-args-nvim
      telescope-undo-nvim
      nvim-neoclip-lua
      
      # File tree
      nvim-tree-lua
      
      # Status line
      lualine-nvim
      
      # Git
      gitsigns-nvim
      vim-fugitive
      
      # LSP and completion
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      luasnip
      
      # AI assistance
      claude-code-nvim
      
      # Quality of life
      comment-nvim
      nvim-autopairs
      indent-blankline-nvim
    ];
    
    extraLuaConfig = ''
      -- Set colorscheme
      vim.cmd.colorscheme "tokyonight-night"
      
      -- Use system clipboard by default
      vim.opt.clipboard = "unnamedplus"
      
      -- Lualine
      require('lualine').setup {
        options = { theme = 'tokyonight' }
      }
      
      -- Gitsigns
      require('gitsigns').setup()
      
      -- Comment
      require('Comment').setup()
      
      -- Autopairs
      require('nvim-autopairs').setup()
      
      -- Indent blankline
      require('ibl').setup()
      
      -- Claude Code AI assistant
      require('claude-code').setup({
        -- Use default settings for now
        keymaps = {
          toggle = {
            normal = "<C-,>",       -- Normal mode keymap
            terminal = "<C-,>",     -- Terminal mode keymap
          },
        },
      })
      
      -- Telescope configuration
      local telescope = require('telescope')
      local builtin = require('telescope.builtin')
      
      telescope.setup({
        defaults = {
          border = true,
          file_ignore_patterns = { '.git/', 'node_modules' },
          layout_config = {
            height = 0.9999999,
            width = 0.99999999,
            preview_cutoff = 0,
            horizontal = { preview_width = 0.60 },
            vertical = { width = 0.999, height = 0.9999, preview_cutoff = 0 },
            prompt_position = 'top',
          },
          path_display = { 'smart' },
          prompt_position = 'top',
          prompt_prefix = ' ',
          selection_caret = '👉',
          sorting_strategy = 'ascending',
          vimgrep_arguments = {
            'rg',
            '--color=never',
            '--no-heading',
            '--hidden',
            '--with-filename',
            '--line-number',
            '--column',
            '--smart-case',
            '--trim',
          },
        },
        pickers = {
          buffers = {
            prompt_prefix = '󰸩 ',
          },
          commands = {
            prompt_prefix = ' ',
            layout_config = {
              height = 0.99,
              width = 0.99,
            },
          },
          command_history = {
            prompt_prefix = ' ',
            layout_config = {
              height = 0.99,
              width = 0.99,
            },
          },
          git_files = {
            prompt_prefix = '󰊢 ',
            show_untracked = true,
          },
          find_files = {
            prompt_prefix = ' ',
            find_command = { 'fd', '-H' },
            layout_config = {
              height = 0.999,
              width = 0.999,
            },
          },
          live_grep = {
            prompt_prefix = '󰱽 ',
          },
          grep_string = {
            prompt_prefix = '󰱽 ',
          },
        },
        extensions = {
          smart_open = {
            cwd_only = true,
            filename_first = true,
          },
        },
      })
      
      -- Load Telescope extensions
      telescope.load_extension('live_grep_args')
      telescope.load_extension('neoclip')
      telescope.load_extension('undo')
      telescope.load_extension('fzy_native')
      
      -- Telescope keybindings
      vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find files' })
      vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Live grep' })
      vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Buffers' })
      vim.keymap.set('n', '<leader>*', builtin.grep_string, { desc = 'Grep word under cursor' })
      vim.keymap.set('n', '<leader>.', builtin.resume, { desc = 'Resume Telescope' })
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Help tags' })
      vim.keymap.set('n', '<leader>fc', builtin.commands, { desc = 'Commands' })
      vim.keymap.set('n', '<leader>fu', '<cmd>Telescope undo<cr>', { desc = 'Undo tree' })
      vim.keymap.set('n', '<leader>fy', '<cmd>Telescope neoclip<cr>', { desc = 'Clipboard history' })
      vim.keymap.set('n', '<leader>fl', '<cmd>Telescope live_grep_args live_grep_args<cr>', { desc = 'Live grep with args' })
      
      -- Nvim-tree
      require('nvim-tree').setup()
      vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', {})
    '';
  };

  # Bat configuration (better cat)
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
      style = "numbers,changes,header";
    };
  };

  # Direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # FZF
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--inline-info"
      "--color=bg+:${colors.surface0},bg:${colors.base},spinner:${colors.rosewater},hl:${colors.red}"
      "--color=fg:${colors.text},header:${colors.red},info:${colors.mauve},pointer:${colors.rosewater}"
      "--color=marker:${colors.rosewater},fg+:${colors.text},prompt:${colors.mauve},hl+:${colors.red}"
    ];
  };

  # Sesh configuration file
  xdg.configFile."sesh/sesh.toml".text = ''
    # Sesh Configuration File
    # Smart tmux session manager configuration

    # Sort order for session types
    sort_order = [
        "tmux",        # Show existing tmux sessions first
        "config",      # Then config sessions (Nix presets)
        "tmuxinator",  # Then tmuxinator sessions
        "zoxide"       # Finally zoxide directories
    ]

    # Default session configuration
    [default_session]
    # Open nvim with telescope on session start
    startup_command = "nvim -c ':Telescope find_files'"
    # Show directory contents with eza when previewing
    preview_command = "eza --all --git --icons --color=always --group-directories-first --long {}"

    # Nix Configuration Sessions
    [[session]]
    name = "nix-config 🔧"
    path = "/etc/nixos"
    startup_command = "nvim configuration.nix"
    preview_command = "bat --color=always /etc/nixos/configuration.nix"

    [[session]]
    name = "nix-home 🏠"
    path = "/etc/nixos"
    startup_command = "nvim home-vpittamp.nix"
    preview_command = "bat --color=always /etc/nixos/home-vpittamp.nix"

    [[session]]
    name = "nix-flake ❄️"
    path = "/etc/nixos"
    startup_command = "nvim flake.nix"
    preview_command = "bat --color=always /etc/nixos/flake.nix"

    # Quick edit session for all Nix configs
    [[session]]
    name = "nix-all 📦"
    path = "/etc/nixos"
    startup_command = ""
    # preview_command = "eza --all --git --icons --color=always --group-directories-first /etc/nixos"
    # windows = [ "git", "build" ]

    # Window definitions for multi-window sessions
    [[window]]
    name = "git"
    startup_command = "git status && git diff"

    [[window]]
    name = "build"
    startup_command = "echo 'Ready to rebuild: sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl'"

    # Development Sessions
    [[session]]
    name = "workspace 💻"
    path = "~/workspace"
    startup_command = "nvim"
    preview_command = "eza --all --git --icons --color=always --group-directories-first {}"

    [[session]]
    name = "dotfiles 📝"
    path = "~/.config"
    startup_command = "nvim"
    preview_command = "eza --all --git --icons --color=always --group-directories-first {}"

    # Kubernetes/Container Sessions
    [[session]]
    name = "k8s-dev ☸️"
    path = "~/k8s"
    startup_command = "k9s"
    preview_command = "kubectl get pods --all-namespaces 2>/dev/null || echo 'No cluster connected'"

    # Blacklist - sessions to hide from results
    # Uncomment to enable
    # blacklist = ["scratch", "tmp"]
  '';

  # Yazi file manager configuration
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    
    settings = {
      mgr = {
        ratio = [1 1 4];
        sort_by = "mtime";
        sort_sensitive = true;
        sort_reverse = true;
        sort_dir_first = true;
        linemode = "none";
        show_hidden = true;
        show_symlink = true;
      };
      
      preview = {
        tab_size = 2;
        max_width = 2000;
        max_height = 1200;
        cache_dir = "";
        ueberzug_scale = 1;
        ueberzug_offset = [0 0 0 0];
      };
      
      opener = {
        edit = [
          { run = "\${EDITOR:-nvim} \"$@\""; block = true; for = "unix"; }
        ];
        open = [
          { run = "xdg-open \"$@\""; desc = "Open"; for = "linux"; }
        ];
        reveal = [
          { run = "exiftool \"$1\"; echo \"Press enter to exit\"; read"; block = true; desc = "Show EXIF"; for = "unix"; }
        ];
        extract = [
          { run = "unar \"$1\""; desc = "Extract here"; for = "unix"; }
        ];
        play = [
          { run = "mpv \"$@\""; orphan = true; for = "unix"; }
          { run = "mediainfo \"$1\"; echo \"Press enter to exit\"; read"; block = true; desc = "Show media info"; for = "unix"; }
        ];
      };
      
      open = {
        rules = [
          { name = "*/"; use = ["edit" "open" "reveal"]; }
          { mime = "text/*"; use = ["edit" "reveal"]; }
          { mime = "image/*"; use = ["open" "reveal"]; }
          { mime = "video/*"; use = ["play" "reveal"]; }
          { mime = "audio/*"; use = ["play" "reveal"]; }
          { mime = "inode/empty"; use = ["edit" "reveal"]; }
          { mime = "application/json"; use = ["edit" "reveal"]; }
          { mime = "*/javascript"; use = ["edit" "reveal"]; }
          { mime = "application/zip"; use = ["extract" "reveal"]; }
          { mime = "application/gzip"; use = ["extract" "reveal"]; }
          { mime = "application/tar"; use = ["extract" "reveal"]; }
          { mime = "application/bzip"; use = ["extract" "reveal"]; }
          { mime = "application/bzip2"; use = ["extract" "reveal"]; }
          { mime = "application/7z-compressed"; use = ["extract" "reveal"]; }
          { mime = "application/rar"; use = ["extract" "reveal"]; }
          { mime = "*"; use = ["open" "reveal"]; }
        ];
      };
      
      tasks = {
        micro_workers = 5;
        macro_workers = 10;
        bizarre_retry = 5;
      };
      
      log = {
        enabled = false;
      };
    };
    
    # VSCode Dark Modern theme configuration
    theme = {
      manager = {
        cwd = { fg = "#569cd6"; };
        
        # Hovered
        hovered = { fg = "#000000"; bg = "#b8d7f3"; };
        preview_hovered = { underline = true; };
        
        # Find
        find_keyword = { fg = "#f9826c"; italic = true; };
        find_position = { fg = "#cccccc"; bg = "#3a3f4b"; italic = true; };
        
        # Marker
        marker_selected = { fg = "#b8d7f3"; bg = "#3c5d80"; };
        marker_copied = { fg = "#b8d7f3"; bg = "#487844"; };
        marker_cut = { fg = "#b8d7f3"; bg = "#d47766"; };
        
        # Tab
        tab_active = { fg = "#000000"; bg = "#569cd6"; };
        tab_inactive = { fg = "#cccccc"; bg = "#3c3c3c"; };
        tab_width = 1;
        
        # Border
        border_symbol = "│";
        border_style = { fg = "#3e3e3e"; };
        
        # Highlighting
        syntect_theme = "";
      };
      
      status = {
        separator_style = { fg = "#4e4e4e"; bg = "#252526"; };
        mode_normal = { fg = "#000000"; bg = "#569cd6"; bold = true; };
        mode_select = { fg = "#000000"; bg = "#c586c0"; bold = true; };
        mode_unset = { fg = "#000000"; bg = "#d7ba7d"; bold = true; };
        
        progress_label = { fg = "#ffffff"; bold = true; };
        progress_normal = { fg = "#569cd6"; bg = "#252526"; };
        progress_error = { fg = "#f44747"; bg = "#252526"; };
        
        permissions_t = { fg = "#569cd6"; };
        permissions_r = { fg = "#d7ba7d"; };
        permissions_w = { fg = "#f44747"; };
        permissions_x = { fg = "#b5cea8"; };
        permissions_s = { fg = "#c586c0"; };
      };
      
      input = {
        border = { fg = "#569cd6"; };
        title = {};
        value = {};
        selected = { reversed = true; };
      };
      
      select = {
        border = { fg = "#569cd6"; };
        active = { fg = "#c586c0"; };
        inactive = {};
      };
      
      tasks = {
        border = { fg = "#569cd6"; };
        title = {};
        hovered = { underline = true; };
      };
      
      which = {
        mask = { bg = "#1e1e1e"; };
        cand = { fg = "#9cdcfe"; };
        rest = { fg = "#808080"; };
        desc = { fg = "#c586c0"; };
        separator = " ";
        separator_style = { fg = "#4e4e4e"; };
      };
      
      help = {
        on = { fg = "#c586c0"; };
        exec = { fg = "#9cdcfe"; };
        desc = { fg = "#808080"; };
        hovered = { bg = "#3c5d80"; bold = true; };
        footer = { fg = "#252526"; bg = "#cccccc"; };
      };
      
      filetype = {
        rules = [
          # Images
          { mime = "image/*"; fg = "#c586c0"; }
          
          # Videos
          { mime = "video/*"; fg = "#d7ba7d"; }
          
          # Audio
          { mime = "audio/*"; fg = "#d7ba7d"; }
          
          # Archives
          { mime = "application/zip"; fg = "#f14c4c"; }
          { mime = "application/gzip"; fg = "#f14c4c"; }
          { mime = "application/x-tar"; fg = "#f14c4c"; }
          { mime = "application/x-bzip"; fg = "#f14c4c"; }
          { mime = "application/x-bzip2"; fg = "#f14c4c"; }
          { mime = "application/x-7z-compressed"; fg = "#f14c4c"; }
          { mime = "application/x-rar"; fg = "#f14c4c"; }
          
          # Fallback
          { name = "*"; fg = "#cccccc"; }
          { name = "*/"; fg = "#569cd6"; }
        ];
      };
      
      icon = {
        rules = [
          # Programming
          { name = "*.c"; text = ""; }
          { name = "*.cpp"; text = ""; }
          { name = "*.h"; text = ""; }
          { name = "*.hpp"; text = ""; }
          { name = "*.rs"; text = ""; }
          { name = "*.go"; text = ""; }
          { name = "*.py"; text = ""; }
          { name = "*.js"; text = ""; }
          { name = "*.jsx"; text = "⚛"; }
          { name = "*.ts"; text = ""; }
          { name = "*.tsx"; text = "⚛"; }
          { name = "*.vue"; text = "﵂"; }
          { name = "*.json"; text = ""; }
          { name = "*.toml"; text = ""; }
          { name = "*.yaml"; text = ""; }
          { name = "*.yml"; text = ""; }
          { name = "*.nix"; text = ""; }
          
          # Text
          { name = "*.txt"; text = ""; }
          { name = "*.md"; text = ""; }
          
          # Archives
          { name = "*.zip"; text = ""; }
          { name = "*.tar"; text = ""; }
          { name = "*.gz"; text = ""; }
          { name = "*.7z"; text = ""; }
          { name = "*.bz2"; text = ""; }
          
          # Default
          { name = "*"; text = ""; }
          { name = "*/"; text = ""; }
        ];
      };
    };
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}

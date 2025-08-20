{ config, pkgs, lib, ... }:

let
  # Determine the host platform
  isLinux  = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
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
in
{
  # Home Manager configuration
  # Set username and home directory based on the platform
  home.username = if isDarwin then "vinodpittampalli" else "vpittamp";
  home.homeDirectory = if isDarwin then "/Users/vinodpittampalli" else "/home/vpittamp";
  home.stateVersion = "25.05";

  # Core packages (install idpbuilder only on Linux)
  home.packages = with pkgs;
    (
      [
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

        # Development tools
        gh
        kubectl
        kubernetes-helm  # Kubernetes package manager
        kind             # Kubernetes in Docker
        vcluster         # Virtual Kubernetes clusters
        direnv
        tree
        htop
        btop  # Better htop
        ncdu
        jq
        yq
        gum  # Charm's interactive shell script builder

        # System tools
        xclip
        file
        which
        curl
        wget
      ]
    ) ++ (lib.optionals isLinux [ idpbuilder ]);

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
      TERM = "xterm-256color";
    }
    // (lib.optionalAttrs isLinux {
      # Only set the Docker socket on Linux/WSL
      DOCKER_HOST = "unix:///mnt/wsl/docker-desktop/shared-sockets/guest-services/docker.proxy.sock";
    });
    
    shellAliases = {
      # Navigation
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
      
      # WSL specific
      winhome = "cd /mnt/c/Users/VinodPittampalli/";
    };
    
    initExtra = ''
      # Fix terminal compatibility
      export TERM=xterm-256color
      export COLORTERM=truecolor
      
      # Add /usr/local/bin to PATH for Docker Desktop
      export PATH="/usr/local/bin:$PATH"
      
      # Disable OSC sequences that might cause issues
      export STARSHIP_DISABLE_ANSI_INJECTION=1
      
      # Better cd with zoxide
      eval "$(zoxide init bash)"
      
      # Set up fzf key bindings
      if command -v fzf &> /dev/null; then
        eval "$(fzf --bash)"
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
      set -g focus-events on
      set -g detach-on-destroy off  # don't exit from tmux when closing a session
      set -g repeat-time 1000
      
      # Pane settings
      set -g pane-base-index 1
      set -g renumber-windows on
      set -g pane-border-lines single
      set -g pane-border-status off
      set -g pane-border-format " #{?pane_active,#[fg=${colors.subtext0}],#[fg=${colors.surface1}]}#{pane_index} "
      
      # Automatic window renaming based on current directory
      set -g automatic-rename on
      set -g automatic-rename-format '#{b:pane_current_path}'
      
      # Status bar styling
      set -g status-position bottom
      set -g status-justify left
      set -g status-style "bg=${colors.base} fg=${colors.text}"
      set -g status-left-length 40
      set -g status-right-length 100
      
      # Left status with mode indicator
      set -g status-left "#{?client_prefix,#[fg=${colors.crust}#,bg=${colors.red}#,bold] PREFIX ,#{?pane_in_mode,#[fg=${colors.crust}#,bg=${colors.yellow}#,bold] COPY ,#[fg=${colors.crust}#,bg=${colors.green}#,bold] TMUX }}#[fg=${colors.crust},bg=${colors.mauve},bold] #S #[fg=${colors.mauve},bg=${colors.base}] "
      
      # Right status (clean, no powerline)
      set -g status-right "#[fg=${colors.text},bg=${colors.surface1}] %H:%M #[fg=${colors.text},bg=${colors.surface2}] %d-%b #[fg=${colors.crust},bg=${colors.blue},bold] #h "
      
      # Window status (clean rectangles)
      set -g window-status-format "#[fg=${colors.text},bg=${colors.surface0}] #I:#W "
      set -g window-status-current-format "#[fg=${colors.crust},bg=${colors.blue},bold] #I:#W "
      set -g window-status-separator " "
      
      # Pane borders
      set -g pane-border-style "fg=${colors.surface0}"
      set -g pane-active-border-style "fg=${colors.blue},bold"
      
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
      bind -N "last-session (via sesh)" L run-shell "sesh last"
      bind-key "T" run-shell "sesh connect \"\$(sesh list --icons | fzf-tmux -p 80%,70% --no-sort --ansi --border-label ' sesh ' --prompt '⚡  ' --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' --bind 'tab:down,btab:up' --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons)' --preview-window 'right:55%' --preview 'sesh preview {}')\""
      
      # Sesh with gum for quick session switching
      bind-key "K" display-popup -E -w 40% "sesh connect \"\$(sesh list -i | gum filter --limit 1 --no-sort --fuzzy --placeholder 'Pick a sesh' --height 50 --prompt='⚡')\""
      
      # Claude popup windows
      bind C display-popup -E -w 80% -h 80% "claude"
      bind R display-popup -E -w 80% -h 80% "claude --continue"
      
      # Generic popup for running commands
      bind p command-prompt -p "Command:" "display-popup -E -w 90% -h 90% '%%'"
      
      # Copy mode
      bind Enter copy-mode
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'xclip -in -selection clipboard'
      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi H send-keys -X start-of-line
      bind -T copy-mode-vi L send-keys -X end-of-line
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'xclip -in -selection clipboard'
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
      
      # Quality of life
      comment-nvim
      nvim-autopairs
      indent-blankline-nvim
    ];
    
    extraLuaConfig = ''
      -- Set colorscheme
      vim.cmd.colorscheme "tokyonight-night"
      
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
      
      -- Telescope
      local builtin = require('telescope.builtin')
      vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
      vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
      vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
      
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

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}

{ config, pkgs, lib, ... }:

let
  # Import user packages
  userPackages = import ./packages.nix { inherit pkgs lib; };
  
  # Select package profile based on environment variable
  packageProfile = 
    let prof = builtins.getEnv "CONTAINER_PROFILE";
    in if prof == "minimal" then userPackages.minimal
       else if prof == "development" then userPackages.development
       else userPackages.essential;  # default to essential
in
{
  # Import the starship configuration
  imports = [ ./container-starship.nix ];

  # Basic home configuration
  home.username = builtins.getEnv "USER";
  home.homeDirectory = builtins.getEnv "HOME";
  home.stateVersion = "24.05";
  
  # Install user packages
  home.packages = packageProfile;
  
  # Enable home-manager
  programs.home-manager.enable = true;
  
  # Git configuration
  programs.git = {
    enable = true;
    userName = "Container User";
    userEmail = "user@container.local";
    
    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      
      # Better diffs
      diff.algorithm = "histogram";
      merge.conflictStyle = "zdiff3";
      
      # Aliases
      alias = {
        st = "status -sb";
        co = "checkout";
        br = "branch";
        ci = "commit";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        visual = "!gitk";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      };
    };
  };
  
  # Bash configuration with prompt
  programs.bash = {
    enable = true;
    enableCompletion = true;
    
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      PAGER = "less";
      LESS = "-R";
    };
    
    shellAliases = {
      ll = "ls -l";
      la = "ls -la";
      ".." = "cd ..";
      "..." = "cd ../..";
      
      # Use eza if available
      ls = "eza --icons=auto";
      l = "eza -l --icons=auto";
      tree = "eza --tree --icons=auto";
      
      # Git shortcuts
      g = "git";
      gs = "git status";
      gp = "git pull";
      gc = "git commit";
      ga = "git add";
      
      # Nix shortcuts
      hm = "home-manager";
      hms = "home-manager switch --impure";
      hme = "home-manager edit";
      hmn = "home-manager news";
    };
    
    initExtra = ''
      # Better history
      export HISTCONTROL=ignoredups:erasedups
      export HISTSIZE=10000
      export HISTFILESIZE=10000
      shopt -s histappend
      
      # Better directory navigation
      shopt -s autocd
      shopt -s cdspell
      shopt -s dirspell
      
      # Enable ** for recursive globbing
      shopt -s globstar
      
      # Update window size after each command
      shopt -s checkwinsize
      
      # Colored GCC warnings and errors
      export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
      
      # Set up fzf key bindings and fuzzy completion
      if command -v fzf >/dev/null 2>&1; then
        eval "$(fzf --bash)"
      fi
      
      # Initialize zoxide for better cd
      if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init bash)"
        alias cd="z"
      fi
      
      # Create a simple function to switch profiles
      switch-profile() {
        local profile="$1"
        if [[ -z "$profile" ]]; then
          echo "Usage: switch-profile [minimal|essential|development]"
          echo "Current profile: ''${CONTAINER_PROFILE:-essential}"
          return 1
        fi
        export CONTAINER_PROFILE="$profile"
        home-manager switch --impure
      }
    '';
  };
  
  # Tmux configuration
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    historyLimit = 10000;
    keyMode = "vi";
    
    extraConfig = ''
      # Better prefix key
      unbind C-b
      set -g prefix C-a
      bind C-a send-prefix
      
      # Split panes with | and -
      bind | split-window -h
      bind - split-window -v
      
      # Vim-style pane navigation
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      
      # Enable mouse
      set -g mouse on
      
      # Status bar
      set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
      set -g status-left '#[fg=#89b4fa,bold] #S '
      set -g status-right '#[fg=#f9e2af] %H:%M '
      
      # Active pane border
      set -g pane-active-border-style 'fg=#89b4fa'
    '';
  };
  
  # Neovim configuration - better than vim, no conflicts
  programs.neovim = {
    enable = true;
    viAlias = true;    # vim command runs neovim
    vimAlias = true;   # vi command runs neovim
    defaultEditor = true;
    plugins = []; # Start with no plugins to avoid permission issues
    extraConfig = ''
      " Basic settings
      set number
      set relativenumber
      set expandtab
      set shiftwidth=2
      set tabstop=2
      
      " Enable syntax highlighting
      syntax enable
      
      " Better search
      set ignorecase
      set smartcase
      set incsearch
      set hlsearch
      
      " Show matching brackets
      set showmatch
      
      " Enable mouse
      set mouse=a
      
      " Better colors for dark terminals
      set background=dark
      
      " Status line always visible
      set laststatus=2
      
      " Basic status line
      set statusline=%F%m%r%h%w\ [%{&ff}]\ [%Y]\ [%l,%v][%p%%]
    '';
  };
  
  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableBashIntegration = true;
  };
  
  # FZF for fuzzy finding
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--inline-info"
      "--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8"
      "--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc"
      "--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
    ];
  };
  
  # Bat (better cat)
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
      style = "numbers,changes";
    };
  };
  
  # Zoxide (better cd)
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };
  
  # Eza (better ls)  
  programs.eza = {
    enable = true;
    enableBashIntegration = true;
    icons = "auto";
    git = true;
  };
  
  # Ripgrep configuration
  programs.ripgrep = {
    enable = true;
    arguments = [
      "--max-columns=150"
      "--max-columns-preview"
      "--smart-case"
    ];
  };
}
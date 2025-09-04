# Minimal container configuration that avoids all build issues
{ config, pkgs, lib, ... }:

let
  userPackages = import ./packages.nix { inherit pkgs lib; };
in
{
  # Import configurations
  imports = [ 
    ./container-starship.nix
    ./container-neovim.nix  # Our build-free neovim config
  ];

  # Basic home configuration
  # These can be overridden in the flake
  home.username = lib.mkDefault (
    let user = builtins.getEnv "USER";
    in if user != "" then user else "user"
  );
  home.homeDirectory = lib.mkDefault (
    let home = builtins.getEnv "HOME";
    in if home != "" then home else "/home/user"
  );
  home.stateVersion = "24.05";
  
  # Essential packages only - no vim/neovim via home.packages
  home.packages = with pkgs; [
    # Core tools
    git
    curl
    wget
    tmux
    fzf
    ripgrep
    fd
    bat
    eza
    jq
    yq
    
    # From userPackages
    htop
    tree
    ncdu
  ] ++ (
    # Package profile selection - can be overridden via flake
    let prof = config.home.sessionVariables.CONTAINER_PROFILE or (builtins.getEnv "CONTAINER_PROFILE");
    in if prof == "minimal" then []
       else if prof == "development" then userPackages.development
       else with pkgs; [ yazi yarn ]  # essential extras
  );
  
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
    };
  };
  
  # Bash configuration
  programs.bash = {
    enable = true;
    enableCompletion = true;
    
    shellAliases = {
      # Navigation
      ll = "ls -l";
      la = "ls -la";
      ".." = "cd ..";
      
      # Neovim
      vim = "nvim";
      vi = "nvim";
      
      # Git
      g = "git";
      gs = "git status";
      
      # Use eza
      ls = "eza --icons=auto";
      l = "eza -l --icons=auto";
    };
    
    initExtra = ''
      # Set editor if nvim is available
      if command -v nvim >/dev/null 2>&1; then
        export EDITOR="nvim"
        export VISUAL="nvim"
      fi
      
      # Better history
      export HISTCONTROL=ignoredups:erasedups
      export HISTSIZE=10000
      export HISTFILESIZE=10000
      shopt -s histappend
      
      # FZF integration
      if command -v fzf >/dev/null 2>&1; then
        eval "$(fzf --bash)"
      fi
      
      # Zoxide integration
      if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init bash)"
        alias cd="z"
      fi
    '';
  };
  
  # Tmux - simple config without plugins
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    prefix = "C-a";
    keyMode = "vi";
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    
    # No plugins - avoiding all build issues
    plugins = [];
    
    extraConfig = ''
      # Split panes
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      
      # Navigate panes
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      
      # Status bar
      set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
      set -g status-left '#[fg=#89b4fa,bold] #S '
      set -g status-right '#[fg=#f9e2af] %H:%M '
    '';
  };
  
  # FZF
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };
  
  # Direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableBashIntegration = true;
  };
  
  # Zoxide
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };
  
  # Bat
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
    };
  };
  
  # Eza
  programs.eza = {
    enable = true;
    enableBashIntegration = true;
    icons = "auto";
    git = true;
  };
}
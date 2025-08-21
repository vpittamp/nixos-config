# Enhanced container configuration with home-manager integration
{ pkgs, lib, config, ... }:

let
  # Import the actual home-manager configuration to get packages
  # This ensures we have a single source of truth
  homeConfig = import ./home-vpittamp.nix { 
    inherit config pkgs lib; 
  };
  
  # Extract packages from the home configuration
  # This way we don't duplicate the package list
  homePackages = homeConfig.home.packages or [];

  # Create initialization script that properly handles PATH
  initScript = pkgs.writeScriptBin "container-init" ''
    #!${pkgs.bashInteractive}/bin/bash
    set -e
    
    echo "🚀 Initializing NixOS Container Environment"
    
    # Detect user context
    ACTUAL_USER=$(whoami)
    if [ "$ACTUAL_USER" = "root" ]; then
      export HOME=/root
      export PROFILE_DIR=/root/.local/state/nix/profiles
    else
      export HOME=/home/$ACTUAL_USER
      export PROFILE_DIR=/home/$ACTUAL_USER/.local/state/nix/profiles
    fi
    
    # Create necessary directories
    mkdir -p $HOME/.config/nix
    mkdir -p $HOME/.local/state/nix/profiles
    mkdir -p $HOME/.cache
    
    # Configure Nix
    cat > $HOME/.config/nix/nix.conf << 'EOF'
    experimental-features = nix-command flakes
    max-jobs = auto
    trusted-users = root vpittamp
    EOF
    
    # Set up PATH to include all necessary directories
    export PATH="$PROFILE_DIR/home-manager/home-path/bin:$PATH"
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
    export PATH="/run/current-system/sw/bin:$PATH"
    
    # Source configuration from GitHub if GITHUB_CONFIG is set
    if [ -n "$GITHUB_CONFIG" ]; then
      echo "→ Fetching configuration from GitHub..."
      if [ -d "$HOME/nixos-config" ]; then
        cd "$HOME/nixos-config"
        git pull origin main || git pull origin master
      else
        git clone https://github.com/vpittamp/nixos-config.git "$HOME/nixos-config"
      fi
      
      cd "$HOME/nixos-config"
      
      # Build and activate home-manager if available
      if [ -f "flake.nix" ] && grep -q "homeConfigurations\|nixosConfigurations" flake.nix; then
        echo "→ Building home-manager configuration..."
        export NIX_REMOTE=
        
        # Try to build home-manager configuration
        if nix build .#nixosConfigurations.nixos-wsl.config.home-manager.users.vpittamp.home.activationPackage 2>/dev/null; then
          if [ -f ./result/activate ]; then
            echo "→ Activating home-manager configuration..."
            ./result/activate
          fi
        fi
      fi
    fi
    
    # Set up shell environment
    export EDITOR=nvim
    export VISUAL=nvim
    export PAGER=less
    export LESS="-R"
    export TERM=xterm-256color
    
    # Create bashrc with proper aliases and PATH
    cat > $HOME/.bashrc << 'BASHRC'
    # Ensure PATH includes home-manager binaries
    export PATH="$HOME/.local/state/nix/profiles/home-manager/home-path/bin:$PATH"
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
    
    # Aliases
    alias ..="cd .."
    alias ...="cd ../.."
    alias ....="cd ../../.."
    
    # Use absolute paths for safety
    HM_BIN="$HOME/.local/state/nix/profiles/home-manager/home-path/bin"
    
    if [ -f "$HM_BIN/eza" ]; then
      alias ls="$HM_BIN/eza --group-directories-first"
      alias ll="$HM_BIN/eza -l --group-directories-first"
      alias la="$HM_BIN/eza -la --group-directories-first"
      alias lt="$HM_BIN/eza --tree"
    else
      alias ll="ls -l"
      alias la="ls -la"
    fi
    
    if [ -f "$HM_BIN/bat" ]; then
      alias cat="$HM_BIN/bat"
    fi
    
    if [ -f "$HM_BIN/rg" ]; then
      alias grep="$HM_BIN/rg"
    fi
    
    # Git aliases
    alias g="git"
    alias gs="git status"
    alias ga="git add"
    alias gc="git commit"
    alias gp="git push"
    alias gl="git log --oneline --graph --decorate"
    alias gd="git diff"
    alias gco="git checkout"
    alias gb="git branch"
    
    # Kubernetes aliases
    alias k="kubectl"
    alias kgp="kubectl get pods"
    alias kgs="kubectl get svc"
    alias kgd="kubectl get deployment"
    
    # Clear workaround if ncurses not available
    if ! command -v clear &> /dev/null; then
      alias clear='printf "\033c"'
    fi
    
    # Initialize tools if available
    if command -v starship &> /dev/null; then
      eval "$(starship init bash)"
    fi
    
    if command -v zoxide &> /dev/null; then
      eval "$(zoxide init bash)"
    fi
    
    if command -v direnv &> /dev/null; then
      eval "$(direnv hook bash)"
    fi
    
    BASHRC
    
    # Source the bashrc
    source $HOME/.bashrc
    
    echo "✅ Container environment initialized!"
    echo "📝 PATH configured with home-manager tools"
    
    # Start bash with the configured environment
    exec ${pkgs.bashInteractive}/bin/bash
  '';

in
{
  # Enhanced container with home-manager packages pre-installed
  backstage-dev-container = pkgs.dockerTools.buildLayeredImage {
    name = "backstage-dev-hm";
    tag = "latest";
    maxLayers = 128;  # Optimize for layer sharing
    
    contents = with pkgs; [
      # Base system
      bashInteractive
      coreutils
      cacert
      gitMinimal
      
      # Nix for runtime configuration
      nix
      
      # User management
      shadow
      su
      sudo
      
      # Required for various operations
      gnused
      gnutar
      gzip
      xz
      findutils
      gnugrep
      gawk
      
      # Include all home-manager packages
    ] ++ homePackages ++ [
      # Add the initialization script
      initScript
    ];
    
    # Extra commands to set up the container filesystem
    extraCommands = ''
      # Create user directories
      mkdir -p home/vpittamp/.local/state/nix/profiles
      mkdir -p home/vpittamp/.config
      mkdir -p home/vpittamp/.cache
      mkdir -p root/.local/state/nix/profiles
      mkdir -p root/.config/nix
      mkdir -p etc/nix
      
      # Create nix.conf at system level
      cat > etc/nix/nix.conf << 'EOF'
      experimental-features = nix-command flakes
      sandbox = false
      trusted-users = root vpittamp
      EOF
      
      # Create passwd and group entries for vpittamp user
      echo "vpittamp:x:1000:1000::/home/vpittamp:/bin/bash" >> etc/passwd
      echo "vpittamp:x:1000:" >> etc/group
      
      # Set up sudoers
      mkdir -p etc/sudoers.d
      echo "vpittamp ALL=(ALL) NOPASSWD:ALL" > etc/sudoers.d/vpittamp
    '';
    
    config = {
      Env = [
        # Base PATH with all necessary directories
        "PATH=/home/vpittamp/.local/state/nix/profiles/home-manager/home-path/bin:/root/.local/state/nix/profiles/home-manager/home-path/bin:/nix/var/nix/profiles/default/bin:/bin:/usr/bin:/run/current-system/sw/bin"
        
        # Nix configuration
        "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
        "NIX_REMOTE="  # Single-user mode for containers
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        
        # User environment
        "USER=root"
        "HOME=/root"
        "LANG=en_US.UTF-8"
        
        # Terminal
        "TERM=xterm-256color"
        
        # Optional: Enable GitHub config fetching
        "GITHUB_CONFIG=true"
      ];
      
      Cmd = [ "/bin/container-init" ];
      WorkingDir = "/";
      
      # Volumes for persistent data
      Volumes = {
        "/nix/store" = {};
        "/nix/var" = {};
        "/home" = {};
        "/app" = {};  # For application code
      };
      
      # Expose common ports
      ExposedPorts = {
        "3000/tcp" = {};  # Frontend
        "7007/tcp" = {};  # Backend
        "8080/tcp" = {};  # Alternative
      };
    };
  };
  
  # Lightweight init container for Kubernetes
  nix-init-container = pkgs.dockerTools.buildLayeredImage {
    name = "nix-init";
    tag = "latest";
    
    contents = with pkgs; [
      bashInteractive
      coreutils
      nix
      cacert
      gitMinimal
      gnused
    ];
    
    config = {
      Env = [
        "NIX_REMOTE="
        "PATH=/bin:/usr/bin"
      ];
      Cmd = [ "/bin/bash" "-c" "echo 'Init container for setting up Nix environment'" ];
    };
  };
}
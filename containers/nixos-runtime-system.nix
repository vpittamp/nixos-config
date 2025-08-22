{ pkgs, lib, inputs }:

let
  # Minimal runtime packages - only what's needed inside containers
  runtimePackages = with pkgs; [
    # Core utilities
    bashInteractive
    coreutils
    cacert
    shadow
    su
    sudo
    ncurses  # Provides clear, tput, reset
    findutils
    gnused
    gnutar
    gzip
    xz
    which
    file
    procps  # For ps, top, etc.
    
    # Essential development tools
    git
    neovim
    tmux
    
    # Shell utilities
    fzf
    ripgrep
    fd
    bat
    eza
    zoxide
    jq
    yq
    tree
    htop
    
    # Network tools
    curl
    wget
    
    # Runtime dependencies
    nodejs_20  # Required for Backstage
    
    # Kubernetes interaction (minimal)
    kubectl  # Keep for apps that need K8s access
    
    # Custom packages
    (pkgs.callPackage ../packages/claude-manager-multiplatform.nix { 
      inherit (pkgs.stdenv.hostPlatform) system;
    })
  ];
  
  # Minimal bash configuration
  bashConfig = ''
    # Environment variables
    export EDITOR=nvim
    export VISUAL=nvim
    export PAGER=less
    export LESS="-R"
    export TERM=xterm-256color
    
    # Aliases
    alias ls='eza --group-directories-first'
    alias ll='eza -l --group-directories-first'
    alias la='eza -la --group-directories-first'
    alias lt='eza --tree'
    alias cat='bat'
    alias grep='rg'
    alias vim='nvim'
    alias k='kubectl'
    
    # Git aliases
    alias g='git'
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git log --oneline --graph --decorate'
    alias gd='git diff'
    
    # Initialize tools
    if command -v zoxide >/dev/null 2>&1; then
      eval "$(zoxide init bash)"
    fi
  '';
  
  # Initialization script
  initScript = pkgs.writeScriptBin "container-init" ''
    #!${pkgs.bashInteractive}/bin/bash
    set -e
    
    echo "🚀 Initializing NixOS Runtime Container (Slim)"
    
    # Set up environment
    export HOME=/root
    export USER=root
    export PATH="/bin:/usr/bin:/usr/local/bin:$PATH"
    
    # Create necessary directories
    mkdir -p /root/.config/{tmux,nvim}
    mkdir -p /root/.cache
    mkdir -p /tmp
    chmod 1777 /tmp
    
    # Write minimal bashrc
    cat > /root/.bashrc << 'BASHRC_EOF'
    ${bashConfig}
    BASHRC_EOF
    
    # Write tmux configuration
    cat > /root/.config/tmux/tmux.conf << 'TMUX_EOF'
    set -g prefix \`
    set -g base-index 1
    set -g history-limit 10000
    set -g mode-keys vi
    set -g mouse on
    TMUX_EOF
    
    # Source bashrc and start bash
    cd /root
    exec ${pkgs.bashInteractive}/bin/bash --rcfile /root/.bashrc
  '';
in
pkgs.dockerTools.buildLayeredImage {
  name = "nixos-runtime-system";
  tag = "latest";
  created = "now";
  maxLayers = 64;  # Fewer layers for smaller image
  
  contents = pkgs.buildEnv {
    name = "nixos-runtime-env";
    paths = runtimePackages ++ [ initScript ];
    pathsToLink = [ "/bin" "/lib" "/share" "/etc" ];
  };
  
  # Create essential system files
  extraCommands = ''
    # Create /etc directory structure
    mkdir -p etc/pam.d
    mkdir -p root
    mkdir -p tmp
    chmod 1777 tmp
    mkdir -p var/tmp
    chmod 1777 var/tmp
    
    # Create minimal passwd file
    cat > etc/passwd << 'EOF'
    root:x:0:0:root:/root:/bin/bash
    nobody:x:65534:65534:nobody:/nonexistent:/bin/false
    EOF
    
    # Create minimal group file
    cat > etc/group << 'EOF'
    root:x:0:
    wheel:x:1:
    users:x:100:
    nobody:x:65534:
    EOF
    
    # Create shadow file (empty passwords)
    cat > etc/shadow << 'EOF'
    root:!:19000:0:99999:7:::
    nobody:!:19000:0:99999:7:::
    EOF
    
    # Create resolv.conf for DNS
    cat > etc/resolv.conf << 'EOF'
    nameserver 8.8.8.8
    nameserver 8.8.4.4
    EOF
  '';
  
  config = {
    User = "root";
    WorkingDir = "/app";
    
    Env = [
      "PATH=/bin:/usr/bin:/usr/local/bin"
      "HOME=/root"
      "USER=root"
      "TERM=xterm-256color"
      "EDITOR=nvim"
      "VISUAL=nvim"
      "PAGER=less"
      "LESS=-R"
      "LANG=C.UTF-8"
      "LC_ALL=C.UTF-8"
    ];
    
    Cmd = [ "/bin/container-init" ];
    
    Volumes = {
      "/app" = {};
      "/workspace" = {};
    };
    
    Labels = {
      "org.opencontainers.image.source" = "https://github.com/vpittamp/nixos-config";
      "org.opencontainers.image.description" = "Minimal NixOS runtime container for production";
      "org.opencontainers.image.authors" = "Vinod Pittampalli <vinod@pittampalli.com>";
      "org.opencontainers.image.variant" = "runtime-slim";
    };
  };
}
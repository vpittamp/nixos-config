# Package overlay sets for modular NixOS configuration
# Allows building containers of different sizes based on use case
{ pkgs, lib, ... }:

rec {
  # Core packages - Essential tools that should always be included
  # Approximate size: ~500MB
  core = with pkgs; [
    # Core utilities
    bashInteractive
    coreutils
    tmux
    git
    vim
    neovim
    
    # Essential CLI tools
    fzf
    ripgrep
    fd
    bat
    eza
    zoxide
    
    # Basic system tools
    curl
    wget
    jq
    yq
    which
    file
    tree
    htop
    ps
    procps
    
    # Terminal utilities
    ncurses  # Provides clear, tput, reset
    less
    gnutar
    gzip
    xz
    
    # Text processing
    gnused
    gawk
    grep
    
    # Shell enhancement
    direnv
    stow
  ];
  
  # Kubernetes tools - For K8s development and management
  # Approximate size: ~600MB
  kubernetes = with pkgs; [
    kubectl        # Core K8s CLI (58MB) - often needed
    kubernetes-helm # Package manager (76MB)
    k9s            # Terminal UI (159MB)
    argocd         # GitOps (161MB)
    vcluster       # Virtual clusters (119MB)
    kind           # K8s in Docker (102MB)
  ];
  
  # Development tools - Programming and development utilities
  # Approximate size: ~600MB
  development = with pkgs; [
    # Version control
    gh             # GitHub CLI (52MB)
    
    # Container tools
    docker-compose # Multi-container apps (64MB)
    
    # Development platforms
    devspace       # Cloud-native dev (390MB)
    deno          # JS/TS runtime (156MB)
    nodejs_20     # Node.js runtime
    
    # Custom tools
    # idpbuilder is defined separately (47MB)
  ];
  
  # IDE and editor tools
  # Approximate size: ~200MB
  ide = with pkgs; [
    # Code editors and IDE tools
    # claude-code  # Claude Code CLI (165MB) - defined in configuration.nix
  ];
  
  # Monitoring and analysis tools - Optional system monitoring
  # Approximate size: ~100MB
  monitoring = with pkgs; [
    btop          # Better htop
    ncdu          # Disk usage analyzer
    iotop         # I/O monitoring
    nethogs       # Network monitoring
  ];
  
  # File management tools - Optional file managers
  # Approximate size: ~50MB
  fileManagement = with pkgs; [
    yazi          # Terminal file manager
    ranger        # Another file manager option
  ];
  
  # Interactive shell tools - Charm tools and similar
  # Approximate size: ~50MB
  interactive = with pkgs; [
    gum           # Interactive shell script builder
    glow          # Markdown renderer
    charm         # Charm account management
  ];
  
  # Session management - tmux and session tools
  # Approximate size: ~20MB
  sessionTools = with pkgs; [
    sesh          # Smart tmux session manager
    tmuxp         # Tmux session manager
  ];
  
  # Get packages for a specific profile
  getProfile = profile: 
    if profile == "minimal" then
      core
    else if profile == "runtime" then
      core ++ sessionTools ++ [ pkgs.kubectl ]  # Add kubectl for runtime
    else if profile == "development" then
      core ++ sessionTools ++ kubernetes ++ development ++ interactive
    else if profile == "full" then
      core ++ sessionTools ++ kubernetes ++ development ++ monitoring ++ 
      fileManagement ++ interactive ++ ide
    else
      core;  # Default to core if unknown profile
  
  # Helper to check if a package set should be included
  shouldInclude = setName: profile:
    let
      includes = {
        minimal = [ "core" ];
        runtime = [ "core" "sessionTools" ];
        development = [ "core" "sessionTools" "kubernetes" "development" "interactive" ];
        full = [ "core" "sessionTools" "kubernetes" "development" "monitoring" 
                 "fileManagement" "interactive" "ide" ];
      };
    in
      lib.elem setName (includes.${profile} or [ "core" ]);
}
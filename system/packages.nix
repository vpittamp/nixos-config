# System-level packages that require root/build permissions
# These packages contain custom derivations, chmod operations, or other
# operations that fail in restricted container environments
{ pkgs, lib, ... }:

let
  # Custom binary packages that need chmod +x
  idpbuilder = pkgs.callPackage ../packages/idpbuilder.nix { };
  
  vscode-cli = pkgs.callPackage ../packages/vscode-cli.nix { };
  
  azure-cli-bin = pkgs.callPackage ../packages/azure-cli-bin.nix { };
  
  claude-manager = pkgs.callPackage ../packages/claude-manager-fetchurl.nix { 
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  
  # Plugins are now managed through home-manager:
  # - Tmux plugins via programs.tmux.plugins
  # - Vim plugins via programs.neovim.plugins

  # System utilities and tools
  systemTools = with pkgs; [
    # Core system utilities
    coreutils
    findutils
    gnused
    gawk
    gnutar
    gzip
    which
    file
    ncurses
    
    # WSL integration
    wslu
    wl-clipboard
    
    # Nix tools
    nix
    cachix
  ];

  # Development tools that work better at system level
  developmentTools = with pkgs; [
    # Container tools
    docker-compose
    devpod
    devcontainer
    devspace
    
    # Version control
    git
    gh
    lazygit
    
    # Build tools
    gnumake
    gcc
    pkg-config
    
    # Language support
    nodejs_20
    python3
    go
    rustc
    cargo
  ];

  # Kubernetes tools (often need system access)
  kubernetesTools = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
    argocd
    vcluster
    kind
  ];

in {
  # Export different package sets
  custom = [
    idpbuilder
    vscode-cli
    azure-cli-bin
    claude-manager
  ];
  
  # Plugins moved to home-manager
  tmuxPlugins = [];
  vimPlugins = [];
  
  system = systemTools;
  development = developmentTools;
  kubernetes = kubernetesTools;
  
  # All system packages
  all = systemTools ++ developmentTools ++ kubernetesTools ++ [
    idpbuilder
    vscode-cli
    azure-cli-bin
    claude-manager
  ];
  
  # Essential system packages only
  essential = systemTools ++ [
    vscode-cli
    claude-manager
  ] ++ (with pkgs; [
    git
    docker-compose
    nodejs_20
    python3
  ]);
  
  # Minimal for containers
  minimal = with pkgs; [
    coreutils
    findutils
    gnused
    git
    which
    file
  ];
}
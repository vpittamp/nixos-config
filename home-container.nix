# Home configuration for containers (without problematic local files)
{ config, pkgs, lib, inputs ? {}, ... }:

let
  # Import main config but exclude packages that need local files
  mainConfig = import ./home-vpittamp.nix { 
    inherit config pkgs lib inputs; 
  };
  
  # All packages except claude-manager
  containerPackages = with pkgs; [
    # Core utilities
    tmux
    git
    stow
    fzf
    ripgrep
    fd
    bat
    eza
    zoxide
    sesh
    yazi
    
    # Development tools
    gh
    kubectl
    kubernetes-helm
    k9s
    direnv
    tree
    htop
    btop
    ncdu
    jq
    yq
    gum
    
    # System tools
    file
    which
    curl
    wget
    ncurses
  ];
in
{
  # Copy everything from main config
  home = mainConfig.home // {
    # Override packages to exclude claude-manager
    packages = containerPackages;
  };
  
  # Keep all program configurations
  programs = mainConfig.programs;
  
  # Keep services if defined
  services = mainConfig.services or {};
  
  # Keep XDG config
  xdg = mainConfig.xdg or {};
}
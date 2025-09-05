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
    
    # Core configuration (required for colors)
    ../home-modules/colors.nix
    
    # Terminal configurations (matching local system)
    ../home-modules/terminal/sesh.nix
    ../home-modules/terminal/tmux.nix
    
    # Tool configurations (matching local system)
    ../home-modules/tools/git.nix
    ../home-modules/tools/bat.nix
    ../home-modules/tools/direnv.nix
    ../home-modules/tools/fzf.nix
    ../home-modules/tools/yazi.nix
    
    # Shell configurations
    ../home-modules/shell/bash.nix
  ];

  # Basic home configuration
  # These will be overridden by the flake
  # Using mkDefault allows the flake to set the actual values
  home.username = lib.mkDefault "code";
  home.homeDirectory = lib.mkDefault "/home/code";
  home.stateVersion = "24.05";
  
  # Essential packages only - packages from imported modules are handled there
  home.packages = with pkgs; [
    # Core tools not in modules
    curl
    wget
    ripgrep
    fd
    eza
    jq
    yq
    
    # From userPackages
    htop
    tree
    ncdu
  ] ++ (
    # Package profile selection - can be overridden via flake
    let prof = config.home.sessionVariables.CONTAINER_PROFILE or "";
    in if prof == "minimal" then []
       else if prof == "development" then userPackages.development
       else with pkgs; [ yazi yarn ]  # essential extras
  );
  
  # Enable home-manager
  programs.home-manager.enable = true;
  
  # Enable yazi (required for the module)
  modules.tools.yazi.enable = true;
  
  # Zoxide (not in imported modules)
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };
  
  # Eza (not in imported modules)
  programs.eza = {
    enable = true;
    enableBashIntegration = true;
    icons = "auto";
    git = true;
  };
  
  # Ripgrep configuration (not in imported modules)
  programs.ripgrep = {
    enable = true;
    arguments = [
      "--max-columns=150"
      "--max-columns-preview"
      "--smart-case"
    ];
  };
}
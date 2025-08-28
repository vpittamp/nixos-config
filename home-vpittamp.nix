{ config, pkgs, lib, inputs, ... }:

{
  # Import all modular configurations
  imports = [
    # Core configuration
    ./home-modules/colors.nix
    
    # Shell configurations
    ./home-modules/shell/bash.nix
    ./home-modules/shell/starship.nix
    
    # Terminal configurations
    ./home-modules/terminal/tmux.nix
    ./home-modules/terminal/sesh.nix
    
    # Editor configurations
    ./home-modules/editors/neovim.nix
    
    # Tool configurations
    ./home-modules/tools/git.nix
    ./home-modules/tools/ssh.nix
    ./home-modules/tools/bat.nix
    ./home-modules/tools/direnv.nix
    ./home-modules/tools/fzf.nix
    # ./home-modules/tools/k9s.nix  # Temporarily disabled for container build
    ./home-modules/tools/yazi.nix
    
    # AI Assistant configurations
    ./home-modules/ai-assistants/claude-code.nix
    ./home-modules/ai-assistants/codex.nix
    ./home-modules/ai-assistants/gemini-cli.nix
  ];

  # Home Manager configuration
  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";
  home.stateVersion = "25.05";

  # Core packages - using overlay system
  # Control package selection with NIXOS_PACKAGES environment variable:
  #   - "" or unset: essential packages only (default)
  #   - "full": all packages  
  #   - "essential,kubernetes": essential + kubernetes tools
  #   - "essential,development": essential + development tools
  home.packages = let
    overlayPackages = import ./overlays/packages.nix { inherit pkgs lib; };
  in
    overlayPackages.allPackages;

  # Enable yazi (since it uses an option-based enable)
  modules.tools.yazi.enable = true;

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}

{ config, pkgs, lib, inputs, ... }:

{
  # Import all modular configurations
  imports = [
    # Shell configurations
    ./home-modules/shell/bash.nix
    ./home-modules/shell/starship.nix
    ./home-modules/shell/colors.nix
    
    # Terminal configurations
    ./home-modules/terminal/tmux.nix
    ./home-modules/terminal/sesh.nix
    ./home-modules/terminal/konsole-fix.nix
    
    # Editor configurations
    ./home-modules/editors/neovim.nix
    
    # Tool configurations
    ./home-modules/tools/git.nix
    ./home-modules/tools/ssh.nix
    ./home-modules/tools/bat.nix
    ./home-modules/tools/direnv.nix
    ./home-modules/tools/fzf.nix
    ./home-modules/tools/firefox.nix
    ./home-modules/tools/k9s.nix
    ./home-modules/tools/yazi.nix
    ./home-modules/tools/nix.nix
    ./home-modules/tools/cluster-management.nix
    ./home-modules/tools/onepassword-plugins.nix  # 1Password shell plugins
    
    # AI Assistant configurations
    ./home-modules/ai-assistants/claude-code.nix
    ./home-modules/ai-assistants/codex.nix
    ./home-modules/ai-assistants/gemini-cli.nix
  ];

  # Home Manager configuration
  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";
  home.stateVersion = "25.05";

  # Enable xsession for KDE to source home-manager session variables
  # This creates ~/.xprofile which KDE/SDDM sources on login
  xsession.enable = true;

  # User packages - safe for home-manager in any environment
  # These packages are from nixpkgs and don't require special permissions
  home.packages = let
    userPackages = import ./user/packages.nix { inherit pkgs lib; };
    packageConfig = import ./shared/package-lists.nix { inherit pkgs lib; };
  in
    # Use appropriate profile based on environment
    packageConfig.getProfile.user;

  # Enable yazi (since it uses an option-based enable)
  modules.tools.yazi.enable = true;

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}

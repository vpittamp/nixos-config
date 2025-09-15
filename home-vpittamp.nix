{ config, pkgs, lib, inputs, osConfig, ... }:

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
    ./home-modules/terminal/konsole.nix  # Konsole with improved selection
    
    # Editor configurations
    ./home-modules/editors/neovim.nix
    
    # Tool configurations
    ./home-modules/tools/git.nix
    ./home-modules/tools/ssh.nix
    ./home-modules/tools/onepassword.nix  # 1Password settings and config
    ./home-modules/tools/onepassword-env.nix  # 1Password environment setup
    ./home-modules/tools/onepassword-plugins.nix  # 1Password shell plugins
    ./home-modules/tools/onepassword-autostart.nix  # 1Password autostart and checks
    ./home-modules/tools/kwallet-config.nix  # KDE Wallet declarative config
    ./home-modules/tools/bat.nix
    # ./home-modules/tools/clipboard.nix  # DISABLED - Testing native KDE clipboard
    ./home-modules/tools/direnv.nix
    ./home-modules/tools/fzf.nix
    # ./home-modules/tools/firefox.nix  # Disabled - using Chromium as default
    ./home-modules/tools/chromium.nix  # Chromium with 1Password integration
    # ./home-modules/tools/chromium-profiles.nix  # Disabled - certificate handling approach
    # ./home-modules/tools/chromium-unified.nix  # Disabled - certificate handling approach
    
    # Desktop configurations
    ./home-modules/desktop/touchpad-gestures.nix  # Touchpad gestures for KDE
    ./home-modules/desktop/plasma-config.nix  # Comprehensive Plasma configuration
    ./home-modules/tools/k9s.nix
    ./home-modules/tools/yazi.nix
    ./home-modules/tools/nix.nix
    ./home-modules/tools/vscode.nix  # VSCode with 1Password integration
    ./home-modules/tools/gitkraken.nix  # GitKraken with Konsole and 1Password
    ./home-modules/tools/cluster-management.nix
    ./home-modules/tools/onepassword-plugins.nix  # 1Password shell plugins
    
    # Application configurations
    ./home-modules/apps/headlamp.nix  # Headlamp Kubernetes UI with plugins
    
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

  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "text/html" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
  };

  home.sessionVariables = {
    # Display scaling environment variables - conditional based on system
    GDK_DPI_SCALE = if osConfig.networking.hostName == "nixos-m1" then "0.5" else "1.0";
    QT_AUTO_SCREEN_SCALE_FACTOR = "0";
    QT_ENABLE_HIGHDPI_SCALING = "0";
    PLASMA_USE_QT_SCALING = "1";
    GDK_SCALE = if osConfig.networking.hostName == "nixos-m1" then "2" else "1";
    XCURSOR_SIZE = if osConfig.networking.hostName == "nixos-m1" then "48" else "28";
  };


  # Plasma Manager: declarative KDE user configuration
  programs.plasma = {
    enable = true;
    # Keep user changes during initial rollout; flip to true after validation
    overrideConfig = true;

    # Replace XRDP/display tweaks previously set via sessionCommands
    # Per-screen bottom panel with icon-only task manager limited to current screen
    panels = [
      {
        location = "bottom";
        height = 36;
        widgets = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.taskmanager"
          "org.kde.plasma.pager"
          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
      }
    ];
  };

  # Konsole profile via plasma-manager app module
  programs.konsole = {
    enable = true;
    defaultProfile = "Shell";
    profiles.Shell = {
      font.name = "FiraCode Nerd Font";
      font.size = 11;
      command = "/run/current-system/sw/bin/bash -l";
      colorScheme = "WhiteOnBlack";
    };
  };


  # Plasma configuration has been moved to ./home-modules/desktop/plasma-config.nix

}

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
    # Konsole profile/settings will be managed via plasma-manager
    
    # Editor configurations
    ./home-modules/editors/neovim.nix
    
    # Tool configurations
    ./home-modules/tools/git.nix
    ./home-modules/tools/ssh.nix
    ./home-modules/tools/onepassword-env.nix  # 1Password environment setup
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
    # Plasma panels/layout will be managed via plasma-manager
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
    GDK_DPI_SCALE = "1.0";
    QT_AUTO_SCREEN_SCALE_FACTOR = "0";
    QT_ENABLE_HIGHDPI_SCALING = "0";
    PLASMA_USE_QT_SCALING = "1";
    GDK_SCALE = "1";
    XCURSOR_SIZE = "32";
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
      colorScheme = "Catppuccin-Mocha";
    };
  };


  programs.plasma.configFile = {
    "kwinrc".Desktops = {
      Number = 8;
      Rows = 2;
    };
    "kglobalshortcutsrc".kwin = {
      "Switch to Desktop 1" = "Meta+1,none,Switch to Desktop 1";
      "Switch to Desktop 2" = "Meta+2,none,Switch to Desktop 2";
      "Switch to Desktop 3" = "Meta+3,none,Switch to Desktop 3";
      "Switch to Desktop 4" = "Meta+4,none,Switch to Desktop 4";
      "Overview" = "Meta+W,none,Toggle Overview";
    };
    # Mirror prior XRDP tuning precisely
    "kcmfonts".General.forceFontDPI = 110;
    "kdeglobals".KScreen.ScreenScaleFactors = "XORGXRDP0=1.2;";
    # Theme defaults
    "kdeglobals" = {
      General.ColorScheme = "BreezeDark";
      Icons.Theme = "breeze-dark";
      KDE.widgetStyle = "Breeze";
    };
    "kcminputrc".Mouse.cursorTheme = "breeze_cursors";
  };

}

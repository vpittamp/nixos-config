{ config, lib, pkgs, osConfig, ... }:

{
  programs.plasma = {
    # Keep GUI editable while still managing shortcuts declaratively
    immutableByDefault = false;

    # Global theme settings
    workspace.theme = "breeze-dark";
    workspace.iconTheme = "Papirus-Dark";

    configFile = {
      # Disable Yakuake's native F12 binding to prevent conflicts
      "yakuakerc".Shortcuts = {
        "toggle-window-state" = "none";
      };
      # Virtual Desktop Configuration
      "kwinrc".Desktops = {
        Number = lib.mkDefault 2;  # 2 desktops per activity
        Rows = lib.mkDefault 1;    # Single row layout
      };

      # Desktop navigation behavior
      "kwinrc".Windows = {
        RollOverDesktops = true;  # Wrap around when switching desktops
        SeparateScreenFocus = false;
        ActiveMouseScreen = false;
        FocusPolicy = "ClickToFocus";
        NextFocusPrefersMouse = false;
        ClickRaise = true;
        AutoRaise = false;
        AutoRaiseInterval = 750;
        DelayFocusInterval = 300;
        FocusStealingPreventionLevel = 1;  # Low
      };

      # KWin Compositing and Effects
      "kwinrc".Compositing = {
        Backend = "OpenGL";
        Enabled = true;
        GLCore = true;
        GLPreferBufferSwap = "a";  # Automatic
        HiddenPreviews = 5;  # Show previews for all windows
        OpenGLIsUnsafe = false;
        WindowsBlockCompositing = true;
      };

      # Desktop Effects
      "kwinrc".Plugins = {
        overviewEnabled = true;  # Enable Overview effect
        screenedgeEnabled = false;  # Disable screen edge
        presentwindowsEnabled = false;  # Disable present windows
        desktopgridEnabled = false;  # Disable desktop grid (replaced by Overview)
        windowviewEnabled = true;  # Enable window view
        blurEnabled = true;
        contrastEnabled = true;
        slideEnabled = true;
        wobblywindowsEnabled = false;
        zoomEnabled = true;
        mouseclickEnabled = false;
      };

      # Screen Edges - Disable all hot corners
      "kwinrc".Effect-PresentWindows = {
        BorderActivateAll = 9;  # None
        BorderActivate = 9;  # None
        BorderActivateClass = 9;  # None
      };

      "kwinrc".Effect-Overview = {
        BorderActivate = 9;  # Disable hot corner for Overview
      };

      "kwinrc".TabBox = {
        BorderActivate = 9;  # None
        BorderAlternativeActivate = 9;  # None
      };

      # Configure font DPI based on system
      "kcmfonts".General.forceFontDPI =
        if osConfig.networking.hostName == "nixos-m1" then 180 else 100;

      "kdeglobals".KScreen.ScreenScaleFactors =
        if osConfig.networking.hostName == "nixos-m1"
        then "eDP-1=2;"
        else "XORGXRDP0=1.15;";

      # Configure KDE Wallet
      "kwalletrc".Wallet = {
        "Enabled" = true;
        "First Use" = false;
        "Use One Wallet" = true;
        "Close When Idle" = false;
        "Close on Screensaver" = false;
        "Default Wallet" = "kdewallet";
        "Prompt on Open" = false;
      };
    };

    # Custom hotkey commands for launching activity-aware applications
    hotkeys.commands = {
      "launch-konsole-activity" = {
        name = "Launch Konsole (Activity)";
        key = "Ctrl+Alt+T";
        command = "konsole-activity";
      };
      # DISABLED: Yakuake crashes on Wayland/ARM64
      # "launch-yakuake-activity" = {
      #   name = "Launch Yakuake (Activity)";
      #   key = "F12";
      #   command = "yakuake-activity";
      # };
      "launch-dolphin-activity" = {
        name = "Launch Dolphin (Activity)";
        key = "Ctrl+Alt+D";
        command = "dolphin-activity";
      };
      "launch-code-activity" = {
        name = "Launch VS Code (Activity)";
        key = "Ctrl+Alt+E";
        command = "code-activity";
      };
      # Speech-to-text commands moved to speech-to-text-shortcuts.nix
    };

    # Keyboard shortcuts using plasma-manager's shortcuts module
    shortcuts = {
      # KWin window management shortcuts
      kwin = {
        "Overview" = ["Meta+Tab" "Meta+F8"];
        "Switch to Desktop 1" = "Meta+1";
        "Switch to Desktop 2" = "Meta+2";
        "Switch to Desktop 3" = "Meta+3";
        "Switch to Desktop 4" = "Meta+4";
        "Window to Desktop 1" = "Meta+Shift+1";
        "Window to Desktop 2" = "Meta+Shift+2";
        "Window to Desktop 3" = "Meta+Shift+3";
        "Window to Desktop 4" = "Meta+Shift+4";
        "Switch One Desktop Down" = "Meta+Ctrl+Down";
        "Switch One Desktop Up" = "Meta+Ctrl+Up";
        "Switch One Desktop to the Left" = "Meta+Ctrl+Left";
        "Switch One Desktop to the Right" = "Meta+Ctrl+Right";
        "Window Maximize" = "Meta+PgUp";
        "Window Minimize" = "Meta+PgDn";
        "Window Quick Tile Left" = "Meta+Left";
        "Window Quick Tile Right" = "Meta+Right";
        "Window Quick Tile Top" = "Meta+Up";
        "Window Quick Tile Bottom" = "Meta+Down";
      };

      # Plasma shell shortcuts for activities
      plasmashell = {
        "manage activities" = ["Meta+Q" "Ctrl+Alt+A"];
        "next activity" = "Meta+Tab";
        "previous activity" = "Meta+Shift+Tab";
      };

    };
  };
}
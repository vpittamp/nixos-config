{ config, lib, pkgs, osConfig, ... }:

{
  programs.plasma = {
    # Make shortcuts immutable to ensure they're applied
    immutableByDefault = true;

    # Global theme settings
    workspace.theme = "breeze-dark";
    workspace.iconTheme = "Papirus-Dark";

    configFile = {
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

      # Global shortcuts configuration
      "kglobalshortcutsrc" = {
        "plasmashell" = {
          "manage activities" = "Meta+Q,Ctrl+Alt+A,Show Activity Switcher";
          "next activity" = "Meta+Tab,none,Switch to Next Activity";
          "previous activity" = "Meta+Shift+Tab,none,Switch to Previous Activity";
        };

        "kwin" = {
          "Overview" = "Meta+W\tMeta+F8,Meta+W,Toggle Overview";
          "Switch to Desktop 1" = "Meta+1,Meta+1,Switch to Desktop 1";
          "Switch to Desktop 2" = "Meta+2,Meta+2,Switch to Desktop 2";
          "Switch to Desktop 3" = "Meta+3,Meta+3,Switch to Desktop 3";
          "Switch to Desktop 4" = "Meta+4,Meta+4,Switch to Desktop 4";
          "Window to Desktop 1" = "Meta+Shift+1,Meta+Shift+1,Window to Desktop 1";
          "Window to Desktop 2" = "Meta+Shift+2,Meta+Shift+2,Window to Desktop 2";
          "Window to Desktop 3" = "Meta+Shift+3,Meta+Shift+3,Window to Desktop 3";
          "Window to Desktop 4" = "Meta+Shift+4,Meta+Shift+4,Window to Desktop 4";
          "Switch One Desktop Down" = "Meta+Ctrl+Down,Meta+Ctrl+Down,Switch One Desktop Down";
          "Switch One Desktop Up" = "Meta+Ctrl+Up,Meta+Ctrl+Up,Switch One Desktop Up";
          "Switch One Desktop to the Left" = "Meta+Ctrl+Left,Meta+Ctrl+Left,Switch One Desktop to the Left";
          "Switch One Desktop to the Right" = "Meta+Ctrl+Right,Meta+Ctrl+Right,Switch One Desktop to the Right";
          "Window Maximize" = "Meta+PgUp,Meta+PgUp,Maximize Window";
          "Window Minimize" = "Meta+PgDn,Meta+PgDn,Minimize Window";
          "Window Quick Tile Left" = "Meta+Left,Meta+Left,Quick Tile Window to the Left";
          "Window Quick Tile Right" = "Meta+Right,Meta+Right,Quick Tile Window to the Right";
          "Window Quick Tile Top" = "Meta+Up,Meta+Up,Quick Tile Window to the Top";
          "Window Quick Tile Bottom" = "Meta+Down,Meta+Down,Quick Tile Window to the Bottom";
        };
      };
    };

    # Keyboard shortcuts for activity-aware applications
    shortcuts = {
      # Activity-aware application shortcuts
      "services/konsole-activity.desktop"."_launch" = "Ctrl+Alt+T";
      "services/yakuake-activity.desktop"."_launch" = "F12";
      "services/dolphin-activity.desktop"."_launch" = "Ctrl+Alt+D";
      "services/code-activity.desktop"."_launch" = "Ctrl+Alt+E";

      # Activity management shortcuts
      "plasmashell"."manage activities" = ["Meta+Q" "Ctrl+Alt+A"];
      "plasmashell"."next activity" = ["Meta+Tab"];
      "plasmashell"."previous activity" = ["Meta+Shift+Tab"];
      "plasmashell"."stop current activity" = [];  # Disabled

      # Desktop switching
      "kwin"."Switch to Desktop 1" = ["Meta+1"];
      "kwin"."Switch to Desktop 2" = ["Meta+2"];
      "kwin"."Switch to Desktop 3" = ["Meta+3"];
      "kwin"."Switch to Desktop 4" = ["Meta+4"];

      # Window movement to desktops
      "kwin"."Window to Desktop 1" = ["Meta+Shift+1"];
      "kwin"."Window to Desktop 2" = ["Meta+Shift+2"];
      "kwin"."Window to Desktop 3" = ["Meta+Shift+3"];
      "kwin"."Window to Desktop 4" = ["Meta+Shift+4"];

      # Desktop navigation
      "kwin"."Switch One Desktop Down" = ["Meta+Ctrl+Down"];
      "kwin"."Switch One Desktop Up" = ["Meta+Ctrl+Up"];
      "kwin"."Switch One Desktop to the Left" = ["Meta+Ctrl+Left"];
      "kwin"."Switch One Desktop to the Right" = ["Meta+Ctrl+Right"];

      # Overview (replaces desktop grid)
      "kwin"."Overview" = ["Meta+W" "Meta+F8"];

      # Window management
      "kwin"."Window Maximize" = ["Meta+PgUp"];
      "kwin"."Window Minimize" = ["Meta+PgDn"];
      "kwin"."Window Close" = ["Alt+F4"];
      "kwin"."Window Fullscreen" = [];  # Disabled
      "kwin"."Window Operations Menu" = ["Alt+F3"];
      "kwin"."Window Quick Tile Left" = ["Meta+Left"];
      "kwin"."Window Quick Tile Right" = ["Meta+Right"];
      "kwin"."Window Quick Tile Top" = ["Meta+Up"];
      "kwin"."Window Quick Tile Bottom" = ["Meta+Down"];
    };
  };
}
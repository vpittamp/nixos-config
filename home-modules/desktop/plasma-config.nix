{ config, lib, pkgs, osConfig, ... }:

{
  # Import PWA mapping generator
  imports = [
    ./pwas/generator.nix
  ];

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
        then "eDP-1=1.75;"
        else "XORGXRDP0=1.15;";

      # XWayland scaling - only for M1 with native Retina display
      # This ensures XWayland apps (X11 apps running on Wayland) scale correctly
      # Using 1.75x for better balance between screen real estate and readability
      "kwinrc".Xwayland = lib.mkIf (osConfig.networking.hostName == "nixos-m1") {
        Scale = 1.75;
      };

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

      # Session Management - Start with empty session
      "ksmserverrc".General = {
        loginMode = "emptySession";  # Start with an empty session (don't restore apps)
        confirmLogout = true;  # Ask for confirmation on shutdown/logout
      };

      # Baloo File Indexing - Disable for performance
      # Baloo indexes files for search but can be resource-intensive
      "baloofilerc"."Basic Settings" = {
        "Indexing-Enabled" = false;  # Disable file indexing
      };

      # Dolphin File Manager Preferences
      "dolphinrc".General = {
        # ViewPropsTimestamp is system-generated, not managed here
      };
      "dolphinrc"."KFileDialog Settings" = {
        "Places Icons Auto-resize" = false;
        "Places Icons Static Size" = 22;
      };
      "dolphinrc".Search = {
        Location = "Everywhere";  # Search in all locations by default
      };

      # Kate Text Editor Preferences
      "katerc".General = {
        "Days Meta Infos" = 30;  # Keep file metadata for 30 days
        "Save Meta Infos" = true;  # Save cursor position, etc.
        "Show Full Path in Title" = false;
        "Show Menu Bar" = true;
        "Show Status Bar" = true;
        "Show Tab Bar" = true;
        "Show Url Nav Bar" = true;
      };

      # Spectacle Screenshot Tool
      "spectaclerc".General = {
        # Screenshot preferences can be added here as needed
        # Most spectacle config is done via shortcuts in this file
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
      # Spectacle screenshot tool - GUI mode
      # MX Keys camera button sends Print Screen (configured in Logitech Options+)
      "launch-spectacle-gui" = {
        name = "Launch Spectacle (Screenshot Tool)";
        key = "Print,Meta+Shift+S";
        command = "spectacle --launchonly";
      };
      # Speech-to-text commands moved to speech-to-text-shortcuts.nix
    };

    # KWin window rules - merged from three auto-generated sources:
    # 1. Activity-based rules (VS Code, Konsole, Dolphin) - from project-activities/window-rules.nix
    # 2. PWA rules (YouTube, Google AI, Headlamp, etc.) - from pwas/window-rules.nix
    # 3. Browser rules (Firefox, Chromium) - from browser-window-rules.nix
    #
    # All rules are auto-generated from declarative data sources:
    # - Activities: project-activities/data.nix
    # - PWAs: pwas/data.nix
    # - Browsers: browser-window-rules.nix (manually maintained)
    configFile."kwinrulesrc" =
      let
        # Get activity definitions from project-activities
        activityData = import ./project-activities/data.nix { inherit lib config; pkgs = null; };

        # 1. Generate activity-based rules for VS Code, Konsole, Dolphin
        activityRules = import ./project-activities/window-rules.nix {
          inherit lib config;
          activities = activityData.activities;
        };

        # 2. Generate PWA rules from pwas/data.nix
        pwaRules = import ./pwas/window-rules.nix { inherit lib config; };

        # 3. Get browser rules (manually maintained)
        browserRules = import ./browser-window-rules.nix { inherit lib config; };

        # Extract just the rules (without General sections)
        activityRulesOnly = lib.filterAttrs (name: _: name != "General") activityRules.kwinrulesrc;
        pwaRulesOnly = lib.filterAttrs (name: _: name != "General") pwaRules.kwinrulesrc;
        browserRulesOnly = lib.filterAttrs (name: _: name != "General") browserRules.kwinrulesrc;

        # Merge all rule sets
        # Order: PWA → Browser → Activity (first has precedence for duplicate names)
        allRules = pwaRulesOnly // browserRulesOnly // activityRulesOnly;

        # Get all rule names for General section
        allRuleNames = lib.attrNames allRules;
        ruleCount = builtins.length allRuleNames;
      in
        allRules // {
          General = {
            count = ruleCount;
            rules = lib.concatStringsSep "," allRuleNames;
          };
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

      # Spectacle (screenshot tool) shortcuts
      "org.kde.spectacle.desktop" = {
        # Disable default launch shortcut - using custom hotkeys.commands instead
        "_launch" = "none";
        # Capture active window
        "ActiveWindowScreenShot" = "Meta+Print";
        # Capture full screen
        "FullScreenScreenShot" = ["Shift+Print" "Meta+Shift+3"];
        # Capture rectangular region
        "RectangularRegionScreenShot" = ["Meta+Shift+Print" "Meta+Shift+4"];
      };

    };
  };
}
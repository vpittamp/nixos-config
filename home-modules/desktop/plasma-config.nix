{ config, lib, pkgs, osConfig, ... }:

{
  # Comprehensive Plasma Configuration via plasma-manager
  # This module demonstrates various configurable properties
  
  programs.plasma.configFile = {
    # Virtual Desktop Configuration - 4 desktops in 2x2 grid
    "kwinrc".Desktops = {
      Number = 4;
      Rows = 2;
      Name_1 = "Development";
      Name_2 = "Communication";
      Name_3 = "Research";
      Name_4 = "System";
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
      blurEnabled = true;
      contrastEnabled = true;
      desktopgridEnabled = true;
      highlightwindowEnabled = true;
      kwin4_effect_dimscreenEnabled = true;
      kwin4_effect_translucencyEnabled = false;
      magiclampEnabled = true;  # Magic lamp minimize effect
      overviewEnabled = true;  # Meta+W overview
      slideEnabled = true;  # Slide when switching desktops
      wobblywindowsEnabled = false;
      zoomEnabled = true;  # Magnifier
    };
    
    # Desktop Effect Settings
    "kwinrc".Effect-overview = {
      BorderActivate = 9;  # Top-right corner
      BorderActivateAll = 7;  # Top-left corner
    };
    
    "kwinrc".Effect-desktopgrid = {
      BorderActivate = 3;  # Bottom-right corner
      DesktopNameAlignment = 0;  # Center
      LayoutMode = 1;  # Pager layout
      ShowAddRemove = true;
    };
    
    "kwinrc".Effect-PresentWindows = {
      BorderActivate = 1;  # Bottom-left corner
      BorderActivateAll = 5;  # Left edge
      BorderActivateClass = 0;  # None
    };
    
    # TabBox (Alt+Tab) Configuration
    "kwinrc".TabBox = {
      ActivitiesMode = 1;  # Show windows from current activity
      ApplicationsMode = 0;  # Show one window per application
      BorderActivate = 0;  # No edge activation
      BorderAlternativeActivate = 0;
      DesktopMode = 1;  # Show windows from current desktop
      HighlightWindows = true;
      LayoutName = "thumbnail_grid";
      MinimizedMode = 0;  # Ignore minimized windows
      MultiScreenMode = 0;  # Ignore multi-screen
      ShowDesktopMode = 0;  # Do not show desktop
      ShowTabBox = true;
      SwitchingMode = 0;  # Focus on switching
    };
    
    # Activities Configuration
    # Note: Activities require UUIDs, using existing one and creating test entries
    "kactivitymanagerdrc".activities = {
      "7ddbcb0a-1539-4ed5-854d-2ac3971f0f34" = "Default";
      # Additional activities would need to be created via KDE UI first to get UUIDs
    };
    
    "kactivitymanagerdrc".main = {
      currentActivity = "7ddbcb0a-1539-4ed5-854d-2ac3971f0f34";
    };
    
    # Activity Manager Plugins Configuration
    "kactivitymanagerd-pluginsrc"."Plugin-org.kde.ActivityManager.Resources.Scoring" = {
      blocked = "firefox.desktop,google-chrome.desktop";
      keep-history-for = 3;  # months
    };
    
    # Screen Edges Actions
    "kwinrc".ElectricBorders = {
      Bottom = "None";
      BottomLeft = "PresentWindows";
      BottomRight = "ShowDesktop";
      Left = "None";
      Right = "None";
      Top = "None";
      TopLeft = "Overview";
      TopRight = "DesktopGrid";
    };
    
    # Mouse Actions on Desktop
    "kwinrc".MouseBindings = {
      CommandActiveTitlebar1 = "Raise";
      CommandActiveTitlebar2 = "Nothing";
      CommandActiveTitlebar3 = "Operations menu";
      CommandAll1 = "Move";
      CommandAll2 = "Toggle raise and lower";
      CommandAll3 = "Resize";
      CommandAllKey = "Meta";
      CommandAllWheel = "Nothing";
      CommandInactiveTitlebar1 = "Activate and raise";
      CommandInactiveTitlebar2 = "Nothing";
      CommandInactiveTitlebar3 = "Operations menu";
      CommandTitlebarWheel = "Nothing";
      CommandWindow1 = "Activate, raise and pass click";
      CommandWindow2 = "Activate and pass click";
      CommandWindow3 = "Activate and pass click";
      CommandWindowWheel = "Scroll";
    };
    
    # Global Shortcuts - Extended configuration
    "kglobalshortcutsrc".kwin = {
      # Desktop switching
      "Switch to Desktop 1" = "Meta+1,none,Switch to Desktop 1";
      "Switch to Desktop 2" = "Meta+2,none,Switch to Desktop 2";
      "Switch to Desktop 3" = "Meta+3,none,Switch to Desktop 3";
      "Switch to Desktop 4" = "Meta+4,none,Switch to Desktop 4";
      
      # Move windows to desktops
      "Window to Desktop 1" = "Meta+Shift+1,none,Window to Desktop 1";
      "Window to Desktop 2" = "Meta+Shift+2,none,Window to Desktop 2";
      "Window to Desktop 3" = "Meta+Shift+3,none,Window to Desktop 3";
      "Window to Desktop 4" = "Meta+Shift+4,none,Window to Desktop 4";
      
      # Desktop navigation
      "Switch One Desktop Down" = "Meta+Ctrl+Down,none,Switch One Desktop Down";
      "Switch One Desktop Up" = "Meta+Ctrl+Up,none,Switch One Desktop Up";
      "Switch One Desktop to the Left" = "Meta+Ctrl+Left,none,Switch One Desktop to the Left";
      "Switch One Desktop to the Right" = "Meta+Ctrl+Right,none,Switch One Desktop to the Right";
      
      # Window management
      "Overview" = "Meta+W,none,Toggle Overview";
      "Expose" = "Meta+Tab,none,Toggle Present Windows (Current desktop)";
      "ExposeAll" = "Meta+Shift+Tab,none,Toggle Present Windows (All desktops)";
      "DesktopGrid" = "Meta+F8,none,Show Desktop Grid";
      
      # Window operations
      "Window Maximize" = "Meta+Up,none,Maximize Window";
      "Window Minimize" = "Meta+Down,none,Minimize Window";
      "Window Close" = "Alt+F4,none,Close Window";
      "Window Fullscreen" = "none,none,Make Window Fullscreen";
      "Window Operations Menu" = "Alt+F3,none,Window Operations Menu";
      
      # Window tiling
      "Window Quick Tile Bottom" = "Meta+Alt+Down,none,Quick Tile Window to the Bottom";
      "Window Quick Tile Top" = "Meta+Alt+Up,none,Quick Tile Window to the Top";
      "Window Quick Tile Left" = "Meta+Alt+Left,none,Quick Tile Window to the Left";
      "Window Quick Tile Right" = "Meta+Alt+Right,none,Quick Tile Window to the Right";
      
      # Special features
      "ShowDesktop" = "Meta+D,none,Show Desktop";
      "Activate Window Demanding Attention" = "Meta+A,none,Activate Window Demanding Attention";
      "Kill Window" = "Meta+Ctrl+Esc,none,Kill Window";
      
      # Zoom
      "view_zoom_in" = "Meta+=,none,Zoom In";
      "view_zoom_out" = "Meta+-,none,Zoom Out";
      "view_actual_size" = "Meta+0,none,Actual Size";
      
      # Activities shortcuts (when activities are enabled)
      "switch to next activity" = "Meta+Period,none,Walk through activities";
      "switch to previous activity" = "Meta+Comma,none,Walk through activities (Reverse)";
      "ActivityManager" = "Meta+Q,none,Show Activity Switcher";
    };
    
    # Window Rules Examples
    "kwinrulesrc"."1" = {
      Description = "Firefox on Desktop 2";
      desktop = 2;
      desktoprule = 2;  # Force
      wmclass = "firefox";
      wmclasscomplete = false;
      wmclassmatch = 1;  # Contains
    };
    
    "kwinrulesrc"."2" = {
      Description = "Konsole Always on Top";
      above = true;
      aboverule = 2;  # Force
      wmclass = "konsole";
      wmclasscomplete = false;
      wmclassmatch = 1;  # Contains
    };
    
    "kwinrulesrc"."3" = {
      Description = "Discord on Desktop 2 Maximized";
      desktop = 2;
      desktoprule = 2;  # Force
      maximizehoriz = true;
      maximizehorizrule = 3;  # Apply Initially
      maximizevert = true;
      maximizevertrule = 3;  # Apply Initially
      wmclass = "discord";
      wmclasscomplete = false;
      wmclassmatch = 1;  # Contains
    };
    
    # Additional KDE Global Settings
    "kdeglobals".KDE = {
      AnimationDurationFactor = 1;
      ShowDeleteCommand = false;
      SingleClick = false;  # Double-click to open
      widgetStyle = "Breeze";
    };
    
    "kdeglobals".General = {
      AccentColor = "128,178,230";  # Light blue accent
      ColorScheme = "BreezeDark";
      TerminalApplication = "konsole";
      TerminalService = "org.kde.konsole.desktop";
      XftAntialias = true;
      XftHintStyle = "hintslight";
      XftSubPixel = "rgb";
      fixed = "FiraCode Nerd Font Mono,11,-1,5,50,0,0,0,0,0";
      font = "Noto Sans,10,-1,5,50,0,0,0,0,0";
      menuFont = "Noto Sans,10,-1,5,50,0,0,0,0,0";
      smallestReadableFont = "Noto Sans,8,-1,5,50,0,0,0,0,0";
      toolBarFont = "Noto Sans,10,-1,5,50,0,0,0,0,0";
    };
    
    # Input Configuration
    "kcminputrc".Mouse = {
      cursorSize = if osConfig.networking.hostName == "nixos-m1" then 32 else 24;
      cursorTheme = "breeze_cursors";
    };
    
    "kcminputrc".Keyboard = {
      KeyboardRepeating = 0;
      NumLock = 0;  # Leave unchanged
      RepeatDelay = 600;
      RepeatRate = 25;
    };
    
    # Touchpad Configuration (for M1)
    "kcminputrc".Libinput = lib.mkIf (osConfig.networking.hostName == "nixos-m1") {
      ClickMethod = 2;  # Two-finger click for right-click
      NaturalScroll = true;
      PointerAcceleration = "0.2";
      TapToClick = true;
    };
    
    # Note: Power Management and Notification configurations with deeply nested keys
    # are not supported by plasma-manager's current structure.
    # These would need to be configured via GUI or rc2nix tool.
    
    # Example of what would be configured (currently commented out):
    # "powermanagementprofilesrc"."AC.Display" would control AC power display settings
    # "plasmanotifyrc"."Applications.discord" would control Discord notifications
    
    # Baloo File Indexer
    "baloofilerc"."Basic Settings" = {
      "Indexing-Enabled" = true;
      "only basic indexing" = false;
    };
    
    "baloofilerc".General = {
      dbVersion = 2;
      "exclude filters" = "*.log,*.tmp,node_modules/,target/,.git/";
      "exclude filters version" = 8;
    };
    
    # Screen Locker
    "kscreenlockerrc".Daemon = {
      Autolock = true;
      LockGrace = 5;
      LockOnResume = true;
      Timeout = 10;  # minutes
    };
    
    # Note: Deeply nested wallpaper config not supported by plasma-manager
    # Would need to be configured via GUI or rc2nix tool
    
    # Session Management
    "ksmserverrc".General = {
      confirmLogout = true;
      excludeApps = "";
      loginMode = "default";
      offerShutdown = true;
      shutdownType = 2;  # Shutdown
    };
    
    # Klipper Clipboard Manager
    "ksmserverrc"."org.kde.klipper".autostart = true;
    
    "klipperrc".General = {
      KeepClipboardContents = true;
      MaxClipItems = 100;
      PreventEmptyClipboard = true;
      SyncClipboards = true;
    };
    
    # KRunner Configuration
    "krunnerrc".General = {
      ActivateWhenTypingOnDesktop = true;
      FreeFloating = true;
      HistoryEnabled = true;
      RetainPriorSearch = false;
    };
    
    "krunnerrc".Plugins = {
      baloosearchEnabled = true;
      calculatorEnabled = true;
      "org.kde.datetime" = true;
      "org.kde.windowedwidgets" = false;
      recentdocumentsEnabled = true;
      servicesEnabled = true;
      shellEnabled = true;
      webshortcutsEnabled = true;
    };
    
    # Display scaling configuration based on system
    # M1 needs higher DPI/scale for Retina display, Hetzner needs lower for RDP
    "kcmfonts".General.forceFontDPI = 
      if osConfig.networking.hostName == "nixos-m1" then 180 else 100;
    
    "kdeglobals".KScreen.ScreenScaleFactors = 
      if osConfig.networking.hostName == "nixos-m1" 
      then "eDP-1=2;" 
      else "XORGXRDP0=1.15;";
    
    # Icons Theme
    "kdeglobals".Icons.Theme = "breeze-dark";
    
    # Configure KDE Wallet for 1Password support with minimal interference
    "kwalletrc"."Wallet" = {
      "Enabled" = true;  # Enable for 1Password's keyring needs
      "First Use" = false;
      "Use One Wallet" = true;  # Single wallet for simplicity
      "Close When Idle" = false;  # Keep open to avoid repeated prompts
      "Close on Screensaver" = false;
      "Default Wallet" = "kdewallet";
      "Password Length" = 32;  # Stronger password
      "Prompt on Open" = false;  # Minimize prompts
      "Leave Manager Open" = false;  # Don't show manager window
      "Leave Open" = true;  # Keep wallet open to reduce prompts
      "Cipher" = "Blowfish";  # Encryption cipher
      "Auto Deny" = false;
      "Auto Allow" = true;  # Auto-allow trusted apps
      "Show Manager" = false;
    };
    
    # Auto-allow 1Password applications
    "kwalletrc"."Auto Allow" = {
      "1password" = true;
      "1Password" = true;
      "op" = true;
    };
    
    # Grant full access to 1Password
    "kwalletrc"."AccessControl" = {
      "1password" = "*";
      "1Password" = "*";
      "op" = "*";
    };
    
    # Auto-close wallet manager window but keep service running
    "kwalletmanagerrc"."General" = {
      "AutoStart" = false;  # Don't show manager GUI
      "ShowInSystemTray" = false;  # No tray icon
      "Close To Tray" = false;
    };
    
    # Configure applications to use KDE Wallet only when necessary
    "kdeglobals"."Passwords" = {
      "UseKWallet" = true;  # Available for apps that need it (like 1Password)
    };
  };
}
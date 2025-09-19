{lib, ...}: let
  generated = {
    configFile = {
      baloofilerc = {
        "Basic Settings" = {
          Indexing-Enabled = true;
          "only basic indexing" = false;
        };
        General = {
          dbVersion = 2;
          "exclude filters" = "*.log,*.tmp,node_modules/,target/,.git/";
          "exclude filters version" = 8;
        };
      };
      dolphinrc = {
        General = {
          ViewPropsTimestamp = "2025,9,19,10,21,1.124";
        };
        "KFileDialog Settings" = {
          "Places Icons Auto-resize" = false;
          "Places Icons Static Size" = 22;
        };
      };
      kactivitymanagerdrc = {
        "0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4" = {
          Description = "General development workspace and experiments.";
          Icon = "applications-engineering";
          Name = "Dev";
        };
        "6ed332bc-fa61-5381-511d-4d5ba44a293b" = {
          Description = "System configuration, infra-as-code, and declarative desktop tweaks.";
          Icon = "nix-snowflake";
          Name = "NixOS";
        };
        activities = {
          "0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4" = "Dev";
          "6ed332bc-fa61-5381-511d-4d5ba44a293b" = "NixOS";
          b4f4e6c4-e52c-1f6b-97f5-567b04283fac = "Stacks";
          dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = "Backstage";
        };
        activities-descriptions = {
          "0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4" = "General development workspace and experiments.";
          "6ed332bc-fa61-5381-511d-4d5ba44a293b" = "System configuration, infra-as-code, and declarative desktop tweaks.";
          b4f4e6c4-e52c-1f6b-97f5-567b04283fac = "Platform engineering stacks and deployment playbooks.";
          dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = "Backstage developer portal and CNOE platform.";
        };
        activities-icons = {
          "0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4" = "applications-engineering";
          "6ed332bc-fa61-5381-511d-4d5ba44a293b" = "nix-snowflake";
          b4f4e6c4-e52c-1f6b-97f5-567b04283fac = "application-x-yaml";
          dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = "applications-development";
        };
        b4f4e6c4-e52c-1f6b-97f5-567b04283fac = {
          Description = "Platform engineering stacks and deployment playbooks.";
          Icon = "application-x-yaml";
          Name = "Stacks";
        };
        dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = {
          Description = "Backstage developer portal and CNOE platform.";
          Icon = "applications-development";
          Name = "Backstage";
        };
        main = {
          currentActivity = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
          runningActivities = "b4f4e6c4-e52c-1f6b-97f5-567b04283fac,dcc377c8-d627-4d0b-8dd7-27d83f8282b3,0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4,6ed332bc-fa61-5381-511d-4d5ba44a293b";
          stoppedActivities = "";
        };
      };
      kcminputrc = {
        Keyboard = {
          KeyboardRepeating = 0;
          NumLock = 0;
          RepeatDelay = 600;
          RepeatRate = 25;
        };
        Mouse = {
          cursorSize = 24;
          cursorTheme = "breeze_cursors";
        };
      };
      kded5rc = {
        Module-device_automounter = {
          autoload = false;
        };
      };
      kdeglobals = {
        General = {
          AccentColor = "128,178,230";
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
        Icons = {
          Theme = "Papirus-Dark";
        };
        KDE = {
          AnimationDurationFactor = 1;
          ShowDeleteCommand = false;
          SingleClick = false;
          widgetStyle = "Breeze";
        };
        KScreen = {
          ScreenScaleFactors = "XORGXRDP0=1.15;";
        };
        "KShortcutsDialog Settings" = {
          "Dialog Size" = "600,480";
        };
        Passwords = {
          UseKWallet = true;
        };
        WM = {
          activeBackground = "39,44,49";
          activeBlend = "252,252,252";
          activeForeground = "252,252,252";
          inactiveBackground = "32,36,40";
          inactiveBlend = "161,169,177";
          inactiveForeground = "161,169,177";
        };
      };
      klipperrc = {
        General = {
          KeepClipboardContents = true;
          MaxClipItems = 100;
          PreventEmptyClipboard = true;
          SyncClipboards = true;
        };
      };
      krunnerrc = {
        General = {
          ActivateWhenTypingOnDesktop = true;
          FreeFloating = true;
          HistoryEnabled = true;
          RetainPriorSearch = false;
        };
        Plugins = {
          baloosearchEnabled = true;
          calculatorEnabled = true;
          "org.kde.datetime" = true;
          "org.kde.windowedwidgets" = false;
          recentdocumentsEnabled = true;
          servicesEnabled = true;
          shellEnabled = true;
          webshortcutsEnabled = true;
        };
      };
      kscreenlockerrc = {
        Daemon = {
          Autolock = true;
          LockGrace = 5;
          LockOnResume = true;
          Timeout = 10;
        };
      };
      ksmserverrc = {
        General = {
          confirmLogout = true;
          excludeApps = "";
          loginMode = "default";
          offerShutdown = true;
          shutdownType = 2;
        };
        "SubSession: 2051858d-90bf-40ba-9f0c-183a9f266df0" = {
          count = 0;
        };
        "SubSession: 2e03af40-7a66-4052-be6c-4bb22790625a" = {
          count = 0;
        };
        "SubSession: 46d5b60f-26f7-4eeb-a478-c127edbd6880" = {
          count = 0;
        };
        "SubSession: 8d6c6639-7ffd-4e70-92d1-9c87fb3e4c55" = {
          count = 0;
        };
        "SubSession: 9208007a-b52d-4548-9593-cef43dbdda5f" = {
          count = 0;
        };
        "SubSession: 98b93db7-e611-468d-a18e-2db116e7c246" = {
          count = 0;
        };
        "SubSession: a105b4a3-5257-407e-8111-aa8bdd272eb6" = {
          count = 0;
        };
        "SubSession: d3ecf427-d25f-4c48-b233-0495fb6d01fe" = {
          count = 0;
        };
        "SubSession: ee09d5b7-4647-4a5e-b1b7-5934e793becc" = {
          count = 0;
        };
        "org.kde.klipper" = {
          autostart = true;
        };
      };
      kuriikwsfilterrc = {
        General = {
          DefaultWebShortcut = "ddg";
          EnableWebShortcuts = true;
          KeywordDelimiter = 58;
          PreferredWebShortcuts = "nixos,nix,github";
          UsePreferredWebShortcutsOnly = false;
        };
        nix = {
          Name = "NixOS Packages";
          Query = "https://search.nixos.org/packages?queryx3d\\{@}";
        };
        nixopt = {
          Charset = "utf-8";
          Name = "NixOS Options";
          Query = "https://search.nixos.org/options?queryx3d\\{@}";
        };
        nixos = {
          Charset = "utf-8";
          Name = "NixOS Package Search";
          Query = "https://search.nixos.org/packages?queryx3d\\{@}";
        };
        nixpkgs = {
          Charset = "utf-8";
          Name = "Nixpkgs GitHub Search";
          Query = "https://github.com/NixOS/nixpkgs/search?qx3d\\{@}";
        };
        nixwiki = {
          Name = "NixOS Wiki";
          Query = "https://wiki.nixos.org/index.php?searchx3d\\{@}";
        };
      };
      kwalletrc = {
        AccessControl = {
          "1Password" = "*";
          "1password" = "*";
          op = "*";
        };
        "Auto Allow" = {
          "1Password" = true;
          "1password" = true;
          op = true;
        };
        Wallet = {
          "Auto Allow" = true;
          "Auto Deny" = false;
          Cipher = "Blowfish";
          "Close When Idle" = false;
          "Close on Screensaver" = false;
          "Default Wallet" = "kdewallet";
          Enabled = true;
          "First Use" = false;
          "Leave Manager Open" = false;
          "Leave Open" = true;
          "Password Length" = 32;
          "Prompt on Open" = false;
          "Show Manager" = false;
          "Use One Wallet" = true;
        };
      };
      kwinrc = {
        Compositing = {
          Backend = "OpenGL";
          Enabled = true;
          GLCore = true;
          GLPreferBufferSwap = "a";
          HiddenPreviews = 5;
          OpenGLIsUnsafe = false;
          WindowsBlockCompositing = true;
        };
        Desktops = {
          Id_1 = "68e1c320-3d23-41ac-aac6-f7f92da7bcbd";
          Id_2 = "3e4c7f2d-c428-4587-861a-43fac2ba47b5";
          Id_3 = "94c23eba-0cfc-4020-afe2-a50d33386599";
          Id_4 = "d55470a1-67df-4668-9714-3f7e5f4466d0";
          Number = 4;
          Rows = 2;
        };
        Effect-PresentWindows = {
          BorderActivate = 0;
          BorderActivateAll = 0;
          BorderActivateClass = 0;
        };
        Effect-desktopgrid = {
          BorderActivate = 0;
          DesktopNameAlignment = 0;
          LayoutMode = 1;
          ShowAddRemove = true;
        };
        Effect-overview = {
          BorderActivate = 0;
          BorderActivateAll = 0;
        };
        ElectricBorders = {
          Bottom = "None";
          BottomLeft = "None";
          BottomRight = "None";
          Left = "None";
          Right = "None";
          Top = "None";
          TopLeft = "None";
          TopRight = "None";
        };
        MouseBindings = {
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
        Plugins = {
          blurEnabled = true;
          contrastEnabled = true;
          desktopgridEnabled = true;
          highlightwindowEnabled = true;
          kwin4_effect_dimscreenEnabled = true;
          kwin4_effect_translucencyEnabled = false;
          magiclampEnabled = true;
          overviewEnabled = false;
          slideEnabled = true;
          wobblywindowsEnabled = false;
          zoomEnabled = true;
        };
        "SubSession: 2051858d-90bf-40ba-9f0c-183a9f266df0" = {
          active = "-1";
          count = 0;
        };
        "SubSession: 2e03af40-7a66-4052-be6c-4bb22790625a" = {
          active = "-1";
          count = 0;
        };
        "SubSession: 46d5b60f-26f7-4eeb-a478-c127edbd6880" = {
          active = "-1";
          count = 0;
        };
        "SubSession: 9208007a-b52d-4548-9593-cef43dbdda5f" = {
          active = "-1";
          count = 0;
        };
        "SubSession: 98b93db7-e611-468d-a18e-2db116e7c246" = {
          active = "-1";
          count = 0;
        };
        "SubSession: d3ecf427-d25f-4c48-b233-0495fb6d01fe" = {
          active = "-1";
          count = 0;
        };
        "SubSession: ee09d5b7-4647-4a5e-b1b7-5934e793becc" = {
          active = "-1";
          count = 0;
        };
        TabBox = {
          ActivitiesMode = 1;
          ApplicationsMode = 0;
          BorderActivate = 0;
          BorderAlternativeActivate = 0;
          DesktopMode = 1;
          HighlightWindows = true;
          LayoutName = "thumbnail_grid";
          MinimizedMode = 0;
          MultiScreenMode = 1;
          ShowDesktopMode = 0;
          ShowTabBox = true;
          SwitchingMode = 0;
        };
        Tiling = {
          padding = 4;
        };
        "Tiling/7672d168-2ff3-5755-8864-62ce0326032c" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
        "Tiling/a941f271-1df2-5896-9240-4f1a4693889e" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
        "Tiling/bf638f19-0052-5377-bbec-c3966fb73cc5" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
        Windows = {
          ActiveMouseScreen = false;
          AutoRaise = false;
          AutoRaiseInterval = 750;
          ClickRaise = true;
          DelayFocusInterval = 300;
          FocusPolicy = "ClickToFocus";
          FocusStealingPreventionLevel = 1;
          NextFocusPrefersMouse = false;
          RollOverDesktops = true;
          SeparateScreenFocus = false;
        };
      };
      plasma-localerc = {
        Formats = {
          LANG = "en_US.UTF-8";
        };
      };
      plasmarc = {
        Theme = {
          name = "breeze-dark";
        };
      };
      spectaclerc = {
        ImageSave = {
          translatedScreenshotsFolder = "Screenshots";
        };
        VideoSave = {
          translatedScreencastsFolder = "Screencasts";
        };
      };
    };
    dataFile = {
      "kate/anonymous.katesession" = {
        "Document 0" = {
          URL = "";
        };
        "Kate Plugins" = {
          bookmarksplugin = false;
          cmaketoolsplugin = false;
          compilerexplorer = false;
          eslintplugin = false;
          externaltoolsplugin = true;
          formatplugin = false;
          katebacktracebrowserplugin = false;
          katebuildplugin = false;
          katecloseexceptplugin = false;
          katecolorpickerplugin = false;
          katectagsplugin = false;
          katefilebrowserplugin = false;
          katefiletreeplugin = true;
          kategdbplugin = false;
          kategitblameplugin = false;
          katekonsoleplugin = true;
          kateprojectplugin = true;
          katereplicodeplugin = false;
          katesearchplugin = true;
          katesnippetsplugin = false;
          katesqlplugin = false;
          katesymbolviewerplugin = false;
          katexmlcheckplugin = false;
          katexmltoolsplugin = false;
          keyboardmacrosplugin = false;
          ktexteditorpreviewplugin = false;
          latexcompletionplugin = false;
          lspclientplugin = true;
          openlinkplugin = false;
          rainbowparens = false;
          rbqlplugin = false;
          tabswitcherplugin = true;
          templateplugin = false;
          textfilterplugin = true;
        };
        MainWindow0 = {
          "Active ViewSpace" = 0;
          Kate-MDI-H-Splitter = "0,595,0";
          Kate-MDI-Sidebar-0-Bar-0-TvList = "kate_private_plugin_katefiletreeplugin,kateproject,kateprojectgit,lspclient_symbol_outline";
          Kate-MDI-Sidebar-0-LastSize = 200;
          Kate-MDI-Sidebar-0-SectSizes = 0;
          Kate-MDI-Sidebar-0-Splitter = 401;
          Kate-MDI-Sidebar-1-Bar-0-TvList = "";
          Kate-MDI-Sidebar-1-LastSize = 200;
          Kate-MDI-Sidebar-1-SectSizes = 0;
          Kate-MDI-Sidebar-1-Splitter = 401;
          Kate-MDI-Sidebar-2-Bar-0-TvList = "";
          Kate-MDI-Sidebar-2-LastSize = 200;
          Kate-MDI-Sidebar-2-SectSizes = 0;
          Kate-MDI-Sidebar-2-Splitter = 595;
          Kate-MDI-Sidebar-3-Bar-0-TvList = "output,diagnostics,kate_plugin_katesearch,kateprojectinfo,kate_private_plugin_katekonsoleplugin";
          Kate-MDI-Sidebar-3-LastSize = 200;
          Kate-MDI-Sidebar-3-SectSizes = 0;
          Kate-MDI-Sidebar-3-Splitter = 348;
          Kate-MDI-Sidebar-Style = 2;
          Kate-MDI-Sidebar-Visible = true;
          Kate-MDI-ToolView-diagnostics-Position = 3;
          Kate-MDI-ToolView-diagnostics-Show-Button-In-Sidebar = true;
          Kate-MDI-ToolView-diagnostics-Visible = false;
          Kate-MDI-ToolView-kate_plugin_katesearch-Position = 3;
          Kate-MDI-ToolView-kate_plugin_katesearch-Show-Button-In-Sidebar = true;
          Kate-MDI-ToolView-kate_plugin_katesearch-Visible = false;
          Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Position = 0;
          Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Show-Button-In-Sidebar = true;
          Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Visible = false;
          Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Position = 3;
          Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Show-Button-In-Sidebar = true;
          Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Visible = false;
          Kate-MDI-ToolView-kateproject-Position = 0;
          Kate-MDI-ToolView-kateproject-Show-Button-In-Sidebar = true;
          Kate-MDI-ToolView-kateproject-Visible = false;
          Kate-MDI-ToolView-kateprojectgit-Position = 0;
          Kate-MDI-ToolView-kateprojectgit-Show-Button-In-Sidebar = true;
          Kate-MDI-ToolView-kateprojectgit-Visible = false;
          Kate-MDI-ToolView-kateprojectinfo-Position = 3;
          Kate-MDI-ToolView-kateprojectinfo-Show-Button-In-Sidebar = true;
          Kate-MDI-ToolView-kateprojectinfo-Visible = false;
          Kate-MDI-ToolView-lspclient_symbol_outline-Position = 0;
          Kate-MDI-ToolView-lspclient_symbol_outline-Show-Button-In-Sidebar = true;
          Kate-MDI-ToolView-lspclient_symbol_outline-Visible = false;
          Kate-MDI-ToolView-output-Position = 3;
          Kate-MDI-ToolView-output-Show-Button-In-Sidebar = true;
          Kate-MDI-ToolView-output-Visible = false;
          Kate-MDI-V-Splitter = "0,401,0";
        };
        "MainWindow0 Settings" = {
          WindowState = 8;
        };
        "MainWindow0-Splitter 0" = {
          Children = "MainWindow0-ViewSpace 0";
          Orientation = 1;
          Sizes = 595;
        };
        "MainWindow0-ViewSpace 0" = {
          "Active View" = 0;
          Count = 1;
          Documents = 0;
          "View 0" = 0;
        };
        "Open Documents" = {
          Count = 1;
        };
        "Open MainWindows" = {
          Count = 1;
        };
        "Plugin:kateprojectplugin:" = {
          projects = "";
        };
        "Plugin:katesearchplugin:MainWindow:0" = {
          BinaryFiles = false;
          CurrentExcludeFilter = "-1";
          CurrentFilter = "-1";
          ExcludeFilters = "";
          ExpandSearchResults = false;
          Filters = "";
          FollowSymLink = false;
          HiddenFiles = false;
          MatchCase = false;
          Place = 1;
          Recursive = true;
          Replaces = "";
          Search = "";
          SearchAsYouTypeAllProjects = true;
          SearchAsYouTypeCurrentFile = true;
          SearchAsYouTypeFolder = true;
          SearchAsYouTypeOpenFiles = true;
          SearchAsYouTypeProject = true;
          SearchDiskFiles = "";
          SearchDiskFiless = "";
          SizeLimit = 128;
          UseRegExp = false;
        };
      };
    };
    shortcuts = {
      ActivityManager = {
        switch-to-activity-0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4 = "Meta+4,none,Switch to activity \"Dev\"";
        switch-to-activity-6ed332bc-fa61-5381-511d-4d5ba44a293b = "Meta+1,none,Switch to activity \"NixOS\"";
        switch-to-activity-b4f4e6c4-e52c-1f6b-97f5-567b04283fac = "Meta+2,none,Switch to activity \"Stacks\"";
        switch-to-activity-dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = "Meta+3,none,Switch to activity \"Backstage\"";
      };
      "KDE Keyboard Layout Switcher" = {
        "Switch to Last-Used Keyboard Layout" = "Meta+Alt+L,none,Switch to Last-Used Keyboard Layout";
        "Switch to Next Keyboard Layout" = "Meta+Alt+K,none,Switch to Next Keyboard Layout";
      };
      kaccess = {
        "Toggle Screen Reader On and Off" = "Meta+Alt+S";
      };
      kmix = {
        decrease_microphone_volume = "Microphone Volume Down";
        decrease_volume = "Volume Down";
        decrease_volume_small = "Shift+Volume Down";
        increase_microphone_volume = "Microphone Volume Up";
        increase_volume = "Volume Up";
        increase_volume_small = "Shift+Volume Up";
        mic_mute = [
          "Microphone Mute"
          "Meta+Volume Mute,Microphone Mute"
          "Meta+Volume Mute,Mute Microphone"
        ];
        mute = "Volume Mute";
      };
      ksmserver = {
        "Halt Without Confirmation" = "none,,Shut Down Without Confirmation";
        "Lock Session" = [
          "Meta+L"
          "Screensaver,Meta+L"
          "Screensaver,Lock Session"
        ];
        "Log Out" = "Ctrl+Alt+Del";
        "Log Out Without Confirmation" = "none,,Log Out Without Confirmation";
        LogOut = "none,,Log Out";
        Reboot = "none,,Reboot";
        "Reboot Without Confirmation" = "none,,Reboot Without Confirmation";
        "Shut Down" = "none,,Shut Down";
      };
      kwin = {
        "Activate Window Demanding Attention" = "Meta+Ctrl+A";
        "Decrease Opacity" = "none,,Decrease Opacity of Active Window by 5%";
        "Edit Tiles" = "Meta+T";
        Expose = "Ctrl+F9";
        ExposeAll = [
          "Ctrl+F10"
          "Launch (C),Ctrl+F10"
          "Launch (C),Toggle Present Windows (All desktops)"
        ];
        ExposeClass = "Ctrl+F7";
        ExposeClassCurrentDesktop = [];
        "Increase Opacity" = "none,,Increase Opacity of Active Window by 5%";
        "Kill Window" = "Meta+Ctrl+Esc";
        MoveMouseToCenter = "Meta+F6";
        MoveMouseToFocus = "Meta+F5";
        MoveZoomDown = [];
        MoveZoomLeft = [];
        MoveZoomRight = [];
        MoveZoomUp = [];
        "Setup Window Shortcut" = "none,,Setup Window Shortcut";
        "Show Desktop" = "Meta+D";
        "Suspend Compositing" = "Alt+Shift+F12";
        "Switch One Desktop Down" = "Meta+Ctrl+Down";
        "Switch One Desktop Up" = "Meta+Ctrl+Up";
        "Switch One Desktop to the Left" = "Meta+Ctrl+Left";
        "Switch One Desktop to the Right" = "Meta+Ctrl+Right";
        "Switch Window Down" = "Meta+Alt+Down";
        "Switch Window Left" = "Meta+Alt+Left";
        "Switch Window Right" = "Meta+Alt+Right";
        "Switch Window Up" = "Meta+Alt+Up";
        "Switch to Desktop 1" = "Ctrl+F1";
        "Switch to Desktop 10" = "none,,Switch to Desktop 10";
        "Switch to Desktop 11" = "none,,Switch to Desktop 11";
        "Switch to Desktop 12" = "none,,Switch to Desktop 12";
        "Switch to Desktop 13" = "none,,Switch to Desktop 13";
        "Switch to Desktop 14" = "none,,Switch to Desktop 14";
        "Switch to Desktop 15" = "none,,Switch to Desktop 15";
        "Switch to Desktop 16" = "none,,Switch to Desktop 16";
        "Switch to Desktop 17" = "none,,Switch to Desktop 17";
        "Switch to Desktop 18" = "none,,Switch to Desktop 18";
        "Switch to Desktop 19" = "none,,Switch to Desktop 19";
        "Switch to Desktop 2" = "Ctrl+F2";
        "Switch to Desktop 20" = "none,,Switch to Desktop 20";
        "Switch to Desktop 3" = "Ctrl+F3";
        "Switch to Desktop 4" = "Ctrl+F4";
        "Switch to Desktop 5" = "none,,Switch to Desktop 5";
        "Switch to Desktop 6" = "none,,Switch to Desktop 6";
        "Switch to Desktop 7" = "none,,Switch to Desktop 7";
        "Switch to Desktop 8" = "none,,Switch to Desktop 8";
        "Switch to Desktop 9" = "none,,Switch to Desktop 9";
        "Switch to Next Desktop" = "none,,Switch to Next Desktop";
        "Switch to Next Screen" = "none,,Switch to Next Screen";
        "Switch to Previous Desktop" = "none,,Switch to Previous Desktop";
        "Switch to Previous Screen" = "none,,Switch to Previous Screen";
        "Switch to Screen 0" = "none,,Switch to Screen 0";
        "Switch to Screen 1" = "none,,Switch to Screen 1";
        "Switch to Screen 2" = "none,,Switch to Screen 2";
        "Switch to Screen 3" = "none,,Switch to Screen 3";
        "Switch to Screen 4" = "none,,Switch to Screen 4";
        "Switch to Screen 5" = "none,,Switch to Screen 5";
        "Switch to Screen 6" = "none,,Switch to Screen 6";
        "Switch to Screen 7" = "none,,Switch to Screen 7";
        "Switch to Screen Above" = "none,,Switch to Screen Above";
        "Switch to Screen Below" = "none,,Switch to Screen Below";
        "Switch to Screen to the Left" = "none,,Switch to Screen to the Left";
        "Switch to Screen to the Right" = "none,,Switch to Screen to the Right";
        "Toggle Night Color" = [];
        "Toggle Window Raise/Lower" = "none,,Toggle Window Raise/Lower";
        "Walk Through Windows" = [
          "Meta+Tab"
          "Alt+Tab,Meta+Tab"
          "Alt+Tab,Walk Through Windows"
        ];
        "Walk Through Windows (Reverse)" = [
          "Meta+Shift+Tab"
          "Alt+Shift+Tab,Meta+Shift+Tab"
          "Alt+Shift+Tab,Walk Through Windows (Reverse)"
        ];
        "Walk Through Windows Alternative" = [];
        "Walk Through Windows Alternative (Reverse)" = [];
        "Walk Through Windows of Current Application" = [
          "Meta+`"
          "Alt+`,Meta+`"
          "Alt+`,Walk Through Windows of Current Application"
        ];
        "Walk Through Windows of Current Application (Reverse)" = [
          "Meta+~"
          "Alt+~,Meta+~"
          "Alt+~,Walk Through Windows of Current Application (Reverse)"
        ];
        "Walk Through Windows of Current Application Alternative" = [];
        "Walk Through Windows of Current Application Alternative (Reverse)" = [];
        "Window Above Other Windows" = "none,,Keep Window Above Others";
        "Window Below Other Windows" = "none,,Keep Window Below Others";
        "Window Close" = "Alt+F4";
        "Window Custom Quick Tile Bottom" = "none,,Custom Quick Tile Window to the Bottom";
        "Window Custom Quick Tile Left" = "none,,Custom Quick Tile Window to the Left";
        "Window Custom Quick Tile Right" = "none,,Custom Quick Tile Window to the Right";
        "Window Custom Quick Tile Top" = "none,,Custom Quick Tile Window to the Top";
        "Window Fullscreen" = "none,,Make Window Fullscreen";
        "Window Grow Horizontal" = "none,,Expand Window Horizontally";
        "Window Grow Vertical" = "none,,Expand Window Vertically";
        "Window Lower" = "none,,Lower Window";
        "Window Maximize" = "Meta+PgUp";
        "Window Maximize Horizontal" = "none,,Maximize Window Horizontally";
        "Window Maximize Vertical" = "none,,Maximize Window Vertically";
        "Window Minimize" = "Meta+PgDown";
        "Window Move" = "none,,Move Window";
        "Window Move Center" = "none,,Move Window to the Center";
        "Window No Border" = "none,,Toggle Window Titlebar and Frame";
        "Window On All Desktops" = "none,,Keep Window on All Desktops";
        "Window One Desktop Down" = "Meta+Ctrl+Shift+Down";
        "Window One Desktop Up" = "Meta+Ctrl+Shift+Up";
        "Window One Desktop to the Left" = "Meta+Ctrl+Shift+Left";
        "Window One Desktop to the Right" = "Meta+Ctrl+Shift+Right";
        "Window One Screen Down" = "none,,Move Window One Screen Down";
        "Window One Screen Up" = "none,,Move Window One Screen Up";
        "Window One Screen to the Left" = "none,,Move Window One Screen to the Left";
        "Window One Screen to the Right" = "none,,Move Window One Screen to the Right";
        "Window Operations Menu" = "Alt+F3";
        "Window Pack Down" = "none,,Move Window Down";
        "Window Pack Left" = "none,,Move Window Left";
        "Window Pack Right" = "none,,Move Window Right";
        "Window Pack Up" = "none,,Move Window Up";
        "Window Quick Tile Bottom" = "Meta+Down";
        "Window Quick Tile Bottom Left" = "none,,Quick Tile Window to the Bottom Left";
        "Window Quick Tile Bottom Right" = "none,,Quick Tile Window to the Bottom Right";
        "Window Quick Tile Left" = "Meta+Left";
        "Window Quick Tile Right" = "Meta+Right";
        "Window Quick Tile Top" = "Meta+Up";
        "Window Quick Tile Top Left" = "none,,Quick Tile Window to the Top Left";
        "Window Quick Tile Top Right" = "none,,Quick Tile Window to the Top Right";
        "Window Raise" = "none,,Raise Window";
        "Window Resize" = "none,,Resize Window";
        "Window Shade" = "none,,Shade Window";
        "Window Shrink Horizontal" = "none,,Shrink Window Horizontally";
        "Window Shrink Vertical" = "none,,Shrink Window Vertically";
        "Window to Desktop 1" = "none,,Window to Desktop 1";
        "Window to Desktop 10" = "none,,Window to Desktop 10";
        "Window to Desktop 11" = "none,,Window to Desktop 11";
        "Window to Desktop 12" = "none,,Window to Desktop 12";
        "Window to Desktop 13" = "none,,Window to Desktop 13";
        "Window to Desktop 14" = "none,,Window to Desktop 14";
        "Window to Desktop 15" = "none,,Window to Desktop 15";
        "Window to Desktop 16" = "none,,Window to Desktop 16";
        "Window to Desktop 17" = "none,,Window to Desktop 17";
        "Window to Desktop 18" = "none,,Window to Desktop 18";
        "Window to Desktop 19" = "none,,Window to Desktop 19";
        "Window to Desktop 2" = "none,,Window to Desktop 2";
        "Window to Desktop 20" = "none,,Window to Desktop 20";
        "Window to Desktop 3" = "none,,Window to Desktop 3";
        "Window to Desktop 4" = "none,,Window to Desktop 4";
        "Window to Desktop 5" = "none,,Window to Desktop 5";
        "Window to Desktop 6" = "none,,Window to Desktop 6";
        "Window to Desktop 7" = "none,,Window to Desktop 7";
        "Window to Desktop 8" = "none,,Window to Desktop 8";
        "Window to Desktop 9" = "none,,Window to Desktop 9";
        "Window to Next Desktop" = "none,,Window to Next Desktop";
        "Window to Next Screen" = "Meta+Shift+Right";
        "Window to Previous Desktop" = "none,,Window to Previous Desktop";
        "Window to Previous Screen" = "Meta+Shift+Left";
        "Window to Screen 0" = "none,,Move Window to Screen 0";
        "Window to Screen 1" = "none,,Move Window to Screen 1";
        "Window to Screen 2" = "none,,Move Window to Screen 2";
        "Window to Screen 3" = "none,,Move Window to Screen 3";
        "Window to Screen 4" = "none,,Move Window to Screen 4";
        "Window to Screen 5" = "none,,Move Window to Screen 5";
        "Window to Screen 6" = "none,,Move Window to Screen 6";
        "Window to Screen 7" = "none,,Move Window to Screen 7";
        view_actual_size = "Meta+0";
        view_zoom_in = [
          "Meta++"
          "Meta+=,Meta++"
          "Meta+=,Zoom In"
        ];
        view_zoom_out = "Meta+-";
      };
      mediacontrol = {
        mediavolumedown = "none,,Media volume down";
        mediavolumeup = "none,,Media volume up";
        nextmedia = "Media Next";
        pausemedia = "Media Pause";
        playmedia = "none,,Play media playback";
        playpausemedia = "Media Play";
        previousmedia = "Media Previous";
        stopmedia = "Media Stop";
      };
      org_kde_powerdevil = {
        "Decrease Keyboard Brightness" = "Keyboard Brightness Down";
        "Decrease Screen Brightness" = "Monitor Brightness Down";
        "Decrease Screen Brightness Small" = "Shift+Monitor Brightness Down";
        Hibernate = "Hibernate";
        "Increase Keyboard Brightness" = "Keyboard Brightness Up";
        "Increase Screen Brightness" = "Monitor Brightness Up";
        "Increase Screen Brightness Small" = "Shift+Monitor Brightness Up";
        PowerDown = "Power Down";
        PowerOff = "Power Off";
        Sleep = "Sleep";
        "Toggle Keyboard Backlight" = "Keyboard Light On/Off";
        "Turn Off Screen" = [];
        powerProfile = [
          "Battery"
          "Meta+B,Battery"
          "Meta+B,Switch Power Profile"
        ];
      };
      plasmashell = {
        "activate application launcher" = [
          "Meta"
          "Alt+F1,Meta"
          "Alt+F1,Activate Application Launcher"
        ];
        "activate task manager entry 1" = "none,Meta+1,Activate Task Manager Entry 1";
        "activate task manager entry 10" = "none,,Activate Task Manager Entry 10";
        "activate task manager entry 2" = "none,Meta+2,Activate Task Manager Entry 2";
        "activate task manager entry 3" = "none,Meta+3,Activate Task Manager Entry 3";
        "activate task manager entry 4" = "none,Meta+4,Activate Task Manager Entry 4";
        "activate task manager entry 5" = "Meta+5";
        "activate task manager entry 6" = "Meta+6";
        "activate task manager entry 7" = "Meta+7";
        "activate task manager entry 8" = "Meta+8";
        "activate task manager entry 9" = "Meta+9";
        clear-history = "none,,Clear Clipboard History";
        clipboard_action = "Meta+Ctrl+X";
        cycle-panels = "Meta+Alt+P";
        cycleNextAction = "none,,Next History Item";
        cyclePrevAction = "none,,Previous History Item";
        edit_clipboard = "none,,Edit Contents…";
        "manage activities" = "Meta+Q";
        "next activity" = "Meta+A,none,Walk through activities";
        "previous activity" = "Meta+Shift+A,none,Walk through activities (Reverse)";
        repeat_action = "none,,Manually Invoke Action on Current Clipboard";
        "show dashboard" = "Ctrl+F12";
        show-barcode = "none,,Show Barcode…";
        show-on-mouse-pos = "Meta+V";
        "stop current activity" = "Meta+S";
        "switch to next activity" = "none,,Switch to Next Activity";
        "switch to previous activity" = "none,,Switch to Previous Activity";
        "toggle do not disturb" = "none,,Toggle do not disturb";
      };
      "services/code-activity.desktop" = {
        _launch = "Ctrl+Alt+C";
      };
      "services/dolphin-activity.desktop" = {
        _launch = "Ctrl+Alt+F";
      };
      "services/konsole-activity.desktop" = {
        _launch = "Ctrl+Alt+T";
      };
      "services/org.kde.konsole.desktop" = {
        _launch = [];
      };
      "services/services\\/code-activity.desktop" = {
        _launch = "Ctrl+Alt+C";
      };
      "services/services\\/dolphin-activity.desktop" = {
        _launch = "Ctrl+Alt+F";
      };
      "services/services\\/konsole-activity.desktop" = {
        _launch = "Ctrl+Alt+T";
      };
      "services/services\\/yakuake-activity.desktop" = {
        _launch = "F12";
      };
      "services/yakuake-activity.desktop" = {
        _launch = [];
      };
      yakuake = {
        toggle-window-state = "none,F12,Open/Retract Yakuake";
      };
    };
  };
in {
  programs.plasma =
    {
      enable = lib.mkDefault true;
    }
    // generated;
}

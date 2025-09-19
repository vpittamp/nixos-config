{lib, ...}: let
  generated = {
    configFile = {
      baloofilerc = {
        General = {
          dbVersion = 2;
          "exclude filters" = "*~,*.part,*.o,*.la,*.lo,*.loT,*.moc,moc_*.cpp,qrc_*.cpp,ui_*.h,cmake_install.cmake,CMakeCache.txt,CTestTestfile.cmake,libtool,config.status,confdefs.h,autom4te,conftest,confstat,Makefile.am,*.gcode,.ninja_deps,.ninja_log,build.ninja,*.csproj,*.m4,*.rej,*.gmo,*.pc,*.omf,*.aux,*.tmp,*.po,*.vm*,*.nvram,*.rcore,*.swp,*.swap,lzo,litmain.sh,*.orig,.histfile.*,.xsession-errors*,*.map,*.so,*.a,*.db,*.qrc,*.ini,*.init,*.img,*.vdi,*.vbox*,vbox.log,*.qcow2,*.vmdk,*.vhd,*.vhdx,*.sql,*.sql.gz,*.ytdl,*.tfstate*,*.class,*.pyc,*.pyo,*.elc,*.qmlc,*.jsc,*.fastq,*.fq,*.gb,*.fasta,*.fna,*.gbff,*.faa,po,CVS,.svn,.git,_darcs,.bzr,.hg,CMakeFiles,CMakeTmp,CMakeTmpQmake,.moc,.obj,.pch,.uic,.npm,.yarn,.yarn-cache,__pycache__,node_modules,node_packages,nbproject,.terraform,.venv,venv,core-dumps,lost+found";
          "exclude filters version" = 9;
        };
      };
      kactivitymanagerdrc = {
        activities = {
          "9407befb-12cd-4127-8552-7ab56c6d6a5a" = "Default";
        };
        main = {
          currentActivity = "9407befb-12cd-4127-8552-7ab56c6d6a5a";
        };
      };
      kded5rc = {
        Module-device_automounter = {
          autoload = false;
        };
      };
      kdeglobals = {
        WM = {
          activeBackground = "227,229,231";
          activeBlend = "227,229,231";
          activeForeground = "35,38,41";
          inactiveBackground = "239,240,241";
          inactiveBlend = "239,240,241";
          inactiveForeground = "112,125,138";
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
        Wallet = {
          "First Use" = false;
        };
      };
      kwinrc = {
        Desktops = {
          Id_1 = "5ce8a17c-4bba-4ed9-b9ec-2b87a2000ee2";
          Number = 1;
          Rows = 1;
        };
        Tiling = {
          padding = 4;
        };
        "Tiling/7672d168-2ff3-5755-8864-62ce0326032c" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
        "Tiling/bf638f19-0052-5377-bbec-c3966fb73cc5" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
      };
      plasma-localerc = {
        Formats = {
          LANG = "en_US.UTF-8";
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
        switch-to-activity-0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4 = "Meta+Ctrl+2,none,Switch to activity \"Dev\"";
        switch-to-activity-6ed332bc-fa61-5381-511d-4d5ba44a293b = "Meta+Ctrl+3,none,Switch to activity \"NixOS\"";
        switch-to-activity-9407befb-12cd-4127-8552-7ab56c6d6a5a = [];
        switch-to-activity-b4f4e6c4-e52c-1f6b-97f5-567b04283fac = "Meta+Ctrl+4,none,Switch to activity \"Stacks\"";
        switch-to-activity-dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = "Meta+Ctrl+1,none,Switch to activity \"Backstage\"";
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
        "Halt Without Confirmation" = [];
        "Lock Session" = [
          "Meta+L"
          "Screensaver,Meta+L"
          "Screensaver,Lock Session"
        ];
        "Log Out" = "Ctrl+Alt+Del";
        "Log Out Without Confirmation" = [];
        LogOut = [];
        Reboot = [];
        "Reboot Without Confirmation" = [];
        "Shut Down" = [];
      };
      kwin = {
        "Activate Window Demanding Attention" = "Meta+Ctrl+A";
        "Cycle Overview" = [];
        "Cycle Overview Opposite" = [];
        "Decrease Opacity" = [];
        "Edit Tiles" = "Meta+T";
        Expose = "Ctrl+F9";
        ExposeAll = [
          "Ctrl+F10"
          "Launch (C),Ctrl+F10"
          "Launch (C),Toggle Present Windows (All desktops)"
        ];
        ExposeClass = "Ctrl+F7";
        ExposeClassCurrentDesktop = [];
        "Grid View" = "Meta+G";
        "Increase Opacity" = [];
        "Kill Window" = "Meta+Ctrl+Esc";
        MoveMouseToCenter = "Meta+F6";
        MoveMouseToFocus = "Meta+F5";
        MoveZoomDown = [];
        MoveZoomLeft = [];
        MoveZoomRight = [];
        MoveZoomUp = [];
        Overview = "Meta+W";
        "Setup Window Shortcut" = [];
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
        "Switch to Desktop 10" = [];
        "Switch to Desktop 11" = [];
        "Switch to Desktop 12" = [];
        "Switch to Desktop 13" = [];
        "Switch to Desktop 14" = [];
        "Switch to Desktop 15" = [];
        "Switch to Desktop 16" = [];
        "Switch to Desktop 17" = [];
        "Switch to Desktop 18" = [];
        "Switch to Desktop 19" = [];
        "Switch to Desktop 2" = "Ctrl+F2";
        "Switch to Desktop 20" = [];
        "Switch to Desktop 3" = "Ctrl+F3";
        "Switch to Desktop 4" = "Ctrl+F4";
        "Switch to Desktop 5" = [];
        "Switch to Desktop 6" = [];
        "Switch to Desktop 7" = [];
        "Switch to Desktop 8" = [];
        "Switch to Desktop 9" = [];
        "Switch to Next Desktop" = [];
        "Switch to Next Screen" = [];
        "Switch to Previous Desktop" = [];
        "Switch to Previous Screen" = [];
        "Switch to Screen 0" = [];
        "Switch to Screen 1" = [];
        "Switch to Screen 2" = [];
        "Switch to Screen 3" = [];
        "Switch to Screen 4" = [];
        "Switch to Screen 5" = [];
        "Switch to Screen 6" = [];
        "Switch to Screen 7" = [];
        "Switch to Screen Above" = [];
        "Switch to Screen Below" = [];
        "Switch to Screen to the Left" = [];
        "Switch to Screen to the Right" = [];
        "Toggle Night Color" = [];
        "Toggle Window Raise/Lower" = [];
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
        "Window Above Other Windows" = [];
        "Window Below Other Windows" = [];
        "Window Close" = "Alt+F4";
        "Window Custom Quick Tile Bottom" = [];
        "Window Custom Quick Tile Left" = [];
        "Window Custom Quick Tile Right" = [];
        "Window Custom Quick Tile Top" = [];
        "Window Fullscreen" = [];
        "Window Grow Horizontal" = [];
        "Window Grow Vertical" = [];
        "Window Lower" = [];
        "Window Maximize" = "Meta+PgUp";
        "Window Maximize Horizontal" = [];
        "Window Maximize Vertical" = [];
        "Window Minimize" = "Meta+PgDown";
        "Window Move" = [];
        "Window Move Center" = [];
        "Window No Border" = [];
        "Window On All Desktops" = [];
        "Window One Desktop Down" = "Meta+Ctrl+Shift+Down";
        "Window One Desktop Up" = "Meta+Ctrl+Shift+Up";
        "Window One Desktop to the Left" = "Meta+Ctrl+Shift+Left";
        "Window One Desktop to the Right" = "Meta+Ctrl+Shift+Right";
        "Window One Screen Down" = [];
        "Window One Screen Up" = [];
        "Window One Screen to the Left" = [];
        "Window One Screen to the Right" = [];
        "Window Operations Menu" = "Alt+F3";
        "Window Pack Down" = [];
        "Window Pack Left" = [];
        "Window Pack Right" = [];
        "Window Pack Up" = [];
        "Window Quick Tile Bottom" = "Meta+Down";
        "Window Quick Tile Bottom Left" = [];
        "Window Quick Tile Bottom Right" = [];
        "Window Quick Tile Left" = "Meta+Left";
        "Window Quick Tile Right" = "Meta+Right";
        "Window Quick Tile Top" = "Meta+Up";
        "Window Quick Tile Top Left" = [];
        "Window Quick Tile Top Right" = [];
        "Window Raise" = [];
        "Window Resize" = [];
        "Window Shade" = [];
        "Window Shrink Horizontal" = [];
        "Window Shrink Vertical" = [];
        "Window to Desktop 1" = [];
        "Window to Desktop 10" = [];
        "Window to Desktop 11" = [];
        "Window to Desktop 12" = [];
        "Window to Desktop 13" = [];
        "Window to Desktop 14" = [];
        "Window to Desktop 15" = [];
        "Window to Desktop 16" = [];
        "Window to Desktop 17" = [];
        "Window to Desktop 18" = [];
        "Window to Desktop 19" = [];
        "Window to Desktop 2" = [];
        "Window to Desktop 20" = [];
        "Window to Desktop 3" = [];
        "Window to Desktop 4" = [];
        "Window to Desktop 5" = [];
        "Window to Desktop 6" = [];
        "Window to Desktop 7" = [];
        "Window to Desktop 8" = [];
        "Window to Desktop 9" = [];
        "Window to Next Desktop" = [];
        "Window to Next Screen" = "Meta+Shift+Right";
        "Window to Previous Desktop" = [];
        "Window to Previous Screen" = "Meta+Shift+Left";
        "Window to Screen 0" = [];
        "Window to Screen 1" = [];
        "Window to Screen 2" = [];
        "Window to Screen 3" = [];
        "Window to Screen 4" = [];
        "Window to Screen 5" = [];
        "Window to Screen 6" = [];
        "Window to Screen 7" = [];
        view_actual_size = "Meta+0";
        view_zoom_in = [
          "Meta++"
          "Meta+=,Meta++"
          "Meta+=,Zoom In"
        ];
        view_zoom_out = "Meta+-";
      };
      mediacontrol = {
        mediavolumedown = [];
        mediavolumeup = [];
        nextmedia = "Media Next";
        pausemedia = "Media Pause";
        playmedia = [];
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
        "activate task manager entry 1" = "Meta+1";
        "activate task manager entry 10" = [];
        "activate task manager entry 2" = "Meta+2";
        "activate task manager entry 3" = "Meta+3";
        "activate task manager entry 4" = "Meta+4";
        "activate task manager entry 5" = "Meta+5";
        "activate task manager entry 6" = "Meta+6";
        "activate task manager entry 7" = "Meta+7";
        "activate task manager entry 8" = "Meta+8";
        "activate task manager entry 9" = "Meta+9";
        clear-history = [];
        clipboard_action = "Meta+Ctrl+X";
        cycle-panels = "Meta+Alt+P";
        cycleNextAction = [];
        cyclePrevAction = [];
        edit_clipboard = [];
        "manage activities" = "Meta+Q";
        "next activity" = "Meta+A,none,Walk through activities";
        "previous activity" = "Meta+Shift+A,none,Walk through activities (Reverse)";
        repeat_action = [];
        "show dashboard" = "Ctrl+F12";
        show-barcode = [];
        show-on-mouse-pos = "Meta+V";
        "stop current activity" = "Meta+S";
        "switch to next activity" = [];
        "switch to previous activity" = [];
        "toggle do not disturb" = [];
      };
      yakuake = {
        toggle-window-state = "F12";
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

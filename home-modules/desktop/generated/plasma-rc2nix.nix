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
      dolphinrc = {
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
        "645bcfb7-e769-4000-93be-ad31eb77ea2e" = {
          Description = "System resource monitoring and performance dashboards.";
          Icon = "utilities-system-monitor";
          Name = "Monitoring";
        };
        "6ed332bc-fa61-5381-511d-4d5ba44a293b" = {
          Description = "System configuration, infra-as-code, and declarative desktop tweaks.";
          Icon = "nix-snowflake";
          Name = "NixOS";
        };
        activities = {
          "645bcfb7-e769-4000-93be-ad31eb77ea2e" = "Monitoring";
          "6ed332bc-fa61-5381-511d-4d5ba44a293b" = "NixOS";
          b4f4e6c4-e52c-1f6b-97f5-567b04283fac = "Stacks";
          dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = "Backstage";
        };
        activities-descriptions = {
          "645bcfb7-e769-4000-93be-ad31eb77ea2e" = "System resource monitoring and performance dashboards.";
          "6ed332bc-fa61-5381-511d-4d5ba44a293b" = "System configuration, infra-as-code, and declarative desktop tweaks.";
          b4f4e6c4-e52c-1f6b-97f5-567b04283fac = "Platform engineering stacks and deployment playbooks.";
          dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = "Backstage developer portal and CNOE platform.";
        };
        activities-icons = {
          "645bcfb7-e769-4000-93be-ad31eb77ea2e" = "utilities-system-monitor";
          "6ed332bc-fa61-5381-511d-4d5ba44a293b" = "nix-snowflake";
          b4f4e6c4-e52c-1f6b-97f5-567b04283fac = "folder-git";
          dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = "applications-development";
        };
        b4f4e6c4-e52c-1f6b-97f5-567b04283fac = {
          Description = "Platform engineering stacks and deployment playbooks.";
          Icon = "folder-git";
          Name = "Stacks";
        };
        dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = {
          Description = "Backstage developer portal and CNOE platform.";
          Icon = "applications-development";
          Name = "Backstage";
        };
        main = {
          currentActivity = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
          runningActivities = "6ed332bc-fa61-5381-511d-4d5ba44a293b,dcc377c8-d627-4d0b-8dd7-27d83f8282b3,645bcfb7-e769-4000-93be-ad31eb77ea2e,b4f4e6c4-e52c-1f6b-97f5-567b04283fac";
          stoppedActivities = "";
        };
      };
      kcminputrc = {
        Mouse = {
          X11LibInputXAccelProfileFlat = true;
        };
      };
      kded5rc = {
        Module-device_automounter = {
          autoload = false;
        };
      };
      kdeglobals = {
        "DirSelect Dialog" = {
          "DirSelectDialog Size" = "922,558";
          "Splitter State" = "x00x00x00xffx00x00x00x01x00x00x00x02x00x00x00x8cx00x00x02xa8x00xffxffxffxffx01x00x00x00x01x00";
        };
        Icons = {
          Theme = "Papirus-Dark";
        };
        "KFileDialog Settings" = {
          "Allow Expansion" = false;
          "Automatically select filename extension" = true;
          "Breadcrumb Navigation" = true;
          "Decoration position" = 2;
          "LocationCombo Completionmode" = 5;
          "PathCombo Completionmode" = 5;
          "Show Full Path" = false;
          "Show Inline Previews" = true;
          "Show Speedbar" = true;
          "Show hidden files" = false;
          "Sort by" = "Name";
          "Sort directories first" = true;
          "Sort hidden files last" = false;
          "Sort reversed" = false;
          "Speedbar Width" = 140;
          "View Style" = "DetailTree";
        };
        KScreen = {
          ScreenScaleFactors = "XORGXRDP0=1.15;";
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
      ksmserverrc = {
        "SubSession: 0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4" = {
          count = 0;
        };
        "SubSession: 6ed332bc-fa61-5381-511d-4d5ba44a293b" = {
          clientId1 = "101c711014e139000175838168800000112530020";
          count = 1;
          "discardCommand1[\$e]" = "rm,$HOME/.config/session/konsole_101c711014e139000175838168800000112530020_1758389434_272140";
          program1 = "konsole";
          restartCommand1 = "konsole,-session,101c711014e139000175838168800000112530020_1758389434_272140,-name,konsole";
          restartStyleHint1 = 0;
          userId1 = "vpittamp";
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
          "Close When Idle" = false;
          "Close on Screensaver" = false;
          "Default Wallet" = "kdewallet";
          Enabled = true;
          "First Use" = false;
          "Prompt on Open" = false;
          "Use One Wallet" = true;
        };
      };
      kwinrc = {
        "Activities/LastVirtualDesktop" = {
          "6ed332bc-fa61-5381-511d-4d5ba44a293b" = "e15d21e9-5abb-4207-8fbd-94b434f7ff39";
        };
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
          Id_1 = "e15d21e9-5abb-4207-8fbd-94b434f7ff39";
          Id_2 = "0da4e7df-0bcb-4bfe-9128-f403b46b68e6";
          Number = 2;
          Rows = 1;
        };
        Effect-Overview = {
          BorderActivate = 9;
        };
        Effect-PresentWindows = {
          BorderActivate = 9;
          BorderActivateAll = 9;
          BorderActivateClass = 9;
        };
        Plugins = {
          blurEnabled = true;
          contrastEnabled = true;
          desktopgridEnabled = false;
          mouseclickEnabled = false;
          overviewEnabled = true;
          presentwindowsEnabled = false;
          screenedgeEnabled = false;
          slideEnabled = true;
          windowviewEnabled = true;
          wobblywindowsEnabled = false;
          zoomEnabled = true;
        };
        "SubSession: 0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4" = {
          active = "-1";
          count = 0;
        };
        "SubSession: 6ed332bc-fa61-5381-511d-4d5ba44a293b" = {
          active = "-1";
          activities1 = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
          count = 1;
          desktop1 = 1;
          fsrestore1 = "1180,0,0,0";
          fullscreen1 = 0;
          geometry1 = "1180,28,1440,841";
          iconified1 = false;
          keepBelow1 = false;
          maximize1 = 3;
          opacity1 = 1;
          resourceClass1 = "konsole";
          resourceName1 = "konsole";
          restore1 = "1260,48.875,1280,779";
          sessionId1 = "101c711014e139000175838168800000112530020";
          shaded1 = false;
          shortcut1 = "";
          skipPager1 = false;
          skipSwitcher1 = false;
          skipTaskbar1 = false;
          stackingOrder1 = 10;
          staysOnTop1 = false;
          sticky1 = false;
          userNoBorder1 = false;
          windowRole1 = "MainWindow#1";
          windowType1 = "Normal";
          wmCommand1 = "";
        };
        TabBox = {
          BorderActivate = 9;
          BorderAlternativeActivate = 9;
        };
        Tiling = {
          padding = 4;
        };
        "Tiling/0da4e7df-0bcb-4bfe-9128-f403b46b68e6/859058d4-0384-41e6-b029-222d8a9bc250" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
        "Tiling/7672d168-2ff3-5755-8864-62ce0326032c" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
        "Tiling/9350f969-92d0-5658-bb27-639b07d90acc" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
        "Tiling/a941f271-1df2-5896-9240-4f1a4693889e" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
        "Tiling/bf638f19-0052-5377-bbec-c3966fb73cc5" = {
          tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
        };
        "Tiling/e15d21e9-5abb-4207-8fbd-94b434f7ff39/859058d4-0384-41e6-b029-222d8a9bc250" = {
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
        Xwayland = {
          Scale = 1;
        };
      };
      kwinrulesrc = {
        "1" = {
          Description = "VS Code - Backstage";
          activity = "dcc377c8-d627-4d0b-8dd7-27d83f8282b3";
          activityrule = 2;
          clientmachine = "localhost";
          title = "/home/vpittamp/backstage-cnoe";
          titlematch = 1;
          types = 1;
          wmclass = "code";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "10" = {
          Description = "VS Code - Stacks";
          activity = "b4f4e6c4-e52c-1f6b-97f5-567b04283fac";
          activityrule = 2;
          clientmachine = "localhost";
          title = "/home/vpittamp/stacks";
          titlematch = 1;
          types = 1;
          wmclass = "code";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "11" = {
          Description = "Konsole - Stacks";
          activity = "b4f4e6c4-e52c-1f6b-97f5-567b04283fac";
          activityrule = 2;
          clientmachine = "localhost";
          title = "stacks";
          titlematch = 1;
          types = 1;
          wmclass = "konsole";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "12" = {
          Description = "Dolphin - Stacks";
          activity = "b4f4e6c4-e52c-1f6b-97f5-567b04283fac";
          activityrule = 2;
          clientmachine = "localhost";
          title = "stacks";
          titlematch = 1;
          types = 1;
          wmclass = "dolphin";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "13" = {
          Description = "VS Code - Stacks";
          activity = "b4f4e6c4-e52c-1f6b-97f5-567b04283fac";
          activityrule = 2;
          clientmachine = "localhost";
          title = "/home/vpittamp/stacks";
          titlematch = 1;
          types = 1;
          wmclass = "code";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "14" = {
          Description = "Konsole - Stacks";
          activity = "b4f4e6c4-e52c-1f6b-97f5-567b04283fac";
          activityrule = 2;
          clientmachine = "localhost";
          title = "stacks";
          titlematch = 1;
          types = 1;
          wmclass = "konsole";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "15" = {
          Description = "Dolphin - Stacks";
          activity = "b4f4e6c4-e52c-1f6b-97f5-567b04283fac";
          activityrule = 2;
          clientmachine = "localhost";
          title = "stacks";
          titlematch = 1;
          types = 1;
          wmclass = "dolphin";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "2" = {
          Description = "Konsole - Backstage";
          activity = "dcc377c8-d627-4d0b-8dd7-27d83f8282b3";
          activityrule = 2;
          clientmachine = "localhost";
          title = "backstage-cnoe";
          titlematch = 1;
          types = 1;
          wmclass = "konsole";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "3" = {
          Description = "Dolphin - Backstage";
          activity = "dcc377c8-d627-4d0b-8dd7-27d83f8282b3";
          activityrule = 2;
          clientmachine = "localhost";
          title = "backstage-cnoe";
          titlematch = 1;
          types = 1;
          wmclass = "dolphin";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "4" = {
          Description = "VS Code - Monitoring";
          activity = "645bcfb7-e769-4000-93be-ad31eb77ea2e";
          activityrule = 2;
          clientmachine = "localhost";
          title = "/home/vpittamp/coordination";
          titlematch = 1;
          types = 1;
          wmclass = "code";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "5" = {
          Description = "Konsole - Monitoring";
          activity = "645bcfb7-e769-4000-93be-ad31eb77ea2e";
          activityrule = 2;
          clientmachine = "localhost";
          title = "coordination";
          titlematch = 1;
          types = 1;
          wmclass = "konsole";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "6" = {
          Description = "Dolphin - Monitoring";
          activity = "645bcfb7-e769-4000-93be-ad31eb77ea2e";
          activityrule = 2;
          clientmachine = "localhost";
          title = "coordination";
          titlematch = 1;
          types = 1;
          wmclass = "dolphin";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "7" = {
          Description = "VS Code - NixOS";
          activity = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
          activityrule = 2;
          clientmachine = "localhost";
          title = "/etc/nixos";
          titlematch = 1;
          types = 1;
          wmclass = "code";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "8" = {
          Description = "Konsole - NixOS";
          activity = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
          activityrule = 2;
          clientmachine = "localhost";
          title = "nixos";
          titlematch = 1;
          types = 1;
          wmclass = "konsole";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        "9" = {
          Description = "Dolphin - NixOS";
          activity = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
          activityrule = 2;
          clientmachine = "localhost";
          title = "nixos";
          titlematch = 1;
          types = 1;
          wmclass = "dolphin";
          wmclasscomplete = false;
          wmclassmatch = 1;
        };
        General = {
          count = 12;
          rules = "1,2,3,4,5,6,7,8,9,10,11,12";
        };
      };
      plasma-localerc = {
        Formats = {
          LANG = "en_US.UTF-8";
        };
      };
      plasmanotifyrc = {
        "Applications/net.mkiol.SpeechNote" = {
          Seen = true;
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
        "manage activities" = "Meta+W";
        "stop current activity" = [];
        "switch to next activity" = [];
        "switch to previous activity" = "Meta+Shift+Tab,none,Switch to Previous Activity";
        switch-to-activity-645bcfb7-e769-4000-93be-ad31eb77ea2e = "Meta+Ctrl+1,none,Switch to activity \"Monitoring\"";
        switch-to-activity-6ed332bc-fa61-5381-511d-4d5ba44a293b = [];
        switch-to-activity-b4f4e6c4-e52c-1f6b-97f5-567b04283fac = "Meta+Ctrl+3,none,Switch to activity \"Stacks\"";
        switch-to-activity-dcc377c8-d627-4d0b-8dd7-27d83f8282b3 = "Meta+Ctrl+4,none,Switch to activity \"Backstage\"";
      };
      "KDE Keyboard Layout Switcher" = {
        "Switch to Last-Used Keyboard Layout" = "Meta+Alt+L";
        "Switch to Next Keyboard Layout" = "Meta+Alt+K";
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
        "Cycle Overview" = [];
        "Cycle Overview Opposite" = [];
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
        "Grid View" = "Meta+G";
        "Increase Opacity" = "none,,Increase Opacity of Active Window by 5%";
        "Kill Window" = "Meta+Ctrl+Esc";
        MoveMouseToCenter = "Meta+F6";
        MoveMouseToFocus = "Meta+F5";
        MoveZoomDown = [];
        MoveZoomLeft = [];
        MoveZoomRight = [];
        MoveZoomUp = [];
        Overview = "Meta+F8,Meta+W,Toggle Overview";
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
        "Switch to Desktop 1" = "Meta+1,Ctrl+F1,Switch to Desktop 1";
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
        "Switch to Desktop 2" = "Meta+2,Ctrl+F2,Switch to Desktop 2";
        "Switch to Desktop 20" = "none,,Switch to Desktop 20";
        "Switch to Desktop 3" = "Meta+3,Ctrl+F3,Switch to Desktop 3";
        "Switch to Desktop 4" = "Meta+4,Ctrl+F4,Switch to Desktop 4";
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
          "Alt+Tab,Meta+Tab"
          "Alt+Tab,Walk Through Windows"
        ];
        "Walk Through Windows (Reverse)" = [
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
        "Window Minimize" = "none,Meta+PgDown,Minimize Window";
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
        "Window to Desktop 1" = "Meta+Shift+1,,Window to Desktop 1";
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
        "Window to Desktop 2" = "Meta+Shift+2,,Window to Desktop 2";
        "Window to Desktop 20" = "none,,Window to Desktop 20";
        "Window to Desktop 3" = "Meta+Shift+3,,Window to Desktop 3";
        "Window to Desktop 4" = "Meta+Shift+4,,Window to Desktop 4";
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
        "activate task manager entry 5" = "none,Meta+5,Activate Task Manager Entry 5";
        "activate task manager entry 6" = "none,Meta+6,Activate Task Manager Entry 6";
        "activate task manager entry 7" = "none,Meta+7,Activate Task Manager Entry 7";
        "activate task manager entry 8" = "none,Meta+8,Activate Task Manager Entry 8";
        "activate task manager entry 9" = "none,Meta+9,Activate Task Manager Entry 9";
        clear-history = "none,,Clear Clipboard History";
        clipboard_action = "Meta+Ctrl+X";
        cycle-panels = "Meta+Alt+P";
        cycleNextAction = "none,,Next History Item";
        cyclePrevAction = "none,,Previous History Item";
        edit_clipboard = "none,,Edit Contents…";
        "manage activities" = [
          "Meta+Q"
          "Ctrl+Alt+A,Meta+Q,Show Activity Switcher"
        ];
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
      "services/org.kde.konsole.desktop" = {
        _launch = [];
      };
      "services/plasma-manager-commands.desktop" = {
        launch-code-activity = "Ctrl+Alt+E";
        launch-dolphin-activity = "Ctrl+Alt+D";
        launch-konsole-activity = "Ctrl+Alt+T";
        speech-to-clipboard = "Meta+Alt+C";
        toggle-speech-dictation = "Meta+Alt+D";
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

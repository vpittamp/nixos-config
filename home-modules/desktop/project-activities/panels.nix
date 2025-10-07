{ lib, config, osConfig, activities, mkUUID, ... }@args:

let
  # Machine-specific PWA IDs
  # Each machine generates unique IDs when PWAs are installed
  # Run 'pwa-get-ids' on each machine after installing PWAs to get these IDs

  # Get hostname from osConfig which is passed from NixOS to home-manager
  hostname = osConfig.networking.hostName or "";

  # Hetzner server PWA IDs (updated 2025-09-28 with new Backstage URL)
  hetznerIds = {
    googleId = "01K665SPD8EPMP3JTW02JM1M0Z";  # Google AI mode
    youtubeId = "01K666N2V6BQMDSBMX3AY74TY7";  # YouTube with proper icon
    giteaId = "01K665SRSVT5KS6ZG7QKCRW2WG";
    backstageId = "01K6BFEMQCS9JFJKWPAB2N2RB4";  # Backstage at cnoe.localtest.me:8443
    kargoId = "01K665SVEFF313F0BEWFJ8S9PE";
    argoCDId = "01K665SWVY47Y54NDQJVXG2R7D";
    homeAssistantId = "01K66QAZXGDH3SBWPPNPV1YGRH";  # Home Assistant
    uberEatsId = "01K66QB12CHJDWAET5M9BKPEF5";  # Uber Eats
  };

  # M1 MacBook PWA IDs (updated 2025-09-27)
  m1Ids = {
    googleId = "01K664F9E8KXZPXYF4V1Q8A93V";  # Google AI mode
    youtubeId = "01K663E3K8FMGTFVQ6Z6Q2RX7X";
    giteaId = "01K663E4T77WRVG5SVE0WQQPT0";
    backstageId = "01K663E623PJ5W8R659HGSCXBS";
    kargoId = "01K663E79AJG7Z2PSRWF0SXFBE";
    argoCDId = "01K663E8S01M7HTQG6VQ5YF8PY";
    homeAssistantId = "01K66AGFCPXE13NK7YXFEF78BN";  # Home Assistant
    uberEatsId = "01K66F8FWRP6643P7V6QQWA28X";  # Uber Eats
  };

  # Select appropriate IDs based on hostname
  pwaIds =
    if hostname == "nixos-hetzner" then hetznerIds
    else if hostname == "nixos-m1" then m1Ids
    else hetznerIds;  # Default to Hetzner for now

  # Generate PWA launcher list for plasma-manager
  pwaLaunchers =
    let
      inherit (pwaIds) googleId youtubeId giteaId backstageId kargoId argoCDId homeAssistantId uberEatsId;
    in [
      "file:///home/vpittamp/.local/share/applications/FFPWA-${googleId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${youtubeId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${giteaId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${backstageId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${kargoId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${argoCDId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${homeAssistantId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${uberEatsId}.desktop"
    ];

  # Base launchers (common apps)
  baseLaunchers = [
    "applications:firefox.desktop"
    "applications:org.kde.dolphin.desktop"
    "applications:org.kde.konsole.desktop"
  ];

  # Combined launcher list
  allLaunchers = baseLaunchers ++ pwaLaunchers;

in {
  # Primary panel configuration using plasma-manager declarative API
  panels = [
    # Main panel (bottom, all activities)
    {
      location = "bottom";
      height = 44;
      lengthMode = "fill";
      alignment = "center";
      hiding = "none";
      floating = false;

      widgets = [
        # Application launcher
        {
          name = "org.kde.plasma.kickoff";
          config.General.favoritesPortedToKAstats = true;
        }

        # Icon tasks (with PWA launchers)
        {
          name = "org.kde.plasma.icontasks";
          config.General = {
            launchers = allLaunchers;
            showOnlyCurrentActivity = true;
            showOnlyCurrentDesktop = false;
            showOnlyCurrentScreen = true;
            # Icon size for M1 at 1.75x scaling
            iconSize = lib.mkIf (hostname == "nixos-m1") 16;
          };
        }

        # Panel spacer (expanding)
        {
          name = "org.kde.plasma.panelspacer";
          config.General.expanding = true;
        }

        # Activity manager
        "org.kde.plasma.showActivityManager"

        # Panel spacer (expanding)
        {
          name = "org.kde.plasma.panelspacer";
          config.General.expanding = true;
        }

        # Margin separator
        "org.kde.plasma.marginsseparator"

        # System tray
        {
          name = "org.kde.plasma.systemtray";
          config = {
            General = {
              extraItems = "org.kde.plasma.notifications,org.kde.plasma.manage-inputmethod,org.kde.plasma.devicenotifier,org.kde.plasma.clipboard,org.kde.plasma.cameraindicator,org.kde.plasma.printmanager,org.kde.plasma.battery,org.kde.plasma.keyboardindicator,org.kde.plasma.brightness,org.kde.plasma.keyboardlayout,org.kde.plasma.weather,org.kde.kdeconnect,org.kde.plasma.bluetooth,org.kde.plasma.mediacontroller,org.kde.plasma.volume,org.kde.kscreen";
              knownItems = "org.kde.plasma.notifications,org.kde.plasma.manage-inputmethod,org.kde.plasma.devicenotifier,org.kde.plasma.clipboard,org.kde.plasma.cameraindicator,org.kde.plasma.printmanager,org.kde.plasma.battery,org.kde.plasma.keyboardindicator,org.kde.plasma.brightness,org.kde.plasma.keyboardlayout,org.kde.plasma.weather,org.kde.kdeconnect,org.kde.plasma.bluetooth,org.kde.plasma.mediacontroller,org.kde.plasma.volume,org.kde.kscreen";
            };
          };
        }

        # Digital clock
        {
          name = "org.kde.plasma.digitalclock";
          config.Appearance.fontWeight = 400;
        }

        # Show desktop
        "org.kde.plasma.showdesktop"
      ];
    }

    # Monitoring activity panel (top, monitoring activity only)
    {
      location = "top";
      height = 44;
      lengthMode = "fill";
      alignment = "center";
      hiding = "none";
      floating = false;
      screen = 0;

      widgets = [
        # CPU Usage
        {
          name = "org.kde.plasma.systemmonitor.cpu";
          config = {
            Appearance = {
              title = "CPU Usage";
              chartFace = "org.kde.ksysguard.barchart";
            };
            SensorColors."cpu/all/usage" = "61,174,233";
            Sensors = {
              highPrioritySensorIds = ["cpu/all/usage"];
              totalSensors = ["cpu/all/usage"];
            };
          };
        }

        # Memory
        {
          name = "org.kde.plasma.systemmonitor.memory";
          config = {
            Appearance = {
              title = "Memory";
              chartFace = "org.kde.ksysguard.piechart";
            };
            SensorColors = {
              "memory/physical/used" = "233,120,61";
              "memory/physical/free" = "61,233,140";
            };
            Sensors = {
              highPrioritySensorIds = ["memory/physical/used" "memory/physical/free"];
              totalSensors = ["memory/physical/used" "memory/physical/free"];
            };
          };
        }

        # Network
        {
          name = "org.kde.plasma.systemmonitor.net";
          config = {
            Appearance = {
              title = "Network";
              chartFace = "org.kde.ksysguard.linechart";
            };
            SensorColors = {
              "network/all/download" = "61,233,61";
              "network/all/upload" = "233,61,61";
            };
            Sensors.highPrioritySensorIds = ["network/all/download" "network/all/upload"];
          };
        }

        # Disk I/O
        {
          name = "org.kde.plasma.systemmonitor.diskactivity";
          config = {
            Appearance = {
              title = "Disk I/O";
              chartFace = "org.kde.ksysguard.linechart";
            };
            SensorColors = {
              "disk/all/read" = "61,120,233";
              "disk/all/write" = "233,174,61";
            };
            Sensors.highPrioritySensorIds = ["disk/all/read" "disk/all/write"];
          };
        }

        # System Load
        {
          name = "org.kde.plasma.systemmonitor";
          config = {
            Appearance = {
              title = "System Load";
              chartFace = "org.kde.ksysguard.linechart";
            };
            SensorColors = {
              "cpu/system/loadAverage1" = "174,61,233";
              "cpu/system/loadAverage5" = "120,61,233";
              "cpu/system/loadAverage15" = "61,61,233";
            };
            Sensors.highPrioritySensorIds = ["cpu/system/loadAverage1" "cpu/system/loadAverage5" "cpu/system/loadAverage15"];
          };
        }

        # Spacer
        {
          name = "org.kde.plasma.panelspacer";
          config.General = {
            expanding = false;
            length = 20;
          };
        }

        # Digital clock
        {
          name = "org.kde.plasma.digitalclock";
          config.Appearance.showDate = true;
        }
      ];
    }

    # Secondary screen panel 1 (screen 1)
    {
      location = "bottom";
      height = 44;
      screen = 1;
      lengthMode = "fill";

      widgets = [
        {
          name = "org.kde.plasma.icontasks";
          config.General = {
            launchers = [];
            showOnlyCurrentActivity = true;
            showOnlyCurrentDesktop = false;
            showOnlyCurrentScreen = true;
          };
        }

        {
          name = "org.kde.plasma.panelspacer";
          config.General.expanding = true;
        }

        "org.kde.plasma.showActivityManager"

        {
          name = "org.kde.plasma.panelspacer";
          config.General.expanding = true;
        }
      ];
    }

    # Secondary screen panel 2 (screen 2)
    {
      location = "bottom";
      height = 44;
      screen = 2;
      lengthMode = "fill";

      widgets = [
        {
          name = "org.kde.plasma.icontasks";
          config.General = {
            launchers = [];
            showOnlyCurrentActivity = true;
            showOnlyCurrentDesktop = false;
            showOnlyCurrentScreen = true;
          };
        }

        {
          name = "org.kde.plasma.panelspacer";
          config.General.expanding = true;
        }

        "org.kde.plasma.showActivityManager"

        {
          name = "org.kde.plasma.panelspacer";
          config.General.expanding = true;
        }
      ];
    }
  ];
}

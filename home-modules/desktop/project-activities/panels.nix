{ lib, config, osConfig, activities, mkUUID, ... }@args:

let
  # Machine-specific PWA IDs
  # Each machine generates unique IDs when PWAs are installed
  # Run 'pwa-get-ids' on each machine after installing PWAs to get these IDs

  # Get hostname from osConfig which is passed from NixOS to home-manager
  hostname = osConfig.networking.hostName or "";

  # Hetzner server PWA IDs (updated 2025-10-10 with new PWAs)
  hetznerIds = {
    googleId = "01K665SPD8EPMP3JTW02JM1M0Z";  # Google AI mode
    youtubeId = "01K666N2V6BQMDSBMX3AY74TY7";  # YouTube with proper icon
    giteaId = "01K665SRSVT5KS6ZG7QKCRW2WG";
    backstageId = "01K6BFEMQCS9JFJKWPAB2N2RB4";  # Backstage at cnoe.localtest.me:8443
    kargoId = "01K665SVEFF313F0BEWFJ8S9PE";
    argoCDId = "01K665SWVY47Y54NDQJVXG2R7D";
    homeAssistantId = "01K66QAZXGDH3SBWPPNPV1YGRH";  # Home Assistant
    uberEatsId = "01K66QB12CHJDWAET5M9BKPEF5";  # Uber Eats
    githubCodespacesId = "01K772Z7AY5J36Q3NXHH9RYGC0";  # GitHub Codespaces
    azurePortalId = "01K772Z8M8NHD0TXCJ7CC3BRVQ";  # Azure Portal
    hetznerCloudId = "01K772ZA22Y9RF558NQJDHHFKN";  # Hetzner Cloud
    chatgptCodexId = "01K772ZBM45JD68HXYNM193CVW";  # ChatGPT Codex
  };

  # M1 MacBook PWA IDs (updated 2025-10-10 with new PWAs)
  m1Ids = {
    googleId = "01K664F9E8KXZPXYF4V1Q8A93V";  # Google AI mode
    youtubeId = "01K663E3K8FMGTFVQ6Z6Q2RX7X";
    giteaId = "01K663E4T77WRVG5SVE0WQQPT0";
    backstageId = "01K663E623PJ5W8R659HGSCXBS";
    kargoId = "01K663E79AJG7Z2PSRWF0SXFBE";
    argoCDId = "01K663E8S01M7HTQG6VQ5YF8PY";
    homeAssistantId = "01K66AGFCPXE13NK7YXFEF78BN";  # Home Assistant
    uberEatsId = "01K66F8FWRP6643P7V6QQWA28X";  # Uber Eats
    # TODO: Install these PWAs on M1 and run 'pwa-get-ids' to get actual IDs
    githubCodespacesId = "00000000000000000000000000";  # Placeholder - not installed
    azurePortalId = "00000000000000000000000000";  # Placeholder - not installed
    hetznerCloudId = "00000000000000000000000000";  # Placeholder - not installed
    chatgptCodexId = "00000000000000000000000000";  # Placeholder - not installed
  };

  # Select appropriate IDs based on hostname
  pwaIds =
    if hostname == "nixos-hetzner" then hetznerIds
    else if hostname == "nixos-m1" then m1Ids
    else hetznerIds;  # Default to Hetzner for now

  # Generate PWA launcher list for plasma-manager
  pwaLaunchers =
    let
      inherit (pwaIds) googleId youtubeId giteaId backstageId kargoId argoCDId homeAssistantId uberEatsId githubCodespacesId azurePortalId hetznerCloudId chatgptCodexId;
    in [
      "file:///home/vpittamp/.local/share/applications/FFPWA-${googleId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${youtubeId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${giteaId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${backstageId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${kargoId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${argoCDId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${homeAssistantId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${uberEatsId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${githubCodespacesId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${azurePortalId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${hetznerCloudId}.desktop"
      "file:///home/vpittamp/.local/share/applications/FFPWA-${chatgptCodexId}.desktop"
    ];

  # Base launchers (common apps)
  baseLaunchers = [
    "applications:firefox.desktop"
    "applications:org.kde.dolphin.desktop"
    "applications:org.kde.konsole.desktop"
    "applications:k9s.desktop"
  ];

  # Combined launcher list
  allLaunchers = baseLaunchers ++ pwaLaunchers;

  # Multi-monitor configuration
  # Determine number of screens - can be overridden per machine
  # NOTE: Plasma-manager has a bug where panel screen assignments may not be
  # correctly applied on first run. If panels appear on wrong screens, run:
  #   rm ~/.local/share/plasma-manager/last_run_desktop_script_panels
  #   systemctl --user restart plasma-plasmashell.service
  # Or use the fix-panel-screens script (TODO: create this)
  #
  # For Hetzner RDP: Support both single display and multi-monitor configurations
  # - Single display: numScreens = 1 (one virtual display)
  # - Multi-monitor: numScreens = 3 (three monitors via extended desktop)
  # The RDP client determines which mode based on "Use all my monitors" setting
  numScreens =
    if hostname == "nixos-hetzner" then 3  # Support 3-monitor RDP configuration
    else if hostname == "nixos-m1" then 1
    else 1;  # Default to single screen

  # Calculate primary screen based on number of screens
  # - 1 screen: primary = 0 (only screen)
  # - 2 screens: primary = 0 (left screen)
  # - 3 screens: primary = 1 (middle screen)
  # - 4+ screens: primary = floor(numScreens / 2) (middle screen)
  primaryScreen =
    if numScreens == 1 then 0
    else if numScreens == 2 then 0
    else builtins.div numScreens 2;  # Integer division for middle screen

  # Generate secondary screen list (all screens except primary)
  secondaryScreens = lib.filter (s: s != primaryScreen) (lib.range 0 (numScreens - 1));

  # Main panel configuration (full taskbar)
  mainPanel = {
    location = "bottom";
    height = 36;
    screen = primaryScreen;
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
  };

  # Secondary panel configuration (same as primary for consistent experience)
  # Each monitor gets a full panel with all widgets and launchers
  mkSecondaryPanel = screenNum: {
    location = "bottom";
    height = 36;
    screen = screenNum;
    lengthMode = "fill";
    alignment = "center";
    hiding = "none";
    floating = false;

    widgets = mainPanel.widgets;  # Use same widgets as main panel
  };

  # Generate secondary panels for all non-primary screens
  # Each screen gets identical functionality for seamless multi-monitor experience
  secondaryPanels = map mkSecondaryPanel secondaryScreens;

in {
  # Primary panel configuration using plasma-manager declarative API
  # Dynamically generates panels based on number of screens:
  # - 1 screen: main panel on screen 0
  # - 2 screens: main panel on screen 0, secondary on screen 1
  # - 3 screens: main panel on screen 1 (middle), secondary on screens 0 and 2
  # - 4+ screens: main panel on middle screen, secondary on all others
  panels = [ mainPanel ] ++ secondaryPanels;
}

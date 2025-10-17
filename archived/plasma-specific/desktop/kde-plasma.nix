# KDE Plasma 6 Desktop Environment Configuration
{ config, lib, pkgs, ... }:

{
  # Enable X11 and KDE Plasma 6
  services.xserver = {
    enable = true;

    # Configure for headless operation with virtual display (for cloud servers)
    videoDrivers = lib.mkDefault [ "modesetting" "fbdev" ];

    # Enable DRI for better performance
    deviceSection = ''
      Option "DRI" "3"
      Option "AccelMethod" "glamor"
    '';
  };

  # Display manager
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true; # Enable Wayland as recommended by Asahi Linux

      # Workaround for black screen on logout
      settings = {
        General = {
          # Don't halt the display server on logout - helps prevent black screen
          HaltCommand = "";
          RebootCommand = "";
        };
      };
    };
    defaultSession = lib.mkDefault "plasma"; # Use Wayland session by default (can override per-target)
  };

  # Desktop environment
  services.desktopManager.plasma6.enable = true;

  # Enable Plasma browser integration
  programs.firefox.nativeMessagingHosts.packages = [ pkgs.kdePackages.plasma-browser-integration ];

  # Touchegg for X11 gesture support (only enable for X11 sessions)
  services.touchegg.enable = lib.mkDefault false; # Disabled by default, Wayland has native gestures

  # Configure touchegg gestures for KDE (only used if touchegg is enabled)
  environment.etc."touchegg/touchegg.conf".text = ''
    <touchégg>
      <settings>
        <property name="animation_delay">150</property>
        <property name="action_execute_threshold">20</property>
        <property name="color">auto</property>
        <property name="borderColor">auto</property>
      </settings>
      
      <application name="All">
        <!-- 3 finger swipe up: Overview -->
        <gesture type="SWIPE" fingers="3" direction="UP">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut Overview'</command>
          </action>
        </gesture>
        
        <!-- 3 finger swipe down: Show Desktop -->
        <gesture type="SWIPE" fingers="3" direction="DOWN">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut ShowDesktop'</command>
          </action>
        </gesture>
        
        <!-- 3 finger swipe left: Next Desktop -->
        <gesture type="SWIPE" fingers="3" direction="LEFT">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.KWin /KWin nextDesktop'</command>
          </action>
        </gesture>

        <!-- 3 finger swipe right: Previous Desktop -->
        <gesture type="SWIPE" fingers="3" direction="RIGHT">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.KWin /KWin previousDesktop'</command>
          </action>
        </gesture>

        <!-- 3 finger pinch out: Activity Switcher -->
        <gesture type="PINCH" fingers="3" direction="OUT">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut ActivityManager'</command>
          </action>
        </gesture>

        <!-- 4 finger swipe up: Present Windows (All) -->
        <gesture type="SWIPE" fingers="4" direction="UP">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut ExposeAll'</command>
          </action>
        </gesture>

        <!-- 4 finger swipe down: Present Windows (Current Desktop) -->
        <gesture type="SWIPE" fingers="4" direction="DOWN">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut Expose'</command>
          </action>
        </gesture>

        <!-- 4 finger swipe left: Next Activity -->
        <gesture type="SWIPE" fingers="4" direction="LEFT">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities.NextActivity'</command>
          </action>
        </gesture>

        <!-- 4 finger swipe right: Previous Activity -->
        <gesture type="SWIPE" fingers="4" direction="RIGHT">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities.PreviousActivity'</command>
          </action>
        </gesture>

        <!-- Pinch in/out: Zoom -->
        <gesture type="PINCH" fingers="2" direction="IN">
          <action type="SEND_KEYS">
            <keys>Control+minus</keys>
          </action>
        </gesture>
        
        <gesture type="PINCH" fingers="2" direction="OUT">
          <action type="SEND_KEYS">
            <keys>Control+plus</keys>
          </action>
        </gesture>
      </application>
    </touchégg>
  '';

  # Sound system - Default to PipeWire (can be overridden per-target)
  # Note: Hetzner overrides this to use PulseAudio for XRDP compatibility
  services.pulseaudio.enable = lib.mkDefault false;
  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    alsa.support32Bit = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
    jack.enable = lib.mkDefault true;

    # Enable WirePlumber session manager (required for PipeWire)
    wireplumber.enable = lib.mkDefault true;
  };

  # Enable hardware acceleration
  hardware.graphics.enable = true;

  # Desktop packages
  environment.systemPackages = with pkgs; [
    # KDE applications
    kdePackages.kate
    kdePackages.konsole
    kdePackages.dolphin
    kdePackages.ark
    kdePackages.spectacle
    kdePackages.okular
    kdePackages.gwenview
    kdePackages.kdeconnect-kde # Phone/device integration
    kdePackages.plasma-browser-integration # Browser integration for KDE

    # Clipboard management - using native Klipper
    # copyq  # Advanced clipboard manager with history (disabled - using Klipper)
    wl-clipboard # Wayland clipboard utilities (primary)
    xclip # X11 clipboard utilities (for XWayland apps)
    xorg.libxcb # XCB library for Qt
    libxkbcommon # Keyboard handling for Qt

    # QDBus for system integration
    libsForQt5.qttools # Provides qdbus command

    # Browsers
    chromium # Default browser with 1Password integration
    # firefox  # Disabled - using Chromium as default
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ pkgs.gitkraken ];

  # Enable flatpak for additional apps
  services.flatpak.enable = false;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

  # Enable CUPS for printing
  services.printing.enable = true;

  # Enable bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # Enable KDE Connect for phone/device integration
  programs.kdeconnect.enable = true;

  # Set system-wide default browser to Chromium
  # Multi-screen environment variables for non-HiDPI systems  
  # IMPORTANT: M1 configuration overrides these for HiDPI displays
  environment.sessionVariables = lib.mkDefault {
    DEFAULT_BROWSER = "chromium";
    BROWSER = "chromium";
    # Multi-screen setup - these are overridden in m1.nix for HiDPI
    PLASMA_USE_QT_SCALING = "1";
    QT_SCREEN_SCALE_FACTORS = ""; # Let Qt auto-detect
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
  };

  # Enable PAM integration for KDE Wallet auto-unlock
  # This allows the wallet to unlock automatically with the user's login password
  # Configure for different login methods - only enabled services will be affected
  security.pam.services = {
    sddm.enableKwallet = lib.mkIf config.services.displayManager.sddm.enable true;
    xrdp-sesman.enableKwallet = lib.mkIf config.services.xrdp.enable true;
    login.enableKwallet = true;  # Fallback for console/SSH logins
  };

  # Yakuake dropdown terminal autostart - DISABLED due to issues
  # Uncomment the following block to re-enable Yakuake autostart
  # environment.etc."xdg/autostart/yakuake.desktop".text = ''
  #   [Desktop Entry]
  #   Type=Application
  #   Name=Yakuake
  #   Comment=Drop-down terminal emulator
  #   Exec=${pkgs.kdePackages.yakuake}/bin/yakuake
  #   Icon=yakuake
  #   Terminal=false
  #   Categories=Qt;KDE;System;TerminalEmulator;
  #   X-KDE-autostart-after=panel
  #   X-GNOME-Autostart-enabled=true
  # '';

}

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
      wayland.enable = false;  # Disable Wayland due to Mesa/GPU issues on Apple Silicon
      
      # Workaround for black screen on logout on Apple Silicon
      settings = {
        General = {
          # Don't halt the X server on logout - helps prevent black screen
          HaltCommand = "";
          RebootCommand = "";
        };
      };
    };
    defaultSession = lib.mkForce "plasmax11";  # Force X11 session (stable on Apple Silicon)
  };
  
  # Desktop environment
  services.desktopManager.plasma6.enable = true;
  
  # Enable touchegg for X11 gesture support
  services.touchegg.enable = true;
  
  # Configure touchegg gestures for KDE
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

  # Sound system
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
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
    
    # Clipboard management - using native Klipper instead of CopyQ
    # copyq  # Advanced clipboard manager with history (disabled - using Klipper)
    wl-clipboard  # Wayland clipboard utilities
    xclip  # X11 clipboard utilities (fallback)
    xorg.libxcb  # XCB library for Qt
    libxkbcommon  # Keyboard handling for Qt
    
    # QDBus for touchpad gestures (touchegg needs this)
    libsForQt5.qttools  # Provides qdbus command
    
    # Browsers
    chromium  # Default browser with 1Password integration
    # firefox  # Disabled - using Chromium as default
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ pkgs.gitkraken ];

  # Enable flatpak for additional apps
  services.flatpak.enable = true;
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

  # Set system-wide default browser to Chromium
  environment.sessionVariables = {
    DEFAULT_BROWSER = "chromium";
    BROWSER = "chromium";
  };

  # Enable PAM integration for KDE Wallet auto-unlock
  # This allows the wallet to unlock automatically with the user's login password
  security.pam.services.sddm.enableKwallet = true;
  security.pam.services.login.enableKwallet = true;

  # Yakuake dropdown terminal autostart
  # Creates an XDG autostart entry for Yakuake to start with KDE Plasma
  environment.etc."xdg/autostart/yakuake.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Yakuake
    Comment=Drop-down terminal emulator
    Exec=${pkgs.kdePackages.yakuake}/bin/yakuake
    Icon=yakuake
    Terminal=false
    Categories=Qt;KDE;System;TerminalEmulator;
    X-KDE-autostart-after=panel
    X-GNOME-Autostart-enabled=true
  '';

}
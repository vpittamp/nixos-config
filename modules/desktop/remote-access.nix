# Remote Desktop Access Configuration (RDP & VNC)
{ config, lib, pkgs, ... }:

{
  # XRDP for X11 sessions (legacy)
  services.xrdp = {
    enable = true;
    audio.enable = true;  # Enable audio redirection support
    defaultWindowManager = "startplasma-x11-xrdp";
    openFirewall = true;
    port = 3389;
  };

  # Create custom XRDP startwm script that handles logout properly
  environment.etc."xrdp/startwm.sh" = {
    enable = true;
    mode = "0755";
    text = ''
      #!/bin/sh
      . /etc/profile

      # Set up audio if available
      if [ -f ${pkgs.pulseaudio-module-xrdp}/libexec/pulsaudio-xrdp-module/pulseaudio_xrdp_init ]; then
        ${pkgs.pulseaudio-module-xrdp}/libexec/pulsaudio-xrdp-module/pulseaudio_xrdp_init
      fi

      # Start Plasma X11 session with custom wrapper
      exec startplasma-x11-xrdp
    '';
  };

  # Configure xrdp settings via configuration file
  environment.etc."xrdp/xrdp.ini".text = lib.mkAfter ''
    # Device redirection settings
    [Channels]
    rdpdr=true
    rdpsnd=true
    drdynvc=true
    cliprdr=true
    rail=true
    xrdpvr=true

    [Sessions]
    # Enable all redirection features
    use_fastpath=both
    require_credentials=yes
    bulk_compression=yes
    new_cursors=yes
    use_bitmap_cache=yes
    use_bitmap_compression=yes
  '';

  # Configure sesman for better session management
  environment.etc."xrdp/sesman.ini".text = lib.mkAfter ''
    [Globals]
    EnableSyslog=yes
    SyslogLevel=INFO

    [Security]
    AllowRootLogin=no
    MaxLoginRetry=4

    [Sessions]
    X11DisplayOffset=10
    MaxSessions=50
    KillDisconnected=yes        # Kill sessions when user disconnects
    DisconnectedTimeLimit=60    # Terminate disconnected sessions after 60 seconds
    IdleTimeLimit=0             # No idle timeout (0 = disabled)

    [Xorg]
    param=Xorg
    param=-config
    param=xrdp/xorg.conf
    param=-noreset
    param=-nolisten
    param=tcp
    param=-logfile
    param=/var/log/xrdp-sesman.log
  '';

  # Firewall configuration for remote access
  networking.firewall.allowedTCPPorts = [
    3389   # RDP (XRDP)
    5900   # VNC (KRFB default)
  ];

  networking.firewall.allowedUDPPorts = [
    3389   # RDP
    5900   # VNC
  ];

  # Remote access tools - servers and clients
  environment.systemPackages = with pkgs; [
    # KDE Native Remote Desktop Solutions
    kdePackages.krfb     # KDE's VNC server (works with both X11 and Wayland)

    # Remote access clients
    # remmina  # Disabled to prevent autostart issues - use KRFB or XRDP instead
    freerdp
    xorg.xauth      # X authentication

    # XRDP startup wrapper for KDE Plasma X11
    # Note: Server must not auto-start a console session (SDDM disabled on Hetzner)
    # This ensures RDP creates the only KDE session, avoiding D-Bus conflicts
    (pkgs.writeScriptBin "startplasma-x11-xrdp" ''
      #!/bin/sh
      # Set X authorization file (required for X11 connection)
      export XAUTHORITY=$HOME/.Xauthority

      # Set session environment for KDE
      export XDG_SESSION_TYPE=x11
      export XDG_SESSION_CLASS=user
      export XDG_CURRENT_DESKTOP=KDE

      # Use standard KDE Plasma X11 startup
      # This handles all KDE services (kwin, plasmashell, kglobalaccel, etc.)
      exec startplasma-x11
    '')

    # Session cleanup helper script
    (pkgs.writeScriptBin "xrdp-logout" ''
      #!${pkgs.bash}/bin/bash
      # Proper XRDP session logout script

      echo "Logging out XRDP session..."

      # Kill KDE session processes
      ${pkgs.killall}/bin/killall -u $USER plasmashell kwin_x11 kded6 || true

      # Terminate the loginctl session
      SESSION_ID=$(loginctl show-user $USER --property=Sessions --value | cut -d' ' -f1)
      if [ -n "$SESSION_ID" ]; then
        loginctl terminate-session $SESSION_ID
      fi

      # Kill remaining XRDP processes
      pkill -u $USER -f xrdp || true

      echo "Logout complete"
    '')
  ];

  # Enable USB/IP kernel modules for potential USB redirection
  # Note: USB/IP tools need to be installed separately if needed
  boot.kernelModules = [ "vhci-hcd" ];

  # Ensure X11 forwarding is enabled for SSH
  services.openssh.settings.X11Forwarding = lib.mkForce true;

  # REMOTE ACCESS NOTES:
  #
  # XRDP Configuration:
  # - XRDP requires X11 session (cannot work with Wayland)
  # - Hetzner is configured to use "plasmax11" session by default
  # - Connect using Windows Remote Desktop to port 3389
  #
  # Alternative: KRFB (VNC)
  # - Works with both X11 and Wayland
  # - Start from application menu or run 'krfb'
  # - Connect using any VNC client to port 5900
  #
  # Session Configuration:
  # - Hetzner: Uses X11 by default (for XRDP compatibility)
  # - M1 MacBook: Uses Wayland (better for HiDPI displays)
  # - WSL: Can use either session type
}

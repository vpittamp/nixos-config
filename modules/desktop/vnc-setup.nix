# VNC Server Declarative Configuration
{ config, lib, pkgs, ... }:

{
  # VNC configuration files managed by home-manager
  home-manager.users.vpittamp = {
    # VNC server configuration optimized for M1 MacBook Pro
    home.file.".vnc/config".text = ''
      # TigerVNC Configuration for M1 MacBook Pro Retina Display
      geometry=2560x1600
      depth=24
      localhost=no
      alwaysshared=yes
      desktop=Hetzner-KDE
      SecurityTypes=VncAuth,TLSVnc
      # Performance optimizations
      CompareFB=1
      Protocol3.3=off
      # Quality settings for LAN/fast connections
      QualityLevel=9
      CompressLevel=1
      # Enable full color
      FullColor=1
      # DPI for Retina display
      DPI=144
    '';
    
    # VNC startup script for KDE Plasma
    home.file.".vnc/xstartup" = {
      text = ''
        #!/bin/sh
        unset SESSION_MANAGER
        unset DBUS_SESSION_BUS_ADDRESS
        export XKL_XMODMAP_DISABLE=1
        
        # Start D-Bus session
        if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
            eval $(dbus-launch --sh-syntax)
            export DBUS_SESSION_BUS_ADDRESS
        fi
        
        # Start KDE Plasma
        exec startplasma-x11
      '';
      executable = true;
    };
    
    # VNC password setup script in bash profile
    programs.bash.initExtra = ''
      # Check for VNC password on login
      if [ ! -f ~/.vnc/passwd ] || [ ! -s ~/.vnc/passwd ]; then
        echo "================================================"
        echo "VNC PASSWORD NOT SET!"
        echo "Please run: vncpasswd"
        echo "to set your VNC password for remote access"
        echo "================================================"
      fi
    '';
  };
}
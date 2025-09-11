# VNC Server Declarative Configuration
{ config, lib, pkgs, ... }:

{
  # VNC configuration files managed by home-manager
  home-manager.users.vpittamp = {
    # VNC server configuration
    home.file.".vnc/config".text = ''
      # TigerVNC Configuration
      geometry=1920x1080
      depth=24
      localhost=no
      alwaysshared=yes
      desktop=Hetzner-KDE
      SecurityTypes=VncAuth,TLSVnc
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
    
    # VNC password file - needs to be created by user for security
    # User must run: vncpasswd
    # We'll create an empty placeholder
    home.activation.vncPasswordCheck = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ ! -f ~/.vnc/passwd ]; then
        mkdir -p ~/.vnc
        touch ~/.vnc/passwd
        chmod 600 ~/.vnc/passwd
        echo "================================================"
        echo "VNC PASSWORD NOT SET!"
        echo "Please run: vncpasswd"
        echo "to set your VNC password"
        echo "================================================"
      fi
    '';
  };
}
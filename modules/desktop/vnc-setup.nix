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
    
    # VNC password file - using a hashed password
    # To generate: echo -n "yourpassword" | vncpasswd -f > passwd
    # For now, we'll create an empty file that prompts for password on first run
    home.file.".vnc/passwd" = {
      source = pkgs.writeText "vnc-passwd" "";
      mode = "600";
      onChange = ''
        # If password file is empty, prompt to set it
        if [ ! -s ~/.vnc/passwd ]; then
          echo "================================================"
          echo "VNC PASSWORD NOT SET!"
          echo "Please run: vncpasswd"
          echo "to set your VNC password"
          echo "================================================"
        fi
      '';
    };
  };
}
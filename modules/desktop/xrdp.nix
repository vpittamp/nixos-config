# XRDP Remote Desktop Configuration Module
# Minimal working version for Phase 2 Foundational
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.xrdp-i3;
in {
  options.services.xrdp-i3 = {
    enable = mkEnableOption "XRDP for i3 window manager";

    port = mkOption {
      type = types.port;
      default = 3389;
      description = "Port for XRDP connections";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open the firewall for XRDP";
    };

    defaultWindowManager = mkOption {
      type = types.str;
      default = "${pkgs.i3}/bin/i3";
      description = "Window manager to launch";
    };
  };

  config = mkIf cfg.enable {
    # Enable XRDP service
    services.xrdp = {
      enable = true;
      audio.enable = true;
      defaultWindowManager = "i3-xrdp-session";
      openFirewall = cfg.openFirewall;
      port = cfg.port;
    };

    # Create XRDP startup script for i3
    environment.etc."xrdp/startwm.sh" = {
      enable = true;
      mode = "0755";
      text = ''
        #!/bin/sh
        . /etc/profile

        # Set up audio if available
        if [ -f /run/current-system/sw/libexec/pulsaudio-xrdp-module/pulseaudio_xrdp_init ]; then
          /run/current-system/sw/libexec/pulsaudio-xrdp-module/pulseaudio_xrdp_init
        fi

        # Start i3 session
        exec i3-xrdp-session
      '';
    };

    # Configure XRDP settings
    environment.etc."xrdp/xrdp.ini".text = mkAfter ''
      # Device redirection settings
      [Channels]
      rdpdr=true
      rdpsnd=true
      drdynvc=true
      cliprdr=true

      [Sessions]
      use_fastpath=both
      require_credentials=yes
      bulk_compression=yes
      new_cursors=yes
      use_bitmap_cache=yes
      use_bitmap_compression=yes
    '';

    # Configure sesman for session management
    environment.etc."xrdp/sesman.ini".text = mkAfter ''
      [Sessions]
      X11DisplayOffset=10
      MaxSessions=50
      KillDisconnected=no        # Keep sessions alive
      DisconnectedTimeLimit=0    # No timeout
      IdleTimeLimit=0            # No idle timeout
    '';

    # i3 XRDP session wrapper
    environment.systemPackages = [
      (pkgs.writeScriptBin "i3-xrdp-session" ''
        #!/bin/sh
        # Set X authorization
        export XAUTHORITY=$HOME/.Xauthority

        # Set session environment
        export XDG_SESSION_TYPE=x11
        export XDG_SESSION_CLASS=user
        export XDG_CURRENT_DESKTOP=i3

        # Launch i3
        exec ${cfg.defaultWindowManager}
      '')
    ];

    # Firewall configuration
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    # Enable X11 forwarding
    services.openssh.settings.X11Forwarding = mkForce true;
  };
}

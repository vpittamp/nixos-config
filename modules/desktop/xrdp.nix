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
      extraConfDirCommands = ''
        cat > $out/startwm.sh <<'EOF'
        #!/bin/sh
        . /etc/profile

        if [ -f /run/current-system/sw/libexec/pulseaudio-xrdp-module/pulseaudio_xrdp_init ]; then
          /run/current-system/sw/libexec/pulseaudio-xrdp-module/pulseaudio_xrdp_init
        fi

        exec i3-xrdp-session
        EOF
        chmod +x $out/startwm.sh

        cat >> $out/xrdp.ini <<'EOF'

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
        EOF
      '';

      # Session Management: Using xrdp upstream defaults
      #
      # Upstream defaults (xrdp 0.10.4.1):
      # - Policy=Default (single session per user, reconnect to existing session)
      # - MaxSessions=50 (generous limit)
      # - KillDisconnected=false (sessions persist indefinitely when disconnected)
      # - DisconnectedTimeLimit=0 (ignored when KillDisconnected=false)
      # - IdleTimeLimit=0 (no idle timeout)
      #
      # These defaults are intentional:
      # - Users can disconnect and reconnect from any device
      # - Work continues exactly where they left off
      # - Sessions only end on logout or system restart
      #
      # With Policy=Default, only ONE session per user should exist.
      # If multiple sessions accumulate, the issue is likely session matching logic,
      # not cleanup configuration.
      #
      # extraConfDirCommands above adds i3-specific startwm.sh and tuning
    };

    # NOTE: sesman.ini configuration is handled via services.xrdp.extraConfDirCommands above
    # Do NOT use environment.etc."xrdp/sesman.ini" as the service uses a NixOS store path

    # i3 XRDP session wrapper
    environment.systemPackages = [
      (pkgs.writeScriptBin "i3-xrdp-session" ''
        #!/bin/sh
        # Set X authorization
        export XAUTHORITY=$HOME/.Xauthority

        # CRITICAL: Ensure DISPLAY is set and propagated to all child processes
        # This prevents applications from launching on wrong displays
        export DISPLAY="''${DISPLAY:-:10}"

        # Set session environment
        export XDG_SESSION_TYPE=x11
        export XDG_SESSION_CLASS=user
        export XDG_CURRENT_DESKTOP=i3

        # Log session start for debugging
        echo "$(date): Starting i3 on DISPLAY=$DISPLAY" >> /tmp/xrdp-session.log

        # Launch i3 with DISPLAY explicitly set
        exec ${cfg.defaultWindowManager}
      '')
    ];

    # Firewall configuration
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    # Enable X11 forwarding
    services.openssh.settings.X11Forwarding = mkForce true;
  };
}

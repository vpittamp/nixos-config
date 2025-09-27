# Scrypted Service Configuration
# Modern video integration platform for Home Assistant
# Supports HomeKit devices including Logitech Circle View cameras
{ config, lib, pkgs, ... }:

{
  # Scrypted runs in Docker
  virtualisation.docker.enable = true;

  # Create Scrypted container as a systemd service
  systemd.services.scrypted = {
    description = "Scrypted - Home Automation Video Integration";
    after = [ "docker.service" "home-assistant.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10s";

      # Run as root to manage Docker
      User = "root";
      Group = "root";

      # Pull and run Scrypted container
      ExecStartPre = "${pkgs.docker}/bin/docker pull koush/scrypted:latest";

      ExecStart = ''
        ${pkgs.docker}/bin/docker run \
          --rm \
          --name scrypted \
          --network host \
          -e SCRYPTED_WEBHOOK_UPDATE_AUTHORIZATION=Bearer \
          -e SCRYPTED_WEBHOOK_UPDATE=http://localhost:10444/v1/update \
          -v /var/lib/scrypted:/server/volume \
          koush/scrypted:latest
      '';

      ExecStop = "${pkgs.docker}/bin/docker stop scrypted";
      ExecStopPost = "${pkgs.docker}/bin/docker rm -f scrypted || true";
    };
  };

  # Alternative: Use docker-compose for more complex setup
  environment.etc."scrypted/docker-compose.yml" = {
    text = ''
      version: '3.8'
      services:
        scrypted:
          image: koush/scrypted:latest
          container_name: scrypted
          restart: unless-stopped
          network_mode: host
          environment:
            - SCRYPTED_WEBHOOK_UPDATE_AUTHORIZATION=Bearer
            - SCRYPTED_WEBHOOK_UPDATE=http://localhost:10444/v1/update
          volumes:
            - /var/lib/scrypted:/server/volume
          # Uncomment for GPU acceleration if available
          # devices:
          #   - /dev/dri:/dev/dri
    '';
  };

  # Create Scrypted data directory
  systemd.tmpfiles.rules = [
    "d /var/lib/scrypted 0755 root root -"
    "d /etc/scrypted 0755 root root -"
  ];

  # Firewall rules for Scrypted
  networking.firewall = {
    allowedTCPPorts = [
      10443  # Scrypted HTTPS port
      11080  # Scrypted HTTP port
      10444  # Scrypted webhook port
    ];

    allowedUDPPorts = [
      5353   # mDNS for discovery
    ];
  };

  # Helper scripts
  environment.systemPackages = with pkgs; [
    # Script to set up Scrypted with Home Assistant
    (writeShellScriptBin "scrypted-setup" ''
      #!/usr/bin/env bash
      echo "=== Scrypted Setup for Circle View Cameras ==="
      echo ""
      echo "1. Access Scrypted at: https://localhost:10443"
      echo "   (HTTP available at: http://localhost:11080)"
      echo ""
      echo "2. Create admin account on first access"
      echo ""
      echo "3. Install plugins:"
      echo "   - HomeKit (to import Circle View cameras)"
      echo "   - Home Assistant (to export to HA)"
      echo "   - Rebroadcast (for RTSP streams)"
      echo ""
      echo "4. Add Circle View cameras:"
      echo "   - Go to HomeKit plugin settings"
      echo "   - Click 'Add HomeKit Device'"
      echo "   - Enter the HomeKit code from your camera"
      echo ""
      echo "5. Configure Home Assistant integration:"
      echo "   - Go to Home Assistant plugin"
      echo "   - Enter HA URL: http://localhost:8123"
      echo "   - Create Long-Lived Access Token in HA"
      echo "   - Paste token in Scrypted"
      echo ""
      echo "Current status:"
      systemctl status scrypted --no-pager | head -10
    '')

    # Script to view Scrypted logs
    (writeShellScriptBin "scrypted-logs" ''
      #!/usr/bin/env bash
      echo "Showing Scrypted logs..."
      docker logs -f scrypted 2>&1
    '')

    # Script to restart Scrypted
    (writeShellScriptBin "scrypted-restart" ''
      #!/usr/bin/env bash
      echo "Restarting Scrypted..."
      sudo systemctl restart scrypted
      sleep 5
      systemctl status scrypted --no-pager
    '')

    # Script to get Home Assistant token
    (writeShellScriptBin "ha-token" ''
      #!/usr/bin/env bash
      echo "To create a Home Assistant Long-Lived Access Token:"
      echo ""
      echo "1. Open Home Assistant: http://localhost:8123"
      echo "2. Click your profile (bottom left)"
      echo "3. Scroll to 'Long-Lived Access Tokens'"
      echo "4. Click 'Create Token'"
      echo "5. Name it 'Scrypted'"
      echo "6. Copy and save the token"
      echo ""
      echo "Use this token in Scrypted's Home Assistant plugin configuration"
    '')
  ];

  # Add user to docker group for management
  users.users.vpittamp = {
    extraGroups = [ "docker" ];
  };
}
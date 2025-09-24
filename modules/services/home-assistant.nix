# Home Assistant Service Configuration
{ config, lib, pkgs, ... }:

{
  # Home Assistant service
  services.home-assistant = {
    enable = true;

    # Extra components to include
    extraComponents = [
      # Core components
      "default_config"
      "met"
      "esphome"
      "homekit"
      "tailscale"

      # Network discovery
      "zeroconf"
      "ssdp"
      "dhcp"

      # Common integrations
      "mqtt"
      "zha"
      "zwave_js"

      # Cloud services
      "google_translate"
      "radio_browser"

      # Media
      "cast"
      "spotify"
      "sonos"
      "plex"

      # Utilities
      "backup"
      "mobile_app"
      "webhook"
      "http"
    ];

    # Extra packages available to Home Assistant
    extraPackages = python3Packages: with python3Packages; [
      # Additional Python packages for integrations
      psycopg2
      gtts
      numpy
      pillow
      aiohttp-cors
      paho-mqtt
      pyserial
      zeroconf

      # HomeKit support
      aiohomekit
      fnv-hash-fast
      pyqrcode
      base36
      HAP-python

      # Tailscale support
      tailscale
    ];

    # Configuration
    config = {
      # Basic configuration
      homeassistant = {
        name = "Home";
        latitude = "!secret latitude";
        longitude = "!secret longitude";
        elevation = "!secret elevation";
        unit_system = "metric";
        temperature_unit = "C";
        time_zone = config.time.timeZone or "America/New_York";
        external_url = "https://homeassistant.vpittamp.tailnet.ts.net:8123";
        internal_url = "http://localhost:8123";
      };

      # Enable the default set of integrations
      default_config = {};

      # HTTP configuration
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
          "100.64.0.0/10"  # Tailscale subnet
        ];
      };

      # Frontend configuration
      frontend = {
        themes = "!include_dir_merge_named themes";
      };

      # Logging
      logger = {
        default = "info";
        logs = {
          "homeassistant.components.http" = "warning";
        };
      };

      # Recorder - use SQLite by default, can switch to PostgreSQL later
      recorder = {
        db_url = "sqlite:////var/lib/hass/home-assistant_v2.db";
        purge_keep_days = 30;
        commit_interval = 5;
      };

      # History
      history = {};

      # Logbook
      logbook = {};

      # System health
      system_health = {};

      # Mobile app support
      mobile_app = {};

      # Backup
      backup = {};

      # HomeKit Bridge configuration
      homekit = [
        {
          name = "Home Assistant Bridge";
          port = 51827;
          filter = {
            # Include domains to expose to HomeKit
            include_domains = [
              "light"
              "switch"
              "sensor"
              "binary_sensor"
              "cover"
              "climate"
              "fan"
              "lock"
              "media_player"
            ];
            # Optionally exclude specific entities
            # exclude_entities = [
            #   "sensor.internal_temperature"
            # ];
          };
          # Entity configuration for better HomeKit compatibility
          entity_config = {};
        }
      ];
    };

    # Open firewall for Home Assistant
    openFirewall = true;
  };

  # Enable mDNS for device discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      hinfo = true;
      domain = true;
    };
    extraServiceFiles = {
      homeassistant = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name>Home Assistant</name>
          <service>
            <type>_home-assistant._tcp</type>
            <port>8123</port>
          </service>
        </service-group>
      '';
    };
  };

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [
      8123  # Home Assistant web interface
      1883  # MQTT (optional, for local MQTT broker)
      5353  # mDNS
    ];
    allowedUDPPorts = [
      5353  # mDNS
      51827 # HomeKit
    ];
  };

  # Create hass user if it doesn't exist
  users.users.hass = {
    isSystemUser = true;
    group = "hass";
    home = "/var/lib/hass";
    createHome = true;
    description = "Home Assistant service user";
  };

  users.groups.hass = {};

  # System packages for Home Assistant
  environment.systemPackages = with pkgs; [
    # Tools useful for Home Assistant
    mosquitto  # MQTT broker
    esphome  # ESP device management

    # Network tools for debugging
    avahi
    nmap
    tcpdump
  ];

  # Optional: PostgreSQL for better performance (commented out by default)
  # services.postgresql = {
  #   enable = true;
  #   ensureDatabases = [ "hass" ];
  #   ensureUsers = [
  #     {
  #       name = "hass";
  #       ensureDBOwnership = true;
  #     }
  #   ];
  # };

  # Systemd service tweaks
  systemd.services.home-assistant = {
    # Restart on failure
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = "5s";
    };

    # Wait for network
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
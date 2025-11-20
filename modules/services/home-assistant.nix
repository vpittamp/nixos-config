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

      # Climate control
      "ecobee"
      "homekit_controller"  # To import HomeKit devices

      # Apple services
      "icloud"

      # Smart home platforms
      "smartthings"

      # AI/LLM integrations
      "openai_conversation"
      "google_generative_ai_conversation"
      "conversation"
      "assist_pipeline"

      # Network discovery
      "zeroconf"
      "ssdp"
      "dhcp"

      # Common integrations
      "mqtt"
      "zha"
      "zwave_js"

      # Bluetooth devices
      "bluetooth"
      "bluetooth_le_tracker"
      "bluetooth_adapters"

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
      hap-python
      python-otbr-api  # Required for HomeKit controller

      # Apple ecosystem support
      pyatv  # Apple TV integration
      pyicloud  # iCloud integration

      # Device discovery
      getmac  # Samsung TV and other integrations
      ibeacon-ble  # iBeacon support

      # Bluetooth device support
      bleak  # Bluetooth Low Energy support
      bleak-retry-connector  # Bluetooth connection reliability
      pycups  # For Ember Mug integration

      # SmartThings support
      pysmartthings

      # AI/LLM support
      openai
      anthropic
      google-generativeai
      tiktoken  # For token counting

      # Tailscale support
      tailscale

      # Performance optimization libraries
      # Note: zlib-ng packages may not be available in nixpkgs
      # The warning is harmless and Home Assistant will fall back to standard zlib
    ];

    # Configuration
    config = {
      # Basic configuration
      homeassistant = {
        name = "Home";
        # Default coordinates - update these via UI or secrets.yaml
        latitude = 40.7128;
        longitude = -74.0060;
        elevation = 10;
        unit_system = "metric";
        temperature_unit = "C";
        time_zone = config.time.timeZone or "America/New_York";
        external_url = "https://homeassistant.vpittamp.tailnet.ts.net:8123";
        internal_url = "http://192.168.1.214:8123";
      };

      # Enable the default set of integrations
      default_config = {};

      # Enable packages for modular configuration
      homeassistant.packages = "!include_dir_named packages";

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

      # Note: LLM integrations (OpenAI, Google AI, Anthropic) are configured via UI
      # API keys are stored in secrets.yaml for use in UI configuration

      # HomeKit Bridge configuration
      # This creates bridges that expose Home Assistant devices to Apple HomeKit
      homekit = [
        {
          # Bridge 1: Current Home (where you are now)
          name = "HA Current Home";
          port = 51827;
          advertise_ip = "192.168.1.214";
          mode = "bridge";

          # Filter for current home devices
          filter = {
            include_domains = [
              "light"
              "camera"
              "switch"
              "sensor"
              "binary_sensor"
              "cover"
              "fan"
              "lock"
              "media_player"
              "vacuum"
            ];

            # Exclude devices that belong to the other home
            exclude_entities = [
              # Add Ecobee and other remote home devices here
              "climate.ecobee"
              "climate.ecobee_thermostat"
              # Add Circle View cameras if they're at other home
              # "camera.circle_view_0ye8"
              # "camera.circle_view_2848"
            ];
          };

          entity_config = {};
        }

        {
          # Bridge 2: Other Home (remote location)
          name = "HA Other Home";
          port = 51828;
          advertise_ip = "192.168.1.214";
          mode = "bridge";

          # Filter for other home devices only
          filter = {
            include_domains = [
              "climate"  # Ecobee thermostat
              "camera"   # Circle View cameras
              "sensor"
              "binary_sensor"
              "alarm_control_panel"
            ];

            # Only include specific entities for the other home
            include_entities = [
              "climate.ecobee"
              "climate.ecobee_thermostat"
              # Ecobee sensors
              "sensor.ecobee_temperature"
              "sensor.ecobee_humidity"
              "binary_sensor.ecobee_occupancy"
              # Circle View cameras (if at other home)
              # "camera.circle_view_0ye8"
              # "camera.circle_view_2848"
              # Add other remote home devices here
            ];

            # Exclude local devices
            exclude_entities = [
              # Add current home devices to exclude
            ];
          };

          entity_config = {
            # Configure Ecobee for better HomeKit compatibility
            "climate.ecobee" = {
              name = "Thermostat";
            };
          };
        }
      ];

      # Note: Tailscale integration should be configured via Home Assistant UI
      # Go to Settings > Devices & Services > Add Integration > Tailscale
      # The API key can be created at https://login.tailscale.com/admin/settings/keys
    };

    # Open firewall for Home Assistant
    openFirewall = true;
  };

  # Note: Environment file at /var/lib/hass/environment should be created manually
  # or via a systemd ExecStartPre script with the actual Tailscale API key.
  # Example: TAILSCALE_API_KEY=your-key-here
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
      userServices = true;
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
      51827 # HomeKit Bridge 1 (Current Home)
      51828 # HomeKit Bridge 2 (Other Home)
      1883  # MQTT (optional, for local MQTT broker)
      5353  # mDNS
    ];
    allowedUDPPorts = [
      5353  # mDNS
      51827 # HomeKit Bridge 1
      51828 # HomeKit Bridge 2
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

  # Ensure Home Assistant data directories exist
  systemd.tmpfiles.rules = [
    "d /var/lib/hass 0755 hass hass -"
    "d /var/lib/hass/packages 0755 hass hass -"
    "d /var/lib/hass/themes 0755 hass hass -"
  ];

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

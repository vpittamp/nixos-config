# Contract Schema: xrdp Multi-Session Configuration
# Module: modules/desktop/xrdp.nix
# Purpose: Define the configuration contract for xrdp multi-session support

{ lib, ... }:

{
  # Multi-session xrdp configuration options
  services.xrdp = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable xrdp RDP server with multi-session support";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3389;
      description = "Port for RDP connections";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall port for RDP connections";
    };

    defaultWindowManager = lib.mkOption {
      type = lib.types.str;
      default = "i3-xrdp-session";
      description = "Default window manager session wrapper script";
    };

    audio = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable audio redirection via PulseAudio";
      };
    };

    sesman = {
      policy = lib.mkOption {
        type = lib.types.enum [ "Default" "UBC" "UBI" "UBDI" "Separate" ];
        default = "UBC";
        description = ''
          Session policy for xrdp-sesman:
          - Default: Reconnect to existing session
          - UBC: New session per User+BitPerPixel+Connection (recommended for multi-device)
          - UBI: New session per User+BitPerPixel+IP
          - UBDI: New session per User+BitPerPixel+Domain+IP
          - Separate: Always create new session (deprecated, use UBC)
        '';
      };

      maxSessions = lib.mkOption {
        type = lib.types.ints.between 1 50;
        default = 5;
        description = "Maximum number of concurrent sessions per user";
      };

      killDisconnected = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to kill sessions when users disconnect.
          Must be false for multi-device support (FR-002, FR-003).
        '';
      };

      disconnectedTimeLimit = lib.mkOption {
        type = lib.types.int;
        default = 86400;  # 24 hours
        description = ''
          Time in seconds before disconnected sessions are cleaned up.
          0 = never cleanup, 86400 = 24 hours (FR-003).
        '';
      };

      idleTimeLimit = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = ''
          Time in seconds before idle sessions are terminated.
          0 = no idle timeout (recommended for development workstations).
        '';
      };

      x11DisplayOffset = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Starting X11 display number (sessions will use :10, :11, :12, ...)";
      };
    };
  };

  # Validation assertions
  config = lib.mkIf config.services.xrdp.enable {
    assertions = [
      {
        assertion = config.services.xrdp.sesman.killDisconnected == false;
        message = "xrdp.sesman.killDisconnected must be false for multi-session support (FR-002)";
      }
      {
        assertion = config.services.xrdp.sesman.maxSessions >= 3;
        message = "xrdp.sesman.maxSessions must be at least 3 for multi-device use case (FR-006a)";
      }
      {
        assertion = config.services.xrdp.sesman.policy == "UBC" || config.services.xrdp.sesman.policy == "Separate";
        message = "xrdp.sesman.policy should be 'UBC' for multi-device support";
      }
    ];
  };
}

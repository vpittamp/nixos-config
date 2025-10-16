{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.pipewire.networkAudio;

in {
  options.services.pipewire.networkAudio = {
    enable = mkEnableOption "PipeWire network audio for remote desktop";

    port = mkOption {
      type = types.port;
      default = 4713;
      description = "PulseAudio protocol port for network audio";
    };

    address = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "IP address to listen on (0.0.0.0 for all interfaces)";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.pipewire.enable;
        message = "PipeWire network audio requires PipeWire to be enabled (services.pipewire.enable = true)";
      }
    ];

    # Enable PipeWire with PulseAudio compatibility
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
    };

    # Configure PipeWire network audio module
    services.pipewire.extraConfig.pipewire."99-network-audio" = {
      "context.modules" = [
        {
          name = "libpipewire-module-protocol-pulse";
          args = {
            "server.address" = [ "tcp:${cfg.address}:${toString cfg.port}" ];
            # Low latency configuration
            "pulse.min.req" = "256/48000";
            "pulse.min.quantum" = "256/48000";
            "pulse.default.req" = "512/48000";
            "pulse.default.quantum" = "512/48000";
            # Allow network connections
            "server.dbus-name" = null;
          };
        }
      ];
    };

    # Open firewall port for network audio
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Install PulseAudio tools for client-side testing
    environment.systemPackages = with pkgs; [
      pulseaudio  # For pactl, pavucontrol
      pavucontrol # Audio mixer GUI
    ];
  };
}

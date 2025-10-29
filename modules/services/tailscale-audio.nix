{ config, lib, ... }:

with lib;

let
  cfg = config.services.tailscaleAudio;
in {
  options.services.tailscaleAudio = {
    enable = mkEnableOption "PipeWire RTP audio sink streamed over Tailscale";

    destinationAddress = mkOption {
      type = types.str;
      example = "100.86.12.34";
      description = ''
        Tailscale IP address or MagicDNS hostname of the client device that should
        receive audio (for example, the Surface laptop running the VNC viewer).
      '';
      default = "";
    };

    destinationPort = mkOption {
      type = types.port;
      default = 4010;
      description = "UDP port that will carry the RTP audio stream";
    };

    sessionName = mkOption {
      type = types.str;
      default = "hetzner-sway";
      description = "Friendly name advertised in the RTP session metadata";
    };

    sinkName = mkOption {
      type = types.str;
      default = "tailscale-rtp";
      description = "PipeWire node name that applications will target";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.destinationAddress != "";
        message = "services.tailscaleAudio.destinationAddress must be set to your Surface laptop's Tailscale IP or MagicDNS hostname.";
      }
    ];

    services.pipewire.extraConfig.pipewire."60-tailscale-rtp" = {
      "context.modules" = [
        {
          name = "libpipewire-module-rtp-sink";
          args = {
            "destination.ip" = cfg.destinationAddress;
            "destination.port" = cfg.destinationPort;
            "sess.name" = cfg.sessionName;
            "audio.format" = "S16LE";
            "audio.rate" = 48000;
            "audio.channels" = 2;
            "audio.position" = [ "FL" "FR" ];
            "stream.props" = {
              "node.name" = cfg.sinkName;
              "node.description" = "${cfg.sessionName} Tailscale RTP";
              "media.class" = "Audio/Sink";
            };
          };
        }
      ];
    };

    networking.firewall.allowedUDPPorts = [ cfg.destinationPort ];
    networking.firewall.interfaces."tailscale0".allowedUDPPorts = [ cfg.destinationPort ];
  };
}

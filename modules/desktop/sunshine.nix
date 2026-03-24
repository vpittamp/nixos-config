# Sunshine Game Streaming Server for Wayland
# Provides low-latency remote desktop with hardware encoding support
#
# Hardware targets:
# - Ryzen (NVIDIA RTX 5070): NVENC hardware encoding (H.264/HEVC/AV1)
# - ThinkPad (Intel Arc): Quick Sync/VA-API hardware encoding
# - Hetzner (headless): Software encoding (x264)
#
# Client: Moonlight (available on all platforms)
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sunshine-streaming;
  sunshineUser = config.services.sunshine.user or "vpittamp";
  sunshineHome =
    if builtins.hasAttr sunshineUser config.users.users && config.users.users.${sunshineUser}.home != null
    then config.users.users.${sunshineUser}.home
    else "/home/${sunshineUser}";
  sunshineStateFile = "${sunshineHome}/.config/sunshine/sunshine_state.json";

  # Sunshine package with CUDA support for NVIDIA hardware encoding
  sunshineCuda = pkgs.sunshine.override { cudaSupport = true; };
  sunshinePackage = if cfg.hardwareType == "nvidia" then sunshineCuda else pkgs.sunshine;

  # Encoder configurations per hardware type
  encoderConfigs = {
    nvidia = {
      encoder = "nvenc";
      # NVENC supports H.264, HEVC, and AV1 on RTX 5070
      adapter_name = "/dev/dri/renderD128";
      nvenc_preset = "p4";  # Balanced quality/performance
      nvenc_tune = "ll";    # Low latency
      nvenc_rc = "cbr";     # Constant bitrate for streaming
    };

    intel = {
      encoder = "vaapi";
      # Intel Quick Sync via VA-API
      adapter_name = "/dev/dri/renderD128";
      vaapi_device = "/dev/dri/renderD128";
    };

    software = {
      encoder = "software";
      # x264 software encoding (CPU-based)
      # Note: sw_preset and sw_tune can be overridden via extraSettings
    };
  };

  # Capture method configurations
  captureConfigs = {
    kms = {
      # KMS/DRM capture - direct framebuffer access (lowest latency)
      # Requires cap_sys_admin capability
      capture = "kms";
    };

    wlroots = {
      # wlroots screencopy - Wayland protocol based
      # Works with headless Sway
      capture = "wlr";
    };

    pipewire = {
      # PipeWire portal capture
      # Fallback for Wayland
      capture = "pw";
    };
  };

  # Generate sunshine config based on hardware type
  # Note: These are base settings - extraSettings can override with mkForce if needed
  mkSunshineConfig = hwType: captureMethod: let
    encoder = encoderConfigs.${hwType};
    capture = captureConfigs.${captureMethod};
  in {
    # Basic settings
    origin_web_ui_allowed = "lan";
    upnp = "off";  # Disable UPnP (use Tailscale instead)

    # Stream settings (use mkDefault so extraSettings can override)
    fps = mkDefault "[30, 60]";
    resolutions = mkDefault ''
      [
        1920x1080,
        2560x1440,
        3840x2160
      ]
    '';

    # Encoder settings
    encoder = encoder.encoder;

    # Quality settings
    min_threads = mkDefault 2;
    hevc_mode = mkDefault 2;  # Always available
    av1_mode = mkDefault (if hwType == "nvidia" then 2 else 0);  # Only NVIDIA supports AV1

    # Audio
    audio_sink = mkDefault "auto";

    # Input
    key_repeat_delay = mkDefault 500;
    key_repeat_frequency = mkDefault 25;
  } // (removeAttrs encoder [ "encoder" ])
    // capture;

  pairedClientsSpec =
    pkgs.writeText "sunshine-paired-clients.json"
      (builtins.toJSON
        (map
          (client: {
            inherit (client) name uuid certificate certificateFile;
          })
          cfg.pairedClients));

  sunshineSyncState =
    pkgs.writeShellScriptBin "sunshine-sync-state" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      state_file=${lib.escapeShellArg sunshineStateFile}
      clients_file=${lib.escapeShellArg pairedClientsSpec}

      if [ ! -f "$state_file" ]; then
        echo "Sunshine state file not found: $state_file" >&2
        exit 1
      fi

      tmp_state=$(mktemp)
      tmp_clients=$(mktemp)
      trap 'rm -f "$tmp_state" "$tmp_clients"' EXIT

      while IFS= read -r client; do
        name=$(${pkgs.jq}/bin/jq -r '.name' <<<"$client")
        uuid=$(${pkgs.jq}/bin/jq -r '.uuid' <<<"$client")
        certificate=$(${pkgs.jq}/bin/jq -r '.certificate // empty' <<<"$client")
        certificate_file=$(${pkgs.jq}/bin/jq -r '.certificateFile // empty' <<<"$client")

        if [ -n "$certificate" ] && [ -n "$certificate_file" ]; then
          echo "Sunshine paired client '$name' cannot define both certificate and certificateFile" >&2
          exit 1
        fi

        if [ -z "$certificate" ] && [ -n "$certificate_file" ]; then
          if [ ! -f "$certificate_file" ]; then
            echo "Sunshine paired client '$name' certificate file not found: $certificate_file" >&2
            exit 1
          fi
          certificate=$(cat "$certificate_file")
        fi

        if [ -z "$certificate" ]; then
          echo "Sunshine paired client '$name' is missing certificate data" >&2
          exit 1
        fi

        ${pkgs.jq}/bin/jq -cn \
          --arg name "$name" \
          --arg uuid "$uuid" \
          --arg cert "$certificate" \
          '{ name: $name, uuid: $uuid, cert: $cert }'
      done < <(${pkgs.jq}/bin/jq -c '.[]' "$clients_file") | ${pkgs.jq}/bin/jq -s '.' > "$tmp_clients"

      ${pkgs.jq}/bin/jq \
        --slurpfile managed "$tmp_clients" \
        --arg unique_id ${lib.escapeShellArg (cfg.hostUniqueId or "")} '
        .root = (.root // {}) |
        if $unique_id != "" then
          .root.uniqueid = $unique_id
        else
          .
        end |
        .root.named_devices =
          (((.root.named_devices // []) | map(
            . as $existing |
            select(($managed[0] | any((.name == $existing.name) or (.uuid == $existing.uuid))) | not)
          )) + $managed[0])
      ' "$state_file" > "$tmp_state"

      mv "$tmp_state" "$state_file"
      chmod 600 "$state_file"
    '';

in {
  options.services.sunshine-streaming = {
    enable = mkEnableOption "Sunshine game streaming server";

    hostUniqueId = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Declarative Sunshine host unique ID stored in
        `~/.config/sunshine/sunshine_state.json` as `root.uniqueid`.
      '';
    };

    hardwareType = mkOption {
      type = types.enum [ "nvidia" "intel" "software" ];
      description = "Hardware encoder type";
      example = "nvidia";
    };

    captureMethod = mkOption {
      type = types.enum [ "kms" "wlroots" "pipewire" ];
      default = "kms";
      description = ''
        Screen capture method:
        - kms: Direct KMS/DRM capture (lowest latency, requires cap_sys_admin)
        - wlroots: wlroots screencopy protocol (for Sway/wlroots compositors)
        - pipewire: PipeWire portal capture (Wayland fallback)
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Sunshine";
    };

    tailscaleOnly = mkOption {
      type = types.bool;
      default = true;
      description = "Only allow connections via Tailscale interface";
    };

    extraSettings = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional Sunshine settings to merge";
      example = {
        fps = "[60, 120]";
        bitrate = 50000;
      };
    };

    desktopAppOverrides = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional attributes to merge into the default Sunshine Desktop app.";
      example = {
        auto-detach = "true";
      };
    };

    pairedClients = mkOption {
      type = types.listOf (types.submodule ({ ... }: {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name shown in Sunshine for the paired client.";
          };

          uuid = mkOption {
            type = types.str;
            description = "Sunshine client UUID for this paired client.";
          };

          certificate = mkOption {
            type = types.nullOr types.lines;
            default = null;
            description = ''
              PEM-encoded public Moonlight client certificate.
            '';
          };

          certificateFile = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Runtime path to a PEM-encoded public Moonlight client certificate.
            '';
          };
        };
      }));
      default = [];
      description = ''
        Declarative Sunshine paired clients. These entries are merged into
        `~/.config/sunshine/sunshine_state.json` before Sunshine starts.

        Managed entries replace any existing Sunshine state with the same
        client name or UUID while leaving unrelated paired clients intact.
      '';
    };

  };

  config = mkIf cfg.enable {
    assertions = map
      (client: {
        assertion = (client.certificate != null) != (client.certificateFile != null);
        message = "Sunshine paired client '${client.name}' must define exactly one of certificate or certificateFile.";
      })
      cfg.pairedClients;

    # Enable the upstream NixOS Sunshine module
    services.sunshine = {
      enable = true;
      autoStart = true;

      # Use CUDA-enabled package for NVIDIA
      package = sunshinePackage;

      # Required for KMS capture on Wayland
      capSysAdmin = true;

      # Let us handle firewall ourselves for Tailscale-only mode
      openFirewall = !cfg.tailscaleOnly && cfg.openFirewall;

      # Merge generated config with user overrides
      settings = mkMerge [
        (mkSunshineConfig cfg.hardwareType cfg.captureMethod)
        cfg.extraSettings
      ];

      # Default applications (desktop streaming)
      applications = {
        apps = [
          ({
            name = "Desktop";
            image-path = "";
          } // cfg.desktopAppOverrides)
        ];
      };
    };

    # Disable Avahi when using Tailscale-only mode (we don't need mDNS discovery)
    # The upstream Sunshine module enables avahi, but we override it
    services.avahi.enable = mkIf cfg.tailscaleOnly (mkForce false);

    # Firewall configuration
    networking.firewall = mkIf cfg.openFirewall (
      if cfg.tailscaleOnly then {
        # Only allow Sunshine ports on Tailscale interface
        interfaces."tailscale0".allowedTCPPorts = [ 47984 47989 47990 48010 ];
        interfaces."tailscale0".allowedUDPPortRanges = [
          { from = 47998; to = 48000; }
          { from = 48002; to = 48002; }
          { from = 48010; to = 48010; }
          { from = 8000; to = 8010; }
        ];
      } else {
        # Allow on all interfaces
        allowedTCPPorts = [ 47984 47989 47990 48010 ];
        allowedUDPPortRanges = [
          { from = 47998; to = 48000; }
          { from = 48002; to = 48002; }
          { from = 48010; to = 48010; }
          { from = 8000; to = 8010; }
        ];
      }
    );

    # Add user to required groups for capture
    users.users.${sunshineUser}.extraGroups = [
      "video"
      "input"
    ];

    # Environment variables for hardware encoding
    environment.sessionVariables = mkMerge [
      # NVIDIA-specific
      (mkIf (cfg.hardwareType == "nvidia") {
        # Ensure NVENC is available
        LIBVA_DRIVER_NAME = "nvidia";
      })

      # Intel-specific
      (mkIf (cfg.hardwareType == "intel") {
        # Use iHD driver for Intel Arc
        LIBVA_DRIVER_NAME = "iHD";
      })
    ];

    # Ensure required packages are available
    environment.systemPackages = [
      sunshinePackage
      sunshineSyncState
    ] ++ optionals (cfg.hardwareType == "nvidia") (with pkgs; [
      # NVIDIA utilities
      nvtopPackages.nvidia
    ]) ++ optionals (cfg.hardwareType == "intel") (with pkgs; [
      # Intel utilities
      intel-gpu-tools
      libva-utils
    ]);

    systemd.user.services.sunshine = mkIf (cfg.pairedClients != [] || cfg.hostUniqueId != null) {
      serviceConfig = {
        ExecStartPre = [ "${sunshineSyncState}/bin/sunshine-sync-state" ];
      };
    };

    # Note: Credentials must be set manually via:
    #   sunshine --creds <username> <password>
    # Or via the web UI at https://localhost:47990
  };
}

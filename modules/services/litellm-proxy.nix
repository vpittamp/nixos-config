# Feature 123: LiteLLM Proxy for Full OpenTelemetry Tracing
#
# LiteLLM acts as a proxy between Claude Code and the Anthropic API,
# capturing detailed trace data including:
# - Request/response content
# - Token usage and costs
# - Latency metrics
# - Model parameters
#
# Architecture:
#   Claude Code → LiteLLM Proxy (4000) → Anthropic API
#                      ↓
#              OTEL Collector (4318)
#
# Usage:
#   export ANTHROPIC_BASE_URL="http://localhost:4000"
#   export ANTHROPIC_AUTH_TOKEN="your-litellm-master-key"
#   claude "your prompt"
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.litellm-proxy;

  # Python environment with LiteLLM and OTEL dependencies
  pythonEnv = pkgs.python311.withPackages (ps: with ps; [
    litellm
    opentelemetry-api
    opentelemetry-sdk
    opentelemetry-exporter-otlp
    uvicorn
    fastapi
  ]);

  # LiteLLM configuration file
  configFile = pkgs.writeText "litellm-config.yaml" ''
    # LiteLLM Proxy Configuration for Claude Code
    # Feature 123: Full OTEL tracing

    model_list:
      # Claude Opus 4.5 - Most capable model
      - model_name: claude-opus-4-5-20251101
        litellm_params:
          model: anthropic/claude-opus-4-5-20251101
          api_key: os.environ/ANTHROPIC_API_KEY

      # Claude Sonnet 4 - Balanced performance
      - model_name: claude-sonnet-4-20250514
        litellm_params:
          model: anthropic/claude-sonnet-4-20250514
          api_key: os.environ/ANTHROPIC_API_KEY

      # Claude Haiku 4.5 - Fast and efficient
      - model_name: claude-haiku-4-5-20251001
        litellm_params:
          model: anthropic/claude-haiku-4-5-20251001
          api_key: os.environ/ANTHROPIC_API_KEY

      # Legacy model names for compatibility
      - model_name: claude-3-5-sonnet-20241022
        litellm_params:
          model: anthropic/claude-3-5-sonnet-20241022
          api_key: os.environ/ANTHROPIC_API_KEY

      - model_name: claude-3-5-haiku-20241022
        litellm_params:
          model: anthropic/claude-3-5-haiku-20241022
          api_key: os.environ/ANTHROPIC_API_KEY

    litellm_settings:
      # Enable OpenTelemetry callback for tracing
      callbacks: ["otel"]

      # Log successful and failed requests
      success_callback: ["otel"]
      failure_callback: ["otel"]

      # Don't redact messages (we want full traces for debugging)
      # Set to true in production for privacy
      turn_off_message_logging: ${if cfg.redactMessages then "true" else "false"}

    ${optionalString (cfg.masterKey != null) ''
    general_settings:
      master_key: os.environ/LITELLM_MASTER_KEY
    ''}

    ${optionalString cfg.enableOtel ''
    # OTEL configuration is set via environment variables:
    # OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_EXPORTER_OTLP_PROTOCOL
    ''}
  '';
in
{
  options.services.litellm-proxy = {
    enable = mkEnableOption "LiteLLM proxy for Claude Code with OTEL tracing";

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "Port for LiteLLM proxy to listen on";
    };

    otelEndpoint = mkOption {
      type = types.str;
      default = "http://localhost:4318";
      description = "OTEL collector endpoint for trace export";
    };

    enableOtel = mkOption {
      type = types.bool;
      default = true;
      description = "Enable OpenTelemetry tracing";
    };

    redactMessages = mkOption {
      type = types.bool;
      default = false;
      description = "Redact message content from traces (for privacy)";
    };

    masterKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Master key for LiteLLM proxy authentication (use null to disable auth)";
    };

    anthropicKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Anthropic API key";
    };
  };

  config = mkIf cfg.enable {
    # Systemd service for LiteLLM proxy
    systemd.services.litellm-proxy = {
      description = "LiteLLM Proxy for Claude Code with OTEL tracing";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "opentelemetry-collector.service" ];

      environment = {
        # OTEL configuration
        OTEL_EXPORTER_OTLP_ENDPOINT = cfg.otelEndpoint;
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/json";
        OTEL_SERVICE_NAME = "litellm-proxy";

        # LiteLLM settings
        LITELLM_LOG = "DEBUG";
      } // optionalAttrs (cfg.masterKey != null) {
        LITELLM_MASTER_KEY = cfg.masterKey;
      };

      serviceConfig = {
        Type = "simple";
        User = "litellm";
        Group = "litellm";
        DynamicUser = true;

        # Load Anthropic API key from file if specified
        EnvironmentFile = mkIf (cfg.anthropicKeyFile != null) cfg.anthropicKeyFile;

        ExecStart = ''
          ${pythonEnv}/bin/litellm \
            --config ${configFile} \
            --port ${toString cfg.port} \
            --host 127.0.0.1
        '';

        Restart = "on-failure";
        RestartSec = "5s";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
      };
    };

    # Firewall rules (only allow localhost by default)
    networking.firewall.allowedTCPPorts = mkIf cfg.enable [];
  };
}

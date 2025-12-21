# Provider Configuration Schema

**Feature**: `125-tracing-parity-codex`
**Date**: 2025-12-21

This document defines the configuration schemas for each AI CLI provider's OpenTelemetry settings.

## Codex CLI Configuration

**File**: `~/.codex/config.toml`

```toml
[otel]
# Environment tag for telemetry
# Type: string
# Default: "dev"
environment = "production"

# OTLP exporter type
# Type: "none" | "otlp-http" | "otlp-grpc"
# Default: "none"
exporter = "otlp-http"

# OTLP endpoint (when exporter is not "none")
# Type: string (URL)
# Required when exporter != "none"
endpoint = "http://localhost:4318"

# Whether to include user prompts in telemetry
# Type: boolean
# Default: false
# Security: Keep false to avoid logging sensitive data
log_user_prompt = false
```

### Home Manager Configuration

```nix
# home-modules/ai-assistants/codex.nix
{ config, lib, pkgs, ... }:

{
  home.file.".codex/config.toml".text = ''
    [otel]
    environment = "production"
    exporter = "otlp-http"
    endpoint = "http://localhost:4318"
    log_user_prompt = false
  '';
}
```

---

## Gemini CLI Configuration

**File**: `~/.gemini/settings.json`

```json
{
  "telemetry": {
    // Enable/disable telemetry collection
    // Type: boolean
    // Default: true
    "enabled": true,

    // Export target
    // Type: "local" | "gcp" | "custom"
    // Default: "local"
    "target": "local",

    // OTLP endpoint (for local/custom targets)
    // Type: string (URL)
    // Required when target is "local" or "custom"
    "otlpEndpoint": "http://localhost:4318",

    // Output file for local logging (optional)
    // Type: string (file path)
    "outfile": ""
  }
}
```

### Home Manager Configuration

```nix
# home-modules/ai-assistants/gemini.nix
{ config, lib, pkgs, ... }:

{
  home.file.".gemini/settings.json".text = builtins.toJSON {
    telemetry = {
      enabled = true;
      target = "local";
      otlpEndpoint = "http://localhost:4318";
    };
  };
}
```

---

## Claude Code Configuration (Reference)

Already implemented in `home-modules/ai-assistants/claude-code.nix`:

```nix
home.sessionVariables = {
  CLAUDE_CODE_ENABLE_TELEMETRY = "1";
  OTEL_LOGS_EXPORTER = "otlp";
  OTEL_METRICS_EXPORTER = "otlp";
  OTEL_TRACES_EXPORTER = "otlp";
  OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
  OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318";
  OTEL_METRIC_EXPORT_INTERVAL = "60000";
  OTEL_LOGS_EXPORT_INTERVAL = "5000";
};
```

---

## Validation Requirements

### All Providers

| Requirement | Validation |
|-------------|------------|
| Endpoint reachable | HTTP 200 on `{endpoint}/v1/traces` POST |
| Telemetry enabled | Config value is truthy |
| Prompt redaction | `log_user_prompt = false` or equivalent |

### Codex CLI Specific

| Requirement | Validation |
|-------------|------------|
| Version ≥ 0.73.0 | `codex --version` output check |
| Exporter configured | `exporter != "none"` |
| OAuth authenticated | `codex auth status` returns success |

### Gemini CLI Specific

| Requirement | Validation |
|-------------|------------|
| Telemetry enabled | `telemetry.enabled = true` |
| Target is local | `telemetry.target = "local"` |
| OAuth authenticated | `gemini auth status` returns success |

---

## Environment Variables

Optional environment variable overrides (all providers):

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Override endpoint for all providers | Config value |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Protocol (http/protobuf, grpc) | `http/protobuf` |
| `OTEL_SERVICE_NAME` | Override service name in telemetry | CLI-specific |

---

## Security Considerations

1. **Prompt Redaction**: Always set `log_user_prompt = false` (Codex) to avoid logging sensitive code/prompts
2. **Local Endpoint**: Use `localhost:4318` to avoid exposing telemetry over network
3. **No API Keys in Config**: All auth via OAuth, no credentials in config files
4. **File Permissions**: Config files should be user-readable only (0600)

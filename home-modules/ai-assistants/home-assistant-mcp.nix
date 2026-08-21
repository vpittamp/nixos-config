{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.aiAssistants.homeAssistantMcp;
  proxyCommand = pkgs.writeShellScript "home-assistant-mcp-proxy" ''
    set -euo pipefail

    api_key="''${HASS_TOKEN:-''${HOMEASSISTANT_TOKEN:-''${HOME_ASSISTANT_TOKEN:-}}}"
    api_key_ref="''${HASS_TOKEN_OP_REF:-${cfg.apiKeyReference}}"
    op_bin="/run/wrappers/bin/op"
    if [ ! -x "$op_bin" ]; then
      op_bin="${pkgs._1password-cli}/bin/op"
    fi
    if [ -z "$api_key" ] && [ -n "$api_key_ref" ]; then
      api_key="$("$op_bin" read "$api_key_ref" 2>/dev/null || true)"
    fi
    if [ -z "$api_key" ]; then
      echo "HASS_TOKEN or HOMEASSISTANT_TOKEN is required for Home Assistant MCP access." >&2
      echo "Create a Long-Lived Access Token in Home Assistant and store it in 1Password at $api_key_ref, or set HASS_TOKEN." >&2
      exit 64
    fi

    # Codex explicitly forwards the available 1Password authentication path
    # and desktop IPC variables to this launcher so `op read` can resolve the
    # credential. Do not let that authority or the raw credential survive into Node/mcp-remote.
    unset DBUS_SESSION_BUS_ADDRESS DISPLAY OP_BIOMETRIC_UNLOCK_ENABLED
    unset OP_SERVICE_ACCOUNT_TOKEN WAYLAND_DISPLAY XDG_RUNTIME_DIR

    mcp_url="''${HASS_MCP_URL:-${cfg.url}}"
    export HASS_MCP_AUTH_HEADER="Bearer $api_key"
    args=(
      -y
      mcp-remote
      "$mcp_url"
      --transport
      http-only
      --header
      'Authorization:''${HASS_MCP_AUTH_HEADER}'
    )

    exec "${pkgs.nodejs}/bin/npx" "''${args[@]}"
  '';
in
{
  options.modules.aiAssistants.homeAssistantMcp = {
    enable = mkEnableOption "Home Assistant MCP server (Streamable HTTP bridge) for local AI CLIs";

    url = mkOption {
      type = types.str;
      default = "http://surface-pro.tail286401.ts.net:8123/api/mcp";
      description = "MCP Streamable HTTP URL consumed by local AI CLIs.";
    };

    apiKeyReference = mkOption {
      type = types.str;
      default = "op://CLI/Home Assistant MCP Token/credential";
      description = ''
        1Password secret reference read at MCP proxy startup when HASS_TOKEN or
        HOMEASSISTANT_TOKEN is unset. The reference may be overridden with
        HASS_TOKEN_OP_REF; the resolved key is never written into the Nix store
        or generated config.
      '';
    };

    proxyCommand = mkOption {
      type = types.package;
      readOnly = true;
      description = ''
        Shared stdio-to-HTTP proxy (mcp-remote) that authenticates with
        HASS_TOKEN / HOMEASSISTANT_TOKEN or the configured 1Password reference
        to talk to Home Assistant's Streamable HTTP /api/mcp endpoint.
      '';
    };
  };

  config.modules.aiAssistants.homeAssistantMcp.proxyCommand = proxyCommand;
}

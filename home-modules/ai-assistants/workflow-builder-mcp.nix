{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.aiAssistants.workflowBuilderMcp;
  proxyCommand = pkgs.writeShellScript "workflow-builder-mcp-proxy" ''
    set -euo pipefail

    api_key="''${WFB_API_KEY:-}"
    api_key_ref="''${WFB_API_KEY_OP_REF:-${cfg.apiKeyReference}}"
    if [ -z "$api_key" ] && [ -n "$api_key_ref" ]; then
      api_key="$(${pkgs._1password-cli}/bin/op read "$api_key_ref" 2>/dev/null || true)"
    fi
    if [ -z "$api_key" ]; then
      echo "WFB_API_KEY is required for workflow-builder MCP access." >&2
      echo "Create a workspace API key in Workflow Builder and store it at $api_key_ref, or set WFB_API_KEY explicitly." >&2
      exit 64
    fi

    mcp_url="''${WFB_MCP_URL:-${cfg.url}}"
    export WFB_MCP_AUTH_HEADER="Bearer $api_key"
    args=(
      -y
      mcp-remote
      "$mcp_url"
      --transport
      http-only
      --header
      'Authorization:''${WFB_MCP_AUTH_HEADER}'
    )

    # A Workflow Builder session is optional lineage for goal/trace tools.
    # It is never inferred from an AI client's transport or conversation id.
    if [ -n "''${WFB_MCP_SESSION_ID:-}" ]; then
      args+=(--header 'X-Wfb-Session-Id:''${WFB_MCP_SESSION_ID}')
    fi

    exec "${pkgs.nodejs}/bin/npx" "''${args[@]}"
  '';
in
{
  options.modules.aiAssistants.workflowBuilderMcp = {
    enable = mkEnableOption "workflow-builder platform MCP server for local AI CLIs";

    tailnetHost = mkOption {
      type = types.str;
      default = "workflow-builder-mcp-dev.tail286401.ts.net";
      description = "Tailnet hostname for the default workflow-builder platform MCP server.";
    };

    url = mkOption {
      type = types.str;
      default = "https://workflow-builder-mcp-dev.tail286401.ts.net/mcp";
      description = "MCP Streamable HTTP URL consumed by local AI CLIs.";
    };

    apiKeyReference = mkOption {
      type = types.str;
      default = "op://hub-eso/WORKFLOW-BUILDER-MCP-API-KEY/password";
      description = ''
        1Password secret reference read at MCP proxy startup when WFB_API_KEY is
        unset. The reference may be overridden with WFB_API_KEY_OP_REF; the
        resolved key is never written into the Nix store or generated config.
      '';
    };

    proxyCommand = mkOption {
      type = types.package;
      readOnly = true;
      description = ''
        Shared stdio-to-HTTP proxy that authenticates with WFB_API_KEY or the
        configured 1Password reference, and optionally attaches the explicit
        WFB_MCP_SESSION_ID lineage header.
      '';
    };
  };

  config.modules.aiAssistants.workflowBuilderMcp.proxyCommand = proxyCommand;
}

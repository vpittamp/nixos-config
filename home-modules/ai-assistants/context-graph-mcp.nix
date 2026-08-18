{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.aiAssistants.contextGraphMcp;
  proxyCommand = pkgs.writeShellScript "context-graph-mcp-proxy" ''
    set -euo pipefail

    # Graph memory (neo4j-agent-memory) MCP server on the dev cluster, exposed
    # over the tailnet by the stacks `context-graph-tailscale` Ingress. The
    # server is auth-less — reachability is bounded by tailnet membership,
    # like the Neo4j Browser exposure — so unlike workflow-builder-mcp this
    # proxy carries no credential. mcp-remote bridges stdio clients to the
    # Streamable HTTP endpoint.
    mcp_url="''${CONTEXT_GRAPH_MCP_URL:-${cfg.url}}"
    exec "${pkgs.nodejs}/bin/npx" -y mcp-remote "$mcp_url" --transport http-only
  '';
in
{
  options.modules.aiAssistants.contextGraphMcp = {
    enable = mkEnableOption "context-graph (Neo4j agent memory) MCP server for local AI CLIs";

    tailnetHost = mkOption {
      type = types.str;
      default = "workflow-builder-context-graph-dev.tail286401.ts.net";
      description = "Tailnet hostname for the dev cluster's context-graph MCP server.";
    };

    url = mkOption {
      type = types.str;
      default = "https://workflow-builder-context-graph-dev.tail286401.ts.net/t/dev-default-project/mcp";
      description = ''
        MCP Streamable HTTP URL consumed by local AI CLIs. Defaults to the dev
        cluster's dev-default-project tenant mount (the identity the platform's
        own ingestion and UI read); use /mcp for the default identity instead.
      '';
    };

    # The 17-tool surface the live server exposes (extended profile plus the
    # platform's graph_write). Consumers that require explicit tool
    # enumeration (antigravity) read this list; others accept every tool.
    toolNames = mkOption {
      type = types.listOf types.str;
      default = [
        "graph_query"
        "graph_write"
        "memory_add_entity"
        "memory_add_fact"
        "memory_add_preference"
        "memory_complete_trace"
        "memory_create_relationship"
        "memory_export_graph"
        "memory_get_context"
        "memory_get_conversation"
        "memory_get_entity"
        "memory_get_observations"
        "memory_list_sessions"
        "memory_record_step"
        "memory_search"
        "memory_start_trace"
        "memory_store_message"
      ];
      description = "Tool names served by the context-graph MCP server.";
    };

    proxyCommand = mkOption {
      type = types.package;
      readOnly = true;
      description = ''
        stdio-to-HTTP proxy (mcp-remote) for the tailnet context-graph MCP
        endpoint. No credential: the server is tailnet-scoped and auth-less.
      '';
    };
  };

  config.modules.aiAssistants.contextGraphMcp.proxyCommand = proxyCommand;
}

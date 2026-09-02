{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.aiAssistants.kiotaMcp;
  proxyCommand = pkgs.writeShellScript "kiota-mcp-proxy" ''
    set -euo pipefail

    # Kiota generated-actions MCP server (workflow-builder services/kiota-mcp)
    # on the dev cluster, exposed over the tailnet by the stacks
    # `kiota-mcp-tailscale` Ingress. It wraps the pinned Kiota CLI: search /
    # show / generate / manifest over allowlisted OpenAPI description origins,
    # plus the deterministic thin and composite action packagers. The server
    # holds no credentials and is auth-less — reachability is bounded by
    # tailnet membership, like context-graph-mcp — so this proxy carries no
    # credential. mcp-remote bridges stdio clients to Streamable HTTP.
    mcp_url="''${KIOTA_MCP_URL:-${cfg.url}}"
    exec "${pkgs.nodejs}/bin/npx" -y mcp-remote "$mcp_url" --transport http-only
  '';
in {
  options.modules.aiAssistants.kiotaMcp = {
    enable = mkEnableOption "kiota generated-actions MCP server for local AI CLIs";

    tailnetHost = mkOption {
      type = types.str;
      default = "kiota-mcp-dev.tail286401.ts.net";
      description = "Tailnet hostname for the dev cluster's kiota-mcp server.";
    };

    url = mkOption {
      type = types.str;
      default = "https://kiota-mcp-dev.tail286401.ts.net/mcp";
      description = ''
        MCP Streamable HTTP URL consumed by local AI CLIs. The same host also
        serves /health and the package handle endpoint /packages/<id> that
        `save_generated_action { packageUrl }` on the workflow-builder MCP
        fetches in-cluster.
      '';
    };

    # The six tools the live server exposes. Consumers that require explicit
    # tool enumeration (antigravity) read this list; others accept every tool.
    toolNames = mkOption {
      type = types.listOf types.str;
      default = [
        "kiota_search"
        "kiota_show"
        "kiota_operations"
        "kiota_generate"
        "kiota_manifest"
        "kiota_package_action"
        "kiota_package_composite"
      ];
      description = "Tool names served by the kiota-mcp server.";
    };

    proxyCommand = mkOption {
      type = types.package;
      readOnly = true;
      description = ''
        stdio-to-HTTP proxy (mcp-remote) for the tailnet kiota-mcp endpoint.
        No credential: the server is tailnet-scoped and auth-less.
      '';
    };
  };

  config.modules.aiAssistants.kiotaMcp.proxyCommand = proxyCommand;
}

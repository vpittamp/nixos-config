{ config, lib, ... }:

with lib;

let
  cfg = config.modules.aiAssistants.workflowBuilderMcp;
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
  };

  config = mkIf cfg.enable {};
}

{ config, pkgs, lib, ... }:

{
  # Claude Code - Anthropic's Claude CLI
  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code;
    
    settings = {
      model = "claude-3-5-sonnet-20241022";
      theme = "dark";
      includeCoAuthoredBy = true;
    };
    
    # Agents configuration (if needed in future)
    # agents = {
    #   "example-agent" = {
    #     description = "Example custom agent";
    #     command = "example-command";
    #   };
    # };
    
    # Custom commands (if needed in future)
    # commands = {
    #   "example" = {
    #     description = "Example custom command";
    #     prompt = "Example prompt template";
    #   };
    # };
    
    # MCP servers (if needed in future)
    # mcpServers = {
    #   "example-server" = {
    #     command = "example-mcp-server";
    #     args = ["--example"];
    #   };
    # };
  };
}
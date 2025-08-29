{ config, pkgs, lib, ... }:

{
  # Claude Code - Anthropic's Claude CLI
  programs.claude-code = {
    enable = false;  # Disabled - using npm-package version from flake.nix instead
    package = pkgs.claude-code;
    
    settings = {
      model = "opus";
      theme = "dark";
      autoCompact = true;
      useTodoList = true;
      verboseOutput = true;
      autoUpdates = true;
      notifications = "bell";
      outputStyle = "default";
      editorMode = "vim";
      autoConnectToIde = true;
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
    
    # MCP servers configuration
    mcpServers = {
      "context7" = {
        transport = "sse";
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-sse"
          "https://mcp.context7.com/sse"
        ];
      };
      
      "grep" = {
        transport = "http";
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-http"
          "https://mcp.grep.app"
        ];
      };

      "playwright" = {
        transport = "http";
        command = "npx";
        args = [
          "@playwright/mcp@latest"
        ];
      };
    };
  };
}
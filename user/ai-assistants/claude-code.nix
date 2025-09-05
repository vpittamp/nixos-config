{ config, pkgs, lib, inputs, ... }:

# Temporarily commenting out npm-package builds for MCP servers
# These cause build issues in restricted container environments
# let
#   # Define MCP server packages using npm-package module
#   mcp-server-sse = inputs.npm-package.lib.${pkgs.system}.npmPackage {
#     name = "mcp-server-sse";
#     packageName = "@modelcontextprotocol/server-sse";
#   };
#   
#   mcp-server-http = inputs.npm-package.lib.${pkgs.system}.npmPackage {
#     name = "mcp-server-http";
#     packageName = "@modelcontextprotocol/server-http";
#   };
#   
#   # Use Puppeteer instead of Playwright - works better in headless/WSL environments
#   mcp-puppeteer = inputs.npm-package.lib.${pkgs.system}.npmPackage {
#     name = "mcp-puppeteer";
#     packageName = "@modelcontextprotocol/server-puppeteer";
#     version = "latest";
#   };
# in
{
  # Install Node.js and Chromium for MCP servers (they'll use npx at runtime)
  home.packages = [
    # mcp-server-sse    # Commented out - using npx instead
    # mcp-server-http   # Commented out - using npx instead  
    # mcp-puppeteer     # Commented out - using npx instead
    pkgs.nodejs_20      # Needed for npx
    pkgs.chromium       # Needed for puppeteer
  ];
  
  # Claude Code configuration with home-manager module
  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code;
    
    # Settings for Claude Code
    settings = {
      model = "opus";
      theme = "dark";
      editorMode = "vim";
      autoCompactEnabled = true;
      todoFeatureEnabled = true;
      verbose = true;
      autoUpdates = true;
      preferredNotifChannel = "terminal_bell";
      autoConnectIde = true;
      includeCoAuthoredBy = true;
      messageIdleNotifThresholdMs = 60000;
      env = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_METRICS_EXPORTER = "otlp";
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
      };
    };
    
    # MCP Servers configuration using npx directly (avoids build issues)
    mcpServers = {
      context7 = {
        command = "npx";
        args = [
          "-y"
          "@upstash/context7-mcp@latest"
        ];
      };
      
      # Temporarily disabled - requires npm-package build
      # grep = {
      #   transport = "http";
      #   command = "${mcp-server-http}/bin/mcp-server-http";
      #   args = [
      #     "https://mcp.grep.app"
      #   ];
      # };
      #
      # puppeteer = {
      #   transport = "stdio";
      #   command = "${mcp-puppeteer}/bin/mcp-puppeteer";
      #   args = [];
      #   env = {
      #     PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
      #   };
      # };
    };
  };
}
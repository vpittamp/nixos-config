{ config, pkgs, lib, inputs, ... }:

let
  # Check if we're on Darwin
  isDarwin = pkgs.stdenv.isDarwin or false;
in
{
  # Install MCP server packages and Chromium for Puppeteer (Linux only)
  home.packages = lib.optionals (!isDarwin) ([
    pkgs.chromium
  ] ++ (if isDarwin then [] else [
    (inputs.npm-package.lib.${pkgs.system}.npmPackage {
      name = "mcp-server-sse";
      packageName = "@modelcontextprotocol/server-sse";
    })
    (inputs.npm-package.lib.${pkgs.system}.npmPackage {
      name = "mcp-server-http";
      packageName = "@modelcontextprotocol/server-http";
    })
    (inputs.npm-package.lib.${pkgs.system}.npmPackage {
      name = "mcp-puppeteer";
      packageName = "@modelcontextprotocol/server-puppeteer";
      version = "latest";
    })
  ]));
  
  # Claude Code configuration with home-manager module
  # Try to enable on all platforms, will fail gracefully if not available
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
    
    # MCP Servers configuration using npm-package installed binaries
    mcpServers = {
      context7 = {
        command = "npx";
        args = [
          "-y"
          "@upstash/context7-mcp@latest"
        ];
      };
      
      grep = {
        transport = "http";
        command = "${mcp-server-http}/bin/mcp-server-http";
        args = [
          "https://mcp.grep.app"
        ];
      };

      puppeteer = {
        transport = "stdio";
        command = "${mcp-puppeteer}/bin/mcp-puppeteer";
        args = [];
        env = {
          PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
          # Redirect logs to temp directory to avoid cluttering project directories
          NODE_ENV = "production";
          LOG_DIR = "/tmp/mcp-puppeteer-logs";
        };
      };
    };
  };
}
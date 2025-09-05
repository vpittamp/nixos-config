{ config, pkgs, lib, inputs, ... }:

{
  # Install Node.js and Chromium for MCP servers
  home.packages = [
    pkgs.nodejs_20
    pkgs.chromium
    
    # Use npm-package to create claude-code wrapper instead of building
    (inputs.npm-package.lib.${pkgs.system}.npmPackage {
      name = "claude";
      packageName = "@anthropic-ai/claude-code";
      version = "latest";
    })
  ];
  
  # Claude Code configuration with home-manager module
  # Note: Since we're using npm-package wrapper, we don't use programs.claude-code
  home.file.".config/claude/settings.json".text = builtins.toJSON {
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
  
  # MCP Servers configuration
  home.file.".config/claude/claude_code_config.json".text = builtins.toJSON {
    mcpServers = {
      context7 = {
        command = "npx";
        args = [
          "-y"
          "@upstash/context7-mcp@latest"
        ];
      };
    };
  };
}
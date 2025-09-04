# Container-compatible AI assistant configuration
# Uses only packages available in nixpkgs without custom module definitions
{ config, pkgs, lib, ... }:

{
  # Allow unfree packages (claude-code is proprietary)
  nixpkgs.config.allowUnfree = true;
  
  # Claude Code - Official Anthropic CLI (only package we're installing)
  home.packages = with pkgs; [
    claude-code          # Official Claude CLI
    
    # Node.js for potential MCP servers
    nodejs_22
    
    # For MCP servers that may need browser
    chromium           # Browser for puppeteer
  ];
  
  # Configure Claude Code settings via config file
  home.file.".config/claude/config.toml".text = ''
    model = "opus"
    theme = "dark"
    editorMode = "vim"
    autoCompactEnabled = true
    todoFeatureEnabled = true
    verbose = true
    autoUpdates = true
    preferredNotifChannel = "terminal_bell"
    autoConnectIde = true
    includeCoAuthoredBy = true
    messageIdleNotifThresholdMs = 60000
    
    [env]
    CLAUDE_CODE_ENABLE_TELEMETRY = "1"
    OTEL_METRICS_EXPORTER = "otlp"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    
    # MCP Servers
    [mcpServers.context7]
    command = "npx"
    args = ["-y", "@upstash/context7-mcp@latest"]
  '';
  
  # Shell aliases
  programs.bash.shellAliases = {
    # Claude shortcuts
    claude = "claude-code";
    cc = "claude-code";
    
    # Helper command to set API key
    claude-key = "echo 'Set: export ANTHROPIC_API_KEY=your-key-here'";
  };
  
  # Environment variables
  home.sessionVariables = {
    CLAUDE_CONFIG_DIR = "$HOME/.config/claude";
    EDITOR = lib.mkDefault "nvim";
  };
  
  # Documentation for Claude Code
  home.file.".config/claude/README.md".text = ''
    # Claude Code Configuration
    
    Claude Code is installed and ready to use.
    
    ## Setup
    1. Set your API key: export ANTHROPIC_API_KEY="your-key-here"
    2. Run: claude-code (or use alias: claude)
    
    ## Configuration
    Settings are in ~/.config/claude/config.toml
    
    ## MCP Servers
    Context7 MCP server is configured for documentation lookup.
  '';
}
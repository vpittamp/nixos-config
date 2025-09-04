# Container-compatible AI assistant configuration
# Uses only packages available in nixpkgs without custom module definitions
{ config, pkgs, lib, ... }:

{
  # Claude Code - Available in nixpkgs
  home.packages = with pkgs; [
    claude-code          # Official Claude CLI
    aider-chat          # AI pair programming (supports Claude, GPT-4, etc.)
    
    # Development tools for AI
    python311
    python311Packages.pip
    nodejs_22
    yarn
    
    # Supporting tools
    gh                  # GitHub CLI
    jq                  # JSON processor
    yq-go              # YAML processor
    httpie             # HTTP client
    direnv             # Environment management
    
    # For MCP servers (if needed)
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
    
    # Aider with different models
    ai = "aider";
    ai-claude = "aider --model claude-3-opus-20240229";
    ai-sonnet = "aider --model claude-3-5-sonnet-20240620";
    ai-gpt4 = "aider --model gpt-4";
    ai-gpt4o = "aider --model gpt-4o";
    
    # Helper commands
    ai-keys = "echo 'Set: export ANTHROPIC_API_KEY=... export OPENAI_API_KEY=...'";
  };
  
  # Environment variables
  home.sessionVariables = {
    CLAUDE_CONFIG_DIR = "$HOME/.config/claude";
    EDITOR = lib.mkDefault "nvim";
  };
  
  # Setup script for Python AI libraries
  home.file.".config/ai/setup.sh".text = ''
    #!/usr/bin/env bash
    echo "Installing AI Python libraries..."
    pip install --user openai anthropic google-generativeai litellm langchain
    echo "Done! Set your API keys:"
    echo "  export ANTHROPIC_API_KEY='your-key'"
    echo "  export OPENAI_API_KEY='your-key'"
    echo "  export GOOGLE_API_KEY='your-key'"
  '';
  home.file.".config/ai/setup.sh".executable = true;
}
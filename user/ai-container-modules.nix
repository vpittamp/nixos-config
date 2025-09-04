# Container-compatible AI assistant configuration
# Uses native home-manager options for AI tools
{ config, pkgs, lib, ... }:

{
  # Allow unfree packages (claude-code is proprietary)
  nixpkgs.config.allowUnfree = true;
  
  # Additional packages for MCP servers
  home.packages = with pkgs; [
    # Node.js for npm packages and MCP servers
    nodejs_22
    
    # For MCP servers that may need browser
    chromium           # Browser for puppeteer
  ];
  
  # Claude Code - Official Anthropic CLI
  programs.claude-code = {
    enable = true;
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
      
      # MCP Servers
      mcpServers.context7 = {
        command = "npx";
        args = ["-y" "@upstash/context7-mcp@latest"];
      };
    };
  };
  
  # Gemini CLI
  programs.gemini-cli = {
    enable = true;
    settings = {
      theme = "Default";
      vimMode = false;
      preferredEditor = "nvim";
      autoAccept = false;
    };
  };
  
  # Codex - Lightweight coding agent
  programs.codex = {
    enable = true;
    settings = {
      model = "claude-3.5-sonnet";
      model_provider = "anthropic";
      auto_save = true;
      theme = "dark";
      vim_mode = false;
    };
  };
  
  # AIChat - Multi-model chat
  programs.aichat = {
    enable = true;
    # AIChat config can be added here if needed
  };
  
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
  
  # Documentation for AI Assistants
  home.file.".config/ai/README.md".text = ''
    # AI Assistants Configuration
    
    ## Installed Tools (Native Home-Manager)
    
    ### Claude Code
    - Command: `claude` or `claude-code`
    - Setup: `export ANTHROPIC_API_KEY="your-key-here"`
    - Config: Managed by home-manager
    
    ### Gemini CLI
    - Command: `gemini` or `gemini-cli`
    - Setup: `export GEMINI_API_KEY="your-key-here"`
    - Config: Managed by home-manager
    
    ### Codex
    - Command: `codex`
    - Setup: Set API keys for your model provider
    - Config: Managed by home-manager
    
    ### AIChat (Multi-model support)
    - Command: `aichat`
    - Supports: Gemini, GPT, Claude, and more
    - Setup: Configure with `aichat --info`
    
    ## MCP Servers
    Context7 MCP server is configured for documentation lookup via Claude Code.
    
    ## API Keys
    Set the following environment variables:
    - ANTHROPIC_API_KEY for Claude
    - GEMINI_API_KEY for Gemini
    - OPENAI_API_KEY for GPT/Codex
  '';
}
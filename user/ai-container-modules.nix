# Container-compatible AI assistant configuration
# Uses the existing ai-assistants modules that are proven to work
{ config, pkgs, lib, inputs, ... }:

{
  # Allow unfree packages (claude-code is proprietary)
  nixpkgs.config.allowUnfree = true;
  
  # Import the existing AI assistant configurations
  imports = [
    ./ai-assistants/claude-code.nix
    ./ai-assistants/gemini-cli.nix
    ./ai-assistants/codex.nix
  ];
  
  # Additional packages for container environment
  home.packages = with pkgs; [
    # aichat for multi-model support
    aichat
  ];
  
  # Documentation for AI Assistants
  home.file.".config/ai/README.md".text = ''
    # AI Assistants Configuration
    
    ## Installed Tools (using proven configurations)
    
    ### Claude Code
    - Command: `claude` 
    - OAuth: `claude login` to authenticate
    - Config: Managed by home-manager
    
    ### Gemini CLI
    - Command: `gemini`
    - OAuth: Run `gemini` and select "Login with Google"
    - Config: Managed by home-manager
    
    ### Codex
    - Command: `codex`
    - OAuth: `codex auth` to authenticate
    - Config: Managed by home-manager
    
    ### AIChat (Multi-model support)
    - Command: `aichat`
    - Setup: Configure with `aichat --info`
    
    ## MCP Servers
    Claude Code has MCP servers configured:
    - Context7 for documentation lookup
    - Grep for code search
    - Puppeteer for browser automation
    
    ## Authentication
    All tools use OAuth authentication (no API keys needed):
    - Claude: `claude login`
    - Gemini: Run `gemini` and select login option
    - Codex: `codex auth`
  '';
}
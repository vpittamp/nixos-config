{ config, pkgs, lib, ... }:

{
  # Claude Code - Anthropic's Claude CLI
  programs.claude-code = {
    enable = true;  # Enable to generate proper configuration
    # Let home-manager use the default package or the one from overlay
    # package = pkgs.claude-cli;  # The overlay package is already in use
    
    settings = {
      theme = "dark";
      model = "claude-3-7-sonnet-20250219";
      includeCoAuthoredBy = true;
      # These settings come from your current .claude.json
      autoUpdates = true;
      verbose = true;
      editorMode = "vim";
      autoCompactEnabled = true;
      todoFeatureEnabled = true;
      autoConnectIde = true;
      autoInstallIdeExtension = true;
      autocheckpointingEnabled = true;
      preferredNotifChannel = "terminal_bell";
      messageIdleNotifThresholdMs = 60000;
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
    
    # Note: MCP servers configuration not directly supported in home-manager module
    # They would need to be configured through custom agents or commands
  };
}
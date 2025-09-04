# AI-assisted container configuration
{ config, pkgs, lib, ... }:

{
  # Import base container configuration
  imports = [ 
    ./container-minimal.nix
  ];
  
  # Override package profile to include development tools
  home.sessionVariables.CONTAINER_PROFILE = lib.mkForce "development";
  
  # Install AI assistant CLI tools that are available in nixpkgs
  home.packages = with pkgs; [
    # AI coding assistants
    aider-chat     # AI pair programming in terminal
    
    # Additional development tools for AI workflows
    python3
    nodejs
    yarn
    
    # Tools often used with AI assistants
    gh             # GitHub CLI for PR/issue management
    jq             # JSON processor for API responses
    httpie         # HTTP client for API testing
  ];
  
  # Shell aliases for AI tools
  programs.bash.shellAliases = lib.mkForce (
    config.programs.bash.shellAliases // {
      ai = "aider";
      # Quick API test commands
      api = "http";
      jsonpp = "jq '.'";
    }
  );
  
  # Environment variables for AI tools
  home.sessionVariables = {
    # Set default editor for AI tools
    EDITOR = "nvim";
    
    # AI tool configurations can be added here
    # OPENAI_API_KEY would be set at runtime or via secrets management
  };
}
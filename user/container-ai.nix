# AI-assisted container configuration
{ config, pkgs, lib, ... }:

{
  # Import base container configuration
  imports = [ 
    ./container-minimal.nix
  ];
  
  # Package profile is set to development (inherited from container-minimal.nix)
  
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
  
  # Additional shell aliases for AI tools
  programs.bash.shellAliases = {
    ai = "aider";
    # Quick API test commands
    api = "http";
    jsonpp = "jq '.'";
  };
  
  # Note: EDITOR is already set to nvim in container-minimal.nix
  # Additional environment variables for AI tools can be added here
  # Example: OPENAI_API_KEY would be set at runtime or via secrets management
}
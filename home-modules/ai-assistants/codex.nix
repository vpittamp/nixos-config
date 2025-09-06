{ config, pkgs, lib, pkgs-unstable ? pkgs, ... }:

{
  # Codex - Lightweight coding agent (using native home-manager module with unstable package)
  programs.codex = {
    enable = true;
    package = pkgs-unstable.codex or pkgs.codex;  # Use unstable if available, fallback to stable
    
    # Custom instructions for the agent
    custom-instructions = ''
      ## Project Context
      - You are working on a NixOS-based development environment
      - Primary projects are in /home/vpittamp/stacks (Kubernetes/CDK8s) and /etc/nixos (NixOS configuration)
      - Use Nix best practices for system configuration
      - Follow TypeScript/JavaScript conventions for CDK8s projects
      
      ## Coding Guidelines
      - Always use conventional commits (feat:, fix:, docs:, etc.)
      - Test configurations with dry-build before applying
      - Use ripgrep (rg) instead of grep when searching code
      - Prefer declarative configuration over imperative commands
      
      ## Security
      - Never commit secrets or credentials
      - Be cautious with sudo commands
      - Always validate user input
      
      ## Development Environment
      - Container-based development using NixOS
      - VS Code Server and remote development workflows
      - Git-based version control with feature branches
      - Kubernetes deployments via ArgoCD
      
      ## Code Style
      - Follow existing code patterns in each project
      - Use TypeScript for CDK8s applications
      - Maintain clean, self-documenting code
      - Add type definitions where applicable
    '';
    
    # Configuration for codex (TOML format)
    settings = {
      # Model configuration
      model = "claude-3.5-sonnet";
      model_provider = "anthropic";
      
      # Project trust settings
      projects = {
        "/home/vpittamp/mcp" = { 
          trust_level = "trusted"; 
        };
        "/home/vpittamp/.claude" = { 
          trust_level = "trusted"; 
        };
        "/home/vpittamp/backstage-cnoe" = { 
          trust_level = "trusted"; 
        };
        "/home/vpittamp/stacks" = { 
          trust_level = "trusted"; 
        };
        "/etc/nixos" = { 
          trust_level = "trusted"; 
        };
      };
      
      # Additional settings
      auto_save = true;
      theme = "dark";
      vim_mode = false;
    };
  };
}
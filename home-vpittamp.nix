{ config, pkgs, lib, inputs, ... }:

{
  # Import all modular configurations
  imports = [
    # Core configuration
    ./home-modules/colors.nix
    
    # Shell configurations
    ./home-modules/shell/bash.nix
    ./home-modules/shell/starship.nix
    
    # Terminal configurations
    ./home-modules/terminal/tmux.nix
    ./home-modules/terminal/sesh.nix
    
    # Editor configurations
    ./home-modules/editors/neovim.nix
    
    # Tool configurations
    ./home-modules/tools/git.nix
    ./home-modules/tools/ssh.nix
    ./home-modules/tools/bat.nix
    ./home-modules/tools/direnv.nix
    ./home-modules/tools/fzf.nix
    # ./home-modules/tools/k9s.nix  # Temporarily disabled for container build
    ./home-modules/tools/yazi.nix
    
  ];

  # Home Manager configuration
  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";
  home.stateVersion = "25.05";

  # Core packages - using overlay system
  # Control package selection with NIXOS_PACKAGES environment variable:
  #   - "" or unset: essential packages only (default)
  #   - "full": all packages  
  #   - "essential,kubernetes": essential + kubernetes tools
  #   - "essential,development": essential + development tools
  home.packages = let
    overlayPackages = import ./overlays/packages.nix { inherit pkgs lib; };
  in
    overlayPackages.allPackages;

  # Enable yazi (since it uses an option-based enable)
  modules.tools.yazi.enable = true;

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
  
  # Claude Code configuration
  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code;
    
    settings = {
      model = "claude-3-5-sonnet-20241022";
      theme = "dark";
      includeCoAuthoredBy = true;
    };
  };
  
  # Codex - Lightweight coding agent
  programs.codex = {
    enable = true;
    package = pkgs.codex;
    
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
    '';
    
    # Configuration for codex (TOML format)
    settings = {
      # Model configuration
      model = "claude-3.5-sonnet";
      model_provider = "anthropic";
      
      # Project trust settings
      projects = {
        "/home/vpittamp/mcp" = { trust_level = "trusted"; };
        "/home/vpittamp/.claude" = { trust_level = "trusted"; };
        "/home/vpittamp/backstage-cnoe" = { trust_level = "trusted"; };
        "/home/vpittamp/stacks" = { trust_level = "trusted"; };
        "/etc/nixos" = { trust_level = "trusted"; };
      };
      
      # Additional settings
      auto_save = true;
      theme = "dark";
      vim_mode = false;
    };
  };
  
  # Gemini CLI - Google's Gemini AI in terminal
  programs.gemini-cli = {
    enable = true;
    package = pkgs.gemini-cli;
    
    # Default model to use
    defaultModel = "gemini-2.0-pro";
    
    # Settings for gemini-cli
    settings = {
      theme = "Default";
      vimMode = false;
      preferredEditor = "nvim";
      autoAccept = false;
    };
    
    # Custom commands
    commands = {
      # Git commit helper
      "commit" = {
        description = "Generate a conventional commit message from staged changes";
        prompt = ''
          Analyze the git diff of staged changes and generate a conventional commit message.
          Use the format: <type>(<scope>): <description>
          
          Types: feat, fix, docs, style, refactor, test, chore
          
          Git diff:
          $(git diff --cached)
          
          Additional context: {{args}}
        '';
      };
      
      # NixOS helper
      "nix-help" = {
        description = "Get help with NixOS configurations and commands";
        prompt = ''
          You are a NixOS expert. Help with the following NixOS-related question or task:
          {{args}}
          
          Context:
          - System: NixOS with home-manager
          - Flake-based configuration in /etc/nixos
          - Using unstable nixpkgs channel
        '';
      };
      
      # Kubernetes/CDK8s helper
      "k8s" = {
        description = "Help with Kubernetes and CDK8s tasks";
        prompt = ''
          You are a Kubernetes and CDK8s expert. Help with the following:
          {{args}}
          
          Context:
          - Using CDK8s with TypeScript
          - ArgoCD for GitOps
          - Kind cluster for local development
          - VClusters for multi-tenancy
        '';
      };
      
      # Code review
      "review" = {
        description = "Review code changes and provide feedback";
        prompt = ''
          Review the following code changes and provide constructive feedback:
          
          Focus on:
          1. Code quality and best practices
          2. Potential bugs or issues
          3. Security concerns
          4. Performance implications
          5. Maintainability
          
          Changes to review: {{args}}
        '';
      };
      
      # Documentation generator
      "docs" = {
        description = "Generate or improve documentation";
        prompt = ''
          Generate clear, comprehensive documentation for: {{args}}
          
          Include:
          - Purpose and overview
          - Usage examples
          - Configuration options
          - Common issues and solutions
          - Best practices
          
          Use Markdown format with proper headings.
        '';
      };
    };
  };
}

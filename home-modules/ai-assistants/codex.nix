{ config, pkgs, lib, pkgs-unstable ? pkgs, ... }:

{
  # Codex - Lightweight coding agent (using native home-manager module with unstable package)
  programs.codex = {
    enable = true;
    package = pkgs-unstable.codex or pkgs.codex; # Use unstable if available, fallback to stable

    # Custom instructions for the agent
    # custom-instructions = 

    # Configuration for codex (TOML format)
    settings = {
      # Model configuration
      model = "gpt-5-codex";
      model_provider = "openai";
      model_reasoning_effort = "high"; # Use high reasoning for complex tasks

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

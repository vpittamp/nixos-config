{ config, lib, pkgs, ... }:

{
  # Sesh session manager configuration
  # Smart tmux session manager with predefined sessions and directory navigation

  # Enable sesh through home-manager
  programs.sesh = {
    enable = true;
    enableAlias = true; # Enable 's' alias for sesh
    enableTmuxIntegration = true;
    icons = true;

    # Sesh configuration settings
    settings = {
      # Sort order for session types
      sort_order = [
        "tmux" # Show existing tmux sessions first
        "config" # Then config sessions (Nix presets)
        "tmuxinator" # Then tmuxinator sessions
        "zoxide" # Finally zoxide directories
      ];

      # Default session configuration
      default_session = {
        # No automatic editor launch - land in terminal
        startup_command = "";
        # Show directory contents with eza when previewing
        preview_command = "eza --all --git --icons --color=always --group-directories-first --long {}";
        # Automatically add these windows to every session
        windows = ["git"];
      };

      # Session configurations
      # Named sessions for global apps that benefit from tmux persistence
      session = [
        {
          name = "k9s";
          path = "~";  # Global scope, no project context needed
          startup_command = "k9s";
        }
      ];

      # Window definitions for multi-window sessions
      window = [
        {
          name = "git";
          startup_command = "lazygit";
        }
        {
          name = "build";
          startup_command = "echo 'Ready to rebuild: sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl'";
        }
      ];

      # Blacklist - sessions to hide from results
      # blacklist = ["scratch" "tmp"];
    };
  };
}

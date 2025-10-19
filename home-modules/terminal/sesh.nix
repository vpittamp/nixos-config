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
      };

      # Session configurations
      # Configured sessions for i3 project workspace integration
      session = [
        # NixOS Configuration Project
        {
          name = "nixos";
          path = "/etc/nixos";
          startup_command = "git status";
          preview_command = "eza --all --git --icons --color=always --group-directories-first --long /etc/nixos";
        }

        # Stacks Project
        {
          name = "stacks";
          path = "~/stacks";
          startup_command = "git status";
          preview_command = "eza --all --git --icons --color=always --group-directories-first --long ~/stacks";
        }
      ];

      # Window definitions for multi-window sessions
      window = [
        {
          name = "git";
          startup_command = "git status && git diff";
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

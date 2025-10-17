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
      # NOTE: Activity-based sessions removed during i3wm migration
      # Users can add custom sessions below or rely on zoxide for directory navigation
      session = [
        # Additional Nix-specific sessions (not tied to activities)
        # {
        #   name = "nix-config";
        #   path = "/etc/nixos";
        #   startup_command = "";
        #   preview_command = "bat --color=always /etc/nixos/configuration.nix";
        # }
        # {
        #   name = "nix-home";
        #   path = "/etc/nixos";
        #   startup_command = "";
        #   preview_command = "bat --color=always /etc/nixos/home-vpittamp.nix";
        # }
        # {
        #   name = "nix-flake";
        #   path = "/etc/nixos";
        #   startup_command = "";
        #   preview_command = "bat --color=always /etc/nixos/flake.nix";
        # }
        # # Additional utility sessions
        # {
        #   name = "dotfiles";
        #   path = "~/.config";
        #   startup_command = "";
        #   preview_command = "eza --all --git --icons --color=always --group-directories-first {}";
        # }
        # {
        #   name = "k8s-dev";
        #   path = "~/k8s";
        #   startup_command = "";
        #   preview_command = "kubectl get pods --all-namespaces 2>/dev/null || echo 'No cluster connected'";
        # }
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

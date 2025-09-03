{ config, lib, pkgs, ... }:

{
  # Sesh session manager configuration
  # Smart tmux session manager with predefined sessions and directory navigation
  # Note: sesh enable option is provided by home-manager's sesh module
  
  # Sesh configuration file
  xdg.configFile."sesh/sesh.toml".text = ''
      # Sesh Configuration File
      # Smart tmux session manager configuration

      # Sort order for session types
      sort_order = [
          "tmux",        # Show existing tmux sessions first
          "config",      # Then config sessions (Nix presets)
          "tmuxinator",  # Then tmuxinator sessions
          "zoxide"       # Finally zoxide directories
      ]

      # Default session configuration
      [default_session]
      # No automatic editor launch - land in terminal
      startup_command = ""
      # Show directory contents with eza when previewing
      preview_command = "eza --all --git --icons --color=always --group-directories-first --long {}"

      # Nix Configuration Sessions
      [[session]]
      name = "nix-config"
      path = "/etc/nixos"
      startup_command = ""
      preview_command = "bat --color=always /etc/nixos/configuration.nix"

      [[session]]
      name = "nix-home"
      path = "/etc/nixos"
      startup_command = ""
      preview_command = "bat --color=always /etc/nixos/home-vpittamp.nix"

      [[session]]
      name = "nix-flake"
      path = "/etc/nixos"
      startup_command = ""
      preview_command = "bat --color=always /etc/nixos/flake.nix"

      # Quick edit session for all Nix configs
      [[session]]
      name = "nix-all"
      path = "/etc/nixos"
      startup_command = ""
      # preview_command = "eza --all --git --icons --color=always --group-directories-first /etc/nixos"
      # windows = [ "git", "build" ]

      # Window definitions for multi-window sessions
      [[window]]
      name = "git"
      startup_command = "git status && git diff"

      [[window]]
      name = "build"
      startup_command = "echo 'Ready to rebuild: sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl'"

      # Development Sessions
      [[session]]
      name = "workspace"
      path = "~/workspace"
      startup_command = ""
      preview_command = "eza --all --git --icons --color=always --group-directories-first {}"

      [[session]]
      name = "dotfiles"
      path = "~/.config"
      startup_command = ""
      preview_command = "eza --all --git --icons --color=always --group-directories-first {}"

      # Kubernetes/Container Sessions
      [[session]]
      name = "k8s-dev"
      path = "~/k8s"
      startup_command = ""
      preview_command = "kubectl get pods --all-namespaces 2>/dev/null || echo 'No cluster connected'"

      # Blacklist - sessions to hide from results
      # Uncomment to enable
      # blacklist = ["scratch", "tmp"]
  '';
}
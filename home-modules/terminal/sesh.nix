{ config, lib, pkgs, ... }:

{
  # Sesh session manager configuration
  # Smart tmux session manager with predefined sessions and directory navigation

  # Override sesh to latest release (nixpkgs lags behind: 2.20.0 → 2.24.1)
  programs.sesh.package = let
    version = "2.24.1";
  in pkgs.buildGoModule {
    pname = "sesh";
    inherit version;

    src = pkgs.fetchFromGitHub {
      owner = "joshmedeski";
      repo = "sesh";
      rev = "v${version}";
      hash = "sha256-VU3LAxujXOynvYpRubssi24tq5LtUU0Exz0WK6trGc8=";
    };

    vendorHash = "sha256-Jm0JNrJpnKns2pokbBwHps4Q3EYPyzAVCKbyNj6tcnA=";
    proxyVendor = true;

    nativeBuildInputs = [ pkgs.go-mockery ];

    # Upstream vendor dir is stale; delete it so go mod vendor regenerates cleanly
    prePatch = ''
      rm -rf vendor
    '';

    preBuild = ''
      mockery
    '';

    ldflags = [ "-s" "-w" "-X main.version=${version}" ];

    nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
    doInstallCheck = true;

    meta = with lib; {
      description = "Smart session manager for the terminal";
      homepage = "https://github.com/joshmedeski/sesh";
      license = licenses.mit;
      mainProgram = "sesh";
    };
  };

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

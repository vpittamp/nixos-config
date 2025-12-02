{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Nix helper tools
    nh  # Yet another nix cli helper
    nix-output-monitor  # Prettier nix build output
    nixpkgs-fmt  # Nix code formatter
    alejandra  # Alternative Nix formatter
    nix-tree  # Visualize Nix store dependencies
    nix-prefetch-git  # Prefetch git repositories
    nix-diff  # Compare Nix derivations
    nix-index  # Files database for nixpkgs
    comma  # Run programs without installing them
  ];

  # Feature 106: Configure nh (Nix Helper) environment variables with lib.mkDefault
  # NH_FLAKE is the default flake for all nh operations
  # NH_OS_FLAKE takes priority for 'nh os' commands
  # Using lib.mkDefault allows shell initialization to override with git discovery
  home.sessionVariables = {
    NH_FLAKE = lib.mkDefault "/etc/nixos";  # Feature 106: Overridable via shell init
    NH_OS_FLAKE = lib.mkDefault "/etc/nixos";  # Feature 106: Overridable via shell init
    # NH_HOME_FLAKE can be set if using a separate home-manager flake
  };

  # Configure nh (Nix Helper) aliases
  programs.bash.shellAliases = {
    # nh shortcuts - now work without specifying path thanks to NH_FLAKE
    nhs = "nh search";
    nho = "nh os switch";  # Uses NH_OS_FLAKE automatically
    nhh = "nh home switch";  # Uses NH_FLAKE by default
    nhc = "nh clean all";
    nhb = "nh os build";  # Build without switching
    nhd = "nh os dry";  # Dry build
  };

  programs.zsh.shellAliases = config.programs.bash.shellAliases;

  # Feature 106: Dynamic FLAKE_ROOT/NH_FLAKE detection in shell initialization
  # When in a git repo with flake.nix, automatically set NH_FLAKE/NH_OS_FLAKE
  # to the current repo, making `nh os switch` work from worktrees
  programs.bash.initExtra = ''
    # Feature 106: Dynamic flake root detection for nh commands
    # Only run if we're in an interactive shell and in a git repository
    _nixos_flake_detect() {
      # Skip if not in a git repo
      local git_root
      git_root=$(git rev-parse --show-toplevel 2>/dev/null) || return

      # Check if the repo contains a flake.nix (likely our NixOS config)
      if [[ -f "$git_root/flake.nix" ]]; then
        # Export for nh and other tools
        export FLAKE_ROOT="$git_root"
        export NH_FLAKE="$git_root"
        export NH_OS_FLAKE="$git_root"
      fi
    }

    # Run detection on shell startup if in a git repo
    _nixos_flake_detect
  '';

  programs.zsh.initExtra = ''
    # Feature 106: Dynamic flake root detection for nh commands
    # Only run if we're in an interactive shell and in a git repository
    _nixos_flake_detect() {
      # Skip if not in a git repo
      local git_root
      git_root=$(git rev-parse --show-toplevel 2>/dev/null) || return

      # Check if the repo contains a flake.nix (likely our NixOS config)
      if [[ -f "$git_root/flake.nix" ]]; then
        # Export for nh and other tools
        export FLAKE_ROOT="$git_root"
        export NH_FLAKE="$git_root"
        export NH_OS_FLAKE="$git_root"
      fi
    }

    # Run detection on shell startup if in a git repo
    _nixos_flake_detect
  '';
}
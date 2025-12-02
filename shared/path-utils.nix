# Path Utilities for Portable NixOS Configuration
# Feature 106: Make NixOS Config Portable
#
# This module provides shell functions for discovering the flake root directory.
# Used in scripts that need to reference other files in the repository.
#
# Usage in Nix modules:
#   let
#     pathUtils = import ../shared/path-utils.nix { inherit pkgs lib; };
#   in {
#     home.packages = [ pathUtils.flakeRootScript ];
#   }
#
# Or include the shell function directly:
#   programs.bash.initExtra = pathUtils.flakeRootShellFunction;
{ pkgs, lib }:

{
  # Shell function definition for get_flake_root
  # Detects git repository root with fallback to /etc/nixos
  # Priority: FLAKE_ROOT env var > git discovery > /etc/nixos fallback
  flakeRootShellFunction = ''
    # Feature 106: Portable flake root discovery
    get_flake_root() {
      # Priority 1: Environment variable (for CI/CD and manual override)
      if [[ -n "''${FLAKE_ROOT:-}" ]]; then
        echo "$FLAKE_ROOT"
        return 0
      fi

      # Priority 2: Git repository detection
      local git_root
      git_root=$(git rev-parse --show-toplevel 2>/dev/null)
      if [[ -n "$git_root" ]]; then
        echo "$git_root"
        return 0
      fi

      # Priority 3: Default fallback (for deployed systems without git)
      echo "/etc/nixos"
    }

    # Export for subshells
    export -f get_flake_root
  '';

  # Standalone script package for flake root detection
  flakeRootScript = pkgs.writeShellApplication {
    name = "get-flake-root";
    runtimeInputs = [ pkgs.git ];
    text = ''
      # Feature 106: Portable flake root discovery
      # Priority 1: Environment variable
      if [[ -n "''${FLAKE_ROOT:-}" ]]; then
        echo "$FLAKE_ROOT"
        exit 0
      fi

      # Priority 2: Git repository detection
      git_root=$(git rev-parse --show-toplevel 2>/dev/null) || true
      if [[ -n "$git_root" ]]; then
        echo "$git_root"
        exit 0
      fi

      # Priority 3: Default fallback
      echo "/etc/nixos"
    '';
  };
}

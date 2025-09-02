# Simplified flake helpers that work without /opt/nix-flakes
{ config, pkgs, lib, ... }:

{
  # Create helper script that uses nix shell directly
  environment.etc."profile.d/flake-helpers.sh".text = ''
    # Flake helper functions for containers
    
    # Function to use development shells with common packages
    nix-dev() {
      # Check if already in a nix shell to prevent recursion
      if [ -n "$IN_NIX_SHELL" ]; then
        echo "Already in a nix development shell"
        return 0
      fi
      
      local shell="''${1:-nodejs}"  # Default to nodejs instead of "default"
      echo "Entering development shell: $shell"
      
      # Map shell names to package sets
      case "$shell" in
        nodejs|node|js)
          local packages="nodejs_20 nodePackages.yarn nodePackages.pnpm"
          echo "Loading Node.js environment..."
          ;;
        python|py)
          local packages="python3 python3Packages.pip python3Packages.virtualenv"
          echo "Loading Python environment..."
          ;;
        go|golang)
          local packages="go gopls"
          echo "Loading Go environment..."
          ;;
        rust|rs)
          local packages="rustc cargo rustfmt rust-analyzer"
          echo "Loading Rust environment..."
          ;;
        *)
          echo "Unknown shell: $shell"
          echo "Available: nodejs, python, go, rust"
          return 1
          ;;
      esac
      
      # Build the nix shell command - simplified version
      local cmd="IN_NIX_SHELL=1 nix shell"
      for pkg in $packages; do
        cmd="$cmd nixpkgs#$pkg"
      done
      cmd="$cmd --impure --command bash --norc"
      
      # Execute the command
      eval $cmd
    }
    
    # Function to add packages temporarily
    nix-add() {
      # Check if already in a nix shell to prevent recursion
      if [ -n "$IN_NIX_SHELL" ]; then
        echo "Already in a nix shell, adding packages to current environment"
      fi
      
      if [ $# -eq 0 ]; then
        echo "Usage: nix-add <package1> [package2] ..."
        echo "Example: nix-add ripgrep fd htop"
        return 1
      fi
      
      local packages=""
      for pkg in "$@"; do
        packages="$packages nixpkgs#$pkg"
      done
      
      echo "Adding packages: $@"
      
      # Use --command with explicit bash to maintain interactive shell
      IN_NIX_SHELL=1 nix shell $packages --impure --command bash -c '
        # Source profile and bashrc for proper initialization
        [ -f /etc/profile ] && source /etc/profile
        [ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null || true
        # Keep the IN_NIX_SHELL marker
        export IN_NIX_SHELL=1
        # Start interactive bash without re-sourcing profiles
        exec bash --norc
      '
    }
    
    # Export functions for use
    export -f nix-dev 2>/dev/null || true
    export -f nix-add 2>/dev/null || true
    
    # Aliases for convenience
    alias nd='nix-dev'
    alias na='nix-add'
    alias ndn='nix-dev nodejs'
    alias ndp='nix-dev python'
    alias ndg='nix-dev go'
    alias ndr='nix-dev rust'
    
    # Info message (only show once per session)
    if [ -z "$_FLAKE_INFO_SHOWN" ]; then
      export _FLAKE_INFO_SHOWN=1
      echo ""
      echo "🚀 Nix shell helpers loaded. Quick commands:"
      echo "  nix-dev [shell]  - Enter development shell (nd)"
      echo "  nix-add pkg ...  - Add packages temporarily (na)"
      echo "  ndn/ndp/ndg/ndr  - Node/Python/Go/Rust shells"
      echo ""
    fi
  '';
}
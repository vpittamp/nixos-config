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
      
      local shell="''${1:-default}"
      echo "Entering development shell: $shell"
      
      # Map shell names to package sets
      case "$shell" in
        nodejs|node)
          local packages="nodejs_20 nodePackages.yarn nodePackages.pnpm"
          echo "Loading Node.js environment..."
          ;;
        python)
          local packages="python3 python3Packages.pip python3Packages.virtualenv"
          echo "Loading Python environment..."
          ;;
        go)
          local packages="go gopls"
          echo "Loading Go environment..."
          ;;
        rust)
          local packages="rustc cargo rustfmt rust-analyzer"
          echo "Loading Rust environment..."
          ;;
        default|*)
          local packages="git curl wget vim"
          echo "Loading default environment..."
          ;;
      esac
      
      # Build the nix shell command
      local cmd="IN_NIX_SHELL=1 nix shell"
      for pkg in $packages; do
        cmd="$cmd nixpkgs#$pkg"
      done
      cmd="$cmd --impure --command bash -c '"
      cmd="$cmd [ -f /etc/profile ] && source /etc/profile;"
      cmd="$cmd [ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null || true;"
      cmd="$cmd export IN_NIX_SHELL=1;"
      cmd="$cmd export NODE_EXTRA_CA_CERTS=\${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-bundle.crt};"
      cmd="$cmd exec bash --norc'"
      
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
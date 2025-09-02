# Proper flake support for containers
# This module provides a working flake environment in containers
# by creating a proper git repository structure

{ config, pkgs, lib, ... }:

{
  # Create a proper flake directory with git initialization
  system.activationScripts.setupContainerFlake = ''
    # Create the container flake directory
    FLAKE_DIR="/opt/nix-flakes"
    
    # Only set up if not already done
    if [ ! -d "$FLAKE_DIR/.git" ]; then
      echo "Setting up container flake environment..."
      
      # Create directory structure
      mkdir -p "$FLAKE_DIR"
      cd "$FLAKE_DIR"
      
      # Copy flake files from /nix/store
      if [ -f "${./flake.nix}" ]; then
        cp "${./flake.nix}" "$FLAKE_DIR/flake.nix"
        cp "${./flake.lock}" "$FLAKE_DIR/flake.lock"
        
        # Initialize git repository (required for flakes to work)
        ${pkgs.git}/bin/git init
        ${pkgs.git}/bin/git config user.email "container@localhost"
        ${pkgs.git}/bin/git config user.name "Container"
        ${pkgs.git}/bin/git add flake.nix flake.lock
        ${pkgs.git}/bin/git commit -m "Initial flake setup for container"
        
        # Make it readable by all users
        chmod -R 755 "$FLAKE_DIR"
        
        echo "Container flake environment ready at $FLAKE_DIR"
      fi
    fi
    
    # Create convenience symlinks for users
    ln -sfn "$FLAKE_DIR" /home/code/flakes 2>/dev/null || true
  '';
  
  # Ensure git is available
  environment.systemPackages = with pkgs; [
    git
  ];
  
  # Environment variables to help users find the flake
  environment.variables = {
    CONTAINER_FLAKE_DIR = "/opt/nix-flakes";
  };
  
  # Create a wrapper script for easier flake usage
  environment.etc."profile.d/flake-helpers.sh".text = ''
    # Flake helper functions for containers
    
    # Function to use development shells easily
    nix-dev() {
      local shell="''${1:-default}"
      echo "Entering development shell: $shell"
      nix develop "/opt/nix-flakes#$shell" --impure
    }
    
    # Function to add packages temporarily
    nix-add() {
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
      nix shell $packages --impure
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
    alias ndf='nix-dev fullstack'
    
    # Info message (only show once per session)
    if [ -z "$_FLAKE_INFO_SHOWN" ]; then
      export _FLAKE_INFO_SHOWN=1
      echo ""
      echo "🚀 Nix flake helpers loaded. Quick commands:"
      echo "  nix-dev [shell]  - Enter development shell (nd)"
      echo "  nix-add pkg ...  - Add packages temporarily (na)"
      echo "  ndn/ndp/ndg/ndr  - Node/Python/Go/Rust shells"
      echo "  Flake location: /opt/nix-flakes"
      echo ""
    fi
  '';
  
  # Update the container README
  environment.etc."nixos/README-CONTAINER.md".text = ''
    # NixOS Container - Runtime Package Management
    
    This container includes a properly configured Nix flake environment.
    
    ## Quick Start
    
    The flake is located at `/opt/nix-flakes` and is a proper git repository.
    
    ### Using Helper Commands (Recommended)
    
    ```bash
    # Enter development shells
    nix-dev           # Default shell
    nix-dev nodejs    # Node.js environment
    ndn               # Shortcut for Node.js
    ndp               # Python environment
    ndg               # Go environment
    ndr               # Rust environment
    ndf               # Full-stack environment
    
    # Add packages temporarily
    nix-add ripgrep fd    # Add multiple packages
    na htop               # Short alias
    ```
    
    ### Using Nix Commands Directly
    
    ```bash
    # From the flake directory
    cd /opt/nix-flakes
    nix develop .#nodejs --impure
    
    # Or use absolute path from anywhere
    nix develop /opt/nix-flakes#nodejs --impure
    
    # Add packages temporarily
    nix shell nixpkgs#ripgrep nixpkgs#fd
    
    # Install persistently (survives container restarts if /home is a volume)
    nix profile install nixpkgs#lazygit
    ```
    
    ## Available Development Shells
    
    - `default` - Basic development tools
    - `nodejs` - Node.js, yarn, pnpm, TypeScript
    - `python` - Python 3, pip, virtualenv, ipython
    - `go` - Go, gopls, go-tools
    - `rust` - Rust, cargo, rustfmt, rust-analyzer
    - `fullstack` - All of the above plus databases
    
    ## Troubleshooting
    
    If you encounter "path does not exist" errors:
    1. Use the helper commands (nix-dev, nix-add) which handle paths correctly
    2. Always use `/opt/nix-flakes` as the flake path
    3. The flake is a git repository - do not modify files there directly
    
    ## SSL/TLS Certificates
    
    SSL certificates are pre-configured. If you encounter certificate errors:
    - For development only: `export NODE_TLS_REJECT_UNAUTHORIZED=0`
    - Check certificate path: `echo $NODE_EXTRA_CA_CERTS`
  '';
}
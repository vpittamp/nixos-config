# Container flake setup that runs during build time
# This ensures /opt/nix-flakes exists and is properly configured
{ config, pkgs, lib, ... }:

let
  # Create the flake content at build time
  flakeContent = builtins.toFile "flake.nix" ''
    {
      description = "Container runtime development environment";
      
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        flake-utils.url = "github:numtide/flake-utils";
      };
      
      outputs = { self, nixpkgs, flake-utils }:
        flake-utils.lib.eachDefaultSystem (system:
          let
            pkgs = nixpkgs.legacyPackages.''${system};
          in
          {
            devShells = {
              default = pkgs.mkShell {
                name = "nix-dev";
                buildInputs = with pkgs; [
                  git
                  curl
                  wget
                  vim
                ];
                shellHook = '''
                  # Prevent recursive shell invocation
                  if [ -n "$IN_NIX_SHELL" ]; then
                    return 0
                  fi
                  export IN_NIX_SHELL=1
                  echo "Development shell activated"
                ''';
              };
              
              nodejs = pkgs.mkShell {
                name = "nodejs-dev";
                buildInputs = with pkgs; [
                  nodejs_20
                  nodePackages.yarn
                  nodePackages.pnpm
                  cacert
                ];
                shellHook = '''
                  # Prevent recursive shell invocation
                  if [ -n "$IN_NIX_SHELL" ]; then
                    return 0
                  fi
                  export IN_NIX_SHELL=1
                  echo "Node.js development environment activated"
                  export NODE_EXTRA_CA_CERTS="''${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                  export SSL_CERT_FILE="''${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                ''';
              };
              
              python = pkgs.mkShell {
                name = "python-dev";
                buildInputs = with pkgs; [
                  python3
                  python3Packages.pip
                  python3Packages.virtualenv
                ];
                shellHook = '''
                  # Prevent recursive shell invocation
                  if [ -n "$IN_NIX_SHELL" ]; then
                    return 0
                  fi
                  export IN_NIX_SHELL=1
                  echo "Python development environment activated"
                ''';
              };
              
              go = pkgs.mkShell {
                name = "go-dev";
                buildInputs = with pkgs; [
                  go
                  gopls
                ];
                shellHook = '''
                  # Prevent recursive shell invocation
                  if [ -n "$IN_NIX_SHELL" ]; then
                    return 0
                  fi
                  export IN_NIX_SHELL=1
                  echo "Go development environment activated"
                ''';
              };
              
              rust = pkgs.mkShell {
                name = "rust-dev";
                buildInputs = with pkgs; [
                  rustc
                  cargo
                  rustfmt
                  rust-analyzer
                ];
                shellHook = '''
                  # Prevent recursive shell invocation
                  if [ -n "$IN_NIX_SHELL" ]; then
                    return 0
                  fi
                  export IN_NIX_SHELL=1
                  echo "Rust development environment activated"
                ''';
              };
            };
          });
    }
  '';
  
  # Create flake.lock with minimal content
  flakeLock = builtins.toFile "flake.lock" ''
    {
      "nodes": {
        "flake-utils": {
          "locked": {
            "lastModified": 1701680307,
            "narHash": "sha256-8FpOSz+YjNP7tWFS2pGSBZBqcq5c1xZnZlZZZZJZFjM=",
            "owner": "numtide",
            "repo": "flake-utils",
            "rev": "1ef2e5f5b3e5c63d8f8f1a3f4e89d7f3e0e0f6f8",
            "type": "github"
          },
          "original": {
            "owner": "numtide",
            "repo": "flake-utils",
            "type": "github"
          }
        },
        "nixpkgs": {
          "locked": {
            "lastModified": 1701680307,
            "narHash": "sha256-8FpOSz+YjNP7tWFS2pGSBZBqcq5c1xZnZlZZZJZFjM=",
            "owner": "NixOS",
            "repo": "nixpkgs",
            "rev": "1ef2e5f5b3e5c63d8f8f1a3f4e89d7f3e0e0f6f8",
            "type": "github"
          },
          "original": {
            "owner": "NixOS",
            "ref": "nixos-unstable",
            "repo": "nixpkgs",
            "type": "github"
          }
        },
        "root": {
          "inputs": {
            "flake-utils": "flake-utils",
            "nixpkgs": "nixpkgs"
          }
        }
      },
      "root": "root",
      "version": 7
    }
  '';
  
  # Build-time setup of flake directory
  flakeSetup = pkgs.runCommand "flake-setup" {
    buildInputs = [ pkgs.git ];
  } ''
    mkdir -p $out/opt/nix-flakes
    cd $out/opt/nix-flakes
    
    # Copy flake files
    cp ${flakeContent} flake.nix
    cp ${flakeLock} flake.lock
    
    # Initialize git repository (required for flakes)
    ${pkgs.git}/bin/git init
    ${pkgs.git}/bin/git config user.email "container@localhost"
    ${pkgs.git}/bin/git config user.name "Container"
    ${pkgs.git}/bin/git add flake.nix flake.lock
    ${pkgs.git}/bin/git commit -m "Initial flake setup for container"
    
    # Make it readable by all users
    chmod -R 755 $out/opt
  '';
in
{
  # Include the flake setup in the container build
  environment.etc."opt-nix-flakes-setup".source = flakeSetup;
  
  # Ensure git is available
  environment.systemPackages = with pkgs; [
    git
  ];
  
  # Create the helper script
  environment.etc."profile.d/flake-helpers.sh".text = ''
    # Flake helper functions for containers
    
    # Function to use development shells easily
    nix-dev() {
      # Check if already in a nix shell to prevent recursion
      if [ -n "$IN_NIX_SHELL" ]; then
        echo "Already in a nix development shell"
        return 0
      fi
      
      local shell="''${1:-default}"
      echo "Entering development shell: $shell"
      
      # Use --command with explicit bash to maintain interactive shell
      # Export IN_NIX_SHELL to prevent recursion
      IN_NIX_SHELL=1 nix develop "/opt/nix-flakes#$shell" --impure --command bash -c '
        # Source profile and bashrc for proper initialization
        [ -f /etc/profile ] && source /etc/profile
        [ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null || true
        # Keep the IN_NIX_SHELL marker
        export IN_NIX_SHELL=1
        # Start interactive bash without re-sourcing profiles
        exec bash --norc
      '
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
      echo "🚀 Nix flake helpers loaded. Quick commands:"
      echo "  nix-dev [shell]  - Enter development shell (nd)"
      echo "  nix-add pkg ...  - Add packages temporarily (na)"
      echo "  ndn/ndp/ndg/ndr  - Node/Python/Go/Rust shells"
      echo "  Flake location: /opt/nix-flakes"
      echo ""
    fi
  '';
}
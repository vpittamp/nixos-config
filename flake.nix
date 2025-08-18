{
  description = "NixOS WSL2 configuration with Home Manager and Container Support";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # NixOS-WSL
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Flake utilities for better system/package definitions
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixos-wsl, home-manager, flake-utils, ... }@inputs: 
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # NixOS configuration for WSL
      nixosConfigurations = {
        nixos-wsl = nixpkgs.lib.nixosSystem {
          inherit system;
          
          modules = [
            # Include the WSL module
            nixos-wsl.nixosModules.wsl
            
            # Main system configuration
            ./configuration.nix
            
            # Home Manager module
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.vpittamp = {
                  imports = [ ./home-vpittamp.nix ];
                  # Fix for version mismatch warning
                  home.enableNixpkgsReleaseCheck = false;
                };
              };
            }
          ];
        };
      };
      
      # Container packages
      packages.${system} = {
        # Example: Basic container with shell utilities
        basic-container = pkgs.dockerTools.buildLayeredImage {
          name = "nixos-basic";
          tag = "latest";
          
          contents = with pkgs; [
            bashInteractive
            coreutils
            curl
            jq
            git
          ];
          
          config = {
            Env = [ "PATH=/bin:/usr/bin" ];
            Cmd = [ "/bin/bash" ];
            WorkingDir = "/";
          };
        };
        
        # Example: Node.js application container
        node-app-container = pkgs.dockerTools.buildLayeredImage {
          name = "node-app";
          tag = "latest";
          
          contents = with pkgs; [
            nodejs_20
            bashInteractive
            coreutils
          ];
          
          config = {
            Env = [ 
              "PATH=/bin:/usr/bin"
              "NODE_ENV=production"
            ];
            Cmd = [ "/bin/node" ];
            WorkingDir = "/app";
            ExposedPorts = {
              "3000/tcp" = {};
            };
          };
        };
        
        # Example: Python application container
        python-app-container = pkgs.dockerTools.buildLayeredImage {
          name = "python-app";
          tag = "latest";
          
          contents = with pkgs; [
            python3
            python3Packages.pip
            python3Packages.requests
            bashInteractive
            coreutils
          ];
          
          config = {
            Env = [ 
              "PATH=/bin:/usr/bin"
              "PYTHONUNBUFFERED=1"
            ];
            Cmd = [ "/bin/python3" ];
            WorkingDir = "/app";
          };
        };
      };
      
      # Development shells
      devShells.${system} = {
        # Default development shell with container tools
        default = pkgs.mkShell {
          name = "container-dev";
          
          buildInputs = with pkgs; [
            # Container tools
            docker-compose
            dive              # Inspect container layers
            
            # Kubernetes tools
            kubectl
            kubernetes-helm
            k9s               # Terminal UI for Kubernetes
            kind              # Kubernetes in Docker
            
            # Development tools
            git
            jq
            yq
            curl
            
            # Nix tools
            nix-prefetch-docker
            nixpkgs-fmt
          ];
          
          shellHook = ''
            echo "🐳 Container Development Environment"
            echo ""
            echo "Available commands:"
            echo "  docker    - Docker CLI (via Docker Desktop)"
            echo "  docker-compose - Multi-container orchestration"
            echo "  kubectl   - Kubernetes CLI"
            echo "  helm      - Kubernetes package manager"
            echo "  k9s       - Kubernetes TUI"
            echo "  kind      - Kubernetes in Docker"
            echo ""
            echo "Build containers with:"
            echo "  nix build .#basic-container"
            echo "  nix build .#node-app-container"
            echo "  nix build .#python-app-container"
            echo ""
            echo "Load into Docker with:"
            echo "  docker load < result"
            echo ""
            echo "Docker alias configured: /run/current-system/sw/bin/docker"
          '';
        };
        
        # Kubernetes-focused shell
        k8s = pkgs.mkShell {
          name = "k8s-dev";
          
          buildInputs = with pkgs; [
            kubectl
            kubernetes-helm
            k9s
            kustomize
            kubectx
            stern             # Multi-pod log tailing
            kubeseal          # Sealed secrets
          ];
          
          shellHook = ''
            echo "☸️  Kubernetes Development Environment"
            echo ""
            echo "Kubernetes tools loaded!"
          '';
        };
      };
      
      # Formatter for 'nix fmt'
      formatter.${system} = pkgs.nixpkgs-fmt;
      
      # Apps for easy container building
      apps.${system} = {
        build-all-containers = {
          type = "app";
          program = "${pkgs.writeShellScript "build-all-containers" ''
            echo "Building all containers..."
            nix build .#basic-container
            echo "✅ basic-container built"
            nix build .#node-app-container
            echo "✅ node-app-container built"
            nix build .#python-app-container
            echo "✅ python-app-container built"
            echo ""
            echo "Load into Docker with: docker load < result"
          ''}";
        };
      };
    };
}

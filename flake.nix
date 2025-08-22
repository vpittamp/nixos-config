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
    
    # 1Password Shell Plugins
    onepassword-shell-plugins = {
      url = "github:1Password/shell-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Flake utilities for better system/package definitions
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixos-wsl, home-manager, onepassword-shell-plugins, flake-utils, ... }@inputs: 
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # NixOS configuration for WSL
      nixosConfigurations = {
        nixos-wsl = nixpkgs.lib.nixosSystem {
          inherit system;
          
          # Pass inputs to configuration modules
          specialArgs = { inherit inputs; };
          
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
                extraSpecialArgs = { inherit inputs; };
                users.vpittamp = {
                  imports = [ 
                    ./home-vpittamp.nix
                    onepassword-shell-plugins.hmModules.default
                  ];
                  # Fix for version mismatch warning
                  home.enableNixpkgsReleaseCheck = false;
                };
              };
            }
          ];
        };
      };
      
      # Container packages - unified with main configuration
      packages.${system} = {
        # Build container from main configuration
        # Usage: NIXOS_CONTAINER=1 NIXOS_PACKAGES="essential" nix build .#container
        container = let
          # Build the NixOS configuration with container mode enabled
          containerConfig = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs; };
            modules = [
              # Use base configuration instead of full WSL config
              ./configuration-base.nix
              # Add home-manager
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users.vpittamp = import ./home-vpittamp.nix;
                home-manager.extraSpecialArgs = { inherit inputs; };
              }
              # Apply container-specific overrides
              ./container-profile.nix
            ];
          };
        in
        pkgs.dockerTools.buildLayeredImage {
          name = "nixos-system";
          tag = let
            profile = builtins.getEnv "NIXOS_PACKAGES";
          in if profile == "" then "latest" else profile;
          
          contents = pkgs.buildEnv {
            name = "container-root";
            paths = [
              containerConfig.config.system.path
              pkgs.bashInteractive
              pkgs.coreutils
            ];
            pathsToLink = [ "/bin" "/lib" "/share" "/etc" ];
          };
          
          config = {
            Env = [
              "PATH=/bin:/usr/bin:/usr/local/bin"
              "HOME=/root"
              "USER=root"
              "TERM=xterm-256color"
            ];
            Cmd = [ "/bin/bash" ];
            WorkingDir = "/";
          };
        };
      };
      
      # Home Manager configurations for standalone use (e.g., in containers)
      homeConfigurations = {
        # Configuration for containers or non-NixOS systems
        vpittamp = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home-vpittamp.nix
            onepassword-shell-plugins.hmModules.default
            {
              # Container/standalone specific settings
              home = {
                username = "root";  # Containers typically run as root
                homeDirectory = "/root";
                stateVersion = "24.05";
                enableNixpkgsReleaseCheck = false;
              };
              
              # Override package selection via environment variable
              nixpkgs.config.allowUnfree = true;
            }
          ];
          extraSpecialArgs = { inherit inputs; };
        };
        
        # Alternative configuration for non-root containers
        vpittamp-user = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home-vpittamp.nix
            onepassword-shell-plugins.hmModules.default
            {
              home = {
                username = "vpittamp";
                homeDirectory = "/home/vpittamp";
                stateVersion = "24.05";
                enableNixpkgsReleaseCheck = false;
              };
              nixpkgs.config.allowUnfree = true;
            }
          ];
          extraSpecialArgs = { inherit inputs; };
        };
      };
      
      # Development shells
      devShells.${system} = import ./shells { inherit pkgs; };
      
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
            nix build .#nixos-full-system
            echo "✅ nixos-full-system built"
            echo ""
            echo "Load into Docker with: docker load < result"
          ''}";
        };
      };
    };
}
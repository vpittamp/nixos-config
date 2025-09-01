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
    
    # Home Manager - using master branch for latest features including claude-code
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # 1Password Shell Plugins
    onepassword-shell-plugins = {
      url = "github:1Password/shell-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # VS Code Server support for NixOS
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Flake utilities for better system/package definitions
    flake-utils.url = "github:numtide/flake-utils";

    # NPM Package utility - for installing npm packages as Nix derivations
    npm-package.url = "github:netbrain/npm-package";
  };

  outputs = { self, nixpkgs, nixos-wsl, home-manager, onepassword-shell-plugins, vscode-server, flake-utils, npm-package, ... }@inputs: 
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
            
            # NPM packages are now defined in overlays/packages.nix
            # to avoid duplication and ensure they're available in containers
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
        # Base container with minimal NixOS and runtime setup capability
        # Usage: nix build .#container-base
        container-base = let
          baseConfig = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs; };
            modules = [
              # Include WSL module (will be disabled by container-profile)
              nixos-wsl.nixosModules.wsl
              ./container-base.nix
              vscode-server.nixosModules.default
            ];
          };
        in with pkgs;
        dockerTools.buildImage {
          name = "nixos-base";
          tag = "latest";
          
          contents = buildEnv {
            name = "container-base-root";
            paths = [
              baseConfig.config.system.path
              bashInteractive
              coreutils
              nix
              
              # Add runtime setup script
              (runCommand "runtime-setup" {} ''
                mkdir -p $out/usr/local/bin
                cp ${./container-runtime-setup.sh} $out/usr/local/bin/nixos-setup
                chmod 755 $out/usr/local/bin/nixos-setup
              '')
            ];
            pathsToLink = [ "/bin" "/lib" "/share" "/etc" "/usr" ];
          };
          
          config = {
            Env = [
              "PATH=/usr/local/bin:/bin:/usr/bin"
              "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
            ];
            Cmd = [ "/usr/local/bin/nixos-setup" ];
            WorkingDir = "/";
          };
        };
        
        # Build container from main configuration (existing approach)
        # Usage: NIXOS_CONTAINER=1 NIXOS_PACKAGES="essential" nix build .#container
        container = let
          # Build the NixOS configuration with container mode enabled
          containerConfig = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs; };
            modules = [
              # Include WSL module (will be disabled by container-profile)
              nixos-wsl.nixosModules.wsl
              # Start with main configuration
              ./configuration.nix
              # Add home-manager
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users = {
                  # Apply home-manager to root user in container
                  root = { config, pkgs, lib, ... }: {
                    imports = [ ./home-vpittamp.nix ];
                    home = {
                      username = lib.mkForce "root";
                      homeDirectory = lib.mkForce "/root";
                    };
                  };
                  # Apply home-manager to both users in container
                  vpittamp = import ./home-vpittamp.nix;
                  # Code user gets the same configuration but with overrides
                  code = { config, pkgs, lib, ... }: {
                    imports = [ ./home-vpittamp.nix ];
                    home = {
                      username = lib.mkForce "code";
                      homeDirectory = lib.mkForce "/home/code";
                    };
                  };
                };
                home-manager.extraSpecialArgs = { inherit inputs; };
              }
              # Add VS Code server support
              vscode-server.nixosModules.default
              # Apply container-specific overrides last
              ./container-profile.nix
            ];
          };
        in with pkgs;
        # Use buildLayeredImage for better caching and faster builds
        dockerTools.buildLayeredImage {
          name = "nixos-dev";
          tag = let
            profile = builtins.getEnv "NIXOS_PACKAGES";
          in if profile == "" then "latest" else profile;
          
          
          contents = let
            # Build home-manager generations for each user to get their config files
            homeManagerPackages = runCommand "home-manager-packages" {} ''
              mkdir -p $out
              
              # Create a marker file to indicate home-manager files should be activated
              touch $out/.hm-activate-required
              
              # Store paths to home-manager generations
              echo "${containerConfig.config.system.path}" > $out/.system-path
            '';
          in buildEnv {
            name = "container-root";
            paths = [
              # Use system.path which contains all packages including home-manager
              containerConfig.config.system.path
              pkgs.bashInteractive
              pkgs.coreutils
              
              # Add /etc files from the system build
              containerConfig.config.system.build.etc
              
              # Include the entire system toplevel for activation scripts
              containerConfig.config.system.build.toplevel
              
              # Include home-manager marker
              homeManagerPackages
              
              # Add entrypoint script with timestamp to force rebuilds
              (runCommand "entrypoint-script-${builtins.substring 0 8 (builtins.hashFile "sha256" ./container-entrypoint.sh)}" {
                entrypoint = ./container-entrypoint.sh;
              } ''
                mkdir -p $out/etc
                cp $entrypoint $out/etc/container-entrypoint.sh
                chmod 755 $out/etc/container-entrypoint.sh
              '')
              
            ];
            pathsToLink = [ 
              "/bin" 
              "/lib" 
              "/share" 
              "/etc"
              "/sw"        # Include sw directory
            ];
            extraOutputsToInstall = [ "out" ];
          };
          
          config = {
            Env = [
              "PATH=/bin:/sbin:/usr/bin:/usr/local/bin"
              "HOME=/root"
              "USER=root"
              "TERM=xterm-256color"
              "CONTAINER_SSH_ENABLED=true"
              "CONTAINER_SSH_PORT=2222"
              # Critical for VS Code server to find libraries
              "LD_LIBRARY_PATH=/lib:/usr/lib:/lib64"
              "NIX_LD_LIBRARY_PATH=/lib:/usr/lib:/lib64"
              # Critical for Nix single-user mode in containers
              "NIX_REMOTE="
              "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
            ];
            Entrypoint = [ "/etc/container-entrypoint.sh" ];
            Cmd = [ "sleep" "infinity" ];
            WorkingDir = "/";
            ExposedPorts = {
              "2222/tcp" = {};
            };
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
            ({ lib, ... }: {
              # Container/standalone specific settings - override with force
              home = {
                username = lib.mkForce "root";  # Containers typically run as root
                homeDirectory = lib.mkForce "/root";
                stateVersion = lib.mkForce "25.05";  # Match home-vpittamp.nix
                enableNixpkgsReleaseCheck = false;
              };
              
              # Override package selection via environment variable
              nixpkgs.config.allowUnfree = true;
            })
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
                stateVersion = "25.05";  # Match home-vpittamp.nix
                enableNixpkgsReleaseCheck = false;
              };
              nixpkgs.config.allowUnfree = true;
            }
          ];
          extraSpecialArgs = { inherit inputs; };
        };
        
        # Devcontainer user "code" - extends vpittamp-user with overrides
        code = self.homeConfigurations.vpittamp-user.extendModules {
          modules = [{
            home = {
              username = nixpkgs.lib.mkForce "code";
              homeDirectory = nixpkgs.lib.mkForce "/home/code";
            };
          }];
        };
      };
      
      # Formatter for 'nix fmt'
      formatter.${system} = pkgs.nixpkgs-fmt;
      
      # Apps for container building
      apps.${system} = {
        build-container = {
          type = "app";
          program = "${pkgs.writeShellScript "build-container" ''
            echo "Building NixOS container..."
            echo "Package selection: ''${NIXOS_PACKAGES:-essential}"
            nix build .#container
            echo "✅ Container built"
            echo ""
            echo "Load into Docker with: docker load < result"
            echo ""
            echo "To build with all packages: NIXOS_PACKAGES=full nix run .#build-container"
          ''}";
        };
      };
    };
}
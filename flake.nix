{
  description = "Unified NixOS Configuration - Hetzner, M1, WSL, and Containers";

  inputs = {
    # Core
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-bleeding.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    
    # Platform support
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    nixos-apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Additional tools
    onepassword-shell-plugins = {
      url = "github:1Password/shell-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    flake-utils.url = "github:numtide/flake-utils";

    # Plasma (KDE) user configuration via Home Manager
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-bleeding, nixos-wsl, nixos-apple-silicon, home-manager, onepassword-shell-plugins, vscode-server, claude-code-nix, disko, flake-utils, ... }@inputs:
    let
      # Helper function to create a system configuration
      mkSystem = { hostname, system, modules }: 
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = modules ++ [
            # Home Manager integration
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                # Disable backups - we have version control
                backupFileExtension = null;
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { 
                  inherit inputs;
                  pkgs-unstable = import nixpkgs-bleeding {
                    inherit system;
                    config.allowUnfree = true;
                  };
                };
                users.vpittamp = {
                  imports = [ 
                    ./home-vpittamp.nix
                    inputs.plasma-manager.homeModules.plasma-manager
                  ];
                  home.enableNixpkgsReleaseCheck = false;
                };
              };
            }
          ];
        };
    in
    {
      # NixOS Configurations
      nixosConfigurations = {
        # Primary: Hetzner Cloud Server (x86_64)
        hetzner = mkSystem {
          hostname = "nixos-hetzner";
          system = "x86_64-linux";
          modules = [ 
            disko.nixosModules.disko
            ./configurations/hetzner.nix 
          ];
        };
        
        # Minimal Hetzner for nixos-anywhere deployment
        hetzner-minimal = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            ./configurations/hetzner-minimal.nix
          ];
        };
        
        # Hetzner example with our SSH key
        hetzner-example = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            ./configurations/hetzner-example.nix
          ];
        };
        
        # Secondary: M1 MacBook Pro (aarch64)
        m1 = mkSystem {
          hostname = "nixos-m1";
          system = "aarch64-linux";
          modules = [ ./configurations/m1.nix ];
        };
        
        # Legacy: WSL2 (x86_64)
        wsl = mkSystem {
          hostname = "nixos-wsl";
          system = "x86_64-linux";
          modules = [ ./configurations/wsl.nix ];
        };
      };
      
      homeConfigurations = let
        currentSystem = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";
        pkgsFor = system: import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        unstableFor = system: import nixpkgs-bleeding {
          inherit system;
          config.allowUnfree = true;
        };
        osConfigFor = system:
          if system == "aarch64-linux" then self.nixosConfigurations.m1.config
          else self.nixosConfigurations.hetzner.config;
        mkHome = modulePath: home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor currentSystem;
          extraSpecialArgs = {
            inherit inputs;
            osConfig = osConfigFor currentSystem;
            pkgs-unstable = unstableFor currentSystem;
          };
          modules = [ modulePath ];
        };
      in {
        vpittamp = mkHome ./home-vpittamp.nix;
        code = mkHome ./home-code.nix;
      };
      
      # Container configurations
      packages = flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          pkgsUnstable = import nixpkgs-bleeding {
            inherit system;
            config.allowUnfree = true;
          };
          mkContainerSystem = profile:
            (nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = {
                inherit inputs pkgsUnstable;
                containerProfile = profile;
              };
              modules = [
                ./configurations/container.nix
                home-manager.nixosModules.home-manager
                ({ config, pkgsUnstable, ... }:
                  {
                    home-manager = {
                      # Disable backups - we have version control
                      backupFileExtension = null;
                      useGlobalPkgs = true;
                      useUserPackages = true;
                      extraSpecialArgs = {
                        inherit inputs;
                        osConfig = config;
                        pkgs-unstable = pkgsUnstable;
                      };
                      users.code = {
                        imports = [ ./home-code.nix ];
                      };
                    };
                  })
              ];
            }).config.system.build.toplevel;
        in
        rec {
          # Minimal container
          container-minimal = pkgs.dockerTools.buildLayeredImage {
            name = "nixos-container";
            tag = "minimal";
            contents = [ (mkContainerSystem "minimal") ];
            config = {
              Cmd = [ "/bin/bash" ];
              Env = [ "NIXOS_CONTAINER=1" "NIXOS_PACKAGES=minimal" ];
            };
          };
          
          # Development container
          container-dev = pkgs.dockerTools.buildLayeredImage {
            name = "nixos-container";
            tag = "development";
            contents = [ (mkContainerSystem "development") ];
            config = {
              Cmd = [ "/bin/bash" ];
              Env = [ "NIXOS_CONTAINER=1" "NIXOS_PACKAGES=development" ];
            };
          };
          
          # Default container output
          default = container-minimal;
        });
      
      # Development shells
      devShells = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          default = pkgs.mkShell {
            name = "nixos-dev";
            buildInputs = with pkgs; [
              # Nix tools
              nixpkgs-fmt
              nixfmt
              statix
              deadnix
              
              # Development tools
              git
              vim
              tmux
              
              # Container tools
              docker
              docker-compose
              kubectl
            ];
            
            shellHook = ''
              echo "NixOS Development Shell"
              echo "Available configurations:"
              echo "  - hetzner: Primary workstation (x86_64)"
              echo "  - m1: Apple Silicon (aarch64)"
              echo "  - wsl: Windows Subsystem for Linux"
              echo "  - container: Docker/K8s containers"
              echo ""
              echo "Build with: nixos-rebuild switch --flake .#<config>"
              echo "Export current Plasma settings: ./scripts/plasma-rc2nix.sh > plasma-latest.nix"
              echo "Apply Home Manager profile: nix run home-manager/master -- switch --flake .#vpittamp"
            '';
          };
        });
    };
}

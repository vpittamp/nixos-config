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
                backupFileExtension = "backup";
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
                    onepassword-shell-plugins.hmModules.default
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
          modules = [ ./configurations/hetzner.nix ];
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
      
      # Container configurations
      packages = flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          # Minimal container
          container-minimal = pkgs.dockerTools.buildLayeredImage {
            name = "nixos-container";
            tag = "minimal";
            contents = [
              (pkgs.nixos {
                imports = [ ./configurations/container.nix ];
                environment.variables.NIXOS_PACKAGES = "minimal";
              }).config.system.build.toplevel
            ];
            config = {
              Cmd = [ "/bin/bash" ];
              Env = [ "NIXOS_CONTAINER=1" "NIXOS_PACKAGES=minimal" ];
            };
          };
          
          # Development container
          container-dev = pkgs.dockerTools.buildLayeredImage {
            name = "nixos-container";
            tag = "development";
            contents = [
              (pkgs.nixos {
                imports = [ ./configurations/container.nix ];
                environment.variables.NIXOS_PACKAGES = "development";
              }).config.system.build.toplevel
            ];
            config = {
              Cmd = [ "/bin/bash" ];
              Env = [ "NIXOS_CONTAINER=1" "NIXOS_PACKAGES=development" ];
            };
          };
          
          # Default container output
          default = self.packages.${system}.container-minimal;
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
            '';
          };
        });
    };
}
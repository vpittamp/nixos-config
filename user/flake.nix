{
  description = "Home Manager configuration for containers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    npm-package = {
      url = "github:serokell/npm-package.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, npm-package, ... } @ inputs: 
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;
      
      # Common module for all configurations
      commonModules = [
        ./container-minimal.nix
      ];
    in {
      homeConfigurations = {
        # Default container configuration
        container = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = commonModules ++ [
            {
              # Set defaults that match common container environments
              home.username = lib.mkDefault "code";
              home.homeDirectory = lib.mkDefault "/home/code";
            }
          ];
        };

        # Minimal profile
        "container-minimal" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = commonModules ++ [
            {
              home.username = lib.mkDefault "code";
              home.homeDirectory = lib.mkDefault "/home/code";
              # Force minimal profile
              home.sessionVariables.CONTAINER_PROFILE = "minimal";
            }
          ];
        };

        # Essential profile (default) - includes AI tools
        "container-essential" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = commonModules ++ [
            ./ai-container-modules.nix
            {
              home.username = lib.mkDefault "code";
              home.homeDirectory = lib.mkDefault "/home/code";
              home.sessionVariables.CONTAINER_PROFILE = "essential";
              # Pass inputs to modules for npm-package
              _module.args = { inherit inputs; };
            }
          ];
        };

        # Development profile - includes AI tools
        "container-development" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = commonModules ++ [
            ./ai-container-modules.nix
            {
              home.username = lib.mkDefault "code";
              home.homeDirectory = lib.mkDefault "/home/code";
              home.sessionVariables.CONTAINER_PROFILE = "development";
              # Pass inputs to modules for npm-package
              _module.args = { inherit inputs; };
            }
          ];
        };
        
        # AI-assisted profile with AI development tools
        "container-ai" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./container-minimal.nix
            ./ai-container-modules.nix
            {
              home.username = lib.mkDefault "code";
              home.homeDirectory = lib.mkDefault "/home/code";
              home.sessionVariables.CONTAINER_PROFILE = "development";
              # Pass inputs to modules for npm-package
              _module.args = { inherit inputs; };
            }
          ];
        };
      };

      # Provide a default package for easy installation
      packages.${system} = {
        default = self.homeConfigurations.container.activationPackage;
        minimal = self.homeConfigurations."container-minimal".activationPackage;
        essential = self.homeConfigurations."container-essential".activationPackage;
        development = self.homeConfigurations."container-development".activationPackage;
        ai = self.homeConfigurations."container-ai".activationPackage;
      };

      # Apps for direct activation
      apps.${system} = {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/activate";
        };
        minimal = {
          type = "app";
          program = "${self.packages.${system}.minimal}/activate";
        };
        essential = {
          type = "app";
          program = "${self.packages.${system}.essential}/activate";
        };
        development = {
          type = "app";
          program = "${self.packages.${system}.development}/activate";
        };
        ai = {
          type = "app";
          program = "${self.packages.${system}.ai}/activate";
        };
      };
    };
}
{
  description = "NixOS WSL2 configuration with Home Manager";

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
  };

  outputs = { self, nixpkgs, nixos-wsl, home-manager, ... }@inputs: {
    # NixOS configuration for WSL
    nixosConfigurations = {
      nixos-wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        
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
    
    # Formatter for 'nix fmt'
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
  };
}

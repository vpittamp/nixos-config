{
  description = "Unified NixOS Configuration - Hetzner, M1, and Containers";

  inputs = {
    # Core
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-bleeding.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Flake organization
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

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
    # ARCHIVED: KDE Plasma removed in Feature 009 (i3wm migration)
    # M1 configuration still uses this temporarily
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # VM image generation
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Walker application launcher
    elephant = {
      url = "github:abenz1267/elephant";
    };

    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };
  };

  outputs = inputs @ { self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Define supported systems
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Import flake modules
      imports = [
        ./packages
        ./checks
        ./devshells
      ];

      # Define flake-level outputs (not per-system)
      flake = {
        # NixOS system configurations
        nixosConfigurations = import ./nixos {
          inherit inputs self;
          lib = inputs.nixpkgs.lib;
        };

        # Standalone Home Manager configurations (for non-NixOS systems)
        homeConfigurations = import ./home {
          inherit inputs self;
        };
      };
    };
}

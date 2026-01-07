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

    # Claude Desktop for Linux (unofficial community package)
    # Provides native desktop app with git worktree support for parallel sessions
    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
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

    # Hardware-specific NixOS modules
    # Provides optimized configurations for various hardware platforms
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # AI-powered NixOS assistant CLI
    nix-ai-help = {
      url = "github:olafkfreund/nix-ai-help";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Cachix Deploy for automated deployments
    cachix-deploy-flake = {
      url = "github:cachix/cachix-deploy-flake";
      inputs.nixpkgs.follows = "nixpkgs";
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

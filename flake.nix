{
  description = "Unified NixOS Configuration - Hetzner, M1, and Containers";

  inputs = {
    # Core
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-bleeding.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Pinned nixpkgs for sunshine — v2025.924.154138 crashes as user service
    # https://github.com/NixOS/nixpkgs/issues/475181
    nixpkgs-sunshine.url = "github:NixOS/nixpkgs/b5ad8986fecea232ef2e1ee9eecce5b972dc4114";

    # Fresh nixpkgs purely to pin the jesseduffield "lazy" TUI family
    # (lazygit, lazydocker) at latest without bumping the main channel.
    # Our main nixpkgs lock (26.05-era) ships lazygit 0.58.1 / lazydocker 0.24.4;
    # nixos-unstable now has lazygit 0.62.1 / lazydocker 0.25.2. Consumed by the
    # per-host nixpkgs.overlays in configurations/{thinkpad,ryzen}.nix.
    # TODO(lazygit-pin): drop this input + overlay once the main nixpkgs bump
    # catches these versions up.
    nixpkgs-lazygit.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Antigravity CLI — Google's Gemini-CLI successor (announced 2026-05-19, I/O 2026).
    # Gemini CLI sunsets requests for Google AI Pro/Ultra/Free on 2026-06-18.
    #
    # Status as of 2026-05-27: antigravity-cli 1.0.3 landed on nixpkgs master
    # via PR #524900 (merged 2026-05-27), but nixos-unstable is still ~2240
    # commits behind that merge commit, so `pkgs.antigravity-cli` isn't yet
    # available via our main `nixpkgs` input. Pin to the master merge commit
    # directly until the channel catches up.
    #
    # TODO(antigravity-cli): once nixos-unstable advances past 3a1ee2b4a (the
    # 1.0.3 merge), delete this input and switch consumers to
    # `pkgs.antigravity-cli` (or `pkgs-unstable.antigravity-cli`).
    nixpkgs-antigravity-cli.url = "github:NixOS/nixpkgs/3a1ee2b4a58de0939ce747fc004461fc44e2c26e";

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

    codex-cli-nix = {
      url = "github:sadjow/codex-cli-nix";
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

    # Herdr terminal multiplexer for AI coding agents
    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Cachix Deploy for automated deployments
    cachix-deploy-flake = {
      url = "github:cachix/cachix-deploy-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Source for the Pittampalli idpbuilder fork.
    # For local idpbuilder iteration, override this explicitly:
    #   --override-input idpbuilder-src path:/home/vpittamp/repos/vpittamp/idpbuilder/main
    idpbuilder-src = {
      url = "github:vpittamp/idpbuilder/main";
      flake = false;
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

# Common helper functions for flake outputs
# These functions reduce duplication across NixOS and Home Manager configurations
{ inputs, self, ... }:

let
  inherit (inputs) nixpkgs nixpkgs-bleeding home-manager;

  # Feature 106: Assets package factory for portable builds
  # Creates a package that copies assets to the Nix store
  mkAssetsPackage = pkgs: import ./assets.nix { inherit pkgs; };

  # Internal helper: Create build metadata configuration
  # Provides git commit info and build details in /etc/nixos-metadata
  mkBuildMetadata = { hostname, system }:
    {
      system.configurationRevision = self.rev or self.dirtyRev or "unknown";

      environment.etc."nixos-metadata".text = ''
        # NixOS Build Metadata
        # Generated at build time - DO NOT EDIT

        # Git Information
        GIT_COMMIT=${self.rev or self.dirtyRev or "unknown"}
        GIT_SHORT_COMMIT=${nixpkgs.lib.substring 0 7 (self.rev or self.dirtyRev or "unknown")}
        GIT_DIRTY=${if self ? rev then "false" else "true"}
        GIT_LAST_MODIFIED=${self.lastModifiedDate or "unknown"}
        GIT_SOURCE_URL=https://github.com/vpittamp/nixos-config/tree/${self.rev or "main"}

        # Flake Input Revisions (for reproducibility)
        NIXPKGS_REV=${inputs.nixpkgs.rev or "unknown"}
        NIXPKGS_NARHASH=${inputs.nixpkgs.narHash or "unknown"}
        HOME_MANAGER_REV=${inputs.home-manager.rev or "unknown"}

        # System Information
        HOSTNAME=${hostname}
        SYSTEM=${system}
        BUILD_DATE=${builtins.substring 0 8 self.lastModifiedDate or "unknown"}
        FLAKE_URL=github:vpittamp/nixos-config/${self.rev or "main"}

        # Useful Commands
        # Rebuild this exact configuration:
        #   sudo nixos-rebuild switch --flake ${self.sourceInfo.outPath or "."}
        # View git commit:
        #   git show ${self.rev or "HEAD"}
        # Switch to this git revision:
        #   git checkout ${self.rev or "main"}
      '';
    };

  # Internal helper: Create pkgs instances for a given system
  mkPkgs = system: import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };

  mkPkgsUnstable = system: import nixpkgs-bleeding {
    inherit system;
    config.allowUnfree = true;
  };

  # Monitor role definitions per hostname
  # Role indices: primary=0, secondary=1, tertiary=2, quaternary=3
  # Widgets should reference roles, not hardcoded output names
  # 4-tier system: primary (WS 1-2), secondary (WS 3-4), tertiary (WS 5-6), quaternary (WS 7+)
  monitorConfig = {
    "thinkpad" = {
      outputs = [ "eDP-1" "HDMI-A-1" "DP-1" ];
      primary = "eDP-1";
      secondary = "HDMI-A-1";
      tertiary = "DP-1";  # USB-C/Thunderbolt display
      quaternary = "DP-1"; # Fallback to tertiary
    };
    # Ryzen Desktop: 4-monitor bare-metal setup with NVIDIA RTX 5070
    # Physical layout (matching sway.nix):
    #   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    #   │  HDMI-A-1   │  │    DP-1     │  │    DP-2     │
    #   │   (Left)    │  │  (Primary)  │  │   (Right)   │
    #   └─────────────┘  └─────────────┘  └─────────────┘
    #                    ┌─────────────┐
    #                    │    DP-3     │
    #                    │  (Bottom)   │
    #                    └─────────────┘
    "ryzen" = {
      outputs = [ "DP-1" "HDMI-A-1" "DP-2" "DP-3" ];
      primary = "DP-1";       # Center monitor (main workspace)
      secondary = "HDMI-A-1"; # Left monitor
      tertiary = "DP-2";      # Right monitor
      quaternary = "DP-3";    # Bottom monitor
    };
  };
in
{
  # Export monitor configuration for use in home-manager modules
  inherit monitorConfig;

  # Feature 106: Export assets package factory for portable builds
  # Usage: assetsPackage = helpers.mkAssetsPackage pkgs;
  inherit mkAssetsPackage;
  # Create a standardized Home Manager configuration for NixOS modules
  # This ensures consistency across all NixOS configurations
  mkHomeManagerConfig = { system, user, modules, osConfig ? null }:
    let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-unstable = import nixpkgs-bleeding {
        inherit system;
        config.allowUnfree = true;
      };
      # Feature 106: Create assets package for this system
      assetsPackage = mkAssetsPackage pkgs;
    in
    {
      home-manager = {
        # Disable home-manager automatic backups; we manage state with git
        # instead. Do NOT set a fixed backupFileExtension here: files re-created
        # as real files every activation (e.g. the writable ~/.claude/settings.json
        # copy from ai-assistants/claude-code.nix) would clobber the same <file>.<ext>
        # backup target on the next run — home-manager then refuses ("backup would
        # be clobbered"), wedging activation on every reboot. Clobbers are fixed at
        # the source by suppressing the offending managed symlink (see
        # ai-assistants/claude-code.nix), not by backing it up here.
        backupFileExtension = null;
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = {
          inherit inputs self pkgs-unstable monitorConfig assetsPackage;
        } // (if osConfig != null then { inherit osConfig; } else { });
        users.${user} = {
          imports = modules;
          home.enableNixpkgsReleaseCheck = false;
        };
      };
    };

  # Create a complete NixOS system configuration
  # This is the recommended pattern for all system configurations
  mkSystem = { hostname, system, modules }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = modules ++ [
        # Add build metadata
        (mkBuildMetadata { inherit hostname system; })

        # Add Home Manager integration
        home-manager.nixosModules.home-manager
      ];
    };
}

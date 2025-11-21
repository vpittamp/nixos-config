# Common helper functions for flake outputs
# These functions reduce duplication across NixOS and Home Manager configurations
{ inputs, self, ... }:

let
  inherit (inputs) nixpkgs nixpkgs-bleeding home-manager;

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
  # Role indices: primary=0, secondary=1, tertiary=2
  # Widgets should reference roles, not hardcoded output names
  monitorConfig = {
    "nixos-hetzner-sway" = {
      outputs = [ "HEADLESS-1" "HEADLESS-2" "HEADLESS-3" ];
      primary = "HEADLESS-1";
      secondary = "HEADLESS-2";
      tertiary = "HEADLESS-3";
    };
    "nixos-m1" = {
      outputs = [ "eDP-1" "HDMI-A-1" ];
      primary = "eDP-1";
      secondary = "HDMI-A-1";
      tertiary = "HDMI-A-1";  # Fallback to secondary if no tertiary
    };
  };
in
{
  # Export monitor configuration for use in home-manager modules
  inherit monitorConfig;
  # Create a standardized Home Manager configuration for NixOS modules
  # This ensures consistency across all NixOS configurations
  mkHomeManagerConfig = { system, user, modules, osConfig ? null }:
    let
      pkgs-unstable = import nixpkgs-bleeding {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      home-manager = {
        # Disable home-manager automatic backups; we manage state with git instead
        backupFileExtension = null;
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = {
          inherit inputs self pkgs-unstable monitorConfig;
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

  # Create a standalone Home Manager configuration
  # Used for non-NixOS systems (macOS, other Linux distros)
  mkHomeConfiguration = { system, modules, username ? "vpittamp" }:
    let
      pkgs = mkPkgs system;
      pkgs-unstable = mkPkgsUnstable system;
    in
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs pkgs-unstable;
        # Note: osConfig intentionally omitted for standalone configs
        # to avoid circular dependencies
      };
      modules = modules;
    };
}

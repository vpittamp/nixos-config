# Package outputs for container images and VM images
# These are built with: nix build .#<package>
#
# Examples:
#   nix build .#container-minimal
#   nix build .#hetzner-sway-qcow2
{ inputs, self, ... }:

let
  inherit (inputs) nixpkgs nixpkgs-bleeding home-manager nixos-generators;
  helpers = import ../lib/helpers.nix { inherit inputs self; };

  # Helper to build container system
  mkContainerSystem = { system, profile }:
    let
      pkgsUnstable = helpers.mkPkgsUnstable system;
    in
    (nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs pkgsUnstable;
        containerProfile = profile;
      };
      modules = [
        ../configurations/container.nix
        home-manager.nixosModules.home-manager
        (helpers.mkHomeManagerConfig {
          inherit system;
          user = "code";
          modules = [ ../home-code.nix ];
        })
      ];
    }).config.system.build.toplevel;
in
{
  perSystem = { system, pkgs, ... }: {
    packages = {
      # KubeVirt Minimal QCOW2 image (Feature 110)
      # Minimal base image for KubeVirt CI/CD testing
      # Uses kubevirt.nix module: cloud-init, QEMU guest agent, SSH, serial console
      # ~500MB compressed, desktop applied via nixos-rebuild
      kubevirt-minimal-qcow2 =
        let
          nixosConfig = (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ ../configurations/kubevirt-minimal.nix ];
          }).config;
        in
        import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
          inherit pkgs;
          lib = pkgs.lib;
          config = nixosConfig;
          diskSize = 10 * 1024; # 10GB in MB (minimal base + rebuild space)
          format = "qcow2";
          partitionTableType = "hybrid";
          memSize = 4096; # 4GB QEMU VM memory for build process
        };

      # KubeVirt Sway Desktop QCOW2 image
      # Full Sway desktop with project management, 1Password, dev tools
      # ~2-3GB, no hardware-specific bloat (optimized for KubeVirt)
      kubevirt-sway-qcow2 =
        let
          nixosConfig = (nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs; };
            modules = [
              ../configurations/kubevirt-sway.nix
              home-manager.nixosModules.home-manager
            ];
          }).config;
        in
        import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
          inherit pkgs;
          lib = pkgs.lib;
          config = nixosConfig;
          diskSize = 80 * 1024; # 80GB in MB (full desktop + dev tools)
          format = "qcow2";
          partitionTableType = "hybrid";
          memSize = 8192; # 8GB QEMU VM memory for build process
        };

      # Hetzner Sway QCOW2 image (Feature 007-number-7-short)
      # Wayland/Sway headless VM with WayVNC server
      hetzner-sway-qcow2 =
        let
          # Build the NixOS configuration
          nixosConfig = (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ ../configurations/hetzner-sway-minimal.nix ];
          }).config;
        in
        # Call make-disk-image.nix directly with 8GB memSize
        import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
          inherit pkgs;
          lib = pkgs.lib;
          config = nixosConfig;
          diskSize = 50 * 1024; # 50GB in MB
          format = "qcow2";
          partitionTableType = "hybrid";
          memSize = 8192; # 8GB QEMU VM memory for build process
        };

      # Minimal container
      container-minimal = pkgs.dockerTools.buildLayeredImage {
        name = "nixos-container";
        tag = "minimal";
        contents = [ (mkContainerSystem { inherit system; profile = "minimal"; }) ];
        config = {
          Cmd = [ "/bin/bash" ];
          Env = [ "NIXOS_CONTAINER=1" "NIXOS_PACKAGES=minimal" ];
        };
      };

      # Development container
      container-dev = pkgs.dockerTools.buildLayeredImage {
        name = "nixos-container";
        tag = "development";
        contents = [ (mkContainerSystem { inherit system; profile = "development"; }) ];
        config = {
          Cmd = [ "/bin/bash" ];
          Env = [ "NIXOS_CONTAINER=1" "NIXOS_PACKAGES=development" ];
        };
      };

      # Default package
      default = pkgs.dockerTools.buildLayeredImage {
        name = "nixos-container";
        tag = "minimal";
        contents = [ (mkContainerSystem { inherit system; profile = "minimal"; }) ];
        config = {
          Cmd = [ "/bin/bash" ];
          Env = [ "NIXOS_CONTAINER=1" "NIXOS_PACKAGES=minimal" ];
        };
      };
    };
  };
}

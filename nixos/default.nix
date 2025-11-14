# NixOS system configurations
# Each entry here defines a complete NixOS system that can be built with:
#   sudo nixos-rebuild switch --flake .#<hostname>
{ inputs, self, lib, ... }:

let
  inherit (inputs) nixpkgs nixpkgs-bleeding home-manager disko;
  helpers = import ../lib/helpers.nix { inherit inputs self; };
in
{
  # Hetzner Cloud Server with Sway (Feature 046)
  # Headless Wayland with VNC remote access
  # Build: sudo nixos-rebuild switch --flake .#hetzner-sway
  hetzner-sway = helpers.mkSystem {
    hostname = "nixos-hetzner-sway";
    system = "x86_64-linux";
    modules = [
      disko.nixosModules.disko
      ../configurations/hetzner-sway.nix

      # Home Manager integration with Sway-specific config
      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/hetzner-sway.nix ];
      })
    ];
  };

  # M1 MacBook Pro (Apple Silicon)
  # Native NixOS on Apple Silicon with Sway/Wayland
  # Build: sudo nixos-rebuild switch --flake .#m1 --impure
  m1 = helpers.mkSystem {
    hostname = "nixos-m1";
    system = "aarch64-linux";
    modules = [
      ../configurations/m1.nix

      # Home Manager integration with M1-specific config
      (helpers.mkHomeManagerConfig {
        system = "aarch64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/m1.nix ];
      })
    ];
  };

  # ARCHIVED CONFIGURATIONS:
  # The following have been moved to archived/obsolete-configs/
  # - hetzner-i3.nix (testing config, consolidated into hetzner.nix)
  # - hetzner-mangowc.nix (MangoWC experimental compositor)
  # - hetzner-minimal.nix, hetzner-example.nix (nixos-anywhere templates)
  # - wsl.nix (WSL2 environment)
  # - vm-*.nix, kubevirt-*.nix (VM/KubeVirt deployments)
}

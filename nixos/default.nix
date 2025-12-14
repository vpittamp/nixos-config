# NixOS system configurations
# Each entry here defines a complete NixOS system that can be built with:
#   sudo nixos-rebuild switch --flake .#<hostname>
{ inputs, self, lib, ... }:

let
  inherit (inputs) nixpkgs nixpkgs-bleeding home-manager disko;
  helpers = import ../lib/helpers.nix { inherit inputs self; };
in
{
  # Hetzner Cloud Server with Sway
  # Headless Wayland with VNC remote access
  # Build: sudo nixos-rebuild switch --flake .#hetzner
  hetzner = helpers.mkSystem {
    hostname = "hetzner";
    system = "x86_64-linux";
    modules = [
      disko.nixosModules.disko
      ../configurations/hetzner.nix

      # Home Manager integration
      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/hetzner.nix ];
      })
    ];
  };

  # Lenovo ThinkPad (Intel Core Ultra 7 155U + Intel Arc)
  # Physical laptop with Sway/Wayland desktop
  # Build: sudo nixos-rebuild switch --flake .#thinkpad
  thinkpad = helpers.mkSystem {
    hostname = "thinkpad";
    system = "x86_64-linux";
    modules = [
      ../configurations/thinkpad.nix

      # Home Manager integration with ThinkPad-specific config
      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/thinkpad.nix ];
      })
    ];
  };

  # AMD Ryzen Desktop (AMD Ryzen 5 7600X3D + AMD GPU)
  # Physical desktop with Sway/Wayland desktop
  # Build: sudo nixos-rebuild switch --flake .#ryzen
  ryzen = helpers.mkSystem {
    hostname = "ryzen";
    system = "x86_64-linux";
    modules = [
      ../configurations/ryzen.nix

      # Home Manager integration with Ryzen-specific config
      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/ryzen.nix ];
      })
    ];
  };

  # ARCHIVED/REMOVED CONFIGURATIONS:
  # The following have been moved to archived/obsolete-configs/
  # - hetzner-i3.nix (testing config, consolidated into hetzner.nix)
  # - hetzner-mangowc.nix (MangoWC experimental compositor)
  # - hetzner-minimal.nix, hetzner-example.nix (nixos-anywhere templates)
  # - wsl.nix (WSL2 environment)
  # - vm-*.nix, kubevirt-*.nix (VM/KubeVirt deployments)
  #
  # The following have been removed (no longer in use):
  # - acer.nix (Acer Swift Go 16 - replaced by thinkpad)
  # - m1.nix (M1 MacBook Pro - Apple Silicon, no longer in use)
}

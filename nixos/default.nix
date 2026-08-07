# NixOS system configurations
# Each entry here defines a complete NixOS system that can be built with:
#   sudo nixos-rebuild switch --flake .#<hostname>
{ inputs, self, lib, ... }:

let
  inherit (inputs) nixpkgs nixpkgs-bleeding home-manager;
  helpers = import ../lib/helpers.nix { inherit inputs self; };
in
{
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

  # Microsoft Surface Laptop 2 (Intel Core i5-8250U + UHD 620)
  # Physical laptop with the full Sway/Wayland desktop stack (mirrors thinkpad).
  # Deploy from another host:
  #   nixos-rebuild switch --flake .#surface --target-host vpittamp@surface
  surface = helpers.mkSystem {
    hostname = "surface";
    system = "x86_64-linux";
    modules = [
      ../configurations/surface.nix

      # Home Manager integration with Surface-specific config
      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/surface.nix ];
      })
    ];
  };

  # Microsoft Surface Pro 3 (Intel Core i5-4300U Haswell + HD Graphics 4400)
  # 3.7 GiB RAM, 128GB SATA SSD. Near-parity with the Laptop 2's Sway/Quickshell
  # desktop; drops only the linux-surface kernel (the Pro 3 uses an N-trig HID
  # digitizer that mainline drives — IPTS is Pro 4 and newer), Podman and CUPS.
  # Always build on ryzen rather than on the device itself:
  #   nixos-rebuild switch --flake .#surface-pro3 \
  #     --target-host vpittamp@surface-pro --use-remote-sudo
  surface-pro3 = helpers.mkSystem {
    hostname = "surface-pro3";
    system = "x86_64-linux";
    modules = [
      ../configurations/surface-pro3.nix

      (helpers.mkHomeManagerConfig {
        system = "x86_64-linux";
        user = "vpittamp";
        modules = [ ../home-modules/surface-pro3.nix ];
      })
    ];
  };

  # ARCHIVED/REMOVED CONFIGURATIONS:
  # The following have been moved to archived/obsolete-configs/
  # - hetzner.nix (Hetzner Cloud Server with Sway - no longer in use)
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

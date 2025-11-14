# Standalone Home Manager configurations
# These are used for non-NixOS systems (macOS, other Linux distros)
# Build with: home-manager switch --flake .#<username>@<hostname>
#
# NOTE: For NixOS systems, Home Manager is integrated as a module in nixosConfigurations
# This avoids duplication and ensures atomic system+user rebuilds.
{ inputs, self, ... }:

let
  helpers = import ../lib/helpers.nix { inherit inputs self; };
in
{
  # Darwin (macOS) Home Manager configuration
  # This is the primary use case for standalone Home Manager configs
  # Usage: home-manager switch --flake .#darwin
  darwin = helpers.mkHomeConfiguration {
    system = "aarch64-darwin";
    username = "vpittamp";
    modules = [ ../home-darwin.nix ];
  };

  # REMOVED: vpittamp and code standalone configurations
  # Rationale: These were redundant with nixosConfigurations.*.home-manager
  # For NixOS systems, use:
  #   sudo nixos-rebuild switch --flake .#hetzner-sway
  #   sudo nixos-rebuild switch --flake .#m1
  #
  # This eliminates duplication and ensures system/user config consistency
}

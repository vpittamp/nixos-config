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

  # Codespaces/Container Home Manager configuration
  # Usage: home-manager switch --flake .#code
  code = helpers.mkHomeConfiguration {
    system = "x86_64-linux";
    username = "code";
    modules = [ ../home-code.nix ];
  };

  # REMOVED: vpittamp standalone configuration
  # Rationale: This was redundant with nixosConfigurations.*.home-manager
  # For NixOS systems, use:
  #   sudo nixos-rebuild switch --flake .#hetzner
  #
  # This eliminates duplication and ensures system/user config consistency
}

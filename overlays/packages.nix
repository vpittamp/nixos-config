# Package filtering overlay for containers
# Respects NIXOS_PACKAGES environment variable to control which packages are included
{ pkgs, lib, ... }:

let
  # Import the shared package lists which handles environment detection
  packageLists = import ../shared/package-lists.nix { inherit pkgs lib; };
  
  # Get the appropriate profile based on environment
  profile = packageLists.getProfile;
in {
  # All packages (system + user) for the current environment
  allPackages = profile.system ++ profile.user;
  
  # System-level packages only (custom derivations, WSL tools)
  systemPackages = profile.system;
  
  # User-level packages only (installable via home-manager)
  userPackages = profile.user;
  
  # Export environment detection for other modules
  inherit (packageLists) isContainer isWSL packageLevel;
}
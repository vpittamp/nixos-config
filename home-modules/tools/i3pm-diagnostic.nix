{ config, lib, pkgs, ... }:

let
  # Feature 039: Diagnostic tooling for i3 project management
  i3pm-diagnostic = pkgs.callPackage ./i3pm-diagnostic/default.nix {};
in
{
  config = {
    # Install i3pm-diagnose binary
    home.packages = [ i3pm-diagnostic ];
  };
}

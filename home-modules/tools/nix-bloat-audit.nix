{ pkgs, ... }:

let
  nix-bloat-audit = pkgs.callPackage ./nix-bloat-audit/default.nix { };
in
{
  home.packages = [ nix-bloat-audit ];
}

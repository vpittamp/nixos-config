{ pkgs, lib, ... }:

# Register the Nix-packaged gh-enhance binary as a gh CLI extension by linking
# it into the extensions data directory that `gh` scans. This makes `gh enhance`
# work in addition to running `gh-enhance` directly.

let
  gh-enhance = pkgs.callPackage ../../packages/gh-enhance.nix { };
in
{
  home.packages = [ gh-enhance ];

  xdg.dataFile."gh/extensions/gh-enhance/gh-enhance".source =
    lib.getExe gh-enhance;
}

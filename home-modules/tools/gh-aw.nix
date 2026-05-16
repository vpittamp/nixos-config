{ config, pkgs, lib, ... }:

# Register the Nix-packaged gh-aw binary as a gh CLI extension by linking it
# into the extensions data directory that `gh` scans. The `gh` CLI does not
# discover extensions from $PATH — it walks $XDG_DATA_HOME/gh/extensions/<name>
# and runs the matching binary inside, which is why a bare $PATH install lets
# you run `gh-aw` directly but fails on `gh aw`.

let
  gh-aw = pkgs.callPackage ../../packages/gh-aw.nix { };
in
{
  home.packages = [ gh-aw ];

  xdg.dataFile."gh/extensions/gh-aw/gh-aw".source =
    lib.getExe gh-aw;
}

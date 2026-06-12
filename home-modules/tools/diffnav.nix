{ pkgs, ... }:

let
  diffnav = pkgs.callPackage ../../packages/diffnav.nix { };
in
{
  home.packages = [ diffnav ];

  xdg.dataFile."gh/extensions/gh-diffnav/gh-diffnav".source =
    "${diffnav}/bin/gh-diffnav";

  xdg.configFile."diffnav/config.yml".text = ''
    ui:
      hideHeader: false
      hideFooter: false
      showFileTree: true
      fileTreeWidth: 32
      searchTreeWidth: 60
      icons: nerd-fonts-status
      colorFileNames: true
      showDiffStats: true
      sideBySide: true
      startFoldersOpenDepth: 1
  '';
}

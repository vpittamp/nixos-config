{ config, pkgs, lib, pkgs-unstable ? pkgs, ... }:

let
  # GitHub Copilot CLI - use nixpkgs package (built from npm @github/copilot)
  # To bump version ahead of nixpkgs, override src + npmDepsHash
  copilotCliPackage = pkgs-unstable.github-copilot-cli or pkgs.github-copilot-cli;

  # Wrapper: clear inherited NODE_OPTIONS when copilot is launched from
  # within another AI CLI's shell/tool process.
  copilotCliWrapped = pkgs.symlinkJoin {
    name = "github-copilot-cli-wrapped";
    paths = [ copilotCliPackage ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/copilot \
        --unset NODE_OPTIONS
    '';
  };
in
{
  home.packages = [ copilotCliWrapped ];
}

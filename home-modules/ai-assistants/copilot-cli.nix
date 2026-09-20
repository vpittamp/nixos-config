{ config, pkgs, lib, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;

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
  sharedSkillsDir = repoRoot + "/shared-skills";
  sharedSkillEntries = if builtins.pathExists sharedSkillsDir then builtins.readDir sharedSkillsDir else {};
  sharedSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink") sharedSkillEntries;
  sharedSkillHomeFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".copilot/skills/${name}" {
        source = sharedSkillsDir + "/${name}";
        recursive = true;
        force = true;
      }
    )
    sharedSkillDirs;
in
{
  home.packages = [ copilotCliWrapped ];
  home.file = sharedSkillHomeFiles;
}

{ lib, pkgs, ... }:

let
  version = "2.3.1";

  git-gtr = pkgs.stdenvNoCC.mkDerivation {
    pname = "git-gtr";
    inherit version;

    src = pkgs.fetchFromGitHub {
      owner = "coderabbitai";
      repo = "git-worktree-runner";
      rev = "v${version}";
      hash = "sha256-NXA2K+9VUejfKnTkkO0V1PXd+PO6diVhGsMlRxWmcus=";
    };

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/share/git-gtr"
      cp -R ./* "$out/share/git-gtr/"
      chmod -R u+w "$out/share/git-gtr"

      mkdir -p "$out/bin"
      ln -s "$out/share/git-gtr/bin/git-gtr" "$out/bin/git-gtr"
      ln -s "$out/share/git-gtr/bin/gtr" "$out/bin/gtr"

      runHook postInstall
    '';

    meta = with lib; {
      description = "Portable CLI for managing git worktrees";
      homepage = "https://github.com/coderabbitai/git-worktree-runner";
      license = licenses.asl20;
      platforms = platforms.unix;
      mainProgram = "git-gtr";
    };
  };
in
{
  home.packages = [ git-gtr ];

  programs.bash.initExtra = lib.mkAfter ''
    # git-gtr shell completion + gtr cd helper
    if command -v git >/dev/null 2>&1 && git gtr version >/dev/null 2>&1; then
      source <(git gtr completion bash 2>/dev/null)
      eval "$(git gtr init bash 2>/dev/null)"
    fi
  '';
}

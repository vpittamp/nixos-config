{ config, pkgs, lib, ... }:

let
  # OpenCode - AI-powered terminal coding agent
  # https://github.com/opencode-ai/opencode
  # Latest release: v0.0.55 (2025-06-27)
  opencodePkg = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "opencode";
    version = "0.0.55";

    src = pkgs.fetchurl {
      url = "https://github.com/opencode-ai/opencode/releases/download/v${version}/opencode-linux-x86_64.tar.gz";
      hash = "sha256-fx9BID55IK7Ejz4iFtM06c6MbQp7EHzrdY/vpNTJgCU=";
    };

    sourceRoot = ".";

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    installPhase = ''
      runHook preInstall
      install -Dm755 opencode $out/bin/opencode
      runHook postInstall
    '';

    meta = {
      description = "AI-powered coding agent built for the terminal";
      homepage = "https://github.com/opencode-ai/opencode";
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "opencode";
    };
  };

  # tsgo - TypeScript native compiler (Go port)
  # https://github.com/microsoft/typescript-go
  # Distributed via npm as @typescript/native-preview
  tsgoPkg = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "tsgo";
    version = "7.0.0-dev.20260219.1";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@typescript/native-preview-linux-x64/-/native-preview-linux-x64-${version}.tgz";
      hash = "sha256-7zMSoMilbtO81NiKiv/Z/qfPdV4cOOdgQlOHNNKrojk=";
    };

    sourceRoot = "package";

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/lib/tsgo
      cp -r lib/*.d.ts $out/lib/tsgo/
      install -Dm755 lib/tsgo $out/lib/tsgo/tsgo
      # Wrapper that sets the lib path so tsgo finds its .d.ts files
      cat > $out/bin/tsgo <<EOF
      #!/bin/sh
      exec $out/lib/tsgo/tsgo "\$@"
      EOF
      chmod +x $out/bin/tsgo
      runHook postInstall
    '';

    meta = {
      description = "TypeScript native compiler written in Go (TypeScript 7 preview)";
      homepage = "https://github.com/microsoft/typescript-go";
      license = lib.licenses.asl20;
      platforms = [ "x86_64-linux" ];
      mainProgram = "tsgo";
    };
  };
in
{
  home.packages = [
    opencodePkg
    tsgoPkg
    pkgs.bun
  ];
}

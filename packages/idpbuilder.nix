{ lib, stdenv, fetchurl, autoPatchelfHook }:

let
  version = "0.10.1";
  system = stdenv.hostPlatform.system;

  assets = {
    "x86_64-linux" = {
      url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${version}/idpbuilder-linux-amd64.tar.gz";
      sha256 = "1w1h6zbr0vzczk1clddn7538qh59zn6cwr37y2vn8mjzhqv8dpsr";
    };
    "aarch64-linux" = {
      url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${version}/idpbuilder-linux-arm64.tar.gz";
      sha256 = "0275gkv4zzkw891ni4dliqjmc08va3w033n57g5hfikq26m35kcf";
    };
  };

  asset = assets.${system} or (throw "Unsupported system for idpbuilder: ${system}");
in
stdenv.mkDerivation {
  pname = "idpbuilder";
  inherit version;

  src = fetchurl asset;

  sourceRoot = ".";
  dontBuild = true;

  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    mkdir -p $out/bin
    cp idpbuilder $out/bin/
    chmod +x $out/bin/idpbuilder
  '';

  meta = with lib; {
    description = "Build Internal Developer Platforms (IDPs) declaratively";
    homepage = "https://github.com/cnoe-io/idpbuilder";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "idpbuilder";
  };
}

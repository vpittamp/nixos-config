{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, buildGoModule
, idpbuilderSrc ? null
}:

let
  upstreamVersion = "0.10.1";
  forkVersion = "0.10.1-vpittamp";
  system = stdenv.hostPlatform.system;

  assets = {
    "x86_64-linux" = {
      url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${upstreamVersion}/idpbuilder-linux-amd64.tar.gz";
      sha256 = "1w1h6zbr0vzczk1clddn7538qh59zn6cwr37y2vn8mjzhqv8dpsr";
    };
    "aarch64-linux" = {
      url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${upstreamVersion}/idpbuilder-linux-arm64.tar.gz";
      sha256 = "0275gkv4zzkw891ni4dliqjmc08va3w033n57g5hfikq26m35kcf";
    };
  };

  asset = assets.${system} or (throw "Unsupported system for idpbuilder: ${system}");
in
if idpbuilderSrc != null then buildGoModule {
  pname = "idpbuilder";
  version = forkVersion;

  src = idpbuilderSrc;
  vendorHash = "sha256-jS5IQ/UIMGAR5ovNg1uunJHRyasGFjigzfFmvN8qsK4=";

  subPackages = [ "." ];
  doCheck = false;

  ldflags = [
    "-X github.com/cnoe-io/idpbuilder/pkg/cmd/version.idpbuilderVersion=${forkVersion}"
    "-X github.com/cnoe-io/idpbuilder/pkg/cmd/version.gitCommit=unknown"
    "-X github.com/cnoe-io/idpbuilder/pkg/cmd/version.buildDate=1970-01-01T00:00:00Z"
  ];

  meta = with lib; {
    description = "Build Internal Developer Platforms (IDPs) declaratively, using the Pittampalli idpbuilder fork";
    homepage = "https://github.com/vpittamp/idpbuilder";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "idpbuilder";
  };
} else stdenv.mkDerivation {
  pname = "idpbuilder";
  version = upstreamVersion;

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

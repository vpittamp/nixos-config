{ lib, stdenv, fetchurl, autoPatchelfHook }:

stdenv.mkDerivation rec {
  pname = "idpbuilder";
  version = "0.10.0";

  src = fetchurl {
    url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${version}/idpbuilder-linux-amd64.tar.gz";
    hash = "sha256-ZE5ActmrVmpJzaL7p/MsAqFjgHdHkpItpQ7WmEMCN7s=";
  };

  dontBuild = true;
  
  sourceRoot = ".";

  nativeBuildInputs = [ autoPatchelfHook ];

  unpackPhase = ''
    tar -xzf $src
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp idpbuilder $out/bin/
    chmod +x $out/bin/idpbuilder
  '';

  meta = with lib; {
    description = "Build Internal Developer Platforms (IDPs) declaratively";
    homepage = "https://github.com/cnoe-io/idpbuilder";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "idpbuilder";
  };
}
{ lib, stdenv, fetchurl }:

stdenv.mkDerivation rec {
  pname = "idpbuilder";
  version = "0.10.1";

  src = fetchurl {
    url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${version}/idpbuilder-linux-arm64.tar.gz";
    sha256 = "11982skp9vm8cbhyvl44avm0777icmk88x5f291rgx2a311y8n6a";
  };

  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out/bin
    cp idpbuilder $out/bin/
    chmod +x $out/bin/idpbuilder
  '';

  meta = with lib; {
    description = "CNOE IDP Builder for creating local development clusters";
    homepage = "https://github.com/cnoe-io/idpbuilder";
    license = licenses.asl20;
    platforms = [ "aarch64-linux" ];
    maintainers = [ ];
  };
}
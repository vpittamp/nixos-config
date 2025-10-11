# virtctl - KubeVirt CLI tool for managing virtual machines in Kubernetes
{ lib, stdenv, fetchurl }:

let
  pname = "virtctl";
  version = "1.6.2";

  # Select architecture-specific source
  src = fetchurl (
    if stdenv.isx86_64 then {
      url = "https://github.com/kubevirt/kubevirt/releases/download/v${version}/virtctl-v${version}-linux-amd64";
      sha256 = "0d0pzkp22n4bm06crbh3sk8i25a068j9sg3flqb8spy3rx9lqp0f";
    } else if stdenv.isAarch64 then {
      url = "https://github.com/kubevirt/kubevirt/releases/download/v${version}/virtctl-v${version}-linux-arm64";
      sha256 = "1z98zazd4124fx2b7dq0va88w0vr7vm7kwyrvqg3yx47y4wbcd43";
    } else throw "Unsupported platform for virtctl"
  );
in
stdenv.mkDerivation {
  inherit pname version src;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -D -m755 $src $out/bin/virtctl

    runHook postInstall
  '';

  meta = with lib; {
    description = "KubeVirt CLI for managing virtual machines in Kubernetes";
    homepage = "https://kubevirt.io/";
    license = licenses.asl20;
    maintainers = with maintainers; [ ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "virtctl";
  };
}

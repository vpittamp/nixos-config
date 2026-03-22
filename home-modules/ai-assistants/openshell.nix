{ config, pkgs, lib, ... }:

let
  # NVIDIA OpenShell - sandboxed runtime for autonomous AI agents
  # https://github.com/NVIDIA/OpenShell
  # Latest release: v0.0.13 (2026-03-21)
  # Requires Docker running for sandbox operations
  openshellPkg = pkgs.python3Packages.buildPythonPackage rec {
    pname = "openshell";
    version = "0.0.13";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/49/6b/7af2242d98397139041f2c806c9ce4d71088c30c15f9e4428b59e6e13b00/openshell-${version}-py3-none-manylinux_2_39_x86_64.whl";
      hash = "sha256-oAMQXJETafJFXqkVrqSBlJieW/urBI5jyuOlJbPm0HA=";
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
    ];

    buildInputs = [
      pkgs.stdenv.cc.cc.lib
    ];

    dependencies = with pkgs.python3Packages; [
      cloudpickle
      grpcio
      protobuf
    ];

    doCheck = false;

    meta = {
      description = "NVIDIA OpenShell - sandboxed runtime for autonomous AI agents";
      homepage = "https://github.com/NVIDIA/OpenShell";
      license = lib.licenses.asl20;
      platforms = [ "x86_64-linux" ];
      mainProgram = "openshell";
    };
  };
in
{
  home.packages = [ openshellPkg ];
}

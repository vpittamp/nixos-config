{ lib, pkgs, ... }:

let
  # External Secrets Operator plugin for Headlamp
  esoPlugin = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "external-secrets-operator-headlamp-plugin";
    version = "0.1.0-beta7";
    src = pkgs.fetchurl {
      url = "https://github.com/magohl/external-secrets-operator-headlamp-plugin/releases/download/${version}/${pname}-${version}.tar.gz";
      sha256 = "sha256-776NO3HJBLi8Nh0DcGyFuECozsGodwr8Obt3yX2RSh0=";
    };
    dontBuild = true;
    unpackPhase = ''
      runHook preUnpack
      mkdir -p source
      tar -xzf "$src" -C source
      runHook postUnpack
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/plugins"
      cp -a source/external-secrets-operator-headlamp-plugin \
        "$out/plugins/external-secrets-operator-headlamp-plugin"
      runHook postInstall
    '';
    meta = with lib; {
      description = "Headlamp plugin for External Secrets Operator";
      homepage = "https://github.com/magohl/external-secrets-operator-headlamp-plugin";
      license = licenses.asl20;
      platforms = platforms.linux;
    };
  };

  pluginsOut = pkgs.symlinkJoin {
    name = "headlamp-plugins-bundle";
    paths = [ esoPlugin ];
  };
in
{
  # Preinstall required Headlamp plugins for the user
  home.file.".config/Headlamp/plugins" = {
    source = pluginsOut + "/plugins";
    recursive = true;
  };
}

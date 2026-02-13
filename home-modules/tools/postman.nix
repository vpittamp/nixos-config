# Postman API Development Environment
# Electron-based desktop app with CA cert trust for K8s cluster endpoints
{ config, pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
  home.packages = [
    # Wrap Postman with NODE_EXTRA_CA_CERTS for K8s cluster CA trust
    # The NSS DB trust from chromium.nix handles Electron's Chromium layer
    (pkgs.symlinkJoin {
      name = "postman-wrapped";
      paths = [ pkgs.postman ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/postman \
          --set NODE_EXTRA_CA_CERTS /etc/ssl/certs/ca-certificates.crt
      '';
    })
  ];
}

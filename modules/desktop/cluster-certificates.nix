{ config, lib, pkgs, ... }:

let
  stacksDir = "/home/vpittamp/stacks";
  syncScript = "${stacksDir}/scripts/sync-cluster-certificates.sh";
  certPath = "${stacksDir}/certs/idpbuilder-ca.crt";
in
{
  systemd.services.cluster-cert-sync = {
    description = "Install IDPBuilder certificates into system trust stores";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      STACKS_DIR = stacksDir;
      TARGET_USER = "vpittamp";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${syncScript} --system";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };

  systemd.paths.cluster-cert-sync = {
    description = "Watch IDPBuilder certificate for updates";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      Unit = "cluster-cert-sync.service";
      PathChanged = certPath;
      PathExists = certPath;
    };
  };
}

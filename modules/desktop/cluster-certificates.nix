{ config, lib, pkgs, ... }:

let
  certDir = "/home/vpittamp/stacks/certs";
  
  # List of certificate files that may exist
  possibleCerts = [
    "${certDir}/idpbuilder-ca.crt"
    "${certDir}/argocd-server-tls.crt"
    "${certDir}/kargo-webhooks-server-cert.crt"
  ];
  
  # Filter to only existing certificates
  existingCerts = builtins.filter (cert: builtins.pathExists cert) possibleCerts;
  
  # Create etc entries for existing certificates
  certEtcEntries = builtins.listToAttrs (
    builtins.map (cert: {
      name = "ssl/certs/cluster-${builtins.baseNameOf cert}";
      value = {
        source = cert;
        mode = "0444";
      };
    }) existingCerts
  );
in
{
  # System-wide certificate trust for IDPBuilder/Kind cluster
  # Only add certificates that actually exist
  security.pki.certificateFiles = lib.mkIf (existingCerts != []) existingCerts;
  
  # Create symlinks for certificates in standard locations
  environment.etc = lib.mkIf (existingCerts != []) certEtcEntries;
  
  # Note: Certificates will be imported when the cluster is created
  # Run: /home/vpittamp/stacks/scripts/import-cluster-certs.sh
}

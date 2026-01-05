# Cluster CA Certificate Trust Module
#
# Configures NixOS to trust self-signed CA certificates from local Kubernetes clusters.
# This is required for Nix to fetch from binary caches (like Attic) that use HTTPS
# with cluster-generated certificates.
#
# The CA certificate is synced by: stacks/scripts/certificates/sync-cluster-certificates.sh
# which extracts the CA from the idpbuilder-cert secret and saves it locally.
#
# Usage:
#   services.clusterCerts = {
#     enable = true;
#     caFile = "/path/to/custom/ca.crt";  # optional, has sensible default
#   };

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.clusterCerts;
  # Convert string path to Nix path for proper store handling
  caPath = /. + cfg.caFile;
  caExists = builtins.pathExists caPath;
  # Read the certificate content and create a store path
  caCert = if caExists then
    pkgs.writeText "cluster-ca.crt" (builtins.readFile caPath)
  else null;
in {
  options.services.clusterCerts = {
    enable = mkEnableOption "Trust local Kubernetes cluster CA certificates";

    caFile = mkOption {
      type = types.str;
      default = "/home/vpittamp/.local/share/cluster-certs/idpbuilder-ca.crt";
      description = ''
        Path to the cluster CA certificate file.
        This file is created by the sync-cluster-certificates.sh script
        after extracting the CA from the Kubernetes cluster.

        If this file doesn't exist, run:
          stacks/scripts/certificates/sync-cluster-certificates.sh
      '';
    };
  };

  config = mkIf (cfg.enable && caExists) {
    # Add the cluster CA to the system trust store
    # This allows Nix, curl, and other tools to trust HTTPS connections
    # to services using cluster-issued certificates (e.g., Attic, Gitea)
    # Use certificates (inline content) instead of certificateFiles for reliability
    security.pki.certificates = [ (builtins.readFile caPath) ];
  };
}

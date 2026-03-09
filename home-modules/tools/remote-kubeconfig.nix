{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.tools.remoteKubeconfig;
in
{
  options.modules.tools.remoteKubeconfig = {
    enable = mkEnableOption "remote kubeconfig helper backed by Tailscale service endpoints";

    targetConfig = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Filesystem path to the kubeconfig that should receive the merged content.
        Defaults to ~/.kube/config.
      '';
    };

    tailscaleEndpoints = mkOption {
      type = types.listOf types.str;
      default = [
        "k8s-api-hub.tail286401.ts.net"
        "k8s-api-dev.tail286401.ts.net"
        "k8s-api-staging.tail286401.ts.net"
        "k8s-api-ryzen.tail286401.ts.net"
      ];
      example = [
        "k8s-api-hub.tail286401.ts.net"
        "k8s-api-dev.tail286401.ts.net"
      ];
      description = ''
        Canonical Tailscale Kubernetes API service endpoints to configure into the
        local kubeconfig. Unreachable endpoints are skipped.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      targetPath =
        if cfg.targetConfig != null
        then cfg.targetConfig
        else "${config.home.homeDirectory}/.kube/config";
      targetDir = dirOf targetPath;
      endpointsFile = pkgs.writeText "remote-kubeconfig-endpoints.json" (builtins.toJSON cfg.tailscaleEndpoints);
      mergeScript = pkgs.writeShellScriptBin "merge-remote-kubeconfig" ''
        set -euo pipefail

        TARGET=${lib.escapeShellArg targetPath}

        for cmd in kubectl tailscale ${pkgs.python3}/bin/python3; do
          if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: required command '$cmd' not found in PATH" >&2
            exit 1
          fi
        done

        mkdir -p "$(dirname "$TARGET")"
        touch "$TARGET"
        chmod 600 "$TARGET"

        mapfile -t ENDPOINTS < <(${pkgs.python3}/bin/python3 -c 'import json,sys; [print(x) for x in json.load(open(sys.argv[1]))]' ${endpointsFile})

        for endpoint in "''${ENDPOINTS[@]}"; do
          [ -z "$endpoint" ] && continue
          echo "Configuring kubeconfig for $endpoint..."
          if KUBECONFIG="$TARGET" tailscale configure kubeconfig "$endpoint" >/dev/null 2>&1; then
            echo "✓ Added/updated $endpoint"
          else
            echo "WARNING: skipped unreachable endpoint $endpoint"
          fi
        done

        echo "Done. Available contexts in $TARGET:"
        kubectl config get-contexts || true
      '';
    in
    {
      home.packages = [ mergeScript ];

      home.activation.ensureKubeConfigDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg targetDir}
        $DRY_RUN_CMD chmod 700 ${lib.escapeShellArg targetDir}
      '';
    }
  );
}

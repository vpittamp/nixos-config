# Tailnet kubectl access to the PittampalliOrg/stacks fleet clusters from any
# user workstation (thinkpad, ryzen, …).
#
# Two access patterns, because the fleet has two kinds of tailnet kube-api exposure:
#
#  1. OPERATOR APISERVER-PROXY clusters (hub, dev, staging) — the spoke/hub
#     Tailscale operator runs an apiserver-proxy (mode:auth) that TLS-terminates
#     with its own cert and applies ACL impersonation. `tailscale configure
#     kubeconfig <service>` sets up a TOKEN-FREE context (authenticated purely by
#     Tailscale identity via the vpittamp@github → system:masters grant in
#     policy.hujson). No secret on disk.
#
#  2. HOST-PASSTHROUGH clusters (ryzen) — the durable, no-Let's-Encrypt path:
#     the host runs `tailscale serve --tcp=6443` as a RAW TCP passthrough to the
#     Talos kube-apiserver, which presents its OWN cert (valid for
#     ryzen.tail286401.ts.net, NOT ryzen-api-v3). Raw passthrough has no auth
#     proxy, so `tailscale configure kubeconfig` does NOT work here — kubectl
#     must hit the host endpoint with the Talos CA + a real bearer token. We pull
#     the SA token + CA from Azure Key Vault (the same creds the hub's
#     ExternalSecret-cluster-ryzen uses), so a recreate just needs a re-run.
#
# `sync-fleet-kubeconfigs` is idempotent — re-run any time (e.g. after a spoke
# recreate). Clusters whose API isn't currently advertised/reachable are skipped.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.tools.fleetKubeconfigs;
in {
  options.modules.tools.fleetKubeconfigs = {
    enable = mkEnableOption "tailnet kubectl access to the stacks fleet clusters";

    proxyServices = mkOption {
      type = types.listOf types.str;
      default = [ "k8s-api-hub" "dev-api-v2" "staging-api-v2" ];
      description = ''
        Tailscale operator apiserver-proxy Service names to register TOKEN-FREE via
        `tailscale configure kubeconfig` (impersonation via the device owner's
        policy.hujson grant).
      '';
    };

  };

  config = mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellScriptBin "sync-fleet-kubeconfigs" ''
        set -uo pipefail
        PATH="${makeBinPath [ pkgs.tailscale pkgs.kubectl pkgs.coreutils pkgs.gnugrep ]}:$PATH"

        echo "→ operator apiserver-proxy clusters (token-free via Tailscale identity)"
        for svc in ${concatStringsSep " " cfg.proxyServices}; do
          if tailscale configure kubeconfig "$svc" 2>/dev/null; then
            echo "  ✓ $svc"
          else
            echo "  ⚠ $svc not reachable/advertised right now (skipped)"
          fi
        done

        # Drop the stale ryzen-api-v3 proxy context if a previous version created it
        # (ryzen-api-v3 is now raw passthrough — that context can't authenticate).
        kubectl config delete-context ryzen-api-v3.tail286401.ts.net >/dev/null 2>&1 || true
        kubectl config delete-cluster ryzen-api-v3.tail286401.ts.net >/dev/null 2>&1 || true

        # The ryzen host-passthrough step was removed 2026-08-23: the ryzen Talos
        # cluster has been decommissioned (no Talos containers on the host, no
        # `tailscale serve --tcp=6443` passthrough, and no working ryzen kube
        # context). It pulled ARGOCD-CLUSTER-RYZEN-{TOKEN,CA} from Azure Key Vault
        # and was the last runtime consumer of azure-cli (~1.88 GiB in the closure).
        # The hub/dev fleet moved to 1Password (ClusterSecretStore onepassword-store,
        # onepasswordSDK provider); no azurekv store exists on any cluster. If a
        # ryzen cluster ever comes back, prefer `talosctl kubeconfig` or the operator
        # apiserver-proxy above over reintroducing a cloud secret store here.

        echo "kubectl contexts now available:"
        kubectl config get-contexts -o name 2>/dev/null | sed 's/^/  /'
      '')
    ];
  };
}

# Tailnet kubectl access to the PittampalliOrg/stacks fleet clusters from any
# user workstation (thinkpad, ryzen, …) WITHOUT managing bearer tokens.
#
# The device owner (vpittamp@github) holds an `impersonate: system:masters`
# grant to the operator API-server proxies in the tailnet ACL (policy.hujson),
# so `tailscale configure kubeconfig <service>` adds a kubectl context that
# authenticates purely by Tailscale identity — no token, no kubeconfig secret to
# rotate. This module installs `sync-fleet-kubeconfigs`, which configures a
# context per fleet cluster API service. Re-run it any time (e.g. after a spoke
# recreate); it is idempotent and refreshes in place.
#
# NOTE on ryzen: `ryzen-api-v3` is the spoke Tailscale operator's apiserver-proxy
# (token-free, fine for an occasional workstation kubectl). The hub→ryzen GitOps
# path was moved OFF that proxy to a durable host passthrough
# (ryzen.tail286401.ts.net:6443, bearer token) because its per-hostname Let's
# Encrypt cert can't survive rapid recreate churn — but that constraint does not
# affect a human workstation. If the ryzen operator proxy is ever retired,
# replace "ryzen-api-v3" here with a host-endpoint kubeconfig (needs a token).
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.tools.fleetKubeconfigs;
in {
  options.modules.tools.fleetKubeconfigs = {
    enable = mkEnableOption "token-free tailnet kubectl access to the stacks fleet clusters";

    services = mkOption {
      type = types.listOf types.str;
      default = [ "k8s-api-hub" "ryzen-api-v3" "dev-api-v2" "staging-api-v2" ];
      description = ''
        Tailscale kube-apiserver Service names to register as kubectl contexts
        via `tailscale configure kubeconfig`. Each must be advertised by an
        operator apiserver-proxy and approved for vpittamp@github in policy.hujson.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellScriptBin "sync-fleet-kubeconfigs" ''
        set -uo pipefail
        services="${concatStringsSep " " cfg.services}"
        echo "→ configuring token-free kubectl contexts for the stacks fleet (Tailscale auth proxy)"
        any=0
        for svc in $services; do
          if ${pkgs.tailscale}/bin/tailscale configure kubeconfig "$svc" 2>/dev/null; then
            echo "  ✓ $svc"
            any=1
          else
            echo "  ⚠ $svc not reachable/advertised right now (skipped)"
          fi
        done
        if [ "$any" = "1" ]; then
          echo "kubectl contexts now available:"
          ${pkgs.kubectl}/bin/kubectl config get-contexts -o name 2>/dev/null | sed 's/^/  /'
        else
          echo "no fleet services were reachable — is Tailscale up (tailscale status)?" >&2
          exit 1
        fi
      '')
    ];
  };
}

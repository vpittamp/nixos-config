# Expose a local Talos-in-Docker kube-apiserver on the tailnet for an external
# ArgoCD (the PittampalliOrg/stacks hub) to reach over Tailscale — the durable
# hub→spoke connectivity path that REPLACES the spoke Tailscale operator's
# apiserver-proxy and its per-hostname Let's Encrypt cert (whose 5-dup-certs/week
# limit broke the fleet under destroy/recreate churn).
#
# Mechanism: a oneshot runs `tailscale serve --tcp=<port>` as a RAW TCP
# passthrough (NOT --tls-terminated-tcp) to the Talos kube-apiserver, so the
# apiserver's OWN serving cert is presented end-to-end and the hub verifies it
# against the Talos CA. The hub-side cluster Secret carries the matching caData +
# a per-recreate SA bearer token, and the Talos apiserver cert carries certSANs
# for this host's tailnet FQDN/IP (set by the stacks bootstrap --config-patch).
#
# Host-agnostic: discovers the Talos controlplane container by name pattern
# (talosctl maps kube-api 6443 to a random host port per `cluster create`, so the
# target is resolved at start). Fail-safe: exits 0 (no serve) when no cluster is
# running, so it never blocks a nixos-rebuild — the failure mode that retired the
# original kind-era oneshot. Enable on any host that runs (or may run) a
# ryzen-style Talos-in-Docker spoke; the stacks bootstrap restarts this unit
# after each `talosctl cluster create` to re-point it at the new port.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.tailscaleK8sApiserver;
in {
  options.services.tailscaleK8sApiserver = {
    enable = mkEnableOption "raw-TCP Tailscale passthrough to the local Talos kube-apiserver";

    servePort = mkOption {
      type = types.port;
      default = 6443;
      description = "Tailnet port to expose the kube-apiserver on (clients connect to <host>.<tailnet>:<servePort>).";
    };

    containerPattern = mkOption {
      type = types.str;
      default = "controlplane-1$";
      description = ''
        Regex (grep -E) matched against `docker ps` names to find the Talos
        controlplane container. The default matches the talosctl convention
        `<cluster>-controlplane-1` (e.g. ryzen-controlplane-1) regardless of
        cluster name, so the same module works on any spoke host.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.tailscale-serve-k8s-apiserver = {
      description = "Expose Talos kube-apiserver on the tailnet (raw TCP passthrough for hub ArgoCD)";
      after = [ "tailscaled.service" "docker.service" ];
      wants = [ "tailscaled.service" "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "tailscale-serve-k8s-apiserver-up" ''
          set -uo pipefail
          cname="$(${pkgs.docker}/bin/docker ps --format '{{.Names}}' 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E '${cfg.containerPattern}' | ${pkgs.coreutils}/bin/head -n1)"
          if [ -z "$cname" ]; then
            echo "no Talos controlplane container (pattern '${cfg.containerPattern}'); skipping serve (cluster not up)"
            exit 0
          fi
          port="$(${pkgs.docker}/bin/docker port "$cname" 6443 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.gnused}/bin/sed 's/.*://')"
          if [ -z "$port" ]; then
            echo "$cname has no 6443 mapping yet; skipping serve"
            exit 0
          fi
          echo "exposing tailnet :${toString cfg.servePort} -> 127.0.0.1:$port (raw TCP passthrough, container $cname)"
          ${pkgs.tailscale}/bin/tailscale serve --bg --tcp=${toString cfg.servePort} "tcp://127.0.0.1:$port"
        '';
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --tcp=${toString cfg.servePort} off";
      };
    };
  };
}

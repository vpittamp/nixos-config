{ config, lib, pkgs, ... }:

let
  cfg = config.services.ryzen-stacks-watch;

  ryzenStacksWatch = pkgs.writeShellScriptBin "ryzen-stacks-watch" ''
    set -euo pipefail

    export PATH="${lib.makeBinPath [
      pkgs.coreutils
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
      pkgs.kubectl
      pkgs.podman
      pkgs.skopeo
    ]}:/etc/profiles/per-user/vpittamp/bin:/run/current-system/sw/bin:$PATH"

    stacks_dir="''${STACKS_DIR:-${cfg.stacksDir}}"
    cluster_name="''${CLUSTER_NAME:-${cfg.clusterName}}"
    debounce="''${RYZEN_STACKS_WATCH_DEBOUNCE:-${cfg.debounce}}"
    sync_wait_timeout="''${RYZEN_STACKS_SYNC_WAIT_TIMEOUT:-${cfg.syncWaitTimeout}}"
    container_engine="''${RYZEN_STACKS_CONTAINER_ENGINE:-podman}"
    seed_image_push_engine="''${RYZEN_STACKS_SEED_IMAGE_PUSH_ENGINE:-skopeo}"
    refresh_mode="''${RYZEN_STACKS_REFRESH_MODE:-affected}"

    if ! command -v idpbuilder >/dev/null 2>&1; then
      echo "idpbuilder not found in PATH" >&2
      exit 127
    fi

    exec idpbuilder stacks sync \
      --cluster-name "$cluster_name" \
      --stacks-repo "$stacks_dir" \
      --watch \
      --debounce "$debounce" \
      --container-engine "$container_engine" \
      --seed-image-push-engine "$seed_image_push_engine" \
      --refresh-mode="$refresh_mode" \
      --sync-wait-timeout="$sync_wait_timeout"
  '';
in
{
  options.services.ryzen-stacks-watch = {
    enable = lib.mkEnableOption "supervised ryzen idpbuilder stacks sync watch service";

    stacksDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/vpittamp/repos/PittampalliOrg/stacks/main";
      description = "Stacks checkout watched by idpbuilder for ryzen local GitOps iteration.";
    };

    clusterName = lib.mkOption {
      type = lib.types.str;
      default = "ryzen";
      description = "Local idpbuilder cluster name.";
    };

    debounce = lib.mkOption {
      type = lib.types.str;
      default = "2s";
      description = "Debounce duration passed to idpbuilder stacks sync --watch.";
    };

    syncWaitTimeout = lib.mkOption {
      type = lib.types.str;
      default = "3m";
      description = "Wait timeout passed to affected-app sync.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ ryzenStacksWatch ];

    # Install the unit without enabling it. Operators opt in with:
    #   systemctl --user enable --now ryzen-stacks-watch.service
    xdg.configFile."systemd/user/ryzen-stacks-watch.service".text = ''
      [Unit]
      Description=Ryzen idpbuilder affected-app stacks watch
      Documentation=file://${cfg.stacksDir}/AGENTS.md
      After=network-online.target
      StartLimitIntervalSec=60
      StartLimitBurst=5

      [Service]
      Type=simple
      WorkingDirectory=${cfg.stacksDir}
      Environment=STACKS_DIR=${cfg.stacksDir}
      Environment=XDG_CACHE_HOME=%h/.cache
      Environment=KUBECONFIG=%h/.kube/config
      ExecStart=${ryzenStacksWatch}/bin/ryzen-stacks-watch
      Restart=on-failure
      RestartSec=5s
      KillSignal=SIGINT
      TimeoutStopSec=30s

      [Install]
      WantedBy=default.target
    '';
  };
}

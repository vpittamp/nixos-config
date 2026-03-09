{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.tools.remoteKubeconfig;
in
{
  options.modules.tools.remoteKubeconfig = {
    enable = mkEnableOption "local admin kubeconfig sync owned by the stacks repo";

    stacksRepoPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/repos/PittampalliOrg/stacks/main";
      description = ''
        Local checkout of the stacks repo that owns kubeconfig synchronization.
      '';
    };

    outputDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.kube/stacks";
      description = ''
        Directory owned by the stacks kubeconfig sync process. Contains per-cluster
        kubeconfigs plus the merged config consumed by k9s.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      stacksSyncScript = "${cfg.stacksRepoPath}/deployment/scripts/tailscale/sync-local-kubeconfigs.sh";
      syncScript = pkgs.writeShellScriptBin "sync-stacks-kubeconfigs" ''
        set -euo pipefail

        if [[ ! -x "${stacksSyncScript}" ]]; then
          echo "Error: stacks kubeconfig sync script not found or not executable: ${stacksSyncScript}" >&2
          exit 1
        fi

        exec "${stacksSyncScript}" --output-dir ${lib.escapeShellArg cfg.outputDir}
      '';
    in
    {
      home.packages = [ syncScript ];

      home.activation.ensureKubeConfigDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg cfg.outputDir}
        $DRY_RUN_CMD chmod 700 ${lib.escapeShellArg cfg.outputDir}
      '';
    }
  );
}

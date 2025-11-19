{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.tools.remoteKubeconfig;
in
{
  options.modules.tools.remoteKubeconfig = {
    enable = mkEnableOption "remote kubeconfig helper backed by 1Password";

    onePasswordItem = mkOption {
      type = types.str;
      default = "remote-kubeconfig";
      description = ''
        1Password document item name (or UUID) that stores the kubeconfig YAML to merge.
      '';
    };

    targetConfig = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Filesystem path to the kubeconfig that should receive the merged content.
        Defaults to ~/.kube/config.
      '';
    };

    hostnameReplacements = mkOption {
      type = types.listOf (types.submodule ({ ... }: {
        options = {
          from = mkOption {
            type = types.str;
            description = "Hostname or identifier to search for in the downloaded kubeconfig.";
          };

          to = mkOption {
            type = types.str;
            description = "Replacement value that should be written locally.";
          };
        };
      }));
      default = [
        {
          from = "kind-operator-113";
          to = "kind-operator-3";
        }
      ];
      example = [
        { from = "cluster-old"; to = "cluster-new"; }
      ];
      description = "Optional string replacements applied to the remote kubeconfig before merging.";
    };
  };

  config = mkIf cfg.enable (
    let
      targetPath =
        if cfg.targetConfig != null
        then cfg.targetConfig
        else "${config.home.homeDirectory}/.kube/config";
      targetDir = dirOf targetPath;
      replacementsFile =
        if cfg.hostnameReplacements == []
        then null
        else pkgs.writeText "remote-kubeconfig-replacements.json" (builtins.toJSON cfg.hostnameReplacements);
      mergeScript = pkgs.writeShellScriptBin "merge-remote-kubeconfig" ''
        set -euo pipefail

        ITEM_NAME="''${1:-${cfg.onePasswordItem}}"
        TARGET=${lib.escapeShellArg targetPath}

        for cmd in kubectl op; do
          if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: required command '$cmd' not found in PATH" >&2
            exit 1
          fi
        done

        temp_kubeconfig=$(mktemp /tmp/remote-kubeconfig.XXXXXX.yaml)
        merged_config=$(mktemp /tmp/merged-kubeconfig.XXXXXX.yaml)

        cleanup() {
          rm -f "$temp_kubeconfig" "$merged_config"
        }
        trap cleanup EXIT

        echo "Fetching '$ITEM_NAME' from 1Password..."
        if ! op document get "$ITEM_NAME" --out-file "$temp_kubeconfig"; then
          echo "Failed to download kubeconfig from 1Password" >&2
          exit 1
        fi

        ${lib.optionalString (replacementsFile != null) ''
          # Apply hostname replacements to keep local cluster identifiers aligned
          ${pkgs.python3}/bin/python3 ${replacementsFile} "$temp_kubeconfig" <<'PY'
import json
import pathlib
import sys

replacements = json.load(open(sys.argv[1]))
temp_path = pathlib.Path(sys.argv[2])
data = temp_path.read_text()
updated = False

for repl in replacements:
    source = repl["from"]
    dest = repl["to"]
    if source in data:
        data = data.replace(source, dest)
        print(f"Updated hostname to {dest}")
        updated = True

if updated:
    temp_path.write_text(data)
PY
        ''}

        mkdir -p "$(dirname "$TARGET")"

        if [ -s "$TARGET" ]; then
          echo "Merging into $TARGET..."
          KUBECONFIG="$TARGET:$temp_kubeconfig" kubectl config view --flatten > "$merged_config"
          mv "$merged_config" "$TARGET"
        else
          echo "No existing kubeconfig found at $TARGET. Using remote copy."
          cp "$temp_kubeconfig" "$TARGET"
        fi

        chmod 600 "$TARGET"

        echo "Done. Available contexts:"
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

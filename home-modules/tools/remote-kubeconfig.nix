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
      default = [];  # Dynamic detection handles hostname/protocol/port automatically
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
        if ! op document get "$ITEM_NAME" --out-file "$temp_kubeconfig" --force; then
          echo "Failed to download kubeconfig from 1Password" >&2
          exit 1
        fi

        # Auto-detect online Tailscale API proxy hostname
        if command -v tailscale >/dev/null 2>&1; then
          BASE_HOSTNAME="kind-api"
          ONLINE_PROXY=$(tailscale status | grep -E '^[0-9.]+\s+'"$BASE_HOSTNAME" | grep -v 'offline' | awk '{print $2}' | head -1)

          if [ -n "$ONLINE_PROXY" ]; then
            # Extract current hostname from kubeconfig
            CURRENT_HOSTNAME=$(grep -oE '(kind-operator|kind-api)[^.]*' "$temp_kubeconfig" | head -1)

            if [ -n "$CURRENT_HOSTNAME" ] && [ "$CURRENT_HOSTNAME" != "$ONLINE_PROXY" ]; then
              # Replace hostname
              sed -i "s/$CURRENT_HOSTNAME/$ONLINE_PROXY/g" "$temp_kubeconfig"
              echo "✓ Updated hostname: $CURRENT_HOSTNAME -> $ONLINE_PROXY"

              # Fix protocol if needed (kind-api uses HTTP:8001, kind-operator uses HTTPS:443)
              if echo "$ONLINE_PROXY" | grep -q "kind-api"; then
                sed -i 's|https://|http://|g' "$temp_kubeconfig"
                sed -i 's|:443|:8001|g' "$temp_kubeconfig"
                echo "✓ Updated protocol: HTTPS:443 -> HTTP:8001"
              fi
            else
              echo "✓ Hostname already correct: $ONLINE_PROXY"
            fi
          else
            echo "WARNING: No online $BASE_HOSTNAME found in Tailscale"
          fi
        else
          echo "WARNING: tailscale command not found, skipping hostname detection"
        fi

        ${lib.optionalString (replacementsFile != null) ''
          # Apply additional static hostname replacements if configured
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
          # Put temp file FIRST so its cluster definition takes precedence
          KUBECONFIG="$temp_kubeconfig:$TARGET" kubectl config view --flatten > "$merged_config"
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

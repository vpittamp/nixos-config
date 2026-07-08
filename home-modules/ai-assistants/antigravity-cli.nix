{ config, pkgs, pkgs-unstable, lib, inputs, ... }:

# Antigravity CLI — Google's Gemini-CLI successor.
#
# Background: Google announced Antigravity 2.0 at I/O 2026 (2026-05-19) and is
# sunsetting Gemini CLI for Google AI Pro/Ultra/Free on 2026-06-18.
# https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/
#
# The CLI is now available in nixpkgs as `antigravity-cli`; consume the standard
# package from pkgs-unstable so it tracks the main toolchain update path.
#
# Follow the patterns from claude-code.nix / codex.nix as the CLI's Nix-managed
# config surface grows:
#   - wrapped binary with OTEL_RESOURCE_ATTRIBUTES and i3pm.* tags
#   - service.name routing in modules/services/grafana-alloy.nix
#   - MLflow experiment ID in configurations/{ryzen,thinkpad,hetzner}.nix
#   - hooks / skills (Antigravity CLI keeps Agent Skills, Hooks, Subagents)

let
  antigravityCliPackage = pkgs-unstable.antigravity-cli;
  workflowBuilderMcp = config.modules.aiAssistants.workflowBuilderMcp;
  workflowBuilderMcpConfig = pkgs.writeText "antigravity-workflow-builder-mcp_config.json" (
    builtins.toJSON {
      mcpServers = {
        "workflow-builder" = {
          # AGY uses serverUrl for remote MCP servers. The old Gemini-style
          # `url` key is accepted by some configs but fails silently in AGY.
          serverUrl = workflowBuilderMcp.url;
          timeoutSeconds = 300;
          strictArgumentValidation = true;
          enabledTools = [
            "get_workflow_script_spec"
            "validate_workflow_script"
            "run_workflow_script"
          ];
        };
      };
    } + "\n"
  );
in
{
  home.packages = [ antigravityCliPackage ];

  home.activation.materializeAntigravityMcpConfig = lib.mkIf workflowBuilderMcp.enable (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail

    CONFIG="$HOME/.gemini/config/mcp_config.json"
    SRC="${workflowBuilderMcpConfig}"
    TEMP="$(${pkgs.coreutils}/bin/mktemp)"

    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.gemini/config"

    if [ -L "$CONFIG" ]; then
      ${pkgs.coreutils}/bin/rm -f "$CONFIG"
    fi

    if [ -s "$CONFIG" ]; then
      if ! ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$CONFIG" "$SRC" > "$TEMP"; then
        ${pkgs.coreutils}/bin/cp "$SRC" "$TEMP"
      fi
    else
      ${pkgs.coreutils}/bin/cp "$SRC" "$TEMP"
    fi

    ${pkgs.coreutils}/bin/install -m 0644 "$TEMP" "$CONFIG"
    ${pkgs.coreutils}/bin/rm -f "$TEMP"
  '');
}

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
  # Pinned to nixpkgs master rather than pkgs-unstable: the unstable channel
  # lags master on this package (unstable 1.1.19 vs master 1.1.24 as of
  # 2026-09-02). See the nixpkgs-antigravity input in flake.nix, which carries
  # the TODO to revert this to `pkgs-unstable.antigravity-cli` once the channel
  # catches up.
  antigravityCliPackage = (import inputs.nixpkgs-antigravity {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  }).antigravity-cli;

  sharedBrowserMcp = import ./browser-mcp-shared.nix { inherit config lib pkgs; };
  nodeNpx = "${pkgs.nodejs_22}/bin/npx";
  enableBrowserMcpServers = sharedBrowserMcp.enableBrowserMcpServers;

  workflowBuilderMcp = config.modules.aiAssistants.workflowBuilderMcp;
  contextGraphMcp = config.modules.aiAssistants.contextGraphMcp;
  kiotaMcp = config.modules.aiAssistants.kiotaMcp;
  homeAssistantMcp = config.modules.aiAssistants.homeAssistantMcp;
  fabricMcp = config.modules.aiAssistants.fabricMcp;

  mcpServers =
    (lib.optionalAttrs workflowBuilderMcp.enable {
      "workflow-builder" = {
        # Use the same authenticated proxy as the other local AI clients so
        # workspace identity and optional session lineage have one contract.
        command = "${workflowBuilderMcp.proxyCommand}";
        args = [];
        timeoutSeconds = 300;
        strictArgumentValidation = true;
        enabledTools = [
          "get_workflow_context"
          "list_workflows"
          "get_workflow"
          "execute_workflow"
          "get_workflow_script_spec"
          "validate_workflow_script"
          "run_workflow_script"
          "save_workflow_script"
        ];
      };
    })
    // (lib.optionalAttrs contextGraphMcp.enable {
      # Graph memory (Neo4j context graph) over the tailnet — auth-less,
      # tailnet-scoped; see home-modules/ai-assistants/context-graph-mcp.nix.
      "context-graph" = {
        command = "${contextGraphMcp.proxyCommand}";
        args = [];
        timeoutSeconds = 120;
        strictArgumentValidation = true;
        enabledTools = contextGraphMcp.toolNames;
      };
    })
    // (lib.optionalAttrs kiotaMcp.enable {
      # Kiota generated-actions MCP (OpenAPI → action packages) over the
      # tailnet — auth-less, tailnet-scoped; see home-modules/ai-assistants/kiota-mcp.nix.
      "kiota" = {
        command = "${kiotaMcp.proxyCommand}";
        args = [];
        timeoutSeconds = 300;
        strictArgumentValidation = true;
        enabledTools = kiotaMcp.toolNames;
      };
    })
    // (lib.optionalAttrs homeAssistantMcp.enable {
      # Home Assistant MCP server (Streamable HTTP) via authenticated mcp-remote proxy.
      "homeassistant" = {
        command = "${homeAssistantMcp.proxyCommand}";
        args = [];
        timeoutSeconds = 120;
      };
    })
    // (lib.optionalAttrs fabricMcp.enable {
      # Microsoft Fabric Core MCP server (Streamable HTTP) via authenticated mcp-remote proxy.
      "fabric" = {
        command = "${fabricMcp.proxyCommand}";
        args = [];
        timeoutSeconds = 120;
      };
    })
    // (lib.optionalAttrs enableBrowserMcpServers {
      "chrome-devtools" = {
        command = nodeNpx;
        args = [
          "-y"
          "chrome-devtools-mcp@latest"
          "--browserUrl"
          "${sharedBrowserMcp.chromeDevtoolsBrowserUrl}"
        ];
        timeoutSeconds = 300;
      };
    });

  enableMcpConfig = mcpServers != { };

  antigravityMcpConfigJson = pkgs.writeText "antigravity-mcp_config.json" (
    builtins.toJSON { inherit mcpServers; } + "\n"
  );
in
{
  home.packages = [ antigravityCliPackage ];

  home.activation.materializeAntigravityMcpConfig = lib.mkIf enableMcpConfig (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail

    CONFIG="$HOME/.gemini/config/mcp_config.json"
    SRC="${antigravityMcpConfigJson}"
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

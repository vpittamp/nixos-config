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
  repoRoot = ../../.;

  # Self-contained package in packages/antigravity-cli.nix tracks upstream releases
  # ahead of nixpkgs (version 1.4.5 includes Gemini 4 Argon).
  antigravityCliPackage = pkgs.callPackage ../../packages/antigravity-cli.nix { };

  sharedBrowserMcp = import ./browser-mcp-shared.nix { inherit config lib pkgs; };
  nodeNpx = "${pkgs.nodejs}/bin/npx";
  enableBrowserMcpServers = sharedBrowserMcp.enableBrowserMcpServers;
  antigravityMcpStateRoot = "${config.xdg.stateHome}/antigravity/mcp";
  playwrightProfileDir = sharedBrowserMcp.codexPlaywrightProfileDir;
  playwrightOutputDir = "${antigravityMcpStateRoot}/playwright";
  chromiumConfig = lib.optionalAttrs enableBrowserMcpServers {
    chromiumBin = "${pkgs.google-chrome}/bin/google-chrome-stable";
  };

  workflowBuilderMcp = config.modules.aiAssistants.workflowBuilderMcp;
  contextGraphMcp = config.modules.aiAssistants.contextGraphMcp;
  kiotaMcp = config.modules.aiAssistants.kiotaMcp;
  homeAssistantMcp = config.modules.aiAssistants.homeAssistantMcp;
  fabricMcp = config.modules.aiAssistants.fabricMcp;

  mcpServers =
    {
      openaiDeveloperDocs = {
        url = "https://developers.openai.com/mcp";
        timeoutSeconds = 60;
      };
    }
    // (lib.optionalAttrs workflowBuilderMcp.enable {
      "workflow-builder" = {
        # Use the same authenticated proxy as the other local AI clients so
        # workspace identity and optional session lineage have one contract.
        command = "${workflowBuilderMcp.proxyCommand}";
        args = [];
        timeoutSeconds = 300;
      };
    })
    // (lib.optionalAttrs contextGraphMcp.enable {
      # Graph memory (Neo4j context graph) over the tailnet — auth-less,
      # tailnet-scoped; see home-modules/ai-assistants/context-graph-mcp.nix.
      "context-graph" = {
        command = "${contextGraphMcp.proxyCommand}";
        args = [];
        disabled = true;
        timeoutSeconds = 120;
      };
    })
    // (lib.optionalAttrs kiotaMcp.enable {
      # Kiota generated-actions MCP (OpenAPI → action packages) over the
      # tailnet — auth-less, tailnet-scoped; see home-modules/ai-assistants/kiota-mcp.nix.
      "kiota" = {
        command = "${kiotaMcp.proxyCommand}";
        args = [];
        timeoutSeconds = 300;
      };
    })
    // (lib.optionalAttrs homeAssistantMcp.enable {
      # Home Assistant MCP server (Streamable HTTP) via authenticated mcp-remote proxy.
      "homeassistant" = {
        command = "${homeAssistantMcp.proxyCommand}";
        args = [];
        disabled = true;
        timeoutSeconds = 120;
      };
    })
    // (lib.optionalAttrs fabricMcp.enable {
      # Microsoft Fabric Core MCP server (Streamable HTTP) via authenticated mcp-remote proxy.
      "fabric" = {
        command = "${fabricMcp.proxyCommand}";
        args = [];
        disabled = true;
        timeoutSeconds = 120;
      };
    })
    // (lib.optionalAttrs enableBrowserMcpServers {
      "chrome-devtools" = {
        command = nodeNpx;
        args = sharedBrowserMcp.chromeDevtoolsMcpArgs;
        timeoutSeconds = 120;
      };
      "playwright" = {
        command = nodeNpx;
        args = [
          "-y"
          "@playwright/mcp@latest"
          "--browser"
          "chromium"
          "--executable-path"
          "${chromiumConfig.chromiumBin}"
          "--user-data-dir"
          "${playwrightProfileDir}"
          "--output-dir"
          "${playwrightOutputDir}"
          "--viewport-size"
          "1440x900"
        ];
        disabled = true;
        env = {
          PLAYWRIGHT_SKIP_CHROMIUM_DOWNLOAD = "true";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        };
        timeoutSeconds = 120;
      };
    });

  enableMcpConfig = mcpServers != { };

  antigravityMcpConfigJson = pkgs.writeText "antigravity-mcp_config.json" (
    builtins.toJSON { inherit mcpServers; } + "\n"
  );

  sharedSkillsDir = repoRoot + "/shared-skills";
  sharedSkillEntries = if builtins.pathExists sharedSkillsDir then builtins.readDir sharedSkillsDir else {};
  sharedSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink") sharedSkillEntries;
  sharedSkillHomeFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".gemini/antigravity-cli/skills/${name}" {
        source = sharedSkillsDir + "/${name}";
        recursive = true;
        force = true;
      }
    )
    sharedSkillDirs;
in
{
  home.packages = [ antigravityCliPackage ];
  home.file = sharedSkillHomeFiles;

  home.activation.materializeAntigravityMcpConfig = lib.mkIf enableMcpConfig (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail

    CONFIG="$HOME/.gemini/config/mcp_config.json"
    SRC="${antigravityMcpConfigJson}"

    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.gemini/config"

    if [ -L "$CONFIG" ]; then
      ${pkgs.coreutils}/bin/rm -f "$CONFIG"
    fi

    # Install a fresh writable copy from the declarative Nix config so removed
    # servers and stale per-server keys (e.g. legacy `serverUrl` or `enabledTools`)
    # cannot survive across rebuilds.
    ${pkgs.coreutils}/bin/install -m 0644 "$SRC" "$CONFIG"
  '');
}

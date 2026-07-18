{ config, pkgs, lib, ... }:

# Kimi Code CLI (`kimi`) — Nix-managed config surface for the `kimi` package
# (packages/kimi-code.nix, installed via user/packages.nix).
#
# MCP servers for kimi live in ~/.kimi-code/mcp.json (user level); the CLI also
# reads project-level .kimi-code/mcp.json and Claude-style .mcp.json, both of
# which override the user-level entry of the same name.
#
#   - workflow-builder: direct streamable-HTTP entry (kimi supports `url`
#     natively). Unlike codex.nix / claude-code.nix it does NOT go through an
#     mcp-remote stdio proxy — the tailnet ingress answers plain HTTP MCP
#     without the X-Wfb-Session-Id header.
#   - chrome-devtools / playwright: same stdio servers as codex.nix, gated on a
#     real Sway session via browser-mcp-shared.nix.
#   - mlflow is intentionally absent (no longer used).
#
# Agent Skills: kimi scans ~/.agents/skills/ (cross-tool user-level dir), so the
# repo's shared-skills/ are installed there like claude-code.nix does for
# ~/.claude/skills/.
#
# The CLI rewrites mcp.json when the user runs /mcp-config, so the file must
# stay a writable regular file. Follow the antigravity-cli.nix pattern: merge
# the Nix-rendered server entries into the existing file via an activation
# script instead of a home.file symlink.

let
  repoRoot = ../../.;
  workflowBuilderMcp = config.modules.aiAssistants.workflowBuilderMcp;
  sharedBrowserMcp = import ./browser-mcp-shared.nix { inherit config lib pkgs; };
  enableBrowserMcpServers = sharedBrowserMcp.enableBrowserMcpServers;
  nodeNpx = "${pkgs.nodejs}/bin/npx";

  sharedSkillsDir = repoRoot + "/shared-skills";
  sharedSkillEntries = if builtins.pathExists sharedSkillsDir then builtins.readDir sharedSkillsDir else {};
  sharedSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink") sharedSkillEntries;
  sharedSkillHomeFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".agents/skills/${name}" {
        source = sharedSkillsDir + "/${name}";
        recursive = true;
      }
    )
    sharedSkillDirs;

  # Kimi-specific playwright state (separate from the codex profile so the two
  # CLIs never contend on one Chromium user-data-dir lock).
  kimiMcpStateRoot = "${config.xdg.stateHome}/kimi-code/mcp";
  playwrightProfileDir = "${config.xdg.dataHome}/kimi-code/browser-profiles/playwright";
  playwrightOutputDir = "${kimiMcpStateRoot}/playwright";

  mcpServers =
    lib.optionalAttrs workflowBuilderMcp.enable {
      "workflow-builder" = {
        url = workflowBuilderMcp.url;
        startupTimeoutMs = 30000;
        toolTimeoutMs = 300000;
      };
    }
    // lib.optionalAttrs enableBrowserMcpServers {
      chrome-devtools = {
        command = nodeNpx;
        args = [ "-y" "chrome-devtools-mcp@latest" "--browserUrl" "${sharedBrowserMcp.chromeDevtoolsBrowserUrl}" ];
        startupTimeoutMs = 30000;
        toolTimeoutMs = 120000;
      };
      playwright = {
        command = nodeNpx;
        args = [
          "-y"
          "@playwright/mcp@latest"
          "--browser"
          "chromium"
          "--executable-path"
          "${pkgs.chromium}/bin/chromium"
          "--user-data-dir"
          playwrightProfileDir
          "--output-dir"
          playwrightOutputDir
          "--viewport-size"
          "1440x900"
        ];
        env = {
          PLAYWRIGHT_SKIP_CHROMIUM_DOWNLOAD = "true";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        };
        startupTimeoutMs = 60000;
        toolTimeoutMs = 120000;
      };
    };

  kimiMcpConfig = pkgs.writeText "kimi-mcp.json" (
    builtins.toJSON { inherit mcpServers; } + "\n"
  );

  enableMcpConfig = mcpServers != {};
in
{
  # Install shared skills into ~/.agents/skills/ (kimi user-level scan dir).
  home.file = sharedSkillHomeFiles;

  home.activation.setupKimiMcpRuntimeDirs = lib.mkIf enableBrowserMcpServers (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail

    for dir in \
      "${playwrightProfileDir}" \
      "${playwrightOutputDir}"
    do
      ${pkgs.coreutils}/bin/mkdir -p "$dir"
      ${pkgs.coreutils}/bin/chmod 700 "$dir"
    done
  '');

  home.activation.materializeKimiMcpConfig = lib.mkIf enableMcpConfig (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail

    CONFIG="$HOME/.kimi-code/mcp.json"
    SRC="${kimiMcpConfig}"
    TEMP="$(${pkgs.coreutils}/bin/mktemp)"

    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.kimi-code"

    if [ -L "$CONFIG" ]; then
      ${pkgs.coreutils}/bin/rm -f "$CONFIG"
    fi

    if [ -s "$CONFIG" ]; then
      # Keep servers the user added via /mcp-config, but replace each
      # Nix-managed entry wholesale so stale keys (e.g. a previously
      # hand-added `headers` pair or proxy `command`) cannot survive.
      if ! ${pkgs.jq}/bin/jq -s '
        .[0] as $cur | .[1] as $new
        | ($cur * $new)
        | .mcpServers = (($cur.mcpServers // {}) + $new.mcpServers)
      ' "$CONFIG" "$SRC" > "$TEMP"; then
        ${pkgs.coreutils}/bin/cp "$SRC" "$TEMP"
      fi
    else
      ${pkgs.coreutils}/bin/cp "$SRC" "$TEMP"
    fi

    ${pkgs.coreutils}/bin/install -m 0644 "$TEMP" "$CONFIG"
    ${pkgs.coreutils}/bin/rm -f "$TEMP"
  '');
}

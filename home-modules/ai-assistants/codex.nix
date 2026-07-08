{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;
  sharedBrowserMcp = import ./browser-mcp-shared.nix { inherit config lib pkgs; };

  # MLflow tracking server (Tailscale ingress fronting mlflow.mlflow:5000 in K8s hub).
  mlflowTrackingUri = "https://mlflow-hub.tail286401.ts.net";
  workflowBuilderMcp = config.modules.aiAssistants.workflowBuilderMcp;

  sharedSkillsDir = repoRoot + "/shared-skills";
  sharedSkillEntries = if builtins.pathExists sharedSkillsDir then builtins.readDir sharedSkillsDir else {};
  sharedSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink") sharedSkillEntries;
  sharedSkillHomeFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".codex/skills/${name}" {
        source = sharedSkillsDir + "/${name}";
        recursive = true;
      }
    )
    sharedSkillDirs;

  # Auto-import custom instructions from .codex/INSTRUCTIONS.md
  # This follows the same centralization pattern as Claude Code and Gemini CLI
  instructionsFile = repoRoot + "/.codex/INSTRUCTIONS.md";
  hasInstructions = builtins.pathExists instructionsFile;
  customInstructions = if hasInstructions then builtins.readFile instructionsFile else null;

  # Browser MCP servers only make sense in a real Sway session.
  # The Codex module is also imported by container profiles, so keep docs
  # servers available there while omitting local browser integrations.
  enableBrowserMcpServers = sharedBrowserMcp.enableBrowserMcpServers;

  nodeNpx = "${pkgs.nodejs}/bin/npx";
  codexMcpStateRoot = "${config.xdg.stateHome}/codex/mcp";
  playwrightProfileDir = sharedBrowserMcp.codexPlaywrightProfileDir;
  playwrightOutputDir = "${codexMcpStateRoot}/playwright";
  chromeDevtoolsBrowserUrl = sharedBrowserMcp.chromeDevtoolsBrowserUrl;
  workflowBuilderMcpProxy = pkgs.writeShellScript "workflow-builder-mcp-proxy" ''
    set -euo pipefail

    if [ -z "''${CODEX_THREAD_ID:-}" ]; then
      echo "CODEX_THREAD_ID is required for workflow-builder MCP session attribution" >&2
      exit 64
    fi

    exec "${nodeNpx}" -y mcp-remote "${workflowBuilderMcp.url}" \
      --header "X-Wfb-Session-Id: ''${CODEX_THREAD_ID}" \
      --transport http-only
  '';

  chromiumConfig = lib.optionalAttrs enableBrowserMcpServers {
    chromiumBin = "${pkgs.chromium}/bin/chromium";
  };

  codexPackage = inputs.codex-cli-nix.packages.${pkgs.system}.default or pkgs-unstable.codex or pkgs.codex;
in

{
  # Install Codex skills into ~/.codex/skills/
  # Only shared-skills entries are declared here.
  home.file = sharedSkillHomeFiles;

  # Before home-manager re-links files, drop any SKILL.md that we previously
  # materialized as a regular file. Otherwise home-manager refuses to overwrite
  # the unmanaged file ("would be clobbered") and activation fails. The
  # materializeCodexSkills step below will re-materialize it from the new symlink.
  home.activation.preMaterializeCodexSkills = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    set -euo pipefail

    SKILLS_ROOT="$HOME/.codex/skills"
    if [ ! -d "$SKILLS_ROOT" ]; then
      exit 0
    fi

    for d in "$SKILLS_ROOT"/*; do
      [ -d "$d" ] || continue
      name="$(${pkgs.coreutils}/bin/basename "$d")"
      [ "$name" = ".system" ] && continue
      if [ -f "$d/SKILL.md" ] && [ ! -L "$d/SKILL.md" ]; then
        ${pkgs.coreutils}/bin/rm -f "$d/SKILL.md"
      fi
    done
  '';

  # Codex currently ignores skills whose `SKILL.md` is a symlink (home-manager typically
  # materializes files as symlinks into the Nix store). After home.file links are in place,
  # replace symlinked `SKILL.md` files with regular files so `codex /skills` can discover them.
  home.activation.materializeCodexSkills = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -euo pipefail

    SKILLS_ROOT="$HOME/.codex/skills"
    if [ ! -d "$SKILLS_ROOT" ]; then
      exit 0
    fi

    # Only touch user-installed skills; Codex manages `.system` itself.
    for d in "$SKILLS_ROOT"/*; do
      [ -d "$d" ] || continue
      name="$(${pkgs.coreutils}/bin/basename "$d")"
      [ "$name" = ".system" ] && continue

      if [ -L "$d/SKILL.md" ]; then
        target="$(${pkgs.coreutils}/bin/readlink -f "$d/SKILL.md" || true)"
        if [ -n "$target" ] && [ -f "$target" ]; then
          ${pkgs.coreutils}/bin/rm -f "$d/SKILL.md"
          ${pkgs.coreutils}/bin/install -m 0644 "$target" "$d/SKILL.md"
        fi
      fi
    done
  '';

  home.activation.setupCodexMcpRuntimeDirs = lib.mkIf enableBrowserMcpServers (lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -euo pipefail

    for dir in \
      "${playwrightProfileDir}" \
      "${playwrightOutputDir}"
    do
      ${pkgs.coreutils}/bin/mkdir -p "$dir"
      ${pkgs.coreutils}/bin/chmod 700 "$dir"
    done
  '');

  # Codex - Lightweight coding agent (using native home-manager module with unstable package)
  # NOTE: We do NOT use programs.codex.settings for config because the HM module
  # creates a read-only symlink into /nix/store. Codex needs to write to config.toml
  # at runtime (trust settings, plugin sync), so we generate a mutable copy via
  # activation script instead.
  programs.codex = {
    enable = true;
    package = codexPackage;

    # Custom instructions for the agent - auto-imported from .codex/INSTRUCTIONS.md
    # This follows the same centralization pattern as Claude Code and Gemini CLI
    custom-instructions = lib.mkIf hasInstructions customInstructions;

    # Settings left empty — config.toml is generated by materializeCodexConfig below
  };

  # Generate a mutable ~/.codex/config.toml so Codex can write to it at runtime.
  # The HM codex module would create a read-only Nix store symlink, which causes
  # "thread/start failed during TUI bootstrap" when Codex tries to persist trust
  # settings or sync plugins.
  home.activation.materializeCodexConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -euo pipefail
    CONFIG="$HOME/.codex/config.toml"
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.codex"

    # Remove any stale symlink from a previous HM generation
    if [ -L "$CONFIG" ]; then
      ${pkgs.coreutils}/bin/rm -f "$CONFIG"
    fi

    # Generate the full config as a regular writable file.
    # Preserve any runtime additions (extra [projects.*] entries) that Codex wrote.
    TEMP=$(${pkgs.coreutils}/bin/mktemp)
    ${pkgs.coreutils}/bin/cat > "$TEMP" << 'TOMLEOF'
approval_policy = "never"
auto_save = true
force = true
model = "gpt-5.5"
model_provider = "openai"
model_reasoning_effort = "high"
sandbox_mode = "danger-full-access"
theme = "dark"
vim_mode = true
web_search = "live"

# Codex feature flags (verified against `codex features list`, Codex 0.139.0).
# Every `stable`-stage feature (shell_snapshot, unified_exec, multi_agent, hooks,
# fast_mode, plugins, browser_use, computer_use, ...) is already default-on, so we
# only pin the few that matter for this setup. `goals` graduated to `stable` in
# 0.139; `memories`/`prevent_idle_sleep` are still `experimental`-stage (default-on)
# and pinned here so they survive future default flips. The remaining off-by-default
# flags are either `under development` (incomplete) or niche `experimental` infra
# (external_migration, network_proxy) — intentionally left off.
[features]
goals = true              # Persistent thread goals + automatic continuation (now stable)
memories = true           # Generate/use memories across conversations (/memories)
prevent_idle_sleep = true # Keep machine awake while a thread is actively running

[mcp_servers.openaiDeveloperDocs]
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 60
url = "https://developers.openai.com/mcp"

[mcp_servers.mlflow]
args = ["-y", "@us-all/mlflow-mcp"]
command = "${nodeNpx}"
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 120

[mcp_servers.mlflow.env]
MLFLOW_TRACKING_URI = "${mlflowTrackingUri}"

${lib.optionalString workflowBuilderMcp.enable ''
[mcp_servers.workflow-builder]
args = []
command = "${workflowBuilderMcpProxy}"
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 300
''}

${lib.optionalString enableBrowserMcpServers ''
[mcp_servers.chrome-devtools]
args = ["-y", "chrome-devtools-mcp@latest", "--browserUrl", "${chromeDevtoolsBrowserUrl}"]
command = "${nodeNpx}"
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 120

[mcp_servers.playwright]
args = [
    "-y",
    "@playwright/mcp@latest",
    "--browser",
    "chromium",
    "--executable-path",
    "${chromiumConfig.chromiumBin}",
    "--user-data-dir",
    "${playwrightProfileDir}",
    "--output-dir",
    "${playwrightOutputDir}",
    "--viewport-size",
    "1440x900",
]
command = "${nodeNpx}"
enabled = true
startup_timeout_sec = 60
tool_timeout_sec = 120

[mcp_servers.playwright.env]
PLAYWRIGHT_SKIP_CHROMIUM_DOWNLOAD = "true"
PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true"
''}
[projects."/etc/nixos"]
trust_level = "trusted"

[projects."/home/vpittamp"]
trust_level = "trusted"

[projects."/home/vpittamp/.claude"]
trust_level = "trusted"

[projects."/home/vpittamp/backstage-cnoe"]
trust_level = "trusted"

[projects."/home/vpittamp/mcp"]
trust_level = "trusted"

[projects."/home/vpittamp/stacks"]
trust_level = "trusted"

[sandbox_workspace_write]
exclude_slash_tmp = false
exclude_tmpdir_env_var = false
network_access = true
writable_roots = ["/home/vpittamp", "/tmp", "/etc/nixos"]

[tui]
# Show the active checkout first so Codex prompts always carry repo/branch context.
status_line = ["project_root", "git_branch", "tmux_pane", "model", "context_stats"]
TOMLEOF

    # If an existing mutable config has extra [projects.*] entries added by Codex
    # at runtime, merge them in so they aren't lost on rebuild.
    if [ -f "$CONFIG" ] && [ ! -L "$CONFIG" ]; then
      # Extract project trust entries from the old config that aren't in the new one
      (${pkgs.gnugrep}/bin/grep -E '^\[projects\.' "$CONFIG" 2>/dev/null || true) | while IFS= read -r line; do
        if ! ${pkgs.gnugrep}/bin/grep -qF "$line" "$TEMP"; then
          # Add the project header and its trust_level line
          project_key=$(echo "$line" | ${pkgs.gnused}/bin/sed 's/\[projects\."\(.*\)"\]/\1/')
          printf '\n%s\ntrust_level = "trusted"\n' "$line" >> "$TEMP"
        fi
      done
    fi

    ${pkgs.coreutils}/bin/mv "$TEMP" "$CONFIG"
    ${pkgs.coreutils}/bin/chmod 600 "$CONFIG"
  '';

  home.activation.ensureHerdrCodexIntegration = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/herdr integration install codex || true
  '';

}

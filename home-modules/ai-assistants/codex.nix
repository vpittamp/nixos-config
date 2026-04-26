{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;
  sharedBrowserMcp = import ./browser-mcp-shared.nix { inherit config lib pkgs; };

  # MCP Apps skill: create-mcp-app (from modelcontextprotocol/ext-apps)
  # Installed into ~/.codex/skills/create-mcp-app
  extApps = pkgs.fetchFromGitHub {
    owner = "modelcontextprotocol";
    repo = "ext-apps";
    rev = "30a78b60b4829282656daf10c298e2f5f6510f58";
    hash = "sha256-/9Cq/RYAOFuWu3nXORCe9jDm50D4BUI5ju4UPwBzw0A=";
  };
  createMcpAppSkillDir = extApps + "/plugins/mcp-apps/skills/create-mcp-app";

  codexSkillsDir = repoRoot + "/.codex/skills";
  hasCodexSkillsDir = builtins.pathExists codexSkillsDir;
  hasRepoCreateMcpAppSkill = hasCodexSkillsDir && builtins.pathExists (codexSkillsDir + "/create-mcp-app");

  repoSkillEntries = if hasCodexSkillsDir then builtins.readDir codexSkillsDir else {};
  repoSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink") repoSkillEntries;
  repoSkillHomeFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".codex/skills/${name}" {
        source = codexSkillsDir + "/${name}";
        recursive = true;
      }
    )
    repoSkillDirs;

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

  chromiumConfig = lib.optionalAttrs enableBrowserMcpServers {
    chromiumBin = "${pkgs.chromium}/bin/chromium";
  };

  # Codex OTEL log interceptor (Codex emits OTEL logs, not traces)
  # We synthesize traces from log events and export them via OTLP/HTTP to Alloy.
  codexOtelInterceptorHost = "127.0.0.1";
  codexOtelInterceptorPort = 4319;

  # Wrapper for codex that sets OTEL batch processor env vars for real-time export
  codexPackageRaw = inputs.codex-cli-nix.packages.${pkgs.system}.default or pkgs-unstable.codex or pkgs.codex;

  # Fix missing libcap.so.2: patch RPATH on codex-raw binary so it finds libcap
  # even when codex re-executes itself in a sandboxed subprocess (which strips LD_LIBRARY_PATH)
  codexPackage = codexPackageRaw.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.patchelf ];
    postFixup = (old.postFixup or "") + ''
      if [ -f $out/bin/codex-raw ]; then
        patchelf --add-rpath "${pkgs.libcap.lib}/lib" $out/bin/codex-raw
      fi
    '';
  });

  codexWrapperScript = pkgs.writeShellScriptBin "codex" ''
    # Feature 125: Clear NODE_OPTIONS to prevent Claude Code's interceptor from loading
    # when Codex is run from within Claude Code's Bash tool
    unset NODE_OPTIONS

    # Clear OTEL env vars that would override config.toml settings
    # Codex uses its own config file for OTEL endpoints
    unset OTEL_EXPORTER_OTLP_ENDPOINT
    unset OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
    unset OTEL_EXPORTER_OTLP_LOGS_ENDPOINT
    unset OTEL_EXPORTER_OTLP_PROTOCOL

    # Force frequent batch exports for real-time monitoring
    # OTEL_BLRP = Batch Log Record Processor settings (Rust SDK reads these)
    export OTEL_BLRP_SCHEDULE_DELAY=''${OTEL_BLRP_SCHEDULE_DELAY:-100}
    export OTEL_BLRP_MAX_EXPORT_BATCH_SIZE=''${OTEL_BLRP_MAX_EXPORT_BATCH_SIZE:-1}
    export OTEL_BLRP_MAX_QUEUE_SIZE=''${OTEL_BLRP_MAX_QUEUE_SIZE:-100}

    # Generate trace token for exact identity correlation
    export I3PM_AI_TRACE_TOKEN="$(date +%s%N)-$RANDOM"
    export I3PM_AI_HOST_ALIAS="''${I3PM_LOCAL_HOST_ALIAS:-''${HOSTNAME:-}}"
    if [ -n "''${TMUX:-}" ]; then
      if [ -z "''${TMUX_SESSION:-}" ]; then
        export TMUX_SESSION="$(${pkgs.tmux}/bin/tmux display-message -p '#S' 2>/dev/null || true)"
      fi
      if [ -z "''${TMUX_WINDOW:-}" ]; then
        export TMUX_WINDOW="$(${pkgs.tmux}/bin/tmux display-message -p '#I:#W' 2>/dev/null || true)"
      fi
      if [ -z "''${TMUX_PANE:-}" ]; then
        export TMUX_PANE="$(${pkgs.tmux}/bin/tmux display-message -p '#D' 2>/dev/null || true)"
      fi
    fi
    export I3PM_AI_PANE_KEY=""
    if [ -n "''${I3PM_CONNECTION_KEY:-}" ] && [ -n "''${TMUX_SESSION:-}" ] && [ -n "''${TMUX_WINDOW:-}" ] && [ -n "''${TMUX_PANE:-}" ]; then
      export I3PM_AI_PANE_KEY="''${I3PM_CONNECTION_KEY}::''${TMUX_SESSION}::''${TMUX_WINDOW}::''${TMUX_PANE}"
    fi
    I3PM_OTEL_REMOTE_TARGET=""
    if [ -n "''${I3PM_REMOTE_HOST:-}" ]; then
      I3PM_OTEL_REMOTE_TARGET="''${I3PM_REMOTE_HOST}:''${I3PM_REMOTE_PORT:-22}"
      if [ -n "''${I3PM_REMOTE_USER:-}" ]; then
        I3PM_OTEL_REMOTE_TARGET="''${I3PM_REMOTE_USER}@''${I3PM_OTEL_REMOTE_TARGET}"
      fi
    fi

    # Source-side correlation fix:
    # Ensure Codex OTEL resources always include process/context identity so
    # otel-ai-monitor can resolve PID -> Sway window deterministically.
    append_otel_resource_attr() {
      local key="''${1:-}"
      local value="''${2:-}"
      if [ -z "$key" ] || [ -z "$value" ]; then
        return 0
      fi

      local pair="''${key}=''${value}"
      if [ -n "''${OTEL_RESOURCE_ATTRIBUTES:-}" ]; then
        export OTEL_RESOURCE_ATTRIBUTES="''${OTEL_RESOURCE_ATTRIBUTES},''${pair}"
      else
        export OTEL_RESOURCE_ATTRIBUTES="''${pair}"
      fi
    }

    append_otel_resource_attr "process.pid" "$$"
    append_otel_resource_attr "working_directory" "''${PWD:-}"
    append_otel_resource_attr "i3pm.project_name" "''${I3PM_PROJECT_NAME:-}"
    append_otel_resource_attr "project_path" "''${I3PM_PROJECT_PATH:-''${PWD:-}}"
    append_otel_resource_attr "i3pm.project_path" "''${I3PM_PROJECT_PATH:-''${PWD:-}}"
    append_otel_resource_attr "i3pm.ai_trace_token" "''${I3PM_AI_TRACE_TOKEN:-}"
    append_otel_resource_attr "i3pm.ai.tool" "codex"
    append_otel_resource_attr "i3pm.ai.host_alias" "''${I3PM_AI_HOST_ALIAS:-}"
    append_otel_resource_attr "i3pm.ai.connection_key" "''${I3PM_CONNECTION_KEY:-}"
    append_otel_resource_attr "i3pm.ai.context_key" "''${I3PM_CONTEXT_KEY:-}"
    append_otel_resource_attr "terminal.anchor_id" "''${I3PM_TERMINAL_ANCHOR_ID:-}"
    append_otel_resource_attr "i3pm.terminal_anchor_id" "''${I3PM_TERMINAL_ANCHOR_ID:-}"
    append_otel_resource_attr "i3pm.ai.terminal_anchor_id" "''${I3PM_TERMINAL_ANCHOR_ID:-}"
    append_otel_resource_attr "terminal.execution_mode" "''${I3PM_CONTEXT_VARIANT:-''${I3PM_EXECUTION_MODE:-}}"
    append_otel_resource_attr "i3pm.execution_mode" "''${I3PM_CONTEXT_VARIANT:-''${I3PM_EXECUTION_MODE:-}}"
    append_otel_resource_attr "terminal.connection_key" "''${I3PM_CONNECTION_KEY:-}"
    append_otel_resource_attr "i3pm.connection_key" "''${I3PM_CONNECTION_KEY:-}"
    append_otel_resource_attr "terminal.context_key" "''${I3PM_CONTEXT_KEY:-}"
    append_otel_resource_attr "i3pm.context_key" "''${I3PM_CONTEXT_KEY:-}"
    append_otel_resource_attr "terminal.remote_target" "''${I3PM_OTEL_REMOTE_TARGET:-}"
    append_otel_resource_attr "i3pm.remote_target" "''${I3PM_OTEL_REMOTE_TARGET:-}"
    append_otel_resource_attr "terminal.tmux.session" "''${TMUX_SESSION:-}"
    append_otel_resource_attr "terminal.tmux.window" "''${TMUX_WINDOW:-}"
    append_otel_resource_attr "terminal.tmux.pane" "''${TMUX_PANE:-}"
    append_otel_resource_attr "i3pm.ai.tmux_session" "''${TMUX_SESSION:-}"
    append_otel_resource_attr "i3pm.ai.tmux_window" "''${TMUX_WINDOW:-}"
    append_otel_resource_attr "i3pm.ai.tmux_pane" "''${TMUX_PANE:-}"
    append_otel_resource_attr "i3pm.ai.pane_key" "''${I3PM_AI_PANE_KEY:-}"
    append_otel_resource_attr "terminal.pty" "''${TTY:-}"
    append_otel_resource_attr "host.name" "''${HOSTNAME:-}"

    exec ${codexPackage}/bin/codex "$@"
  '';
  # Preserve version attribute so home-manager uses TOML format (version >= 0.2.0)
  codexWrapped = codexWrapperScript // {
    version = codexPackage.version or "0.80.0";
  };
in

{
  # Install Codex skills into ~/.codex/skills/
  # Repo-managed skills are linked individually so they remain editable in-tree.
  home.file =
    repoSkillHomeFiles
    // (lib.optionalAttrs (!hasRepoCreateMcpAppSkill) {
      ".codex/skills/create-mcp-app" = {
        source = createMcpAppSkillDir;
        recursive = true;
      };
    });

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
  #
  # Also add minimal UI metadata for create-mcp-app (optional, but helps it look nicer in UIs).
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

    if [ -d "$SKILLS_ROOT/create-mcp-app" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "$SKILLS_ROOT/create-mcp-app/agents"

      TMP="$(${pkgs.coreutils}/bin/mktemp)"
      ${pkgs.coreutils}/bin/cat > "$TMP" <<'EOF'
interface:
  display_name: "Create MCP App"
  short_description: "Scaffold MCP Apps (tool + UI resource) using @modelcontextprotocol/ext-apps patterns"
EOF
      if [ ! -f "$SKILLS_ROOT/create-mcp-app/agents/openai.yaml" ] || ! ${pkgs.diffutils}/bin/cmp -s "$TMP" "$SKILLS_ROOT/create-mcp-app/agents/openai.yaml"; then
        ${pkgs.coreutils}/bin/install -m 0644 "$TMP" "$SKILLS_ROOT/create-mcp-app/agents/openai.yaml"
      fi
      ${pkgs.coreutils}/bin/rm -f "$TMP"
    fi
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
    package = codexWrapped; # Wrapper with OTEL batch env vars for real-time monitoring

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
model = "gpt-5.4"
model_provider = "openai"
model_reasoning_effort = "high"
notify = ["${pkgs.nodejs}/bin/node", "${repoRoot}/scripts/codex-hooks/notify.js"]
sandbox_mode = "danger-full-access"
theme = "dark"
vim_mode = true
web_search = "live"

[experimental]
background_terminal = true
shell_snapshotting = true

[mcp_servers.openaiDeveloperDocs]
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 60
url = "https://developers.openai.com/mcp"

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
[otel]
environment = "dev"
log_user_prompt = true

[otel.exporter.otlp-http]
endpoint = "http://${codexOtelInterceptorHost}:${toString codexOtelInterceptorPort}/v1/logs"
protocol = "json"

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
status_line = ["project_root", "tmux_pane", "model", "git_branch", "context_stats"]
TOMLEOF

    # If an existing mutable config has extra [projects.*] entries added by Codex
    # at runtime, merge them in so they aren't lost on rebuild.
    if [ -f "$CONFIG" ] && [ ! -L "$CONFIG" ]; then
      # Extract project trust entries from the old config that aren't in the new one
      ${pkgs.gnugrep}/bin/grep -E '^\[projects\.' "$CONFIG" 2>/dev/null | while IFS= read -r line; do
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

  # Feature 126: Codex OTEL interceptor (local user service)
  systemd.user.services.codex-otel-interceptor = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Codex OTEL interceptor (synthesize traces from Codex log events)";
      After = [ "default.target" ];
      PartOf = [ "default.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.nodejs}/bin/node ${repoRoot}/scripts/codex-otel-interceptor.js";
      Restart = "on-failure";
      RestartSec = 2;

      # Ensure predictable networking + endpoints
      Environment = [
        "CODEX_OTEL_INTERCEPTOR_HOST=${codexOtelInterceptorHost}"
        "CODEX_OTEL_INTERCEPTOR_PORT=${toString codexOtelInterceptorPort}"
        "CODEX_OTEL_INTERCEPTOR_FORWARD_BASE=http://127.0.0.1:4318"
        "LANGFUSE_ENABLED=1"
      ];

      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "codex-otel-interceptor";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}

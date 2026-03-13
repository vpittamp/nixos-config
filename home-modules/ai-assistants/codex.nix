{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;

  # MCP Apps skill: create-mcp-app (from modelcontextprotocol/ext-apps)
  # Installed into ~/.codex/skills/create-mcp-app
  extApps = pkgs.fetchFromGitHub {
    owner = "modelcontextprotocol";
    repo = "ext-apps";
    rev = "b4ea8c53a28c2950f10dcecd672edd43835dc379";
    hash = "sha256-Un+L8DjowfGyEDOwccIJkUDbApjSidDY5HhV9ZeXAnE=";
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

  # Chromium is only available on Linux
  # On Darwin, MCP servers requiring Chromium will be disabled
  enableChromiumMcpServers = pkgs.stdenv.isLinux;

  chromiumConfig = lib.optionalAttrs enableChromiumMcpServers {
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

  # Codex - Lightweight coding agent (using native home-manager module with unstable package)
  programs.codex = {
    enable = true;
    package = codexWrapped; # Wrapper with OTEL batch env vars for real-time monitoring
    # We don't need backups; overwrite the config directly
    settings.force = lib.mkForce true;

    # Custom instructions for the agent - auto-imported from .codex/INSTRUCTIONS.md
    # This follows the same centralization pattern as Claude Code and Gemini CLI
    custom-instructions = lib.mkIf hasInstructions customInstructions;

    # Configuration for codex (TOML format)
    settings = {
      # Model configuration - using latest gpt-5.4 (flagship frontier model)
      model = "gpt-5.4";
      model_provider = "openai";
      model_reasoning_effort = "high"; # Use high reasoning for complex tasks

      # Sandbox and permission settings for sandboxed environment
      # WARNING: This grants full permissions. Only use in trusted/sandboxed environments.
      sandbox_mode = "danger-full-access";  # Disable sandbox (equivalent to --yolo)
      approval_policy = "never";            # Never prompt for permissions

      # Workspace write settings (used when sandbox_mode != danger-full-access)
      sandbox_workspace_write = {
        exclude_tmpdir_env_var = false;  # Allow temp directory access
        exclude_slash_tmp = false;       # Allow /tmp access
        network_access = true;           # Enable network access
        writable_roots = [               # Additional writable locations
          "/home/vpittamp"
          "/tmp"
          "/etc/nixos"
        ];
      };

      # Project trust settings - mark all dev directories as trusted
      projects = {
        "/home/vpittamp/mcp" = {
          trust_level = "trusted";
        };
        "/home/vpittamp/.claude" = {
          trust_level = "trusted";
        };
        "/home/vpittamp/backstage-cnoe" = {
          trust_level = "trusted";
        };
        "/home/vpittamp/stacks" = {
          trust_level = "trusted";
        };
        "/etc/nixos" = {
          trust_level = "trusted";
        };
        "/home/vpittamp" = {
          trust_level = "trusted";
        };
      };

      # Additional settings
      auto_save = true;
      theme = "dark";
      vim_mode = true;
      # Web search: "live", "cached", or "disabled" (top-level, replaces deprecated features.web_search_request)
      web_search = "live";

      # rmcp_client is REQUIRED for MCP server support
      features = {
        rmcp_client = true;  # Required for MCP servers to work
      };

      # Status line configuration for project context and monitoring
      tui = {
        status_line = [
          "project_root"
          "tmux_pane"
          "model"
          "git_branch"
          "context_stats"
        ];
      };

      # Experimental features
      experimental = {
        shell_snapshotting = true;   # Snapshot shell env to avoid re-running login scripts
        background_terminal = true;  # Run long-running terminal commands in background
      };

      # Feature 123: OpenTelemetry configuration for OTLP export
      # Sends logs to local interceptor which synthesizes traces and forwards to Alloy
      otel = {
        environment = "dev";
        log_user_prompt = true;  # Enable for debugging (disable in production)
        exporter = {
          otlp-http = {
            # Send Codex OTLP *logs* to local interceptor (synthesizes traces + forwards)
            endpoint = "http://${codexOtelInterceptorHost}:${toString codexOtelInterceptorPort}/v1/logs";
            # NOTE: traces_endpoint removed - interceptor synthesizes traces from logs
            # Native Codex traces are low-signal; let interceptor create proper OpenInference spans
            protocol = "json";  # Use JSON for compatibility with our receiver
          };
        };
      };

      # Codex hook: external program invoked on certain lifecycle events.
      # Used for explicit Turn completion boundaries (agent-turn-complete).
      notify = [
        "${pkgs.nodejs}/bin/node"
        "${repoRoot}/scripts/codex-hooks/notify.js"
      ];

      # MCP Servers configuration
      # Note: Codex does NOT support a `disabled` flag for MCP servers
      # Servers are either defined (always active) or not defined (unavailable)
      # Only Linux is supported due to Chromium dependency
      mcp_servers = {
        # Mastra Docs MCP server - access Mastra's full documentation
        # Provides tools for querying Mastra framework docs, examples, and API reference
        # Enable via `codex mcp enable mastra-docs` when working on Mastra projects
        # See: https://mastra.ai/docs/getting-started/mcp-docs-server
        mastra-docs = {
          command = "npx";
          args = [
            "-y"
            "@mastra/mcp-docs-server@latest"
          ];
          enabled = true;
          startup_timeout_sec = 30;
          tool_timeout_sec = 60;
        };
      } // lib.optionalAttrs enableChromiumMcpServers {
        # Playwright MCP server for browser automation
        playwright = {
          command = "npx";
          args = [
            "-y"
            "@playwright/mcp@latest"
            "--isolated"
            "--browser"
            "chromium"
            "--executable-path"
            chromiumConfig.chromiumBin
          ];
          env = {
            # Skip downloading Chromium since we use system package
            PLAYWRIGHT_SKIP_CHROMIUM_DOWNLOAD = "true";
            PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
          };
          enabled = true;
          startup_timeout_sec = 30;
          tool_timeout_sec = 60;
        };

        # Chrome DevTools MCP server for browser debugging and performance analysis
        chrome-devtools = {
          command = "npx";
          args = [
            "-y"
            "chrome-devtools-mcp@latest"
            "--isolated"
            "--headless"
            "--executablePath"
            chromiumConfig.chromiumBin
          ];
          enabled = true;
          startup_timeout_sec = 30;  # 30 seconds for browser startup
          tool_timeout_sec = 60;     # 60 seconds for tool operations
        };
      };
    };
  };

  # Feature 123: Create OTEL config section via activation script
  # The home-manager codex module filters unknown settings, so we append OTEL config manually
  home.activation.appendCodexOtelConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    CONFIG="$HOME/.codex/config.toml"
    if [ -L "$CONFIG" ]; then
      # Config is a symlink to nix store - copy and modify
      TEMP=$(${pkgs.coreutils}/bin/mktemp)
      ${pkgs.coreutils}/bin/cat "$CONFIG" > "$TEMP"

      # Feature 126: Ensure notify hook is configured at the TOML root.
      # (In TOML, root keys must appear before any `[table]` headers.)
      if ! ${pkgs.gnugrep}/bin/grep -q '^notify[[:space:]]*=' "$TEMP"; then
        TEMP2=$(${pkgs.coreutils}/bin/mktemp)
        ${pkgs.gawk}/bin/awk \
          -v line='notify = ["${pkgs.nodejs}/bin/node", "${repoRoot}/scripts/codex-hooks/notify.js"]' \
          'BEGIN{inserted=0} /^[[:space:]]*\\[/{ if(!inserted){ print line; inserted=1 } } { print } END{ if(!inserted){ print line } }' \
          "$TEMP" > "$TEMP2"
        ${pkgs.coreutils}/bin/mv "$TEMP2" "$TEMP"
      fi

      # Only add OTEL if not already present
      if ! ${pkgs.gnugrep}/bin/grep -q '^\[otel\]' "$TEMP"; then
        ${pkgs.coreutils}/bin/cat >> "$TEMP" << 'EOF'

# Feature 123: OpenTelemetry configuration for OTLP export
# NOTE: traces_endpoint removed - interceptor synthesizes traces from logs
[otel]
environment = "dev"
log_user_prompt = true

[otel.exporter.otlp-http]
endpoint = "http://${codexOtelInterceptorHost}:${toString codexOtelInterceptorPort}/v1/logs"
protocol = "json"
EOF
      fi

      # Replace symlink with patched file
      ${pkgs.coreutils}/bin/rm -f "$CONFIG"
      ${pkgs.coreutils}/bin/mv "$TEMP" "$CONFIG"
      ${pkgs.coreutils}/bin/chmod 600 "$CONFIG"
    fi
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

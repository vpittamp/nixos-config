{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;

  # MCP Apps skill: create-mcp-app (from modelcontextprotocol/ext-apps)
  # Installed into ~/.claude/skills/create-mcp-app
  extApps = pkgs.fetchFromGitHub {
    owner = "modelcontextprotocol";
    repo = "ext-apps";
    rev = "30a78b60b4829282656daf10c298e2f5f6510f58";
    hash = "sha256-/9Cq/RYAOFuWu3nXORCe9jDm50D4BUI5ju4UPwBzw0A=";
  };
  createMcpAppSkillDir = extApps + "/plugins/mcp-apps/skills/create-mcp-app";

  # Use claude-code from the dedicated flake for latest version
  # Fall back to nixpkgs-unstable if flake not available
  baseClaudeCode = inputs.claude-code-nix.packages.${pkgs.system}.claude-code or pkgs-unstable.claude-code or pkgs.claude-code;

  # Wrapped Claude Code with payload interceptor and Chrome integration
  claudeCodePackage = pkgs.symlinkJoin {
    name = "claude-code-wrapped";
    paths = [ baseClaudeCode ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --run 'export I3PM_AI_TRACE_TOKEN="''$(date +%s%N)-''$RANDOM"' \
        --run 'append_otel_resource_attr() { local key="''${1:-}"; local value="''${2:-}"; [ -n "$key" ] && [ -n "$value" ] || return 0; local pair="''${key}=''${value}"; if [ -n "''${OTEL_RESOURCE_ATTRIBUTES:-}" ]; then export OTEL_RESOURCE_ATTRIBUTES="''${OTEL_RESOURCE_ATTRIBUTES},''${pair}"; else export OTEL_RESOURCE_ATTRIBUTES="''${pair}"; fi; }; I3PM_OTEL_REMOTE_TARGET=""; I3PM_AI_HOST_ALIAS="''${I3PM_LOCAL_HOST_ALIAS:-''${HOSTNAME:-}}"; if [ -n "''${TMUX:-}" ]; then if [ -z "''${TMUX_SESSION:-}" ]; then export TMUX_SESSION="$(${pkgs.tmux}/bin/tmux display-message -p '"'"'#S'"'"' 2>/dev/null || true)"; fi; if [ -z "''${TMUX_WINDOW:-}" ]; then export TMUX_WINDOW="$(${pkgs.tmux}/bin/tmux display-message -p '"'"'#I:#W'"'"' 2>/dev/null || true)"; fi; if [ -z "''${TMUX_PANE:-}" ]; then export TMUX_PANE="$(${pkgs.tmux}/bin/tmux display-message -p '"'"'#D'"'"' 2>/dev/null || true)"; fi; fi; I3PM_AI_PANE_KEY=""; if [ -n "''${I3PM_REMOTE_HOST:-}" ]; then I3PM_OTEL_REMOTE_TARGET="''${I3PM_REMOTE_HOST}:''${I3PM_REMOTE_PORT:-22}"; if [ -n "''${I3PM_REMOTE_USER:-}" ]; then I3PM_OTEL_REMOTE_TARGET="''${I3PM_REMOTE_USER}@''${I3PM_OTEL_REMOTE_TARGET}"; fi; fi; if [ -n "''${I3PM_CONNECTION_KEY:-}" ] && [ -n "''${TMUX_SESSION:-}" ] && [ -n "''${TMUX_WINDOW:-}" ] && [ -n "''${TMUX_PANE:-}" ]; then I3PM_AI_PANE_KEY="''${I3PM_CONNECTION_KEY}::''${TMUX_SESSION}::''${TMUX_WINDOW}::''${TMUX_PANE}"; fi; append_otel_resource_attr "process.pid" "$$"; append_otel_resource_attr "working_directory" "''${PWD:-}"; append_otel_resource_attr "i3pm.project_name" "''${I3PM_PROJECT_NAME:-}"; append_otel_resource_attr "project_path" "''${I3PM_PROJECT_PATH:-''${PWD:-}}"; append_otel_resource_attr "i3pm.project_path" "''${I3PM_PROJECT_PATH:-''${PWD:-}}"; append_otel_resource_attr "i3pm.ai_trace_token" "''${I3PM_AI_TRACE_TOKEN:-}"; append_otel_resource_attr "i3pm.ai.tool" "claude-code"; append_otel_resource_attr "i3pm.ai.host_alias" "''${I3PM_AI_HOST_ALIAS:-}"; append_otel_resource_attr "i3pm.ai.connection_key" "''${I3PM_CONNECTION_KEY:-}"; append_otel_resource_attr "i3pm.ai.context_key" "''${I3PM_CONTEXT_KEY:-}"; append_otel_resource_attr "terminal.anchor_id" "''${I3PM_TERMINAL_ANCHOR_ID:-}"; append_otel_resource_attr "i3pm.terminal_anchor_id" "''${I3PM_TERMINAL_ANCHOR_ID:-}"; append_otel_resource_attr "i3pm.ai.terminal_anchor_id" "''${I3PM_TERMINAL_ANCHOR_ID:-}"; append_otel_resource_attr "terminal.execution_mode" "''${I3PM_CONTEXT_VARIANT:-''${I3PM_EXECUTION_MODE:-}}"; append_otel_resource_attr "i3pm.execution_mode" "''${I3PM_CONTEXT_VARIANT:-''${I3PM_EXECUTION_MODE:-}}"; append_otel_resource_attr "terminal.connection_key" "''${I3PM_CONNECTION_KEY:-}"; append_otel_resource_attr "i3pm.connection_key" "''${I3PM_CONNECTION_KEY:-}"; append_otel_resource_attr "terminal.context_key" "''${I3PM_CONTEXT_KEY:-}"; append_otel_resource_attr "i3pm.context_key" "''${I3PM_CONTEXT_KEY:-}"; append_otel_resource_attr "terminal.remote_target" "''${I3PM_OTEL_REMOTE_TARGET:-}"; append_otel_resource_attr "i3pm.remote_target" "''${I3PM_OTEL_REMOTE_TARGET:-}"; append_otel_resource_attr "terminal.tmux.session" "''${TMUX_SESSION:-}"; append_otel_resource_attr "terminal.tmux.window" "''${TMUX_WINDOW:-}"; append_otel_resource_attr "terminal.tmux.pane" "''${TMUX_PANE:-}"; append_otel_resource_attr "i3pm.ai.tmux_session" "''${TMUX_SESSION:-}"; append_otel_resource_attr "i3pm.ai.tmux_window" "''${TMUX_WINDOW:-}"; append_otel_resource_attr "i3pm.ai.tmux_pane" "''${TMUX_PANE:-}"; append_otel_resource_attr "i3pm.ai.pane_key" "''${I3PM_AI_PANE_KEY:-}"; append_otel_resource_attr "terminal.pty" "''${TTY:-}"; append_otel_resource_attr "host.name" "''${HOSTNAME:-}"' \
        --set CLAUDE_CODE_ENABLE_TELEMETRY "1" \
        --set OTEL_LOGS_EXPORTER "otlp" \
        --set OTEL_METRICS_EXPORTER "otlp" \
        --set OTEL_TRACES_EXPORTER "otlp" \
        --set OTEL_EXPORTER_OTLP_PROTOCOL "http/protobuf" \
        --set OTEL_EXPORTER_OTLP_ENDPOINT "http://localhost:4320" \
        --set NODE_OPTIONS "--require ${repoRoot}/scripts/minimal-otel-interceptor.js" \
        --add-flags "--chrome"
    '';
  };

  # Claude Desktop for Linux (unofficial community package)
  # Use claude-desktop-with-fhs for MCP server support (npx, uvx, docker)
  claudeDesktopPackage = inputs.claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs or null;

  # Claude Code's home-manager module has Chromium dependencies that break on Darwin
  # Only enable on Linux where Chromium is available
  enableClaudeCode = pkgs.stdenv.isLinux;

  # Auto-import all .md files from .claude/commands/ as slash commands
  # This creates an attribute set where keys are command names (without .md)
  # and values are the file contents
  commandFiles = builtins.readDir (repoRoot + "/.claude/commands");
  commands = lib.mapAttrs'
    (name: type:
      lib.nameValuePair
        (lib.removeSuffix ".md" name)
        (builtins.readFile (repoRoot + "/.claude/commands/${name}"))
    )
    (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".md" n) commandFiles);
  # Auto-import skills from .claude/skills/ directory (repo-managed).
  skillsDir = repoRoot + "/.claude/skills";
  hasSkillsDir = builtins.pathExists skillsDir;
  hasRepoCreateMcpAppSkill = hasSkillsDir && builtins.pathExists (skillsDir + "/create-mcp-app");

  repoSkillEntries = if hasSkillsDir then builtins.readDir skillsDir else {};
  repoSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink") repoSkillEntries;
  repoSkillHomeFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".claude/skills/${name}" {
        source = skillsDir + "/${name}";
        recursive = true;
      }
    )
    repoSkillDirs;
in
lib.mkIf enableClaudeCode {
  # Install skills into ~/.claude/skills/
  # Repo-managed skills are linked individually so they remain editable in-tree.
  home.file =
    repoSkillHomeFiles
    // (lib.optionalAttrs (!hasRepoCreateMcpAppSkill) {
      ".claude/skills/create-mcp-app" = {
        source = createMcpAppSkillDir;
        recursive = true;
      };
    })
    // {
      # Force PATH-preferred ~/.local/bin/claude to the wrapped Nix binary so
      # telemetry/session hooks are deterministic across shells and hosts.
      ".local/bin/claude" = {
        source = "${claudeCodePackage}/bin/claude";
        executable = true;
        force = true;
      };

      # LSP plugin for Claude Code — provides code intelligence via language servers
      # All binaries are Nix-managed and available in PATH
      ".claude/plugins/nix-lsp/.claude-plugin/plugin.json".text = builtins.toJSON {
        name = "nix-lsp";
        description = "Language servers for Python, TypeScript, Nix, QML, and YAML";
        version = "1.0.0";
      };
      ".claude/plugins/nix-lsp/.lsp.json".text = builtins.toJSON {
        python = {
          command = "${pkgs.pyright}/bin/pyright-langserver";
          args = [ "--stdio" ];
          extensionToLanguage = {
            ".py" = "python";
            ".pyi" = "python";
          };
        };
        typescript = {
          command = "${pkgs.nodePackages_latest.typescript-language-server}/bin/typescript-language-server";
          args = [ "--stdio" ];
          extensionToLanguage = {
            ".ts" = "typescript";
            ".tsx" = "typescriptreact";
            ".js" = "javascript";
            ".jsx" = "javascriptreact";
          };
        };
        nix = {
          command = "${pkgs.nil}/bin/nil";
          args = [];
          extensionToLanguage = {
            ".nix" = "nix";
          };
        };
        qml = {
          command = "${pkgs.kdePackages.qtdeclarative}/bin/qmlls";
          args = [];
          extensionToLanguage = {
            ".qml" = "qml";
          };
        };
        yaml = {
          command = "${pkgs.nodePackages_latest.yaml-language-server}/bin/yaml-language-server";
          args = [ "--stdio" ];
          extensionToLanguage = {
            ".yaml" = "yaml";
            ".yml" = "yaml";
          };
        };
      };
    };

  # Patch Claude Code plugin scripts for NixOS compatibility
  # Problem: Plugins from the marketplace use #!/bin/bash which doesn't exist on NixOS
  # Solution: Replace with #!/usr/bin/env bash which is portable
  # This runs on every home-manager activation to handle plugin updates
  home.activation.patchClaudePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PLUGIN_CACHE="$HOME/.claude/plugins/cache/claude-code-plugins"
    if [ -d "$PLUGIN_CACHE" ]; then
      run ${pkgs.findutils}/bin/find "$PLUGIN_CACHE" -name "*.sh" -type f \
        -exec ${pkgs.gnused}/bin/sed -i 's|^#!/bin/bash|#!/usr/bin/env bash|' {} \;
    fi
  '';


  # Feature 123: OTEL environment variables for Claude Code telemetry
  # These MUST be session variables (not just settings.env) because the OTEL SDK
  # initializes when Claude Code starts, before it reads settings.json.
  # settings.env only affects subprocesses, not Claude Code itself.
  #
  # Feature 132: Langfuse integration environment variables
  # LANGFUSE_* variables are optional - if set, traces will include Langfuse-specific
  # attributes for proper observation mapping in Langfuse UI.
  home.sessionVariables = {
    CLAUDE_CODE_ENABLE_TELEMETRY = "1";
    OTEL_LOGS_EXPORTER = "otlp";
    OTEL_METRICS_EXPORTER = "otlp";
    OTEL_TRACES_EXPORTER = "otlp";
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4320";
    OTEL_METRIC_EXPORT_INTERVAL = "60000";
    OTEL_METRIC_EXPORT_TIMEOUT = "30000";
    OTEL_LOGS_EXPORT_INTERVAL = "5000";
    OTEL_METRICS_INCLUDE_SESSION_ID = "true";
    OTEL_LOG_USER_PROMPTS = "1";
    # Delta temporality for better memory efficiency with session metrics
    OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "delta";

    # Feature 132: Langfuse integration
    # These variables are used by the interceptor to add Langfuse-specific attributes
    # LANGFUSE_ENABLED - Set to "1" to enable Langfuse-specific attribute emission
    # LANGFUSE_USER_ID - Optional user identifier for Langfuse traces
    # LANGFUSE_SESSION_ID - Optional override for session grouping (defaults to Claude session.id)
    # LANGFUSE_TAGS - Optional JSON array of tags, e.g., '["production", "my-feature"]'
    LANGFUSE_ENABLED = "1";

    # Experimental: Agent Teams - multi-agent coordination
    # Session variable ensures it's set before Claude Code initializes
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
  };

  # Chromium is installed via programs.chromium in tools/chromium.nix
  # No need to install it here - avoids conflicts

  # Install Claude Desktop if available
  # Provides native desktop app with git worktree support for parallel sessions
  home.packages = lib.optionals (claudeDesktopPackage != null) [
    claudeDesktopPackage
  ];

  # Claude Code configuration with home-manager module
  # Only enabled on Linux due to Chromium dependencies in the module
  programs.claude-code = {
    enable = true;
    package = claudeCodePackage;

    # Auto-imported slash commands from .claude/commands/
    # All .md files are automatically discovered and loaded
    commands = commands;

    # Settings for Claude Code
    settings = {
      # Plugin configuration
      # Register the official Anthropic plugin marketplace
      extraKnownMarketplaces = {
        claude-code-plugins = {
          source = {
            source = "github";
            repo = "anthropics/claude-code";
          };
        };
      };

      # Plugins - disabled by default to reduce token overhead
      # Enable interactively when needed via /plugins command
      enabledPlugins = {
        # Ralph Wiggum - autonomous iterative development loops
        # Usage: /ralph-loop "task description" --max-iterations 20 --completion-promise "DONE"
        # Cancel: /cancel-ralph
        "ralph-wiggum@claude-code-plugins" = false;

        # Agent SDK Dev - development tools for building Claude Code agents
        "agent-sdk-dev@claude-code-plugins" = false;

        # LSP plugin - Nix-managed language servers for code intelligence
        "nix-lsp" = true;
      };

      # Experimental: Agent Teams - coordinate multiple Claude instances as a team
      # Enables TeammateTool, spawnTeam, SendMessage for parallel agent collaboration
      # Modes: "auto" (tmux if available, else in-process), "in-process", "tmux"
      teammateMode = "auto";

      # Status line configuration for project context and monitoring
      statusLine = {
        type = "command";
        # Use a Nix-managed script that reads stdin (JSON) and environment variables
        command = "${pkgs.writeShellScript "claude-statusline.sh" ''
          input=$(cat)
          MODEL=$(${pkgs.jq}/bin/jq -r '.model.display_name' <<< \"$input\")
          PERCENT=$(${pkgs.jq}/bin/jq -r '.context_window.usage_percentage' <<< \"$input\")
          COST=$(${pkgs.jq}/bin/jq -r '.session_cost.total_cost' <<< \"$input\")
          PROJECT=\"''${I3PM_PROJECT_NAME:-''${PWD##*/}}\"
          TMUX_STR=\"''${TMUX_PANE:+ | Tmux: ''$TMUX_PANE}\"
          echo -e \"\\e[34m[Proj: $PROJECT$TMUX_STR]\\e[0m | \\e[32m$MODEL\\e[0m | Ctx: $PERCENT% | \\$$COST\"
        ''}";
      };

      # Model selection removed - will use default or user's choice
      theme = "dark";
      editorMode = "vim";
      autoCompactEnabled = true;
      todoFeatureEnabled = true;
      verbose = true;
      autoUpdates = true;
      autoConnectIde = true;
      includeCoAuthoredBy = true;
      env = {
        # Feature 123: Full OpenTelemetry configuration for OTLP export
        # Enables native telemetry to otel-ai-monitor service
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_LOGS_EXPORTER = "otlp";
        OTEL_METRICS_EXPORTER = "otlp";
        OTEL_TRACES_EXPORTER = "otlp";
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
        OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4320";
        # Export intervals - safer for Node.js SDK
        OTEL_METRIC_EXPORT_INTERVAL = "60000";  # 60 seconds
        OTEL_METRIC_EXPORT_TIMEOUT = "30000";   # 30 seconds
        OTEL_LOGS_EXPORT_INTERVAL = "5000";     # 5 seconds (default)
        # Include session ID in metrics for correlation
        OTEL_METRICS_INCLUDE_SESSION_ID = "true";
        OTEL_LOG_USER_PROMPTS = "1";
        # Fix for M1 Apple Silicon: Built-in ripgrep has jemalloc page size incompatibility
        # Apple Silicon uses 16KB pages, jemalloc expects 4KB pages
        # Use system ripgrep instead (available via home-manager)
        USE_BUILTIN_RIPGREP = "0";
        # Experimental: Agent Teams - enables TeammateTool for multi-agent coordination
        # Multiple Claude instances work in parallel with shared task lists and peer messaging
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
      };

      # Hooks - Commands that run in response to Claude Code events
      # See: https://docs.claude.com/en/docs/claude-code/hooks
      #
      # Security Best Practices (per documentation):
      # 1. Use absolute paths for scripts
      # 2. Always quote shell variables with "$VAR" not $VAR
      # 3. Validate and sanitize inputs in hook scripts
      # 4. Set explicit timeouts for commands
      # 5. Use external scripts for complex logic (maintainability)
      #
      # Feature 131: Session metadata hook (bridges Claude Code session.id → interceptor traces)
      # SessionStart: Persist Claude Code session_id (UUID) for the Node interceptor
      # SessionEnd: Clean up the persisted session metadata file
      hooks = {
        # UserPromptSubmit: Establish deterministic Claude turn boundaries before
        # the Stop hook fires so the side panel can retain the explicit stopped
        # notification stage instead of falling back to idle.
        UserPromptSubmit = [{
          hooks = [{
            type = "command";
            command = "${repoRoot}/scripts/claude-hooks/otel-user-prompt-submit.sh";
            timeout = 5;
          }];
        }];

        # SessionStart: Persist Claude Code session_id (UUID) for trace correlation
        # This enables the OTEL interceptor to discover the session ID and export
        # spans with process.pid for deterministic window correlation.
        # Note: New hooks format (Claude Code 2.x) requires hooks array wrapper
        SessionStart = [{
          hooks = [{
            type = "command";
            command = "${repoRoot}/scripts/claude-hooks/otel-session-start.sh";
            timeout = 5;
          }];
        }];

        # SessionEnd: Clean up the persisted session metadata file
        SessionEnd = [{
          hooks = [{
            type = "command";
            command = "${repoRoot}/scripts/claude-hooks/otel-session-end.sh";
            timeout = 5;
          }];
        }];

        # Stop: Unified "finished" notification when Claude Code completes a turn
        # Sends desktop notification with "Return to Terminal" action
        Stop = [{
          hooks = [{
            type = "command";
            command = "${repoRoot}/scripts/claude-hooks/finished.sh";
            timeout = 10;
          }];
        }];
      };

      # Permissions configuration for sandboxed environment
      # WARNING: This grants broad permissions. Only use in trusted/sandboxed environments.
      # Note: Wildcards and patterns have been removed per Claude Code 2.0.11 requirements
      permissions = {
        allow = [
          # Core file and code operations (no parentheses for broad access)
          "Read"
          "Write"
          "Edit"
          "Glob"
          "Grep"

          # Bash and system operations (no parentheses for all commands)
          "Bash"

          # Notebook operations
          "NotebookEdit"

          # Task and planning tools
          "Task"
          "TodoWrite"

          # Web operations (no wildcards - allows all searches/fetches)
          "WebSearch"
          "WebFetch"

          # Background bash operations
          "BashOutput"
          "KillShell"

          # Slash commands
          "SlashCommand"

          # MCP Server permissions
          "mcp__claude-in-chrome"  # Claude-in-Chrome browser automation (built-in via --chrome)
        ];
      };

      # Custom memories - persistent instructions for Claude Code
      # These override default behaviors and provide environment-specific guidance
      memories = [
        {
          name = "extended-thinking-default";
          content = ''
            # Extended Thinking Default Behavior

            ## Always Use Extended Thinking

            You should use extended thinking by default for all non-trivial tasks. Extended thinking gives you enhanced reasoning capabilities for complex tasks by allowing you to reason step-by-step before delivering your final answer.

            ### When to Use Extended Thinking

            **ALWAYS use extended thinking for:**
            - Code implementation and refactoring
            - Debugging and error analysis
            - Architecture decisions
            - Complex configuration changes
            - Multi-step tasks
            - Any task requiring careful planning

            **You may skip extended thinking for:**
            - Simple file reads
            - Basic questions with obvious answers
            - Single-line changes
            - Confirmations and acknowledgments

            ### Thinking Budget Guidelines

            - **Standard tasks**: Use "think" level (moderate budget)
            - **Complex tasks** (multi-file changes, debugging): Use "think hard" level
            - **Critical tasks** (architecture, security, major refactoring): Use "think harder" or "ultrathink" level

            ### Benefits

            Extended thinking enables:
            - More thorough analysis of complex problems
            - Better consideration of edge cases
            - Improved code quality and correctness
            - Reduced errors in multi-step operations

            ### Implementation Note

            This is the user's preference for thorough, well-reasoned responses. Always err on the side of using extended thinking rather than rushing to an answer.
          '';
        }
        {
          name = "nixos-interactive-bash";
          content = ''
            # NixOS/Home-Manager Interactive Bash Environment

            ## Critical: Bash Alias and Function Access

            You are operating in a NixOS environment where the user's bash configuration is managed declaratively via home-manager. The user has custom aliases, functions, and environment setup defined in home-manager modules (specifically in `home-modules/shell/bash.nix`).

            ### The Problem
            When you execute bash commands using the `Bash` tool, you run in a **non-interactive shell** that does NOT load:
            - `~/.bashrc`
            - User-defined aliases
            - User-defined functions
            - Custom environment variables from home-manager
            - Interactive shell initialization

            ### The Solution
            To access the user's bash environment (aliases, functions, environment variables), you MUST use:

            ```bash
            bash -i -c "command-here"
            ```

            The `-i` flag makes bash interactive, which loads `~/.bashrc` and all home-manager bash configuration.

            ### Examples of User Aliases That Require Interactive Bash

            From `home-modules/shell/bash.nix`, these aliases are available:

            **NixOS Rebuild Aliases:**
            - `nh-hetzner` → `nh os switch --hostname hetzner -- --option eval-cache false`
            - `nh-hetzner-fresh` → `nh os switch --hostname hetzner --refresh -- --option eval-cache false`
            - `nh-m1` → `nh os switch --hostname m1 --impure -- --option eval-cache false`
            - `nh-m1-fresh` → `nh os switch --hostname m1 --impure --refresh -- --option eval-cache false`
            - `nh-wsl` → `nh os switch --hostname wsl -- --option eval-cache false`
            - `nh-wsl-fresh` → `nh os switch --hostname wsl --refresh -- --option eval-cache false`

            **Other Useful Aliases:**
            - `ll` → `ls -alF`
            - `la` → `ls -A`
            - `l` → `ls -CF`
            - `grep` → `grep --color=auto`
            - `plasma-export` → `/etc/nixos/scripts/plasma-rc2nix.sh`

            ### When to Use Interactive Bash

            **ALWAYS use `bash -i -c` when:**
            1. Running any of the user's custom aliases (like `nh-hetzner-fresh`)
            2. The user asks you to run a command that might be an alias
            3. You need access to environment variables set in bashrc
            4. You need access to bash functions defined by the user
            5. The command relies on shell customization from home-manager

            **Use regular `bash -c` (or direct Bash tool) when:**
            1. Running standard Unix commands (`ls`, `grep`, `find`, etc.)
            2. The command is known to be a binary in PATH
            3. No aliases or functions are involved

            ### Warning: Terminal Output
            Interactive bash will produce these harmless warnings:
            ```
            bash: cannot set terminal process group (-1): Inappropriate ioctl for device
            bash: no job control in this shell
            ```

            These are **expected and safe to ignore** - they occur because Claude Code's bash execution isn't a real terminal.

            ### Checking for Aliases
            If you're unsure whether a command is an alias, you can check:

            ```bash
            bash -i -c "type command-name"
            ```

            This will tell you if it's an alias, function, or binary.

            ### Example Usage

            ❌ **WRONG** (won't work for aliases):
            ```bash
            nh-hetzner-fresh
            ```
            Result: `command not found`

            ✅ **CORRECT**:
            ```bash
            bash -i -c "nh-hetzner-fresh"
            ```
            Result: Alias expands and runs successfully

            ### Environment Details

            - **OS**: NixOS (Linux)
            - **Shell**: Bash (managed by home-manager)
            - **Configuration**: Declarative via `/etc/nixos/home-modules/shell/bash.nix`
            - **User**: vpittamp
            - **Home Directory**: /home/vpittamp
            - **Bashrc Location**: ~/.bashrc (generated by home-manager)

            ### Additional Context

            The user's bash configuration includes:
            - Starship prompt integration
            - FZF keybindings and completion
            - Atuin history search
            - Custom aliases for NixOS management
            - Git shortcuts
            - 1Password integration
            - Project-specific environment setup

            All of these features are only available in interactive bash sessions.

            ### Summary

            **Always use `bash -i -c "command"` when running user-defined aliases or commands that might rely on bashrc configuration.**
          '';
        }
      ];
    };

    # MCP Servers configuration
    # Uses full Nix store paths to work in isolated environments (devenv, nix-shell)
    # Enable interactively via `/mcp` command or `@` menu when needed
    mcpServers = {};
  };
}

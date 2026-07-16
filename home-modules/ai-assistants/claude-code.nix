{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;

  # MLflow tracking server (Tailscale ingress fronting mlflow.mlflow:5000 in K8s hub).
  mlflowTrackingUri = "https://mlflow-hub.tail286401.ts.net";
  workflowBuilderMcp = config.modules.aiAssistants.workflowBuilderMcp;
  nodeNpx = "${pkgs.nodejs}/bin/npx";
  workflowBuilderMcpProxy = pkgs.writeShellScript "workflow-builder-mcp-proxy-claude" ''
    set -euo pipefail

    session_id="''${WFB_MCP_SESSION_ID:-''${CLAUDE_CODE_SESSION_ID:-}}"
    if [ -z "$session_id" ] && [ -n "''${XDG_RUNTIME_DIR:-}" ] && [ -f "''${XDG_RUNTIME_DIR}/workflow-builder-mcp-session-id" ]; then
      session_id="$(${pkgs.coreutils}/bin/head -n1 "''${XDG_RUNTIME_DIR}/workflow-builder-mcp-session-id" | ${pkgs.gnused}/bin/sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    fi
    if [ -z "$session_id" ] && [ -f "''${HOME}/.cache/workflow-builder/mcp-session-id" ]; then
      session_id="$(${pkgs.coreutils}/bin/head -n1 "''${HOME}/.cache/workflow-builder/mcp-session-id" | ${pkgs.gnused}/bin/sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    fi

    mcp_url="''${WFB_MCP_URL:-${workflowBuilderMcp.url}}"
    args=(-y mcp-remote "$mcp_url" --transport http-only)
    if [ -n "$session_id" ]; then
      args+=(--header "X-Wfb-Session-Id: $session_id")
    fi

    exec "${nodeNpx}" "''${args[@]}"
  '';

  # Use claude-code from the dedicated flake for latest version
  # Fall back to nixpkgs-unstable if flake not available
  baseClaudeCode = inputs.claude-code-nix.packages.${pkgs.system}.claude-code or pkgs-unstable.claude-code or pkgs.claude-code;

  # Wrapped Claude Code with Chrome integration only.
  claudeCodePackage = pkgs.symlinkJoin {
    name = "claude-code-wrapped";
    paths = [ baseClaudeCode ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
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
  sharedSkillsDir = repoRoot + "/shared-skills";
  sharedSkillEntries = if builtins.pathExists sharedSkillsDir then builtins.readDir sharedSkillsDir else {};
  sharedSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink") sharedSkillEntries;
  sharedSkillHomeFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".claude/skills/${name}" {
        source = sharedSkillsDir + "/${name}";
        recursive = true;
      }
    )
    sharedSkillDirs;
in
lib.mkIf enableClaudeCode {
  # Install skills into ~/.claude/skills/
  # Only shared-skills entries are declared here.
  home.file =
    sharedSkillHomeFiles // {
      # Force PATH-preferred ~/.local/bin/claude to the home-manager finalPackage
      # so --mcp-config (which the HM module adds via a second wrapper layer
      # when mcpServers is non-empty) is present.
      ".local/bin/claude" = {
        source = "${config.programs.claude-code.finalPackage}/bin/claude";
        executable = true;
        force = true;
      };

      # The claude-code HM module symlinks settings.json into the read-only Nix
      # store, so Claude Code's own writes (e.g. `/tui fullscreen`, theme toggles)
      # fail with EROFS. Suppress that symlink; the writableClaudeSettings
      # activation below installs a writable copy of the same generated content
      # instead. Declarative settings stay the source of truth (the copy is
      # refreshed on every rebuild); runtime tweaks persist between rebuilds.
      #
      # IMPORTANT (nixpkgs 26.11): the module keys this file by its `configDir`,
      # which now defaults to an ABSOLUTE path ($HOME/.claude). So it declares
      # home.file."${configDir}/settings.json" (e.g.
      # "/home/vpittamp/.claude/settings.json"), NOT the relative
      # ".claude/settings.json". Suppressing only the relative key (as before)
      # left the absolute-key symlink active — it clobbered the writable copy and
      # wedged home-manager activation. Suppress BOTH keys.
      ".claude/settings.json".enable = lib.mkForce false;
      "${config.programs.claude-code.configDir}/settings.json".enable = lib.mkForce false;

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
          command = "${pkgs.typescript-language-server}/bin/typescript-language-server";
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
          command = "${pkgs.yaml-language-server}/bin/yaml-language-server";
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
  # Install ~/.claude/settings.json as a WRITABLE copy of the Nix-generated
  # settings (see the `.claude/settings.json".enable = false` note above).
  # Without this, Claude Code can't persist any runtime setting because the
  # store-backed symlink is read-only (EROFS).
  home.activation.writableClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _src='${pkgs.writeText "claude-settings.json" (builtins.toJSON config.programs.claude-code.settings)}'
    _dst="$HOME/.claude/settings.json"
    run ${pkgs.coreutils}/bin/mkdir -p "$HOME/.claude"
    # Drop any leftover read-only symlink from a previous generation, then
    # refresh the writable copy. Declarative settings win on every rebuild.
    if [ -L "$_dst" ]; then run ${pkgs.coreutils}/bin/rm -f "$_dst"; fi
    run ${pkgs.coreutils}/bin/install -m 0644 "$_src" "$_dst"
  '';

  home.activation.patchClaudePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PLUGIN_CACHE="$HOME/.claude/plugins/cache/claude-code-plugins"
    if [ -d "$PLUGIN_CACHE" ]; then
      run ${pkgs.findutils}/bin/find "$PLUGIN_CACHE" -name "*.sh" -type f \
        -exec ${pkgs.gnused}/bin/sed -i 's|^#!/bin/bash|#!/usr/bin/env bash|' {} \;
    fi
  '';

  home.activation.ensureHerdrClaudeIntegration = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/herdr integration install claude || true
  '';


  home.sessionVariables = {
    # Experimental: Agent Teams - multi-agent coordination
    # Session variable ensures it's set before Claude Code initializes
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";

    # Experimental: Workflows - set before Claude Code initializes
    CLAUDE_CODE_WORKFLOWS = "1";
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
          MODEL=$(${pkgs.jq}/bin/jq -r '.model.display_name // .model.id // "Unknown Model"' <<< "$input")
          PERCENT=$(${pkgs.jq}/bin/jq -r '.context_window.used_percentage // .context_window.usage_percentage // 0 | if type == "number" then round else . end' <<< "$input")
          COST_RAW=$(${pkgs.jq}/bin/jq -r '.session_cost.total_cost // .cost.total_cost_usd // 0' <<< "$input")
          COST=$(printf "%.1f" "$COST_RAW" 2>/dev/null || printf "%.1f" 0)
          PROJECT="''${PWD##*/}"
          TMUX_STR="''${TMUX_PANE:+ | Tmux: ''$TMUX_PANE}"

          # Git status helper
          if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
            MODIFIED=$(git diff --name-only 2>/dev/null | wc -l)
            UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
            STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)

            GIT_STR=" | ⎇ $BRANCH"
            if [ "$STAGED" -gt 0 ] || [ "$MODIFIED" -gt 0 ] || [ "$UNTRACKED" -gt 0 ]; then
              GIT_STR="$GIT_STR ("
              first=1
              if [ "$STAGED" -gt 0 ]; then
                GIT_STR="$GIT_STR+$STAGED"
                first=0
              fi
              if [ "$MODIFIED" -gt 0 ]; then
                if [ $first -eq 0 ]; then GIT_STR="$GIT_STR "; fi
                GIT_STR="$GIT_STR~$MODIFIED"
                first=0
              fi
              if [ "$UNTRACKED" -gt 0 ]; then
                if [ $first -eq 0 ]; then GIT_STR="$GIT_STR "; fi
                GIT_STR="$GIT_STR?$UNTRACKED"
              fi
              GIT_STR="$GIT_STR)"
            fi
          else
            GIT_STR=""
          fi

          echo -e "\e[34m[Proj: $PROJECT$TMUX_STR$GIT_STR]\e[0m | \e[32m$MODEL\e[0m | Ctx: $PERCENT% | \$$COST"
        ''}";
      };

      # Default to Claude Fable 5 (public Mythos-class model, launched 2026-06-09).
      # Access is server-gated by plan entitlement; Claude Code falls back if unavailable.
      model = "claude-fable-5";
      theme = "dark";
      # Terminal UI renderer: "fullscreen" uses the flicker-free alt-screen
      # renderer with virtualized scrollback (equivalent to /tui fullscreen).
      tui = "fullscreen";
      editorMode = "vim";
      autoCompactEnabled = true;
      todoFeatureEnabled = true;
      verbose = true;
      autoUpdates = true;
      autoConnectIde = true;
      includeCoAuthoredBy = true;
      env = {
        # Fix for M1 Apple Silicon: Built-in ripgrep has jemalloc page size incompatibility
        # Apple Silicon uses 16KB pages, jemalloc expects 4KB pages
        # Use system ripgrep instead (available via home-manager)
        USE_BUILTIN_RIPGREP = "0";
        # Experimental: Agent Teams - enables TeammateTool for multi-agent coordination
        # Multiple Claude instances work in parallel with shared task lists and peer messaging
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
        # Experimental: Workflows
        CLAUDE_CODE_WORKFLOWS = "1";
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
          "mcp__workflow-builder__list_workflow_targets"
          "mcp__workflow-builder__get_workflow_target_health"
          "mcp__workflow-builder__get_workflow_target_resources"
          "mcp__workflow-builder__get_workflow_script_spec"
          "mcp__workflow-builder__validate_workflow_script"
          "mcp__workflow-builder__run_workflow_script"
          "mcp__workflow-builder__save_workflow_script"
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

            Rebuilds use `sudo nixos-rebuild switch --flake .#thinkpad` (or
            `.#ryzen`) — the two maintained hosts. Standard aliases like `ll`,
            `la`, `grep`, and git shortcuts also come from the interactive shell
            (defined in `home-modules/shell/bash.nix`).

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
            my-alias
            ```
            Result: `command not found`

            ✅ **CORRECT**:
            ```bash
            bash -i -c "my-alias"
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
    mcpServers = {
      mlflow = {
        command = "${pkgs.nodejs}/bin/npx";
        args = [ "-y" "@us-all/mlflow-mcp" ];
        env = {
          MLFLOW_TRACKING_URI = mlflowTrackingUri;
        };
      };
    } // lib.optionalAttrs workflowBuilderMcp.enable {
      workflow-builder = {
        command = "${workflowBuilderMcpProxy}";
        args = [];
      };
    };
  };
}

{ config, pkgs, lib, inputs, self, pkgs-unstable ? pkgs, ... }:

let
  # Use claude-code from the dedicated flake for latest version (2.0.1)
  # Fall back to nixpkgs-unstable if flake not available
  claudeCodePackage = inputs.claude-code-nix.packages.${pkgs.system}.claude-code or pkgs-unstable.claude-code or pkgs.claude-code;

  # Claude Desktop for Linux (unofficial community package)
  # Use claude-desktop-with-fhs for MCP server support (npx, uvx, docker)
  claudeDesktopPackage = inputs.claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs or null;

  # Claude Code's home-manager module has Chromium dependencies that break on Darwin
  # Only enable on Linux where Chromium is available
  enableClaudeCode = pkgs.stdenv.isLinux;

  # Check if we can enable MCP servers that require Chromium
  # Chromium package is only available on Linux
  enableChromiumMcpServers = pkgs.stdenv.isLinux;

  # Chromium configuration - only define when needed to avoid evaluation on Darwin
  # On Linux: use Nix-managed Chromium
  # On Darwin: MCP servers that need Chromium are disabled
  chromiumConfig = lib.optionalAttrs enableChromiumMcpServers {
    chromiumBin = "${pkgs.chromium}/bin/chromium";
  };

  # Auto-import all .md files from .claude/commands/ as slash commands
  # This creates an attribute set where keys are command names (without .md)
  # and values are the file contents
  commandFiles = builtins.readDir (self + "/.claude/commands");
  commands = lib.mapAttrs'
    (name: type:
      lib.nameValuePair
        (lib.removeSuffix ".md" name)
        (builtins.readFile (self + "/.claude/commands/${name}"))
    )
    (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".md" n) commandFiles);
in
lib.mkIf enableClaudeCode {
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
      # Model selection removed - will use default or user's choice
      theme = "dark";
      editorMode = "vim";
      autoCompactEnabled = true;
      todoFeatureEnabled = true;
      verbose = true;
      autoUpdates = true;
      preferredNotifChannel = "terminal_bell";
      autoConnectIde = true;
      includeCoAuthoredBy = true;
      messageIdleNotifThresholdMs = 60000;
      env = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_METRICS_EXPORTER = "otlp";
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
        # Fix for M1 Apple Silicon: Built-in ripgrep has jemalloc page size incompatibility
        # Apple Silicon uses 16KB pages, jemalloc expects 4KB pages
        # Use system ripgrep instead (available via home-manager)
        USE_BUILTIN_RIPGREP = "0";
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
      hooks = {
        PostToolUse = [{
          # Match all Bash tool executions (case-sensitive)
          matcher = "Bash";
          hooks = [{
            type = "command";
            # Use path to hook script stored in NixOS config
            # This script receives JSON via stdin with structure:
            # {"tool_input": {"command": "..."}, "tool_name": "Bash", ...}
            command = "${self}/scripts/claude-hooks/bash-history.sh";
            # Set 5-second timeout (hook is simple, shouldn't take long)
            timeout = 5;
          }];
        }];

        # UserPromptSubmit hook - Feature 095/117: Activity indicator for Claude Code
        # Creates "working" badge in monitoring panel when user submits a prompt
        # Shows spinner animation indicating Claude Code is processing
        UserPromptSubmit = [{
          hooks = [{
            type = "command";
            # Feature 117: Hook creates badge file at $XDG_RUNTIME_DIR/i3pm-badges/
            # File-based storage is single source of truth (no IPC)
            command = "${self}/scripts/claude-hooks/prompt-submit-notification.sh";
            # Short timeout - file write is quick
            timeout = 3;
          }];
        }];

        # Stop hook - Notify when Claude Code finishes and awaits input
        # Feature 095/117: Changes badge state from "working" to "stopped"
        # Sends concise desktop notification with action to return to terminal
        Stop = [{
          hooks = [{
            type = "command";
            # Feature 117: Hook updates badge file to "stopped" state (bell icon)
            # Sends notification with project name only (concise format)
            # notify-send -w blocks until user clicks action or dismisses
            command = "${self}/scripts/claude-hooks/stop-notification.sh";
            # Longer timeout - notify-send -w blocks until user responds
            timeout = 300;
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

          # MCP Server permissions - servers start disabled but need permissions when enabled via /mcp
          "mcp__context7"
          "mcp__playwright"  # Linux only
          "mcp__chrome-devtools"  # Linux only
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

    # MCP Servers configuration - using npx for cross-platform compatibility
    # Servers are defined with `disabled = true` by default to save context tokens
    # Enable interactively via `/mcp` command or `@` menu when needed
    # Note: Due to bug #11370, disabled servers may still consume some context tokens
    mcpServers = {
      # Context7 - Lightweight documentation lookup (~1.7k tokens)
      # Available on all platforms
      context7 = {
        command = "npx";
        args = [
          "-y"
          "@upstash/context7-mcp@latest"
        ];
        disabled = true;
      };
    } // lib.optionalAttrs enableChromiumMcpServers {
      # Playwright MCP server for browser automation (~13.7k tokens)
      # Only available on Linux where Chromium is available via Nix
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
          PLAYWRIGHT_SKIP_CHROMIUM_DOWNLOAD = "true";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
          NODE_ENV = "production";
          LOG_DIR = "/tmp/mcp-puppeteer-logs";
        };
        disabled = true;
      };

      # Chrome DevTools MCP server for debugging and performance (~17k tokens)
      # Only available on Linux where Chromium is available via Nix
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
        disabled = true;
      };
    };
  };
}

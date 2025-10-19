{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  # Use claude-code from the dedicated flake for latest version (2.0.1)
  # Fall back to nixpkgs-unstable if flake not available
  claudeCodePackage = inputs.claude-code-nix.packages.${pkgs.system}.claude-code or pkgs-unstable.claude-code or pkgs.claude-code;

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
in
lib.mkIf enableClaudeCode {
  # Chromium is installed via programs.chromium in tools/chromium.nix
  # No need to install it here - avoids conflicts

  # Claude Code configuration with home-manager module
  # Only enabled on Linux due to Chromium dependencies in the module
  programs.claude-code = {
    enable = true;
    package = claudeCodePackage;

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

          # MCP Server: Context7 (use server prefix for all tools)
          "mcp__context7"

          # MCP Server: IDE integration (use server prefix for all IDE operations)
          "mcp__ide"
        ] ++ lib.optionals enableChromiumMcpServers [
          # MCP Server: Playwright (use server prefix for all browser automation)
          # Only on Linux where Chromium is available
          "mcp__playwright"

          # MCP Server: Chrome DevTools (use server prefix for all debugging)
          # Only on Linux where Chromium is available
          "mcp__chrome-devtools"
        ];
      };

      # Custom memories - persistent instructions for Claude Code
      # These override default behaviors and provide environment-specific guidance
      memories = [
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
    # Note: All servers enabled - uses ~33k tokens
    # Comment out servers you don't need to save context tokens
    mcpServers = {
      # Context7 - Lightweight documentation lookup (~1.7k tokens)
      # Available on all platforms
      context7 = {
        command = "npx";
        args = [
          "-y"
          "@upstash/context7-mcp@latest"
        ];
      };
    } // lib.optionalAttrs enableChromiumMcpServers {
      # Playwright MCP server for browser automation (~13.7k tokens)
      # Only enabled on Linux where Chromium is available via Nix
      playwright = {
        transport = "stdio";
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
      };

      # Chrome DevTools MCP server for debugging and performance (~17k tokens)
      # Only enabled on Linux where Chromium is available via Nix
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
      };
    };
  };
}

{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  # Use claude-code from the dedicated flake for latest version (2.0.1)
  # Fall back to nixpkgs-unstable if flake not available
  claudeCodePackage = inputs.claude-code-nix.packages.${pkgs.system}.claude-code or pkgs-unstable.claude-code or pkgs.claude-code;

  # Chromium is only available on Linux platforms
  # On macOS, users should install Chrome/Chromium manually or use a different browser
  chromiumBin =
    if pkgs.stdenv.isLinux
    then "${pkgs.chromium}/bin/chromium"
    else if pkgs.stdenv.isDarwin
    then "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"  # Default macOS Chrome path
    else "chromium";  # Fallback

  # Check if we can enable MCP servers that require Chromium
  enableChromiumMcpServers = pkgs.stdenv.isLinux;
in
{
  # Chromium is installed via programs.chromium in tools/chromium.nix
  # No need to install it here - avoids conflicts

  # Claude Code configuration with home-manager module
  # Try to enable on all platforms, will fail gracefully if not available
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
          chromiumBin
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
          chromiumBin
        ];
      };
    };
  };
}

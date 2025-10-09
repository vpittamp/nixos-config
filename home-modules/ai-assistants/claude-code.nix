{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  # Use claude-code from the dedicated flake for latest version (2.0.1)
  # Fall back to nixpkgs-unstable if flake not available
  claudeCodePackage = inputs.claude-code-nix.packages.${pkgs.system}.claude-code or pkgs-unstable.claude-code or pkgs.claude-code;
  chromiumBin = "${pkgs.chromium}/bin/chromium";
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
      permissions = {
        allow = [
          # Core file and code operations
          "Read(*)"
          "Write(*)"
          "Edit(*)"
          "Glob(*)"
          "Grep(*)"

          # Bash and system operations
          "Bash(*)"

          # Notebook operations
          "NotebookEdit(*)"

          # Task and planning tools
          "Task(*)"
          "TodoWrite(*)"

          # Web operations
          "WebFetch(*)"
          "WebSearch(*)"

          # Background bash operations
          "BashOutput(*)"
          "KillShell(*)"

          # Slash commands
          "SlashCommand(*)"

          # MCP Server: Context7
          "mcp__context7__resolve-library-id(*)"
          "mcp__context7__get-library-docs(*)"

          # MCP Server: Playwright (all browser automation operations)
          "mcp__playwright__browser_close(*)"
          "mcp__playwright__browser_resize(*)"
          "mcp__playwright__browser_console_messages(*)"
          "mcp__playwright__browser_handle_dialog(*)"
          "mcp__playwright__browser_evaluate(*)"
          "mcp__playwright__browser_file_upload(*)"
          "mcp__playwright__browser_fill_form(*)"
          "mcp__playwright__browser_install(*)"
          "mcp__playwright__browser_press_key(*)"
          "mcp__playwright__browser_type(*)"
          "mcp__playwright__browser_navigate(*)"
          "mcp__playwright__browser_navigate_back(*)"
          "mcp__playwright__browser_network_requests(*)"
          "mcp__playwright__browser_take_screenshot(*)"
          "mcp__playwright__browser_snapshot(*)"
          "mcp__playwright__browser_click(*)"
          "mcp__playwright__browser_drag(*)"
          "mcp__playwright__browser_hover(*)"
          "mcp__playwright__browser_select_option(*)"
          "mcp__playwright__browser_tabs(*)"
          "mcp__playwright__browser_wait_for(*)"

          # MCP Server: Chrome DevTools (all debugging and performance operations)
          "mcp__chrome-devtools__list_console_messages(*)"
          "mcp__chrome-devtools__emulate_cpu(*)"
          "mcp__chrome-devtools__emulate_network(*)"
          "mcp__chrome-devtools__click(*)"
          "mcp__chrome-devtools__drag(*)"
          "mcp__chrome-devtools__fill(*)"
          "mcp__chrome-devtools__fill_form(*)"
          "mcp__chrome-devtools__hover(*)"
          "mcp__chrome-devtools__upload_file(*)"
          "mcp__chrome-devtools__get_network_request(*)"
          "mcp__chrome-devtools__list_network_requests(*)"
          "mcp__chrome-devtools__close_page(*)"
          "mcp__chrome-devtools__handle_dialog(*)"
          "mcp__chrome-devtools__list_pages(*)"
          "mcp__chrome-devtools__navigate_page(*)"
          "mcp__chrome-devtools__navigate_page_history(*)"
          "mcp__chrome-devtools__new_page(*)"
          "mcp__chrome-devtools__resize_page(*)"
          "mcp__chrome-devtools__select_page(*)"
          "mcp__chrome-devtools__performance_analyze_insight(*)"
          "mcp__chrome-devtools__performance_start_trace(*)"
          "mcp__chrome-devtools__performance_stop_trace(*)"
          "mcp__chrome-devtools__take_screenshot(*)"
          "mcp__chrome-devtools__evaluate_script(*)"
          "mcp__chrome-devtools__take_snapshot(*)"
          "mcp__chrome-devtools__wait_for(*)"

          # MCP Server: IDE integration
          "mcp__ide__getDiagnostics(*)"
          "mcp__ide__executeCode(*)"
        ];
      };
    };

    # MCP Servers configuration - using npx for cross-platform compatibility
    mcpServers = {
      context7 = {
        command = "npx";
        args = [
          "-y"
          "@upstash/context7-mcp@latest"
        ];
      };

      # Playwright MCP server for browser automation
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
          # Skip downloading Chromium since we use system package
          PLAYWRIGHT_SKIP_CHROMIUM_DOWNLOAD = "true";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
          # Redirect logs to temp directory to avoid cluttering project directories
          NODE_ENV = "production";
          LOG_DIR = "/tmp/mcp-puppeteer-logs";
        };
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
          chromiumBin
        ];
      };
    };
  };
}

{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  # Check if we're on Darwin
  isDarwin = pkgs.stdenv.isDarwin or false;

  # Use claude-code from nixpkgs-unstable
  # Note: Version 1.0.105-1.0.107 have TTY issues, latest is 1.0.112
  claudeCodePackage = pkgs-unstable.claude-code or pkgs.claude-code;
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
      model = "opus";
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

      # Using npx for cross-platform compatibility
      puppeteer = {
        transport = "stdio";
        command = "npx";
        args = [
          "-y"
          "@playwright/mcp@latest"
        ];
        env = {
          # Use Chromium on Linux, system Chrome on macOS
          # PUPPETEER_EXECUTABLE_PATH = if isDarwin 
          #   then "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
          #   else "${pkgs.chromium}/bin/chromium";
          # # Launch options for containerized environments
          # PUPPETEER_LAUNCH_OPTIONS = ''{"headless": true, "args": ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage", "--disable-gpu"]}'';
          # PUPPETEER_ALLOW_DANGEROUS = "true";
          # PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = "true";  # Use system chromium
          # # Redirect logs to temp directory to avoid cluttering project directories
          # NODE_ENV = "production";
          # LOG_DIR = "/tmp/mcp-puppeteer-logs";
        };
      };
    };
  };
}

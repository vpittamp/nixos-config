{ config, pkgs, lib, pkgs-unstable ? pkgs, ... }:

let
  # Chromium is only available on Linux
  # On Darwin, MCP servers requiring Chromium will be disabled
  enableChromiumMcpServers = pkgs.stdenv.isLinux;

  chromiumConfig = lib.optionalAttrs enableChromiumMcpServers {
    chromiumBin = "${pkgs.chromium}/bin/chromium";
  };

  # Wrapper for codex that sets OTEL batch processor env vars for real-time export
  codexPackage = pkgs-unstable.codex or pkgs.codex;
  codexWrapperScript = pkgs.writeShellScriptBin "codex" ''
    # Force frequent batch exports for real-time monitoring
    # OTEL_BLRP = Batch Log Record Processor settings (Rust SDK reads these)
    export OTEL_BLRP_SCHEDULE_DELAY=''${OTEL_BLRP_SCHEDULE_DELAY:-500}
    export OTEL_BLRP_MAX_EXPORT_BATCH_SIZE=''${OTEL_BLRP_MAX_EXPORT_BATCH_SIZE:-1}
    export OTEL_BLRP_MAX_QUEUE_SIZE=''${OTEL_BLRP_MAX_QUEUE_SIZE:-100}
    exec ${codexPackage}/bin/codex "$@"
  '';
  # Preserve version attribute so home-manager uses TOML format (version >= 0.2.0)
  codexWrapped = codexWrapperScript // {
    version = codexPackage.version or "0.73.0";
  };
in

{
  # Codex - Lightweight coding agent (using native home-manager module with unstable package)
  programs.codex = {
    enable = true;
    package = codexWrapped; # Wrapper with OTEL batch env vars for real-time monitoring
    # We don't need backups; overwrite the config directly
    settings.force = lib.mkForce true;

    # Custom instructions for the agent
    # custom-instructions = 

    # Configuration for codex (TOML format)
    settings = {
      # Model configuration
      model = "gpt-5-codex";
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
      vim_mode = false;
      # Enable new web search tool (replaces deprecated tools.web_search)
      # rmcp_client is REQUIRED for MCP server support
      features = {
        web_search_request = true;
        rmcp_client = true;  # Required for MCP servers to work
      };

      # Feature 123: OpenTelemetry configuration for OTLP export
      # Sends logs to OTEL Collector for session tracking
      otel = {
        environment = "dev";
        log_user_prompt = true;  # Enable for debugging (disable in production)
        exporter = {
          otlp-http = {
            endpoint = "http://localhost:4318/v1/logs";
            protocol = "json";  # Use JSON for compatibility with our receiver
          };
        };
      };

      # MCP Servers configuration
      # Note: Codex does NOT support a `disabled` flag for MCP servers
      # Servers are either defined (always active) or not defined (unavailable)
      # Only Linux is supported due to Chromium dependency
      mcp_servers = lib.optionalAttrs enableChromiumMcpServers {
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

      # Only add OTEL if not already present
      if ! ${pkgs.gnugrep}/bin/grep -q '^\[otel\]' "$TEMP"; then
        ${pkgs.coreutils}/bin/cat >> "$TEMP" << 'EOF'

# Feature 123: OpenTelemetry configuration for OTLP export
[otel]
environment = "dev"
log_user_prompt = true

[otel.exporter.otlp-http]
endpoint = "http://localhost:4318/v1/logs"
protocol = "json"
EOF
      fi

      # Replace symlink with patched file
      ${pkgs.coreutils}/bin/rm -f "$CONFIG"
      ${pkgs.coreutils}/bin/mv "$TEMP" "$CONFIG"
      ${pkgs.coreutils}/bin/chmod 600 "$CONFIG"
    fi
  '';
}

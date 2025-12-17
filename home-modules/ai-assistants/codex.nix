{ config, pkgs, lib, pkgs-unstable ? pkgs, ... }:

let
  # Chromium is only available on Linux
  # On Darwin, MCP servers requiring Chromium will be disabled
  enableChromiumMcpServers = pkgs.stdenv.isLinux;

  chromiumConfig = lib.optionalAttrs enableChromiumMcpServers {
    chromiumBin = "${pkgs.chromium}/bin/chromium";
  };

  # Feature 123: OTEL config must use inline table format for Codex
  # The home-manager TOML generator uses section headers, but Codex expects inline tables
  otelConfigPatch = pkgs.writeText "codex-otel-patch.toml" ''
    [otel]
    environment = "dev"
    log_user_prompt = false
    exporter = { otlp-http = { endpoint = "http://localhost:4318/v1/logs", protocol = "binary" } }
  '';

  # Wrapper for codex that sets OTEL batch processor env vars for real-time export
  codexPackage = pkgs-unstable.codex or pkgs.codex;
  codexWrapped = pkgs.writeShellScriptBin "codex" ''
    # Force frequent batch exports for real-time monitoring
    # OTEL_BLRP = Batch Log Record Processor settings (Rust SDK reads these)
    export OTEL_BLRP_SCHEDULE_DELAY=''${OTEL_BLRP_SCHEDULE_DELAY:-500}
    export OTEL_BLRP_MAX_EXPORT_BATCH_SIZE=''${OTEL_BLRP_MAX_EXPORT_BATCH_SIZE:-1}
    export OTEL_BLRP_MAX_QUEUE_SIZE=''${OTEL_BLRP_MAX_QUEUE_SIZE:-100}
    exec ${codexPackage}/bin/codex "$@"
  '';
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
      # Note: OTEL config moved to extraConfig for correct inline table format

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

  # Feature 123: Patch codex config to use inline table format for OTEL
  # The home-manager module generates [otel.exporter.otlp-http] section headers,
  # but Codex expects exporter = { otlp-http = { ... } } inline table format.
  # Since the config file is a symlink to nix store (read-only), we need to:
  # 1. Copy the generated config to a temp file
  # 2. Append the OTEL config with correct format
  # 3. Replace the symlink with the patched file
  home.activation.patchCodexOtelConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    CONFIG="$HOME/.codex/config.toml"
    if [ -L "$CONFIG" ] || [ -f "$CONFIG" ]; then
      # Create temp copy of the config (following symlinks)
      TEMP=$(${pkgs.coreutils}/bin/mktemp)
      ${pkgs.coreutils}/bin/cat "$CONFIG" > "$TEMP"

      # Remove incorrectly formatted otel sections using grep/sed
      ${pkgs.gnugrep}/bin/grep -v '^\[otel' "$TEMP" | ${pkgs.gnugrep}/bin/grep -v '^environment = "dev"' | ${pkgs.gnugrep}/bin/grep -v '^log_user_prompt' | ${pkgs.gnugrep}/bin/grep -v '^endpoint' | ${pkgs.gnugrep}/bin/grep -v '^protocol = "binary"' > "$TEMP.clean" || true

      # Append correct OTEL config
      ${pkgs.coreutils}/bin/cat >> "$TEMP.clean" << 'EOF'

[otel]
environment = "dev"
log_user_prompt = false
exporter = { otlp-http = { endpoint = "http://localhost:4318/v1/logs", protocol = "binary" } }
EOF

      # Remove symlink and replace with patched file
      ${pkgs.coreutils}/bin/rm -f "$CONFIG"
      ${pkgs.coreutils}/bin/mv "$TEMP.clean" "$CONFIG"
      ${pkgs.coreutils}/bin/rm -f "$TEMP"
    fi
  '';
}

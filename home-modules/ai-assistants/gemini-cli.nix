{ config, pkgs, lib, self, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;

  # Chromium is only available on Linux
  # On Darwin, MCP servers requiring Chromium will be disabled
  enableChromiumMcpServers = pkgs.stdenv.isLinux;

  chromiumConfig = lib.optionalAttrs enableChromiumMcpServers {
    chromiumBin = "${pkgs.chromium}/bin/chromium";
  };

  # Base gemini-cli package
  baseGeminiCli = pkgs-unstable.gemini-cli or pkgs.gemini-cli;

  # Wrapped gemini-cli with IPv4-first fix for OAuth authentication
  # Issue: https://github.com/google-gemini/gemini-cli/issues/4984
  # On NixOS, Node.js tries IPv6 first which times out before falling back to IPv4.
  # This wrapper forces IPv4 connections for reliable OAuth flows.
  geminiCliWrapped = pkgs.symlinkJoin {
    name = "gemini-cli-wrapped";
    paths = [ baseGeminiCli ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/gemini \
        --set NODE_OPTIONS "--dns-result-order=ipv4first"
    '';
  };

  # Auto-import all .md files from .gemini/commands/ as custom commands
  # This follows the same pattern as Claude Code's slash commands
  commandFiles = builtins.readDir (self + "/.gemini/commands");
  
  # Helper to parse simple YAML frontmatter in Nix
  # Expects format:
  # ---
  # description: some text
  # ---
  # prompt content
  parseCommand = name: content:
    let
      lines = lib.splitString "\n" content;
      hasFrontmatter = lib.length lines > 2 && lib.head lines == "---";
      
      # Find the end of frontmatter (the second ---)
      frontmatterEndIndex = 
        if hasFrontmatter 
        then (let 
                # Find index of second ---
                indices = lib.findFirst (i: i > 0 && lib.elemAt lines i == "---") null (lib.range 1 (lib.length lines - 1));
              in if indices == null then 0 else indices)
        else 0;

      # Extract description from frontmatter
      frontmatterLines = if hasFrontmatter then lib.take frontmatterEndIndex lines else [];
      descriptionLine = lib.findFirst (l: lib.hasPrefix "description:" l) null frontmatterLines;
      description = if descriptionLine != null 
        then lib.replaceStrings ["description: " "description:"] ["" ""] descriptionLine
        else "Custom command: ${name}";

      # Prompt is everything after frontmatter
      promptLines = if hasFrontmatter then lib.drop (frontmatterEndIndex + 1) lines else lines;
      prompt = lib.concatStringsSep "\n" promptLines;
    in
    { inherit description prompt; };

  commands = lib.mapAttrs'
    (name: type:
      lib.nameValuePair
        (lib.removeSuffix ".md" name)
        (parseCommand name (builtins.readFile (self + "/.gemini/commands/${name}")))
    )
    (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".md" n) commandFiles);

  # Settings JSON for activation script - generated with dynamic chromium paths
  # This is written as a real file (not symlink) to allow gemini-cli to write credentials
  settingsJson = builtins.toJSON {
    autoAccept = true;
    preferredEditor = "nvim";
    previewFeatures = true;
    theme = "Default";
    vimMode = true;
    # Feature 123: OpenTelemetry configuration for OTLP export
    # Sends telemetry to otel-ai-monitor service for session tracking
    telemetry = {
      enabled = true;
      target = "local";  # Use local OTLP collector
      # Gemini CLI posts OTLP/HTTP JSON envelopes to `/` (not `/v1/*`).
      # Route via local interceptor which forwards to the collector and synthesizes traces.
      otlpEndpoint = "http://127.0.0.1:4322";
      otlpProtocol = "http";  # Use HTTP for compatibility with our receiver
      logPrompts = true;  # Enable for debugging (helps with session detection)
      useCollector = true;  # Enable external OTLP collector
      # Enable all signals
      signals = {
        logs = true;
        metrics = true;
        traces = true;
      };
    };
    mcpServers = lib.optionalAttrs enableChromiumMcpServers {
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
        };
      };
    };
  };
in
{
  # Create writable .gemini directory with settings
  # Using activation script instead of home.file to allow gemini-cli to write credentials
  # Pattern from docker.nix, codex.nix, copilot-auth.nix
  home.activation.setupGeminiConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    GEMINI_DIR="$HOME/.gemini"

    # Create writable directory
    $DRY_RUN_CMD mkdir -p "$GEMINI_DIR"
    $DRY_RUN_CMD chmod 700 "$GEMINI_DIR"

    # If settings.json is missing OR is a symlink, create real writable file
    # This preserves user customizations if they exist as a real file
    if [ ! -f "$GEMINI_DIR/settings.json" ] || [ -L "$GEMINI_DIR/settings.json" ]; then
      $DRY_RUN_CMD rm -f "$GEMINI_DIR/settings.json"
      $DRY_RUN_CMD cat > "$GEMINI_DIR/settings.json" <<'EOF'
${settingsJson}
EOF
      $DRY_RUN_CMD chmod 600 "$GEMINI_DIR/settings.json"
    else
      # Ensure telemetry config is present and points at our interceptor.
      # Preserve user settings outside `.telemetry`, but enforce the OTLP endpoint so telemetry works.
      WANT_ENDPOINT="http://127.0.0.1:4322"
      if ! ${pkgs.jq}/bin/jq -e --arg ep "$WANT_ENDPOINT" '.telemetry.otlpEndpoint == $ep' "$GEMINI_DIR/settings.json" >/dev/null 2>&1; then
        $DRY_RUN_CMD ${pkgs.jq}/bin/jq --arg ep "$WANT_ENDPOINT" '
          .telemetry = (.telemetry // {}) |
          .telemetry.enabled = true |
          .telemetry.target = "local" |
          .telemetry.otlpEndpoint = $ep |
          .telemetry.otlpProtocol = (.telemetry.otlpProtocol // "http") |
          .telemetry.logPrompts = (.telemetry.logPrompts // true) |
          .telemetry.useCollector = (.telemetry.useCollector // true) |
          .telemetry.signals = (.telemetry.signals // {logs: true, metrics: true, traces: true})
        ' "$GEMINI_DIR/settings.json" > "$GEMINI_DIR/settings.json.tmp"
        $DRY_RUN_CMD mv "$GEMINI_DIR/settings.json.tmp" "$GEMINI_DIR/settings.json"
        $DRY_RUN_CMD chmod 600 "$GEMINI_DIR/settings.json"
      fi
    fi
  '';

  # Gemini CLI - Google's Gemini AI in terminal (using native home-manager module with unstable package)
  programs.gemini-cli = {
    enable = true;
    package = geminiCliWrapped;  # Use wrapped version with IPv4-first fix

    # Default model: Available options with preview features enabled:
    # - Auto (let system choose based on task complexity)
    # - gemini-3-flash-preview (Gemini 3 Flash - fast, 78% SWE-bench)
    # - gemini-3-pro-preview-11-2025 (Gemini 3 Pro - complex tasks)
    # - gemini-2.5-pro, gemini-2.5-flash, gemini-2.5-flash-lite
    defaultModel = "gemini-3-flash-preview";

    # NOTE: settings are NOT managed here to allow credential persistence
    # Settings are written via home.activation.setupGeminiConfig as a real file
    # (not symlink) so gemini-cli can write oauth_creds.json to ~/.gemini/

    # Custom commands for common workflows - auto-imported from .gemini/commands/
    commands = commands;
  };

  # Feature 123: OTEL environment variables for Gemini CLI telemetry
  home.sessionVariables = {
    OTEL_LOGS_EXPORTER = "otlp";
    OTEL_METRICS_EXPORTER = "otlp";
    OTEL_TRACES_EXPORTER = "otlp";
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318";
    OTEL_METRIC_EXPORT_INTERVAL = "60000";
    OTEL_METRIC_EXPORT_TIMEOUT = "30000";
    OTEL_LOGS_EXPORT_INTERVAL = "5000";
    OTEL_LOG_USER_PROMPTS = "1";
  };

  # Gemini OTEL interceptor (local user service)
  systemd.user.services.gemini-otel-interceptor = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Gemini OTEL interceptor (forward OTLP envelopes + synthesize traces)";
      After = [ "default.target" ];
      PartOf = [ "default.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.nodejs}/bin/node ${repoRoot}/scripts/gemini-otel-interceptor.js";
      Restart = "on-failure";
      RestartSec = 2;

      Environment = [
        "GEMINI_OTEL_INTERCEPTOR_HOST=127.0.0.1"
        "GEMINI_OTEL_INTERCEPTOR_PORT=4322"
        "GEMINI_OTEL_INTERCEPTOR_FORWARD_BASE=http://127.0.0.1:4318"
      ];

      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "gemini-otel-interceptor";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}

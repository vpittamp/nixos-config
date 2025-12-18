{ config, pkgs, lib, self, pkgs-unstable ? pkgs, ... }:

let
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
    # Feature 123: OpenTelemetry telemetry configuration
    # Sends traces to local OTEL Collector for session tracking
    telemetry = {
      enabled = true;
      target = "local";  # Use local OTLP endpoint
      otlpEndpoint = "http://localhost:4318";  # Standard OTLP HTTP port
      otlpProtocol = "http";  # Use HTTP (not gRPC)
      logPrompts = true;  # Enable for debugging (disable in production)
      useCollector = true;  # Route through collector
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

    # Update settings.json if:
    # - File is missing
    # - File is a symlink (from old config)
    # - File lacks telemetry config (Feature 123: OTEL support)
    NEEDS_UPDATE=false
    if [ ! -f "$GEMINI_DIR/settings.json" ] || [ -L "$GEMINI_DIR/settings.json" ]; then
      NEEDS_UPDATE=true
    elif ! ${pkgs.gnugrep}/bin/grep -q '"telemetry"' "$GEMINI_DIR/settings.json" 2>/dev/null; then
      # Feature 123: Migrate existing settings to include OTEL telemetry
      NEEDS_UPDATE=true
    fi

    if [ "$NEEDS_UPDATE" = "true" ]; then
      $DRY_RUN_CMD rm -f "$GEMINI_DIR/settings.json"
      $DRY_RUN_CMD cat > "$GEMINI_DIR/settings.json" <<'EOF'
${settingsJson}
EOF
      $DRY_RUN_CMD chmod 600 "$GEMINI_DIR/settings.json"
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
}
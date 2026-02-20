{ config, pkgs, lib, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;

  # MCP Apps skill: create-mcp-app (from modelcontextprotocol/ext-apps)
  # Installed into ~/.gemini/skills/create-mcp-app so Gemini CLI can discover it as a user skill.
  extApps = pkgs.fetchFromGitHub {
    owner = "modelcontextprotocol";
    repo = "ext-apps";
    rev = "0bbbfee8c25e1217011c81b4bbd13c965ec6cb13";
    hash = "sha256-RLdCfASQlf/Am96kYSaTFxpIJvIjItKypnvYDprKTGk=";
  };
  createMcpAppSkillDir = extApps + "/plugins/mcp-apps/skills/create-mcp-app";

  # Alias for backward compatibility with patterns using 'self'
  # All AI assistants now use repoRoot consistently

  # Chromium is only available on Linux
  # On Darwin, MCP servers requiring Chromium will be disabled
  enableChromiumMcpServers = pkgs.stdenv.isLinux;

  chromiumConfig = lib.optionalAttrs enableChromiumMcpServers {
    chromiumBin = "${pkgs.chromium}/bin/chromium";
  };

  # Base gemini-cli package
  # As of 2026-02-20, the latest stable release is v0.29.5.
  #
  # Note: We build our own package instead of `overrideAttrs` because the upstream
  # nixpkgs package bakes in `npmDeps` (so version overrides won't update deps).
  baseGeminiCli = pkgs-unstable.buildNpmPackage (finalAttrs: {
    pname = "gemini-cli";
    version = "0.29.5";

    src = pkgs-unstable.fetchFromGitHub {
      owner = "google-gemini";
      repo = "gemini-cli";
      tag = "v${finalAttrs.version}";
      hash = "sha256-+gFSTq0CXMZa2OhP2gOuWa5WtteKW7Ys78lgnz7J72g=";
    };

    nodejs = pkgs-unstable.nodejs_22;

    npmDepsHash = "sha256-RGiWtJkLFV1UfFahHPzxtzJIsPCseEwfSsPdLfBkavI=";

    dontPatchElf = pkgs-unstable.stdenv.isDarwin;

    nativeBuildInputs =
      [
        pkgs-unstable.jq
        pkgs-unstable.pkg-config
      ]
      ++ lib.optionals pkgs-unstable.stdenv.isDarwin [
        # clang_21 breaks @vscode/vsce's optionalDependencies keytar
        pkgs-unstable.clang_20
      ];

    buildInputs = [
      pkgs-unstable.ripgrep
      pkgs-unstable.libsecret
    ];

    preConfigure = ''
      mkdir -p packages/generated
      echo "export const GIT_COMMIT_INFO = { commitHash: '${finalAttrs.src.rev}' };" > packages/generated/git-commit.ts
    '';

    postPatch = ''
      # Remove node-pty dependency from package.json (not needed, and causes build issues on Nix)
      ${pkgs-unstable.jq}/bin/jq 'del(.optionalDependencies."node-pty")' package.json > package.json.tmp && mv package.json.tmp package.json
      ${pkgs-unstable.jq}/bin/jq 'del(.optionalDependencies."node-pty")' packages/core/package.json > packages/core/package.json.tmp && mv packages/core/package.json.tmp packages/core/package.json

      # Fix ripgrep path for SearchText: avoid downloading a dynamically-linked rg binary.
      substituteInPlace packages/core/src/tools/ripGrep.ts \
        --replace-fail "const rgPath = await ensureRgPath();" "const rgPath = '${lib.getExe pkgs-unstable.ripgrep}';"

      # Fix OAuth browser launch on NixOS: gemini-cli uses the `open` npm package which prefers
      # its bundled `xdg-open` script on Linux. In some environments that ends up launching the
      # browser without the auth URL (opening the homepage). Use gemini-cli's secure launcher
      # instead, which execs the system opener with proper argument passing.
      substituteInPlace packages/core/src/code_assist/oauth2.ts \
        --replace-fail "import open from 'open';" "import { openBrowserSecurely } from '../utils/secure-browser-launcher.js';"
      substituteInPlace packages/core/src/code_assist/oauth2.ts \
        --replace-fail "const childProcess = await open(webLogin.authUrl);" "await openBrowserSecurely(webLogin.authUrl);"
      # Drop the childProcess error handler block (openBrowserSecurely throws on failure).
      sed -i "/^      childProcess\\.on('error'/,/^      });/d" packages/core/src/code_assist/oauth2.ts

      # Disable auto-update by default (auto-updating doesn't work with Nix-managed installs).
      sed -i '/enableAutoUpdate: {/,/}/ s/default: true/default: false/' packages/cli/src/config/settingsSchema.ts
      sed -i '/enableAutoUpdateNotification: {/,/}/ s/default: true/default: false/' packages/cli/src/config/settingsSchema.ts
    '';

    # Prevent npmDeps and python from getting into the closure
    disallowedReferences = [
      finalAttrs.npmDeps
      pkgs-unstable.nodejs_22.python
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/{bin,share/gemini-cli}

      npm prune --omit=dev

      # Remove python files to prevent python from getting into the closure
      find node_modules -name "*.py" -delete
      # keytar/build has gyp-mac-tool with a Python shebang that gets patched,
      # creating a python3 reference in the closure
      rm -rf node_modules/keytar/build

      cp -r node_modules $out/share/gemini-cli/

      rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli
      rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-core
      rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-a2a-server
      rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-test-utils
      rm -f $out/share/gemini-cli/node_modules/gemini-cli-vscode-ide-companion
      cp -r packages/cli $out/share/gemini-cli/node_modules/@google/gemini-cli
      cp -r packages/core $out/share/gemini-cli/node_modules/@google/gemini-cli-core
      cp -r packages/a2a-server $out/share/gemini-cli/node_modules/@google/gemini-cli-a2a-server

      rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-core/dist/docs/CONTRIBUTING.md

      ln -s $out/share/gemini-cli/node_modules/@google/gemini-cli/dist/index.js $out/bin/gemini
      chmod +x "$out/bin/gemini"

      # Clean up any remaining references to npmDeps in node_modules metadata
      find $out/share/gemini-cli/node_modules -name "package-lock.json" -delete
      find $out/share/gemini-cli/node_modules -name ".package-lock.json" -delete
      find $out/share/gemini-cli/node_modules -name "config.gypi" -delete

      runHook postInstall
    '';

    meta = {
      description = "AI agent that brings the power of Gemini directly into your terminal";
      homepage = "https://github.com/google-gemini/gemini-cli";
      license = lib.licenses.asl20;
      platforms = lib.platforms.all;
      mainProgram = "gemini";
    };
  });

  # Wrapped gemini-cli with IPv4-first fix for OAuth authentication
  # Issue: https://github.com/google-gemini/gemini-cli/issues/4984
  # On NixOS, Node.js tries IPv6 first which times out before falling back to IPv4.
  # This wrapper forces IPv4 connections for reliable OAuth flows.
  geminiCliWrapped = pkgs.symlinkJoin {
    name = "gemini-cli-wrapped";
    paths = [ baseGeminiCli ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      # Feature 128: Unset NODE_OPTIONS first to prevent Claude Code's interceptor
      # from being loaded when Gemini is run from within Claude Code's Bash tool,
      # then set IPv4-first for reliable OAuth, plus OTEL service name for identification.
      # Also unset any OTEL exporter vars to prevent conflicts with our local interceptor.
      #
      # Gemini CLI telemetry configuration (set per-process to avoid contaminating others):
      # - GEMINI_TELEMETRY_* vars control the Gemini-specific telemetry
      # - OTEL_SERVICE_NAME identifies this process in OTEL payloads
      wrapProgram $out/bin/gemini \
        --unset NODE_OPTIONS \
        --set NODE_OPTIONS "--dns-result-order=ipv4first" \
        --set OTEL_SERVICE_NAME "gemini-cli" \
        --set GEMINI_TELEMETRY_ENABLED "true" \
        --set GEMINI_TELEMETRY_TARGET "local" \
        --set GEMINI_TELEMETRY_OTLP_ENDPOINT "http://127.0.0.1:4322" \
        --set GEMINI_TELEMETRY_OTLP_PROTOCOL "http" \
        --set GEMINI_TELEMETRY_USE_COLLECTOR "true" \
        --set GEMINI_TELEMETRY_LOG_PROMPTS "true" \
        --unset OTEL_EXPORTER_OTLP_ENDPOINT \
        --unset OTEL_EXPORTER_OTLP_PROTOCOL \
        --unset OTEL_LOGS_EXPORTER \
        --unset OTEL_METRICS_EXPORTER \
        --unset OTEL_TRACES_EXPORTER
    '';
  };

  # Auto-import all .md files from .gemini/commands/ as custom commands
  # This follows the same pattern as Claude Code's slash commands
  commandFiles = builtins.readDir (repoRoot + "/.gemini/commands");
  
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
        (parseCommand name (builtins.readFile (repoRoot + "/.gemini/commands/${name}")))
    )
    (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".md" n) commandFiles);

  # Settings JSON for activation script - generated with dynamic chromium paths
  # This is written as a real file (not symlink) to allow gemini-cli to write credentials
  settingsJson = builtins.toJSON {
    # Gemini CLI v0.28.x settings schema uses nested categories.
    tools.autoAccept = true;
    general = {
      preferredEditor = "nvim";
      previewFeatures = true;
      vimMode = true;
      # Gemini CLI auto-update doesn't work with Nix-managed installs.
      enableAutoUpdate = false;
      enableAutoUpdateNotification = false;
    };
    ui.theme = "Default";
    model.name = "gemini-3.1-pro";
    # Feature 123: OpenTelemetry configuration for OTLP export
    # Sends telemetry to otel-ai-monitor (via our local interceptor).
    telemetry = {
      enabled = true;
      target = "local";
      # Route via local interceptor which forwards to the collector and synthesizes traces.
      otlpEndpoint = "http://127.0.0.1:4322";
      otlpProtocol = "http";
      logPrompts = true;
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
    set -euo pipefail

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
      # Ensure settings are compatible with modern gemini-cli schema and enforce
      # a few critical defaults (telemetry endpoint + default model).
      #
      # We also migrate the legacy flat keys our older config used:
      # - autoAccept -> tools.autoAccept
      # - preferredEditor/previewFeatures/vimMode -> general.*
      # - theme -> ui.theme
      WANT_ENDPOINT="http://127.0.0.1:4322"
      WANT_MODEL="gemini-3.1-pro"

      $DRY_RUN_CMD ${pkgs.jq}/bin/jq --arg ep "$WANT_ENDPOINT" --arg model "$WANT_MODEL" '
        # Migrate legacy top-level keys to the current schema.
        (if (has("autoAccept") and (.tools.autoAccept? == null))
         then (.tools = (.tools // {}) | .tools.autoAccept = .autoAccept)
         else . end) |
        (if (has("preferredEditor") and (.general.preferredEditor? == null))
         then (.general = (.general // {}) | .general.preferredEditor = .preferredEditor)
         else . end) |
        (if (has("previewFeatures") and (.general.previewFeatures? == null))
         then (.general = (.general // {}) | .general.previewFeatures = .previewFeatures)
         else . end) |
        (if (has("vimMode") and (.general.vimMode? == null))
         then (.general = (.general // {}) | .general.vimMode = .vimMode)
         else . end) |
        (if (has("theme") and (.ui.theme? == null))
         then (.ui = (.ui // {}) | .ui.theme = .theme)
         else . end) |
        del(.autoAccept, .preferredEditor, .previewFeatures, .vimMode, .theme) |

        # Enforce telemetry routing to our local interceptor.
        .telemetry = (.telemetry // {}) |
        .telemetry.enabled = true |
        .telemetry.target = "local" |
        .telemetry.otlpEndpoint = $ep |
        .telemetry.otlpProtocol = "http" |
        .telemetry.logPrompts = (.telemetry.logPrompts // true) |

        # Default to Gemini 3.1 Pro (latest, most capable model).
        .model = (.model // {}) |
        .model.name = $model |

        # Ensure reasonable defaults and disable auto-update (Nix-managed).
        .general = (.general // {}) |
        .general.enableAutoUpdate = false |
        .general.enableAutoUpdateNotification = false |
        .general.previewFeatures = (.general.previewFeatures // true) |
        .general.vimMode = (.general.vimMode // true) |
        .general.preferredEditor = (.general.preferredEditor // "nvim") |
        .tools = (.tools // {}) |
        .tools.autoAccept = (.tools.autoAccept // true) |
        .ui = (.ui // {}) |
        .ui.theme = (.ui.theme // "Default")
      ' "$GEMINI_DIR/settings.json" > "$GEMINI_DIR/settings.json.tmp"

      if ! ${pkgs.diffutils}/bin/cmp -s "$GEMINI_DIR/settings.json.tmp" "$GEMINI_DIR/settings.json"; then
        $DRY_RUN_CMD mv "$GEMINI_DIR/settings.json.tmp" "$GEMINI_DIR/settings.json"
        $DRY_RUN_CMD chmod 600 "$GEMINI_DIR/settings.json"
      else
        $DRY_RUN_CMD rm -f "$GEMINI_DIR/settings.json.tmp"
      fi
    fi
  '';

  # Install Gemini CLI Agent Skills into ~/.gemini/skills/
  #
  # Note: home-manager normally symlinks files into the Nix store, but Gemini/Codex skills
  # discovery expects real files. We materialize SKILL.md and minimal UI metadata as regular
  # files under ~/.gemini/skills so `gemini skills list` can discover them reliably.
  home.activation.setupGeminiSkills = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -euo pipefail

    GEMINI_DIR="$HOME/.gemini"
    SKILLS_ROOT="$GEMINI_DIR/skills"
    SKILL_DIR="$SKILLS_ROOT/create-mcp-app"

    $DRY_RUN_CMD mkdir -p "$SKILL_DIR"
    $DRY_RUN_CMD chmod 700 "$SKILLS_ROOT" || true

    # Materialize SKILL.md as a real file (not a symlink).
    if [ ! -f "$SKILL_DIR/SKILL.md" ] || [ -L "$SKILL_DIR/SKILL.md" ]; then
      $DRY_RUN_CMD rm -f "$SKILL_DIR/SKILL.md"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 "${createMcpAppSkillDir}/SKILL.md" "$SKILL_DIR/SKILL.md"
    else
      # Keep it up to date if the Nix-pinned source changes.
      if ! ${pkgs.diffutils}/bin/cmp -s "$SKILL_DIR/SKILL.md" "${createMcpAppSkillDir}/SKILL.md"; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 "${createMcpAppSkillDir}/SKILL.md" "$SKILL_DIR/SKILL.md"
      fi
    fi

    # Optional UI metadata file (improves how the skill appears in some UIs).
    $DRY_RUN_CMD mkdir -p "$SKILL_DIR/agents"
    TMP="$(${pkgs.coreutils}/bin/mktemp)"
    ${pkgs.coreutils}/bin/cat > "$TMP" <<'EOF'
interface:
  display_name: "Create MCP App"
  short_description: "Scaffold MCP Apps (tool + UI resource) using @modelcontextprotocol/ext-apps patterns"
EOF
    if [ ! -f "$SKILL_DIR/agents/openai.yaml" ] || ! ${pkgs.diffutils}/bin/cmp -s "$TMP" "$SKILL_DIR/agents/openai.yaml"; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 "$TMP" "$SKILL_DIR/agents/openai.yaml"
    fi
    $DRY_RUN_CMD rm -f "$TMP"
  '';

  # Gemini CLI - Google's Gemini AI in terminal (using native home-manager module with unstable package)
  programs.gemini-cli = {
    enable = true;
    package = geminiCliWrapped;  # Use wrapped version with IPv4-first fix

    # Default model: Available options with preview features enabled:
    # - Auto (let system choose based on task complexity)
    # - gemini-3.1-pro (Gemini 3.1 Pro - latest, most capable)
    # - gemini-3-flash-preview (Gemini 3 Flash - fast, 78% SWE-bench)
    # - gemini-2.5-pro, gemini-2.5-flash, gemini-2.5-flash-lite
    defaultModel = "gemini-3.1-pro";

    # NOTE: settings are NOT managed here to allow credential persistence
    # Settings are written via home.activation.setupGeminiConfig as a real file
    # (not symlink) so gemini-cli can write oauth_creds.json to ~/.gemini/

    # Custom commands for common workflows - auto-imported from .gemini/commands/
    commands = commands;
  };

  # NOTE: Gemini CLI telemetry is configured via:
  # 1. ~/.gemini/settings.json (written by activation script above)
  # 2. Wrapper script (sets OTEL_SERVICE_NAME only for gemini process)
  # We do NOT set session-level env vars here to avoid contaminating
  # other processes (like Claude Code) with Gemini's OTEL_SERVICE_NAME.

  # Feature 128: Gemini OTEL interceptor (local user service)
  # Receives OTLP from Gemini CLI and synthesizes proper trace spans
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
        "LANGFUSE_ENABLED=1"
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

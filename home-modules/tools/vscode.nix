{ config, pkgs, pkgs-unstable, lib, osConfig, ... }:

let
  # Primary profile used by all VSCode instances
  # This ensures consistent extension/settings across all activities
  primaryProfile = config.modules.tools.vscode.defaultProfile or "default";
  isM1 = osConfig.networking.hostName or "" == "nixos-m1";

  # Chromium is only available on Linux
  enableChromiumMcpServers = pkgs.stdenv.isLinux;

  chromiumConfig = lib.optionalAttrs enableChromiumMcpServers {
    chromiumBin = "${pkgs.chromium}/bin/chromium";
  };

  # Use latest VSCode from unstable channel for newest features and fixes
  vscode = pkgs-unstable.vscode;

  # Declarative VSCode package with proper flags for M1/ARM64
  # Using makeWrapper to add command-line flags for Wayland
  # Remove desktop files since we provide our own activity-aware versions
  vscodeWithFlags = vscode.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (oldAttrs.postFixup or "") + ''
      wrapProgram $out/bin/code \
        --add-flags "--profile ${primaryProfile}" \
        --add-flags "--ozone-platform=wayland" \
        --add-flags "--enable-features=WaylandWindowDecorations" \
        --set ELECTRON_OZONE_PLATFORM_HINT "auto"

      # Remove desktop files to prevent duplicate entries
      rm -rf $out/share/applications
    '';
  });

  playwrightExtension = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "playwright";
      publisher = "ms-playwright";
      version = "1.1.12";
      sha256 = "sha256-B6RYsDp1UKZmBRT/GdTPqxGOyCz2wJYKAqYqSLsez+w=";
    };
    meta = {
      description = "Playwright Test for VS Code";
      license = lib.licenses.mit;
    };
  };

  chatgptExtension = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "chatgpt";
      publisher = "openai";
      version = "0.5.15";
      sha256 = "sha256-NwkWKf86C56G9InKDEdZAKCW8wfmvXjnoqU8GD/mFEI=";
    };
    meta = {
      description = "OpenAI ChatGPT and Codex integration for VS Code";
      license = lib.licenses.mit;
    };
  };

  # GitLens from marketplace (pre-built) - nixpkgs version has webpack build issues
  gitlensExtension = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "gitlens";
      publisher = "eamodio";
      version = "2025.11.1404";
      sha256 = "sha256-Brx0MOKAIPDGoD1Lo51ZCq1BtCEL8rgYW2EbGaOQ97o=";
    };
    meta = {
      description = "Git supercharged";
      license = lib.licenses.mit;
    };
  };

  marketplaceExtensions = [ playwrightExtension chatgptExtension gitlensExtension ];

  baseExtensions = (with pkgs.vscode-extensions; [
    # Development essentials
    ms-vscode-remote.remote-ssh
    ms-vscode-remote.remote-containers
    github.codespaces
    # ms-vscode.remote-server  # May not be available in nixpkgs

    # Networking
    tailscale.vscode-tailscale

    # AI Assistants
    anthropic.claude-code
    github.copilot
    github.copilot-chat
    Google.gemini-cli-vscode-ide-companion

    # Git integration
    # eamodio.gitlens - using marketplace version instead (nixpkgs build fails)
    mhutchie.git-graph
    github.vscode-pull-request-github

    # Container tools
    ms-azuretools.vscode-docker      # Docker extension for VS Code
    ms-azuretools.vscode-containers  # Newer Container Tools extension (includes Docker + Podman)

    # Nix support
    bbenoist.nix
    jnoortheen.nix-ide

    # General development
    esbenp.prettier-vscode
    dbaeumer.vscode-eslint
    ms-python.python
    golang.go
    denoland.vscode-deno
    # rust-lang.rust-analyzer  # Disabled on Darwin - has native build issues

    # Theme and UI
    pkief.material-icon-theme
    zhuangtongfa.material-theme
    catppuccin.catppuccin-vsc
    catppuccin.catppuccin-vsc-icons

    # Productivity
    vscodevim.vim
    streetsidesoftware.code-spell-checker
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    # Linux-only extensions (have native build issues on Darwin)
    rust-lang.rust-analyzer
  ]) ++ [
    # 1Password extension (special syntax due to naming)
    pkgs.vscode-extensions."1Password".op-vscode
  ] ++ marketplaceExtensions;

  baseExtensionIds = [
    "ms-vscode-remote.remote-ssh"
    "ms-vscode-remote.remote-containers"
    "github.codespaces"
    "tailscale.vscode-tailscale"
    "anthropic.claude-code"
    "github.copilot"
    "github.copilot-chat"
    "Google.gemini-cli-vscode-ide-companion"
    "eamodio.gitlens"
    "mhutchie.git-graph"
    "github.vscode-pull-request-github"
    "ms-azuretools.vscode-docker"
    "ms-azuretools.vscode-containers"
    "bbenoist.nix"
    "jnoortheen.nix-ide"
    "esbenp.prettier-vscode"
    "dbaeumer.vscode-eslint"
    "ms-python.python"
    "golang.go"
    "denoland.vscode-deno"
    # "rust-lang.rust-analyzer"  # Disabled on Darwin
    "pkief.material-icon-theme"
    "zhuangtongfa.material-theme"
    "catppuccin.catppuccin-vsc"
    "catppuccin.catppuccin-vsc-icons"
    "vscodevim.vim"
    "streetsidesoftware.code-spell-checker"
    "1Password.op-vscode"
    "ms-playwright.playwright"
    "openai.chatgpt"
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    "rust-lang.rust-analyzer"
  ];

  githubSyncedExtensions = [
    "github.copilot"
    "github.copilot-chat"
    "eamodio.gitlens"
    "mhutchie.git-graph"
  ];

  nixosIgnoredExtensions = lib.subtractLists githubSyncedExtensions baseExtensionIds;

  baseUserSettings = {
    # 1Password integration settings - Best practices from official docs

    # Core functionality
    "1password.items.cacheValues" = true; # Cache CLI values for performance
    "1password.items.useSecretReferences" = true; # Enable secret reference syntax
    "1password.editor.suggestStorage" = true; # Auto-detect and suggest saving secrets

    # Interactive features
    "1password.hover.enableHover" = true; # Show secret details on hover
    "1password.hover.enableUnlock" = true; # Allow unlocking secrets inline
    "1password.codeLens.enable" = true; # Show CodeLens for detected secrets
    "1password.contextMenu.enable" = true; # Add 1Password to context menu

    # Inline suggestions for secret references
    "1password.editor.enableInlineSuggestions" = true; # Suggest secret references while typing

    # Default account configuration
    "1password.account" = "vinod@pittampalli.com"; # Default account email
    "1password.defaultVault" = "Personal"; # Default vault name for new items
    "1password.signInAddress" = "https://my.1password.com/"; # Sign-in address

    # Password generation recipe for new secrets
    "1password.items.passwordRecipe" = {
      "length" = 32;
      "includeSymbols" = true;
      "includeNumbers" = true;
      "includeUppercase" = true;
      "includeLowercase" = true;
    };

    # Secret reference format preference (op://vault/item/field)
    "1password.secretReferenceFormat" = "op://vault/item/field";

    # Secret reference suggestions
    "1password.suggestions.enabled" = true; # Enable autocomplete for secret references
    "1password.suggestions.triggerCharacters" = [ "\"" "'" "=" ]; # Trigger on quotes and equals

    # Automatic secret detection patterns
    "1password.detection.enableAutomaticDetection" = true;
    "1password.detection.filePatterns" = [
      "**/.env*"
      "**/.envrc" # direnv configuration
      "**/config.json"
      "**/config.yaml"
      "**/config.yml"
      "**/settings.json"
      "**/*.config.js"
      "**/*.config.ts"
      "**/docker-compose.yml"
      "**/docker-compose.yaml"
      "**/.aws/credentials"
      "**/*.tfvars" # Terraform variables
      "**/*.tfvars.json"
    ];

    # Additional patterns to detect secrets in code
    "1password.detection.patterns" = [
      "password"
      "secret"
      "api_key"
      "apiKey"
      "token"
      "access_key"
      "private_key"
    ];

    # Use libsecret for persistent credential storage (GitHub OAuth tokens, etc.)
    # 1Password continues to handle git credentials via git-credential-op
    # Using gnome-libsecret as it provides better compatibility with KWallet via Secret Service API
    # Direct kwallet5/kwallet6 options have compatibility issues with VS Code on KDE 6
    # See: https://code.visualstudio.com/docs/configure/settings-sync#_troubleshooting-keychain-issues
    "password-store" = "gnome-libsecret"; # Use libsecret for encrypted, persistent token storage

    # Terminal integration with bash as default
    "terminal.integrated.defaultProfile.linux" = "bash"; # Use bash as default
    "terminal.integrated.profiles.linux" = {
      "bash" = {
        "path" = "${pkgs.bashInteractive}/bin/bash";
        "args" = [ "--login" ];
        "icon" = "terminal-bash";
        "env" = {
          "SSH_AUTH_SOCK" = "$HOME/.1password/agent.sock";
          "BROWSER" = "${pkgs.firefox}/bin/firefox";
        };
      };
      "bash-sesh" = {
        "path" = "${pkgs.bashInteractive}/bin/bash";
        "args" = [
          "--login"
          "-c"
          "if command -v sesh >/dev/null 2>&1; then SESSION=$(basename \"$(pwd)\" | tr '[:upper:]' '[:lower:]'); sesh connect \"$SESSION\" || exec bash -l; else exec bash -l; fi"
        ];
        "icon" = "terminal-tmux";
        "env" = {
          "SSH_AUTH_SOCK" = "$HOME/.1password/agent.sock";
          "VSCODE_TERMINAL" = "true"; # Signal to tmux that we're in VS Code
          "TERM" = "xterm-256color"; # Ensure consistent TERM variable
          "BROWSER" = "${pkgs.firefox}/bin/firefox"; # For OAuth flows
        };
        "overrideName" = true;
      };
    };
    # Use regular bash instead of konsole for external terminal
    "terminal.external.linuxExec" = "${pkgs.bashInteractive}/bin/bash";

    # Terminal sizing and rendering fixes for tmux compatibility
    "terminal.integrated.scrollback" = 10000; # Adequate scrollback buffer
    "terminal.integrated.localEchoExcludePrograms" = [ "tmux" "screen" ]; # Disable local echo for tmux
    "terminal.integrated.environmentChangesRelaunch" = false; # Don't relaunch on env changes
    "terminal.integrated.persistentSessionScrollback" = 100; # Limit persistent scrollback

    # Global terminal environment for OAuth flows
    "terminal.integrated.env.linux" = {
      "BROWSER" = "${pkgs.firefox}/bin/firefox";
    };

    # SSH configuration for 1Password
    "remote.SSH.configFile" = "~/.ssh/config";
    "remote.SSH.showLoginTerminal" = true;
    "remote.SSH.useLocalServer" = false;

    # Tailscale extension configuration
    "tailscale.portDiscovery.enabled" = true;
    "tailscale.ssh.defaultUsername" = "vpittamp";
    "tailscale.ssh.connectionTimeout" = 30000;
    "tailscale.socketPath" = "/run/tailscale/tailscaled.sock";
    "tailscale.fileExplorer.showDotFiles" = true;

    # Git integration
    "git.enableSmartCommit" = true;
    "git.autofetch" = true;
    "git.confirmSync" = false;

    # GitHub authentication - use system credential helper
    "github.gitAuthentication" = true;
    "github.gitProtocol" = "https";
    # Use gh CLI for authentication
    "git.terminalAuthentication" = true;

    # Editor settings - use system scaling
    "editor.fontSize" = 14;
    "editor.fontFamily" = "'JetBrains Mono', 'Fira Code', monospace";
    "editor.fontLigatures" = true;
    "editor.formatOnSave" = true;
    "editor.minimap.enabled" = false;
    "editor.rulers" = [ 80 120 ];
    "editor.renderWhitespace" = "trailing";

    # Display settings - adjust for Wayland HiDPI
    "window.zoomLevel" = 0; # Default zoom level for Wayland
    "terminal.integrated.fontSize" = 14; # Standard terminal font

    # Auto-save configuration
    "files.autoSave" = "afterDelay";
    "files.autoSaveDelay" = 1000;

    # File associations
    "files.associations" = {
      "*.nix" = "nix";
      "flake.lock" = "json";
      ".env*" = "dotenv";
      ".envrc" = "shellscript";
    };

    # Exclude sensitive files from search and Git
    "files.exclude" = {
      "**/.env" = true; # Hide actual .env files (keep .env.example visible)
    };

    # Warn when opening files that might contain secrets
    "files.watcherExclude" = {
      "**/.git/objects/**" = true;
      "**/.git/subtree-cache/**" = true;
      "**/node_modules/**" = true;
    };

    # Workspace
    "workbench.colorTheme" = "Material Theme Darker";
    "workbench.iconTheme" = "material-icon-theme";
    "workbench.startupEditor" = "none";

    # Vim settings (if using VSCodeVim)
    "vim.useSystemClipboard" = true;
    "vim.hlsearch" = true;
    "vim.insertModeKeyBindings" = [
      {
        "before" = [ "j" "j" ];
        "after" = [ "<Esc>" ];
      }
    ];

    # Nix IDE settings
    "nix.enableLanguageServer" = true;
    "nix.serverPath" = "nil";
    "nix.serverSettings" = {
      "nil" = {
        "formatting" = {
          "command" = [ "nixpkgs-fmt" ];
        };
      };
    };

    # Claude Code extension settings
    # Note: VSCode extension uses ~/.claude/settings.json for permissions
    # The permissions configured in home-modules/ai-assistants/claude-code.nix apply here
    "claude-code.enableTelemetry" = true;
    "claude-code.autoCompactEnabled" = true;
    "claude-code.todoFeatureEnabled" = true;
    "claude-code.includeCoAuthoredBy" = true;
    "claude-code.messageIdleNotifThresholdMs" = 60000;

    # GitHub Copilot settings for full automation
    "github.copilot.enable" = {
      "*" = true;
      "yaml" = true;
      "plaintext" = true;
      "markdown" = true;
    };
    "github.copilot.editor.enableAutoCompletions" = true;
    "github.copilot.chat.followUps.enabled" = true;

    # Gemini CLI settings
    "gemini.autoStart" = true;
    "gemini.enableCodeActions" = true;

    # Docker extension settings
    "docker.dockerPath" = "${pkgs.docker}/bin/docker";
    "docker.dockerComposePath" = "${pkgs.docker-compose}/bin/docker-compose";
    "docker.enableDockerComposeLanguageService" = true;
    "docker.showStartPage" = false;
    "docker.environment" = {
      "DOCKER_CONFIG" = "$HOME/.docker";
    };

    # Add Docker-related files to secret detection
    # (Already includes docker-compose.yml in the detection.filePatterns above)
  };

  baseKeybindings = [
    {
      key = "ctrl+shift+p";
      command = "workbench.action.showCommands";
    }
    # 1Password keybindings (matching docs/1PASSWORD_VSCODE.md)
    {
      key = "ctrl+alt+o";
      command = "1password.open";
      when = "editorTextFocus";
    }
    {
      key = "ctrl+alt+g";
      command = "1password.generate";
      when = "editorTextFocus";
    }
    {
      key = "ctrl+alt+s";
      command = "1password.save";
      when = "editorTextFocus && editorHasSelection";
    }
    # Additional 1Password commands
    {
      key = "ctrl+alt+i";
      command = "1password.insertSecretReference";
      when = "editorTextFocus";
    }
    {
      key = "ctrl+alt+k";
      command = "workbench.action.terminal.openNativeConsole";
    }
  ];

  # MCP Server configuration for VSCode
  # These servers enable browser automation and debugging capabilities
  # Only enabled on Linux where Chromium is available
  baseMcpConfig = {
    mcpServers = lib.optionalAttrs enableChromiumMcpServers {
      playwright = {
        command = "${pkgs.nodejs}/bin/npx";
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
          LOG_DIR = "/tmp/mcp-playwright-logs";
        };
      };

      chrome-devtools = {
        command = "${pkgs.nodejs}/bin/npx";
        args = [
          "-y"
          "chrome-devtools-mcp@latest"
          "--isolated"
          "--headless"
          "--executablePath"
          chromiumConfig.chromiumBin
        ];
        env = {
          NODE_ENV = "production";
        };
      };
    };
  };

  # Default profile configuration
  # Using "default" profile name to enable extension update settings
  # which only work on the default profile per home-manager module constraints
  defaultProfile = {
    extensions = baseExtensions;

    # Enable extension and VSCode update checks (only works for default profile)
    enableExtensionUpdateCheck = true;
    enableUpdateCheck = true;

    userSettings = baseUserSettings // {
      # Only sync GitHub-centric extensions; other tooling stays local to this machine
      "settingsSync.keybindingsPerPlatform" = true;
      "settingsSync.ignoredExtensions" = nixosIgnoredExtensions;
      "settingsSync.ignoredSettings" = [
        "1password.account"
        "1password.defaultVault"
        "1password.signInAddress"
        # Don't sync local paths to Codespaces
        "terminal.integrated.profiles.linux"
        "remote.SSH.configFile"
      ];

      # Extension auto-update settings
      "extensions.autoUpdate" = true;
      "extensions.autoCheckUpdates" = true;

      # GitHub Codespaces settings
      "github.codespaces.defaultExtensions" = baseExtensionIds;
      "github.codespaces.devContainerPath" = ".devcontainer/devcontainer.json";
    };
    keybindings = baseKeybindings;
    userMcp = baseMcpConfig;
  };

  # Override standard vscode package to remove desktop files
  vscodeNoDesktop = vscode.overrideAttrs (oldAttrs: {
    postFixup = (oldAttrs.postFixup or "") + ''
      # Remove desktop files to prevent duplicate entries
      rm -rf $out/share/applications
    '';
  });
in
{
  options.modules.tools.vscode = {
    defaultProfile = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Default VSCode profile name used by all instances";
    };
  };

  config = {
    programs.vscode = {
      enable = true;
      package = if isM1 then vscodeWithFlags else vscodeNoDesktop;

    # Allow extensions to be installed/updated manually or by VSCode
    # This is required when using profiles to avoid read-only filesystem conflicts
    mutableExtensionsDir = true;

    # Use the default profile to enable extension auto-update features
    # Per-activity customization is handled via working directories and environment variables
    profiles = {
      default = defaultProfile;
      nixos = defaultProfile;  # Alias for nixos profile with same settings
    };
  };

  # Create VSCode settings directory and SSH config for 1Password
  # Pre-create globalStorage directories for all profiles to prevent SQLITE_CANTOPEN errors
  home.file = {
    ".vscode-server/data/Machine/settings.json" = {
      text = builtins.toJSON config.programs.vscode.profiles.${primaryProfile}.userSettings;
    };
  } // lib.listToAttrs (
    # Dynamically generate globalStorage/.keep for all configured VS Code profiles
    map
      (profileName: {
        name = ".config/Code/User/profiles/${profileName}/globalStorage/.keep";
        value = { text = ""; };
      })
      (builtins.attrNames config.programs.vscode.profiles)
  );

    # Environment variables for VSCode
    home.sessionVariables = {
      # Use 1Password SSH agent in VSCode terminal
      VSCODE_SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
    };
  };
}

{ config, pkgs, lib, osConfig, ... }:

let
  profile = "default";
  isM1 = osConfig.networking.hostName or "" == "nixos-m1";

  # Declarative VSCode package with proper flags for M1/ARM64
  # Using makeWrapper to add command-line flags for Wayland
  vscodeWithFlags = pkgs.vscode.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ pkgs.makeWrapper ];
    postFixup = (oldAttrs.postFixup or "") + ''
      wrapProgram $out/bin/code \
        --add-flags "--ozone-platform=wayland" \
        --add-flags "--enable-features=WaylandWindowDecorations" \
        --set ELECTRON_OZONE_PLATFORM_HINT "auto"
    '';
  });
in
{
  programs.vscode = {
    enable = true;
    package = if isM1 then vscodeWithFlags else pkgs.vscode;

    profiles.${profile} = {
      # Extensions for development and 1Password integration
      extensions = (with pkgs.vscode-extensions; [
      # Development essentials
      ms-vscode-remote.remote-ssh
      ms-vscode-remote.remote-containers
      # ms-vscode.remote-server  # May not be available in nixpkgs

      # Git integration
      eamodio.gitlens
      mhutchie.git-graph

      # Nix support
      bbenoist.nix
      jnoortheen.nix-ide

      # General development
      esbenp.prettier-vscode
      dbaeumer.vscode-eslint
      ms-python.python
      golang.go
      rust-lang.rust-analyzer

      # Theme and UI
      pkief.material-icon-theme
      zhuangtongfa.material-theme

      # Productivity
      vscodevim.vim
      streetsidesoftware.code-spell-checker
    ]) ++ [
      # 1Password extension (special syntax due to naming)
      pkgs.vscode-extensions."1Password".op-vscode
    ];
      # User settings for VSCode
      userSettings = {
      # 1Password integration settings
      "1password.items.cacheValues" = true;  # Cache CLI values for performance
      "1password.items.useSecretReferences" = true;  # Enable secret reference syntax
      "1password.editor.suggestStorage" = true;  # Auto-detect and suggest saving secrets
      "1password.hover.enableHover" = true;  # Show secret details on hover
      "1password.hover.enableUnlock" = true;  # Allow unlocking secrets inline
      "1password.codeLens.enable" = true;  # Show CodeLens for detected secrets
      "1password.contextMenu.enable" = true;  # Add 1Password to context menu

      # Default account configuration
      "1password.account" = "vinod@pittampalli.com";  # Default account email
      "1password.defaultVault" = "Personal";  # Default vault name
      "1password.signInAddress" = "https://my.1password.com/";  # Sign-in address

      # Password generation recipe for new secrets
      "1password.items.passwordRecipe" = {
        "length" = 32;
        "includeSymbols" = true;
        "includeNumbers" = true;
        "includeUppercase" = true;
        "includeLowercase" = true;
      };

      # Secret reference format preference
      "1password.secretReferenceFormat" = "op://vault/item/field";

      # Automatic secret detection patterns
      "1password.detection.enableAutomaticDetection" = true;
      "1password.detection.filePatterns" = [
        "**/.env*"
        "**/config.json"
        "**/settings.json"
        "**/*.config.js"
        "**/*.config.ts"
      ];

      # Disable KDE Wallet integration - use 1Password instead
      "password-store" = "basic";  # Use basic keychain instead of system keychain

      # Terminal integration with tmux sizing fixes
      "terminal.integrated.defaultProfile.linux" = "bash-sesh";  # Use bash-sesh as default
      "terminal.integrated.profiles.linux" = {
        "bash" = {
          "path" = "${pkgs.bashInteractive}/bin/bash";
          "args" = [ "--login" ];
          "icon" = "terminal-bash";
          "env" = {
            "SSH_AUTH_SOCK" = "$HOME/.1password/agent.sock";
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
            "VSCODE_TERMINAL" = "true";  # Signal to tmux that we're in VS Code
            "TERM" = "xterm-256color";  # Ensure consistent TERM variable
          };
          "overrideName" = true;
        };
      };
      # Use regular bash instead of konsole for external terminal
      "terminal.external.linuxExec" = "${pkgs.bashInteractive}/bin/bash";

      # Terminal sizing and rendering fixes for tmux compatibility
      "terminal.integrated.scrollback" = 10000;  # Adequate scrollback buffer
      "terminal.integrated.localEchoExcludePrograms" = [ "tmux" "screen" ];  # Disable local echo for tmux
      "terminal.integrated.environmentChangesRelaunch" = false;  # Don't relaunch on env changes
      "terminal.integrated.persistentSessionScrollback" = 100;  # Limit persistent scrollback

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

      # Editor settings - use system scaling
      "editor.fontSize" = 14;
      "editor.fontFamily" = "'JetBrains Mono', 'Fira Code', monospace";
      "editor.fontLigatures" = true;
      "editor.formatOnSave" = true;
      "editor.minimap.enabled" = false;
      "editor.rulers" = [ 80 120 ];
      "editor.renderWhitespace" = "trailing";

      # Display settings - adjust for Wayland HiDPI
      "window.zoomLevel" = 0;  # Default zoom level for Wayland
      "terminal.integrated.fontSize" = 14;  # Standard terminal font

      # File associations
      "files.associations" = {
        "*.nix" = "nix";
        "flake.lock" = "json";
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
      };

      # Keybindings
      keybindings = [
      {
        key = "ctrl+shift+p";
        command = "workbench.action.showCommands";
      }
      {
        key = "ctrl+shift+o";
        command = "1password.open";
        when = "editorTextFocus";
      }
      {
        key = "ctrl+shift+l";
        command = "1password.generate";
        when = "editorTextFocus";
      }
      {
        key = "ctrl+shift+s";
        command = "1password.save";
        when = "editorTextFocus && editorHasSelection";
      }
      {
        key = "ctrl+alt+k";
        command = "workbench.action.terminal.openNativeConsole";
      }
      ];
    };
  };

  # Create VSCode settings directory and SSH config for 1Password
  home.file.".vscode-server/data/Machine/settings.json" = {
    text = builtins.toJSON config.programs.vscode.profiles.${profile}.userSettings;
  };

  # Environment variables for VSCode
  home.sessionVariables = {
    # Use 1Password SSH agent in VSCode terminal
    VSCODE_SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
  };
}
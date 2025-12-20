{ config, pkgs, lib, ... }:

let
  # Use Nix package reference for 1Password browser support
  onePasswordBrowserSupport = "${pkgs._1password-gui}/share/1password/1Password-BrowserSupport";

in
{
  # Google Chrome browser configuration
  # Switched from Chromium to Chrome for Claude in Chrome compatibility
  # Claude in Chrome requires Google Chrome for full functionality
  home.packages = [
    pkgs.google-chrome
  ];

  # Native messaging host manifest for 1Password (Google Chrome)
  home.file.".config/google-chrome/NativeMessagingHosts/com.1password.1password.json" = {
    text = builtins.toJSON {
      name = "com.1password.1password";
      description = "1Password Native Messaging Host";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
      ];
      path = onePasswordBrowserSupport;
    };
  };

  # Additional native messaging host for 1Password browser support
  home.file.".config/google-chrome/NativeMessagingHosts/com.1password.browser_support.json" = {
    text = builtins.toJSON {
      name = "com.1password.browser_support";
      description = "1Password Browser Support";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
      ];
      path = onePasswordBrowserSupport;
    };
  };

  # Claude Code manages its own native messaging host file at:
  # ~/.config/google-chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json
  # We don't manage it with Nix because Claude Code needs to write to it.
  #
  # However, Claude Code generates ~/.claude/chrome/chrome-native-host with #!/bin/bash shebang
  # which doesn't work on NixOS. We fix this with an activation script below.

  # Fix Claude Code's native host script shebang on activation
  # This runs after Claude Code creates the file, replacing the broken #!/bin/bash shebang
  home.activation.fixClaudeNativeHost = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -f "$HOME/.claude/chrome/chrome-native-host" ]; then
      # Check if the shebang is the problematic #!/bin/bash
      if head -1 "$HOME/.claude/chrome/chrome-native-host" | grep -q '^#!/bin/bash'; then
        echo "Fixing Claude native host shebang for NixOS..."
        # Get the node and cli paths from the existing script
        NODE_PATH=$(grep -o '/nix/store/[^/]*/bin/node' "$HOME/.claude/chrome/chrome-native-host" | head -1)
        CLI_PATH=$(grep -o '/nix/store/[^"]*cli\.js' "$HOME/.claude/chrome/chrome-native-host" | head -1)
        if [ -n "$NODE_PATH" ] && [ -n "$CLI_PATH" ]; then
          cat > "$HOME/.claude/chrome/chrome-native-host" << EOF
#!/usr/bin/env bash
# Chrome native host wrapper script - Fixed for NixOS
exec "$NODE_PATH" "$CLI_PATH" --chrome-native-host
EOF
          chmod +x "$HOME/.claude/chrome/chrome-native-host"
        fi
      fi
    fi
  '';

  # Configure 1Password browser integration settings
  home.file.".config/1Password/settings/browser-support.json" = {
    text = builtins.toJSON {
      "browser.autoFillShortcut" = {
        "enabled" = true;
        "shortcut" = "Ctrl+Shift+L";
      };
      "browser.showSavePrompts" = true;
      "browser.theme" = "system";
      "security.authenticatedUnlock.enabled" = true;
      "security.authenticatedUnlock.method" = "system";
      "security.autolock.minutes" = 10;
      "security.clipboardClearAfterSeconds" = 90;
    };
  };

  # Shell aliases for convenience
  home.shellAliases = {
    chrome = "google-chrome-stable";
    browser = "google-chrome-stable";
  };
}

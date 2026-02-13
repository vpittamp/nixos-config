{ config, pkgs, lib, ... }:

let
  # Use Nix package reference for 1Password browser support
  onePasswordBrowserSupport = "${pkgs._1password-gui}/share/1password/1Password-BrowserSupport";

  # Cluster CA certificate for *.cnoe.localtest.me
  # This is the CA certificate (with CA:TRUE) that signs the server certificates
  # Chrome requires separate NSS database configuration
  clusterCaCert = pkgs.writeText "cnoe-ca.pem" ''
    -----BEGIN CERTIFICATE-----
    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
    CBn6
    -----END CERTIFICATE-----
  '';

in
{
  # Google Chrome browser configuration
  # Switched from Chromium to Chrome for Claude in Chrome compatibility
  # Claude in Chrome requires Google Chrome for full functionality
  home.packages =
    [ pkgs.google-chrome ]
    ++ lib.optionals (pkgs ? google-chrome-beta) [ pkgs.google-chrome-beta ]
    ++ lib.optionals (pkgs ? google-chrome-unstable) [ pkgs.google-chrome-unstable ];

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
    chrome-beta = "google-chrome-beta";
    chrome-dev = "google-chrome-unstable";
  };

  # Add cluster CA certificate to Chrome's NSS database for HTTPS trust
  # Chrome uses ~/.pki/nssdb/ for certificate storage (separate from system CA store)
  # This makes Chrome trust *.cnoe.localtest.me self-signed certificates
  home.activation.chromeTrustClusterCert = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    NSS_DB="$HOME/.pki/nssdb"
    CERT_NICKNAME="CNOE-Local-Dev-CA"

    # Ensure NSS database directory exists with proper permissions
    mkdir -p "$NSS_DB"

    # Initialize NSS database if it doesn't exist
    if [ ! -f "$NSS_DB/cert9.db" ]; then
      echo "Initializing Chrome NSS database..."
      ${pkgs.nssTools}/bin/certutil -d sql:"$NSS_DB" -N --empty-password
    fi

    # Check if certificate already exists
    if ${pkgs.nssTools}/bin/certutil -d sql:"$NSS_DB" -L -n "$CERT_NICKNAME" >/dev/null 2>&1; then
      # Certificate exists - delete and re-add to ensure it's current
      ${pkgs.nssTools}/bin/certutil -d sql:"$NSS_DB" -D -n "$CERT_NICKNAME" 2>/dev/null || true
    fi

    # Add the cluster CA certificate as trusted for SSL (CT,C,C = trusted for SSL/email/code)
    echo "Adding cluster CA certificate to Chrome trust store..."
    ${pkgs.nssTools}/bin/certutil -d sql:"$NSS_DB" -A -n "$CERT_NICKNAME" -t "CT,C,C" -i "${clusterCaCert}"
  '';
}

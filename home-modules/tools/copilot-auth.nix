{ config, pkgs, lib, ... }:

# GitHub Copilot Authentication for NixOS
# Integrates with 1Password for secure token storage
#
# BEST PRACTICE: Use environment variable injection (Method 1)
# copilot.lua natively supports GITHUB_COPILOT_TOKEN or GH_COPILOT_TOKEN
#
# Setup:
# 1. Authenticate with GitHub Copilot (one-time):
#    - Open Neovim and run :Copilot auth
#    - Complete the device flow in browser
#    - Run :Copilot auth info to see the token
#
# 2. Store token in 1Password:
#    copilot-setup-1password  # Automated script (after :Copilot auth)
#    # OR manually:
#    op item create --category=login \
#      --title="GitHub Copilot Token" \
#      --vault="Personal" \
#      "username=YOUR_GITHUB_USERNAME" \
#      "password=ghu_YOUR_TOKEN_HERE"
#
# 3. Use nvim-copilot wrapper (recommended) or rebuild NixOS
#
# The token will be injected via GITHUB_COPILOT_TOKEN environment variable,
# which is more secure than storing in hosts.json (never written to disk).

{
  # Method 1: 1Password wrapper for Neovim (RECOMMENDED - most secure)
  # Token is injected at runtime, never persisted to disk
  home.packages = [
    (pkgs.writeShellScriptBin "nvim-copilot" ''
      # Launch Neovim with GitHub Copilot token from 1Password
      # Uses op run to inject token securely at runtime

      if ! command -v op &> /dev/null; then
        echo "Warning: 1Password CLI not found, launching nvim without Copilot token"
        exec nvim "$@"
      fi

      # Check if 1Password is accessible (might require biometric)
      if op account list &> /dev/null 2>&1; then
        # Inject token via environment variable (best practice per copilot.lua docs)
        export GITHUB_COPILOT_TOKEN=$(op item get "GitHub Copilot Token" --fields password 2>/dev/null || echo "")
        if [ -n "$GITHUB_COPILOT_TOKEN" ]; then
          exec nvim "$@"
        else
          echo "Warning: Token not found in 1Password, launching nvim without Copilot"
          exec nvim "$@"
        fi
      else
        # Fallback: try to use hosts.json if it exists
        if [ -f "$HOME/.config/github-copilot/hosts.json" ]; then
          exec nvim "$@"
        else
          echo "1Password not signed in and no hosts.json found"
          echo "Run: op signin && copilot-refresh-token"
          exec nvim "$@"
        fi
      fi
    '')
  ];

  # Method 2: Static environment variable (fallback, less secure)
  # Uncomment to set token at shell startup (requires op signin first)
  # programs.bash.sessionVariables = {
  #   GITHUB_COPILOT_TOKEN = "$(op item get 'GitHub Copilot Token' --fields password 2>/dev/null || echo '')";
  # };

  # Method 2: Direct environment variable (temporary solution)
  # Set the token directly in your environment before launching nvim
  # export GITHUB_COPILOT_TOKEN="your_token_here"

  # Method 3: Create hosts.json at activation (most compatible)
  # This creates the file that copilot.lua expects
  # Priority: 1Password > apps.json > existing hosts.json
  home.activation.setupCopilotAuth = lib.hm.dag.entryAfter ["writeBoundary"] ''
    COPILOT_DIR="$HOME/.config/github-copilot"
    HOSTS_FILE="$COPILOT_DIR/hosts.json"
    APPS_FILE="$COPILOT_DIR/apps.json"

    # Ensure directory exists and is writable
    mkdir -p "$COPILOT_DIR"
    chmod 700 "$COPILOT_DIR"

    # Try to get token from 1Password first (if signed in)
    if command -v op >/dev/null 2>&1; then
      # Check if we can access 1Password (signed in)
      if op account list >/dev/null 2>&1; then
        TOKEN=$(op item get "GitHub Copilot Token" --fields password 2>/dev/null || echo "")
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
          USER=$(op item get "GitHub Copilot Token" --fields username 2>/dev/null || echo "vpittamp")
          cat > "$HOSTS_FILE" <<EOF
{
  "github.com": {
    "user": "$USER",
    "oauth_token": "$TOKEN"
  }
}
EOF
          chmod 600 "$HOSTS_FILE"
          echo "✓ Created hosts.json from 1Password"
        fi
      fi
    fi

    # Fallback: If hosts.json doesn't exist yet, try apps.json
    if [ ! -f "$HOSTS_FILE" ] && [ -f "$APPS_FILE" ]; then
      echo "Creating hosts.json from apps.json for copilot.lua..."

      # Extract token from apps.json (first token found)
      TOKEN=$(${pkgs.jq}/bin/jq -r '.[] | .oauth_token' "$APPS_FILE" 2>/dev/null | head -1)
      USER=$(${pkgs.jq}/bin/jq -r '.[] | .user' "$APPS_FILE" 2>/dev/null | head -1)

      if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
        # Create hosts.json in the format copilot.lua expects
        cat > "$HOSTS_FILE" <<EOF
{
  "github.com": {
    "user": "$USER",
    "oauth_token": "$TOKEN"
  }
}
EOF
        chmod 600 "$HOSTS_FILE"
        echo "✓ Created hosts.json with token from apps.json"
      fi
    fi
  '';

  # Also create a helper script for manual token refresh
  home.file.".local/bin/copilot-refresh-token" = {
    text = ''
      #!/usr/bin/env bash
      # Refresh GitHub Copilot token from 1Password

      set -euo pipefail

      COPILOT_DIR="$HOME/.config/github-copilot"
      HOSTS_FILE="$COPILOT_DIR/hosts.json"

      if ! command -v op &> /dev/null; then
        echo "Error: 1Password CLI (op) not found"
        exit 1
      fi

      if ! op account list &> /dev/null; then
        echo "Error: Not signed into 1Password. Run: op signin"
        exit 1
      fi

      echo "Fetching token from 1Password..."
      TOKEN=$(op item get "GitHub Copilot Token" --fields password 2>/dev/null || echo "")
      USER=$(op item get "GitHub Copilot Token" --fields username 2>/dev/null || echo "vpittamp")

      if [ -z "$TOKEN" ]; then
        echo "Error: Token not found in 1Password"
        echo "Create it with:"
        echo "  op item create --category=password --title='GitHub Copilot Token' --vault=Personal token[password]='YOUR_TOKEN'"
        exit 1
      fi

      mkdir -p "$COPILOT_DIR"
      cat > "$HOSTS_FILE" <<EOF
{
  "github.com": {
    "user": "$USER",
    "oauth_token": "$TOKEN"
  }
}
EOF
      chmod 600 "$HOSTS_FILE"

      echo "✓ Updated $HOSTS_FILE"
      echo "✓ Restart Neovim to use the new token"
    '';
    executable = true;
  };

  # Helper script to store Copilot token in 1Password
  home.file.".local/bin/copilot-setup-1password" = {
    text = ''
      #!/usr/bin/env bash
      # Store GitHub Copilot token in 1Password
      # This extracts the token from apps.json (created by VS Code or Copilot auth)
      # and stores it in 1Password for secure, centralized management.

      set -euo pipefail

      COPILOT_DIR="$HOME/.config/github-copilot"
      APPS_FILE="$COPILOT_DIR/apps.json"

      if ! command -v op &> /dev/null; then
        echo "Error: 1Password CLI (op) not found"
        exit 1
      fi

      if ! op account list &> /dev/null; then
        echo "Error: Not signed into 1Password. Run: op signin"
        exit 1
      fi

      if [ ! -f "$APPS_FILE" ]; then
        echo "Error: $APPS_FILE not found"
        echo ""
        echo "Please authenticate with GitHub Copilot first:"
        echo "  1. Open Neovim and run :Copilot auth"
        echo "  2. Or use VS Code's GitHub Copilot extension"
        echo "  3. Then run this script again"
        exit 1
      fi

      echo "Extracting token from $APPS_FILE..."
      TOKEN=$(${pkgs.jq}/bin/jq -r '.[] | .oauth_token' "$APPS_FILE" 2>/dev/null | head -1)
      USER=$(${pkgs.jq}/bin/jq -r '.[] | .user' "$APPS_FILE" 2>/dev/null | head -1)

      if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo "Error: No valid token found in apps.json"
        exit 1
      fi

      echo "Token found for user: $USER"
      echo ""

      # Check if item already exists
      if op item get "GitHub Copilot Token" &>/dev/null; then
        echo "Updating existing 1Password item..."
        op item edit "GitHub Copilot Token" \
          "password=$TOKEN" \
          "username=$USER" \
          --vault=Personal
      else
        echo "Creating new 1Password item..."
        op item create \
          --category=login \
          --title="GitHub Copilot Token" \
          --vault=Personal \
          "username=$USER" \
          "password=$TOKEN" \
          "website=https://github.com/features/copilot"
      fi

      echo ""
      echo "✓ Token stored in 1Password (Personal vault)"
      echo "✓ Now run: copilot-refresh-token"
      echo "✓ Or rebuild NixOS to auto-configure"
    '';
    executable = true;
  };

  # Helper script to check Copilot auth status
  home.file.".local/bin/copilot-auth-status" = {
    text = ''
      #!/usr/bin/env bash
      # Check GitHub Copilot authentication status

      COPILOT_DIR="$HOME/.config/github-copilot"
      HOSTS_FILE="$COPILOT_DIR/hosts.json"
      APPS_FILE="$COPILOT_DIR/apps.json"

      echo "=== GitHub Copilot Authentication Status ==="
      echo ""

      # Check hosts.json (used by copilot.lua)
      if [ -f "$HOSTS_FILE" ]; then
        echo "✓ hosts.json exists"
        USER=$(${pkgs.jq}/bin/jq -r '."github.com".user // "unknown"' "$HOSTS_FILE" 2>/dev/null)
        TOKEN=$(${pkgs.jq}/bin/jq -r '."github.com".oauth_token // ""' "$HOSTS_FILE" 2>/dev/null)
        if [ -n "$TOKEN" ]; then
          echo "  User: $USER"
          echo "  Token: ''${TOKEN:0:10}... (''${#TOKEN} chars)"
        else
          echo "  ⚠ No token found in hosts.json"
        fi
      else
        echo "✗ hosts.json not found"
      fi

      echo ""

      # Check apps.json (created by Copilot auth flow)
      if [ -f "$APPS_FILE" ]; then
        echo "✓ apps.json exists (original auth data)"
      else
        echo "✗ apps.json not found (run :Copilot auth in Neovim)"
      fi

      echo ""

      # Check 1Password integration
      if command -v op &> /dev/null; then
        echo "✓ 1Password CLI available"
        if op account list &> /dev/null; then
          echo "  ✓ Signed into 1Password"
          if op item get "GitHub Copilot Token" &>/dev/null; then
            echo "  ✓ Token stored in 1Password"
          else
            echo "  ✗ Token not in 1Password (run: copilot-setup-1password)"
          fi
        else
          echo "  ✗ Not signed into 1Password"
        fi
      else
        echo "✗ 1Password CLI not available"
      fi

      echo ""
      echo "=== Quick Commands ==="
      echo "  nvim-copilot             - Launch Neovim with 1Password token injection (recommended)"
      echo "  copilot-setup-1password  - Store token in 1Password"
      echo "  copilot-refresh-token    - Refresh hosts.json from 1Password"
      echo "  :Copilot auth            - Authenticate in Neovim"
      echo "  :Copilot status          - Check status in Neovim"
      echo ""
      echo "=== Best Practices ==="
      echo "  - Use nvim-copilot wrapper (token never written to disk)"
      echo "  - Store token in 1Password for centralized management"
      echo "  - Token is injected via GITHUB_COPILOT_TOKEN env var"
    '';
    executable = true;
  };

  # Add shell aliases for convenience
  programs.bash.shellAliases = {
    # Use 1Password-integrated Neovim by default (optional - uncomment to enable)
    # nvim = "nvim-copilot";
    # vim = "nvim-copilot";
    # vi = "nvim-copilot";
  };
}

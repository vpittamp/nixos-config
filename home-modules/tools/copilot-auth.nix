{ config, pkgs, lib, ... }:

# GitHub Copilot Authentication for NixOS
# Integrates with 1Password for secure token storage
#
# Setup:
# 1. Authenticate with GitHub Copilot (one-time):
#    - Open any editor with Copilot (VS Code, etc.)
#    - Run Copilot auth and complete the flow
#    - Copy the token from ~/.config/github-copilot/apps.json
#
# 2. Store token in 1Password:
#    op item create --category=password \
#      --title="GitHub Copilot Token" \
#      --vault="Private" \
#      token[password]="ghu_YOUR_TOKEN_HERE"
#
# 3. Rebuild NixOS configuration
#
# The token will be automatically injected into Neovim's environment
# via the GITHUB_COPILOT_TOKEN variable, which copilot.lua natively supports.

{
  # Method 1: Load token from 1Password (requires 1Password CLI and signin)
  # Uncomment and configure after storing token in 1Password
  # programs.bash.sessionVariables = {
  #   GITHUB_COPILOT_TOKEN = "$(op item get 'GitHub Copilot Token' --fields password 2>/dev/null || echo '')";
  # };

  # Method 2: Direct environment variable (temporary solution)
  # Set the token directly in your environment before launching nvim
  # export GITHUB_COPILOT_TOKEN="your_token_here"

  # Method 3: Create hosts.json at activation (most compatible)
  # This creates the file that copilot.lua expects
  home.activation.setupCopilotAuth = lib.hm.dag.entryAfter ["writeBoundary"] ''
    COPILOT_DIR="$HOME/.config/github-copilot"
    HOSTS_FILE="$COPILOT_DIR/hosts.json"
    APPS_FILE="$COPILOT_DIR/apps.json"

    # Ensure directory exists and is writable
    mkdir -p "$COPILOT_DIR"
    chmod 700 "$COPILOT_DIR"

    # If apps.json exists but hosts.json doesn't, create hosts.json from apps.json
    if [ -f "$APPS_FILE" ] && [ ! -f "$HOSTS_FILE" ]; then
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

    # Alternative: If you have token in 1Password, create hosts.json from it
    # Requires 1Password CLI and active session
    # if command -v op >/dev/null 2>&1 && op account list >/dev/null 2>&1; then
    #   TOKEN=$(op item get "GitHub Copilot Token" --fields password 2>/dev/null)
    #   if [ -n "$TOKEN" ]; then
    #     cat > "$HOSTS_FILE" <<EOF
# {
#   "github.com": {
#     "user": "$(op item get "GitHub Copilot Token" --fields username 2>/dev/null || echo "vpittamp")",
#     "oauth_token": "$TOKEN"
#   }
# }
# EOF
    #     chmod 600 "$HOSTS_FILE"
    #     echo "✓ Created hosts.json from 1Password"
    #   fi
    # fi
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
        echo "  op item create --category=password --title='GitHub Copilot Token' --vault=Private token[password]='YOUR_TOKEN'"
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
}

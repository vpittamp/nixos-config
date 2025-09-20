#!/usr/bin/env bash
# 1Password Headless Authentication Setup for Hetzner/Remote Servers
# This script helps configure 1Password CLI for headless authentication

set -e

echo "=== 1Password Headless Setup ==="
echo ""
echo "This script will help you configure 1Password CLI for headless authentication."
echo "You'll need your 1Password master password."
echo ""

# Method 1: Service Account Token (Recommended for CI/CD and automation)
echo "Method 1: Service Account Token (Best for automation)"
echo "------------------------------------------------------"
echo "1. Go to https://my.1password.com/"
echo "2. Settings → Developer → Service Accounts"
echo "3. Create a service account with vault access"
echo "4. Copy the token and run:"
echo ""
echo "   export OP_SERVICE_ACCOUNT_TOKEN='<your-token>'"
echo ""
echo "Then you can use: op item list"
echo ""

# Method 2: Session Token (For interactive use)
echo "Method 2: Session Token (For interactive terminal)"
echo "---------------------------------------------------"
echo "Run this command and enter your password when prompted:"
echo ""
echo "   export OP_SESSION_my=\$(echo '<password>' | op signin --account my.1password.com --raw)"
echo ""
echo "Or for interactive prompt:"
echo ""
echo "   export OP_SESSION_my=\$(op signin --account my.1password.com --raw)"
echo ""
echo "Then you can use: SSH_AUTH_SOCK=~/.1password/agent.sock git push"
echo ""

# Method 3: Device Registration (For persistent authentication)
echo "Method 3: Device Registration (Best for regular use)"
echo "----------------------------------------------------"
echo "1. First time setup - register this device:"
echo ""
echo "   op signin --account my.1password.com"
echo "   # Follow the prompts to authenticate and register device"
echo ""
echo "2. Future logins will be simpler:"
echo ""
echo "   eval \$(op signin)"
echo ""

# Check current status
echo "Current Status:"
echo "--------------"
if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    echo "✓ Service account token is set"
elif [ -n "$OP_SESSION_my" ]; then
    echo "✓ Session token is set"
else
    echo "✗ No authentication configured"
fi

if [ -S "$HOME/.1password/agent.sock" ]; then
    echo "✓ SSH agent socket exists"
else
    echo "✗ SSH agent socket not found"
fi

echo ""
echo "Testing connection..."
if op account list >/dev/null 2>&1; then
    echo "✓ Successfully connected to 1Password"
    echo ""
    echo "You can now use:"
    echo "  SSH_AUTH_SOCK=~/.1password/agent.sock git push"
else
    echo "✗ Not authenticated. Please use one of the methods above."
fi
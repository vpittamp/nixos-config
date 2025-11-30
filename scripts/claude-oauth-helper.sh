#!/usr/bin/env bash
# Claude CLI OAuth Helper for Remote Servers
# This script helps authenticate Claude CLI on remote servers using Tailscale

set -e

echo "Claude CLI OAuth Authentication Helper"
echo "======================================"
echo ""
echo "This script will help you authenticate Claude CLI on your remote server."
echo ""

# Check if running over SSH
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    echo "✓ Detected SSH session"
else
    echo "⚠ Not running over SSH - OAuth should work normally"
    echo "Try running: claude"
    exit 0
fi

# Check if Tailscale is running
if command -v tailscale &> /dev/null && tailscale status &> /dev/null; then
    echo "✓ Tailscale is available and connected"
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [ -n "$TAILSCALE_IP" ]; then
        echo "  Tailscale IP: $TAILSCALE_IP"
    fi
else
    echo "✗ Tailscale is not available or not connected"
    echo "  Please ensure Tailscale is installed and connected"
    exit 1
fi

echo ""
echo "OAuth Authentication Methods:"
echo "============================="
echo ""
echo "Method 1: SSH Port Forwarding (Recommended)"
echo "--------------------------------------------"
echo "1. Exit this SSH session"
echo "2. Reconnect with port forwarding:"
echo "   ssh -L 5173:localhost:5173 vpittamp@nixos-hetzner"
echo "   or if using Tailscale:"
echo "   ssh -L 5173:localhost:5173 vpittamp@$TAILSCALE_IP"
echo "3. Run 'claude' on the remote server"
echo "4. Complete OAuth in your local browser"
echo ""

echo "Method 2: Using socat to forward (if available)"
echo "-----------------------------------------------"
echo "1. Install socat if not available:"
echo "   nix-env -iA nixos.socat"
echo "2. In a new terminal on your local machine, run:"
echo "   ssh vpittamp@$TAILSCALE_IP 'socat TCP-LISTEN:5173,reuseaddr,fork TCP:localhost:5173' &"
echo "3. Then run 'claude' on the remote server"
echo ""

echo "Method 3: Using Tailscale Serve (Beta)"
echo "---------------------------------------"
echo "1. On the remote server, run:"
echo "   tailscale serve https:5173 / proxy http://localhost:5173"
echo "2. Run 'claude' and use the Tailscale HTTPS URL for OAuth"
echo "3. After authentication, stop the serve:"
echo "   tailscale serve https:5173 off"
echo ""

echo "Method 4: Manual Browser Authentication"
echo "---------------------------------------"
echo "1. Run the following on the remote server:"
echo "   DISPLAY=:0 claude"
echo "2. Copy the OAuth URL that appears"
echo "3. Open it in your local browser"
echo "4. After authentication, check if a callback URL appears"
echo "5. If needed, manually complete the flow"
echo ""

echo "Choose a method and follow the instructions above."
echo ""
echo "Tip: Method 1 (SSH Port Forwarding) is usually the most reliable."
#!/usr/bin/env bash
# macOS SSH Server Setup Script

set -e

echo "======================================"
echo "macOS SSH Server Setup"
echo "======================================"
echo ""

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ This script is for macOS only"
    exit 1
fi

echo "1️⃣  Enabling SSH (Remote Login)..."
sudo systemsetup -setremotelogin on

echo ""
echo "2️⃣  Checking SSH service status..."
sudo launchctl list | grep sshd && echo "✅ SSH service is running" || echo "⚠️  SSH service not found"

echo ""
echo "3️⃣  Checking SSH configuration..."
if [[ -f /etc/ssh/sshd_config ]]; then
    echo "✅ SSH config exists at /etc/ssh/sshd_config"
    echo ""
    echo "Current settings:"
    grep "^PasswordAuthentication" /etc/ssh/sshd_config || echo "  PasswordAuthentication: default (yes)"
    grep "^PubkeyAuthentication" /etc/ssh/sshd_config || echo "  PubkeyAuthentication: default (yes)"
    grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "  PermitRootLogin: default (no)"
else
    echo "⚠️  No custom SSH config found (using defaults)"
fi

echo ""
echo "4️⃣  Getting network information..."
echo "Hostname: $(hostname)"
echo "Local IP: $(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "Not found")"
echo "Username: $USER"

echo ""
echo "5️⃣  Checking for authorized SSH keys..."
if [[ -f ~/.ssh/authorized_keys ]]; then
    KEY_COUNT=$(wc -l < ~/.ssh/authorized_keys | tr -d ' ')
    echo "✅ Found $KEY_COUNT authorized key(s)"
    echo ""
    echo "Keys:"
    while IFS= read -r line; do
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            echo "  - $(echo "$line" | awk '{print $NF}')"
        fi
    done < ~/.ssh/authorized_keys
else
    echo "⚠️  No authorized_keys file found"
    echo "   Creating ~/.ssh directory..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo "   ✅ Created ~/.ssh/authorized_keys"
fi

echo ""
echo "6️⃣  Firewall status..."
FIREWALL_STATUS=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate)
echo "$FIREWALL_STATUS"
if [[ "$FIREWALL_STATUS" =~ "enabled" ]]; then
    echo "   Note: Firewall is enabled. SSH should be allowed by default."
    echo "   Check: System Settings → Network → Firewall → Options"
fi

echo ""
echo "======================================"
echo "✅ SSH Setup Complete!"
echo "======================================"
echo ""
echo "To connect from another machine:"
echo "  ssh $USER@$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "<your-ip>")"
echo ""
echo "To add an SSH key, run on the CLIENT machine:"
echo "  ssh-copy-id $USER@$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "<your-ip>")"
echo ""
echo "Or manually add your public key to ~/.ssh/authorized_keys"
echo ""

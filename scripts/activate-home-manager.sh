#!/usr/bin/env bash
# Simple home-manager activation script for containers
# Automatically detects and runs the correct activation for the current user

set -e

# Detect current user and home
CURRENT_USER="${USER:-root}"
CURRENT_HOME="${HOME:-/root}"

echo "🏠 Activating home-manager for $CURRENT_USER..."

# Ensure /tmp exists (required by activation)
mkdir -p /tmp

# Find all activation scripts
ACTIVATIONS=($(find /nix/store -name "activate" -path "*/home-manager-generation/*" 2>/dev/null))

if [ ${#ACTIVATIONS[@]} -eq 0 ]; then
    echo "❌ No home-manager activation scripts found"
    exit 1
fi

echo "📦 Found ${#ACTIVATIONS[@]} activation scripts"

# Try each activation until one works
for activation in "${ACTIVATIONS[@]}"; do
    echo "🔧 Trying: $activation"
    
    # Run with proper environment, suppress user check errors
    if HOME="$CURRENT_HOME" USER="$CURRENT_USER" "$activation" 2>&1 | grep -v "Error: USER is set to" | grep -v "Error: HOME is set to"; then
        echo "✅ Successfully activated home-manager!"
        
        # Check what was activated
        if [ -f "$CURRENT_HOME/.bashrc" ]; then
            echo "📄 .bashrc installed"
        fi
        if [ -d "$CURRENT_HOME/.config" ]; then
            echo "📁 .config directory created"
        fi
        
        exit 0
    fi
done

echo "⚠️  No activation succeeded for user $CURRENT_USER"
echo "💡 You may need to manually specify USER and HOME:"
echo "   USER=root HOME=/root $0"
exit 1
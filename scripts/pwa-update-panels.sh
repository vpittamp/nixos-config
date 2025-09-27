#!/usr/bin/env bash
# Script to update KDE panels with current PWA IDs after installation
# This should be run after installing PWAs with pwa-install-all

set -euo pipefail

CONFIG_FILE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

echo "=== PWA Panel Update Script ==="
echo ""

# Check if firefoxpwa is available
if ! command -v firefoxpwa &> /dev/null; then
    echo "Error: firefoxpwa not found"
    exit 1
fi

# Get current PWA IDs
declare -A pwa_ids
echo "Detecting installed PWAs..."
while IFS=: read -r name_part rest; do
    name=$(echo "$name_part" | sed 's/^- //' | xargs)
    id=$(echo "$rest" | awk -F'[()]' '{print $2}' | xargs)
    if [ ! -z "$id" ]; then
        pwa_ids["$name"]="$id"
        echo "  ✓ Found: $name (ID: $id)"
    fi
done < <(firefoxpwa profile list 2>/dev/null | grep "^- ")

if [ ${#pwa_ids[@]} -eq 0 ]; then
    echo "No PWAs found. Please run 'pwa-install-all' first."
    exit 1
fi

echo ""
echo "Building taskbar configuration..."

# Build launcher string with full file paths
LAUNCHER_STRING="applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop"

# Add PWAs in the expected order (matching firefox-pwas-declarative.nix)
for pwa_name in Google YouTube Gitea Backstage Kargo ArgoCD Headlamp; do
    if [ ! -z "${pwa_ids[$pwa_name]:-}" ]; then
        DESKTOP_FILE="$HOME/.local/share/applications/FFPWA-${pwa_ids[$pwa_name]}.desktop"
        if [ -f "$DESKTOP_FILE" ]; then
            LAUNCHER_STRING="$LAUNCHER_STRING,file://$DESKTOP_FILE"
            echo "  + Adding $pwa_name to taskbar"
        else
            echo "  ! Warning: Desktop file not found for $pwa_name"
        fi
    else
        echo "  - Skipping $pwa_name (not installed)"
    fi
done

echo ""
echo "Updating panel configuration..."

# Stop plasma shell
echo "  Stopping Plasma shell..."
kquitapp5 plasmashell 2>/dev/null || kquitapp6 plasmashell 2>/dev/null || systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
sleep 2

# Backup current configuration
if [ -f "$CONFIG_FILE" ]; then
    BACKUP_FILE="$CONFIG_FILE.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo "  Backed up to: $(basename $BACKUP_FILE)"
fi

# Update the configuration file
if [ -f "$CONFIG_FILE" ]; then
    # Create temporary file
    TEMP_FILE=$(mktemp)
    cp "$CONFIG_FILE" "$TEMP_FILE"

    # Update launcher line in primary panel (Containment 410, Applet 412)
    awk -v new_launchers="$LAUNCHER_STRING" '
        /^\[Containments\]\[410\]\[Applets\]\[412\]\[Configuration\]\[General\]$/ {
            in_section = 1
            print
            next
        }
        in_section && /^launchers=/ {
            print "launchers=" new_launchers
            in_section = 0
            next
        }
        in_section && /^\[/ {
            in_section = 0
        }
        { print }
    ' "$TEMP_FILE" > "$CONFIG_FILE"

    echo "  Configuration updated"
else
    echo "  Warning: Panel configuration file not found"
    echo "  A rebuild may be needed first"
fi

# Restart plasma shell
echo "  Restarting Plasma shell..."
plasmashell --replace > /dev/null 2>&1 &
disown

echo ""
echo "✓ Panel update complete!"
echo ""
echo "If the icons don't appear immediately:"
echo "  1. Log out and log back in"
echo "  2. Or run: plasmashell --replace"
echo ""
echo "To make this permanent, update panels.nix with these IDs and rebuild."
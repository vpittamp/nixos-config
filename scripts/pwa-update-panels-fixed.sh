#!/usr/bin/env bash
# Script to show current PWA status and suggest panel updates
# Since panels are managed by home-manager, this script shows what needs updating

set -euo pipefail

echo "=== PWA Panel Status Check ==="
echo ""

# Check if firefoxpwa is available
if ! command -v firefoxpwa &> /dev/null; then
    echo "Error: firefoxpwa not found"
    exit 1
fi

# Get current PWA IDs
declare -A pwa_ids
echo "Currently installed PWAs:"
echo ""

while IFS=: read -r name_part rest; do
    name=$(echo "$name_part" | sed 's/^- //' | xargs)
    id=$(echo "$rest" | awk -F'[()]' '{print $2}' | xargs)
    if [ ! -z "$id" ]; then
        # Store both full name and simplified name
        pwa_ids["$name"]="$id"
        # Also handle "Google AI" as "Google"
        if [[ "$name" == "Google AI" ]]; then
            pwa_ids["Google"]="$id"
        fi
        printf "  %-15s %s\n" "$name:" "$id"
    fi
done < <(firefoxpwa profile list 2>/dev/null | grep "^- ")

if [ ${#pwa_ids[@]} -eq 0 ]; then
    echo "No PWAs found. Please run 'pwa-install-all' first."
    exit 1
fi

echo ""
echo "Panel configuration status:"
echo ""

# Check if PWAs are in expected order
expected_order=("Google AI" "YouTube" "Gitea" "Backstage" "Kargo" "ArgoCD" "Headlamp")
missing_pwas=()

for pwa_name in "${expected_order[@]}"; do
    # Handle both "Google" and "Google AI"
    check_name="$pwa_name"
    if [[ "$pwa_name" == "Google AI" ]]; then
        if [ -z "${pwa_ids["Google AI"]:-${pwa_ids["Google"]:-}}" ]; then
            missing_pwas+=("$pwa_name")
            echo "  ✗ $pwa_name - NOT INSTALLED"
        else
            id="${pwa_ids["Google AI"]:-${pwa_ids["Google"]:-}}"
            DESKTOP_FILE="$HOME/.local/share/applications/FFPWA-${id}.desktop"
            if [ -f "$DESKTOP_FILE" ]; then
                echo "  ✓ $pwa_name - Ready (ID: $id)"
            else
                echo "  ! $pwa_name - Desktop file missing"
            fi
        fi
    else
        if [ -z "${pwa_ids[$pwa_name]:-}" ]; then
            missing_pwas+=("$pwa_name")
            echo "  ✗ $pwa_name - NOT INSTALLED"
        else
            DESKTOP_FILE="$HOME/.local/share/applications/FFPWA-${pwa_ids[$pwa_name]}.desktop"
            if [ -f "$DESKTOP_FILE" ]; then
                echo "  ✓ $pwa_name - Ready (ID: ${pwa_ids[$pwa_name]})"
            else
                echo "  ! $pwa_name - Desktop file missing"
            fi
        fi
    fi
done

echo ""

if [ ${#missing_pwas[@]} -gt 0 ]; then
    echo "⚠ Missing PWAs: ${missing_pwas[*]}"
    echo ""
    echo "To install missing PWAs:"
    echo "  pwa-install-all"
    echo ""
fi

# Get hostname
HOSTNAME=$(hostname)
echo "Current machine: $HOSTNAME"
echo ""

# Generate the correct panels.nix snippet
echo "To update panels.nix for this machine, use these IDs:"
echo ""

if [[ "$HOSTNAME" == "nixos-hetzner" ]]; then
    echo "  # Hetzner server PWA IDs ($(date +%Y-%m-%d))"
    echo "  hetznerIds = {"
elif [[ "$HOSTNAME" == "nixos-m1" ]]; then
    echo "  # M1 MacBook PWA IDs ($(date +%Y-%m-%d))"
    echo "  m1Ids = {"
else
    echo "  # $HOSTNAME PWA IDs ($(date +%Y-%m-%d))"
    echo "  unknownIds = {"
fi

# Output in the correct format for panels.nix
echo "    googleId = \"${pwa_ids["Google AI"]:-${pwa_ids["Google"]:-""}}\";  # Google AI mode"
echo "    youtubeId = \"${pwa_ids["YouTube"]:-""}\";  # YouTube"
echo "    giteaId = \"${pwa_ids["Gitea"]:-""}\";  # Gitea"
echo "    backstageId = \"${pwa_ids["Backstage"]:-""}\";  # Backstage"
echo "    kargoId = \"${pwa_ids["Kargo"]:-""}\";  # Kargo"
echo "    argoCDId = \"${pwa_ids["ArgoCD"]:-""}\";  # ArgoCD"
echo "    headlampId = \"${pwa_ids["Headlamp"]:-""}\";  # Headlamp"
echo "  };"
echo ""

echo "After updating panels.nix:"
echo "  1. Commit the changes: git add -A && git commit -m \"Update PWA IDs\""
echo "  2. Rebuild: sudo nixos-rebuild switch --flake .#$HOSTNAME"
echo "  3. Restart plasma: systemctl --user restart plasma-plasmashell.service"
echo ""

# Check if panel configuration is managed by home-manager
if [ -L "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
    echo "ℹ Panel configuration is managed by home-manager (read-only)"
    echo "  Changes must be made in panels.nix and rebuilt"
else
    echo "⚠ Panel configuration is not managed by home-manager"
    echo "  You may have local modifications that could be lost on rebuild"
fi
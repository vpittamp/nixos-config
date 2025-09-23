#!/usr/bin/env bash
# Script to update Firefox PWA icons
set -e

# Function to download and install icon
install_icon() {
    local pwa_id="$1"
    local icon_url="$2"
    local name="$3"

    echo "Updating icon for $name (ID: $pwa_id)..."

    # Download icon to temp file
    temp_icon="/tmp/pwa-icon-${pwa_id}.png"
    curl -L "$icon_url" -o "$temp_icon" 2>/dev/null || wget -q "$icon_url" -O "$temp_icon"

    # Install icon in multiple sizes
    for size in 16 32 48 64 96 128 192 256 512; do
        icon_dir="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
        mkdir -p "$icon_dir"

        # Convert and resize icon
        if command -v convert &> /dev/null; then
            convert "$temp_icon" -resize ${size}x${size} "$icon_dir/FFPWA-${pwa_id}.png"
        elif command -v magick &> /dev/null; then
            magick "$temp_icon" -resize ${size}x${size} "$icon_dir/FFPWA-${pwa_id}.png"
        else
            # Fallback: just copy the original
            cp "$temp_icon" "$icon_dir/FFPWA-${pwa_id}.png"
        fi
    done

    # Clean up temp file
    rm -f "$temp_icon"

    echo "✓ Icon updated for $name"
}

# Custom icons for PWAs
declare -A CUSTOM_ICONS=(
    # Google AI (using Google icon)
    ["01K5SRD32G3CDN8FC5KM8HMQNP"]="https://www.gstatic.com/images/branding/product/2x/googleg_96dp.png"

    # YouTube
    ["01K5SC803TS46ABVVPYZ8HYHYK"]="https://www.youtube.com/s/desktop/5e8e6962/img/favicon_144x144.png"

    # Add more PWA IDs and icon URLs here as needed
    # Format: ["PWA_ID"]="ICON_URL"
)

# Names for display (optional)
declare -A PWA_NAMES=(
    ["01K5SRD32G3CDN8FC5KM8HMQNP"]="Google AI"
    ["01K5SC803TS46ABVVPYZ8HYHYK"]="YouTube"
)

# Update icons for known PWAs
for pwa_id in "${!CUSTOM_ICONS[@]}"; do
    icon_url="${CUSTOM_ICONS[$pwa_id]}"
    name="${PWA_NAMES[$pwa_id]:-PWA}"

    # Check if desktop file exists
    if [ -f "$HOME/.local/share/applications/FFPWA-${pwa_id}.desktop" ]; then
        install_icon "$pwa_id" "$icon_url" "$name"
    else
        echo "⚠ Desktop file not found for $name (ID: $pwa_id)"
    fi
done

# Update icon cache
if command -v gtk-update-icon-cache &> /dev/null; then
    gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true
fi

# Update desktop database
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database ~/.local/share/applications 2>/dev/null || true
fi

echo ""
echo "All PWA icons updated! You may need to:"
echo "1. Restart your desktop environment or panel"
echo "2. Re-pin the apps to your taskbar if icons don't update"
echo ""
echo "To restart Plasma panel: systemctl --user restart plasma-plasmashell.service"
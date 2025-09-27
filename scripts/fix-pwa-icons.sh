#!/usr/bin/env bash

# Fix PWA icons for KRunner visibility
# Based on legacy PWA management best practices

set -euo pipefail

echo "Fixing PWA icons for KRunner..."

# Get all installed PWAs
FFPWA="firefoxpwa"
PWA_IDS=$($FFPWA profile list 2>/dev/null | grep "^- " | awk -F'[()]' '{print $2}' | xargs)

# Icon sizes needed for proper KDE integration
ICON_SIZES=(16 22 24 32 48 64 128 256 512)

# Process each PWA
for id in $PWA_IDS; do
    # Get PWA name
    PWA_NAME=$($FFPWA profile list 2>/dev/null | grep "$id" | sed 's/^- \([^:]*\):.*/\1/' | xargs)
    echo "Processing: $PWA_NAME ($id)"

    # Find the largest existing icon
    LARGEST_ICON=""
    for size in 512 256 128 64 48 32 24 22 16; do
        icon_path="$HOME/.local/share/icons/hicolor/${size}x${size}/apps/FFPWA-${id}.png"
        if [ -f "$icon_path" ]; then
            LARGEST_ICON="$icon_path"
            echo "  Found source icon: ${size}x${size}"
            break
        fi
    done

    if [ -z "$LARGEST_ICON" ]; then
        echo "  Warning: No icon found for $PWA_NAME"
        continue
    fi

    # Check if icon is square
    dimensions=$(identify "$LARGEST_ICON" 2>/dev/null | awk '{print $3}' || echo "")
    if [ ! -z "$dimensions" ]; then
        width=$(echo $dimensions | cut -dx -f1)
        height=$(echo $dimensions | cut -dx -f2)

        if [ "$width" != "$height" ]; then
            echo "  Converting non-square icon ($dimensions) to square..."
            # Create square version
            temp_icon="/tmp/pwa-icon-${id}.png"
            convert "$LARGEST_ICON" \
                -resize 512x512 \
                -gravity center \
                -background transparent \
                -extent 512x512 \
                "$temp_icon" 2>/dev/null || magick "$LARGEST_ICON" \
                -resize 512x512 \
                -gravity center \
                -background transparent \
                -extent 512x512 \
                "$temp_icon"
            LARGEST_ICON="$temp_icon"
        fi
    fi

    # Generate all required icon sizes
    for size in "${ICON_SIZES[@]}"; do
        icon_dir="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
        icon_path="$icon_dir/FFPWA-${id}.png"

        mkdir -p "$icon_dir"

        # Generate icon at this size
        convert "$LARGEST_ICON" -resize ${size}x${size} "$icon_path" 2>/dev/null || \
        magick "$LARGEST_ICON" -resize ${size}x${size} "$icon_path"

        echo "  Created ${size}x${size} icon"
    done

    # Clean up temp file if created
    [ -f "/tmp/pwa-icon-${id}.png" ] && rm "/tmp/pwa-icon-${id}.png"
done

echo ""
echo "Updating icon caches..."

# Clear old icon cache
rm -rf ~/.cache/icon-cache.kcache 2>/dev/null || true

# Update desktop database
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database ~/.local/share/applications/ 2>/dev/null || true
fi

# Update XDG menu
if command -v xdg-desktop-menu >/dev/null 2>&1; then
    xdg-desktop-menu forceupdate 2>/dev/null || true
fi

# Rebuild KDE cache
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental 2>/dev/null || true
    echo "KDE cache rebuilt"
fi

# Update GTK icon cache if available
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f ~/.local/share/icons/hicolor/ 2>/dev/null || true
fi

echo ""
echo "Icon fixes completed!"
echo ""
echo "If icons still don't appear in KRunner:"
echo "  1. Try logging out and back in"
echo "  2. Or restart Plasma: kquitapp5 plasmashell && kstart5 plasmashell"
echo ""
echo "To test: Press Alt+Space and search for any PWA name"
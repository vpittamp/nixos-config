#!/usr/bin/env bash

# PWA Sync - Complete solution for NixOS with proper taskbar management

set -uo pipefail

# Configuration
CONFIG_FILE="${PWA_CONFIG:-/etc/nixos/configs/pwas.json}"
PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
ICON_DIR="$HOME/.local/share/icons/hicolor"
DRY_RUN="${DRY_RUN:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"; shift
    case "$level" in
        error) echo -e "${RED}✗${NC} $*" >&2 ;;
        warn)  echo -e "${YELLOW}⚠${NC} $*" ;;
        info)  echo -e "${BLUE}ℹ${NC} $*" ;;
        success) echo -e "${GREEN}✓${NC} $*" ;;
    esac
}

# Ensure plasma config is writable
ensure_writable_config() {
    # If config is a symlink to nix store, remove it and let KDE recreate it
    if [[ -L "$PLASMA_CONFIG" ]]; then
        log info "Detected read-only plasma config symlink"
        rm -f "$PLASMA_CONFIG"

        # Restart plasma to recreate config
        log info "Restarting Plasma to recreate config..."
        pkill plasmashell 2>/dev/null || true
        sleep 2
        nohup kstart5 plasmashell >/dev/null 2>&1 &
        sleep 4

        if [[ -f "$PLASMA_CONFIG" ]] && [[ -w "$PLASMA_CONFIG" ]]; then
            log success "Plasma config is now writable"
            return 0
        else
            log warn "Could not create writable config"
            return 1
        fi
    elif [[ ! -w "$PLASMA_CONFIG" ]]; then
        log warn "Plasma config is not writable"
        return 1
    fi
    return 0
}

# Configure taskbar with all PWAs
configure_taskbar() {
    if ! ensure_writable_config; then
        log warn "Skipping taskbar configuration - config not writable"
        return 1
    fi

    log info "Configuring taskbar pins..."

    # Backup config
    cp "$PLASMA_CONFIG" "$PLASMA_CONFIG.bak" 2>/dev/null || true

    # Get all PWA IDs
    local pwa_ids=""
    for id in "${!PWA_BY_ID[@]}"; do
        pwa_ids="$pwa_ids,applications:FFPWA-${id}.desktop"
    done

    # Build complete launcher list
    local launcher_list="launchers=applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop${pwa_ids}"

    # Find icontasks configuration section
    local found_section=false

    # Look for existing icontasks configuration
    if grep -q "plugin=org.kde.plasma.icontasks" "$PLASMA_CONFIG"; then
        # Find the applet number
        local applet_num=$(grep -B1 "plugin=org.kde.plasma.icontasks" "$PLASMA_CONFIG" | grep "Applets\]\[[0-9]*\]" | grep -o "\[[0-9]*\]$" | tr -d '[]' | head -1)

        if [[ -n "$applet_num" ]]; then
            # Check if configuration section exists
            if grep -q "\[Containments\]\[[0-9]*\]\[Applets\]\[${applet_num}\]\[Configuration\]\[General\]" "$PLASMA_CONFIG"; then
                # Update existing launchers line
                sed -i "/\[Containments\]\[[0-9]*\]\[Applets\]\[${applet_num}\]\[Configuration\]\[General\]/,/^\[/ {
                    /^launchers=/d
                }" "$PLASMA_CONFIG"

                sed -i "/\[Containments\]\[[0-9]*\]\[Applets\]\[${applet_num}\]\[Configuration\]\[General\]/a\\${launcher_list}" "$PLASMA_CONFIG"
                found_section=true
                log success "Updated existing taskbar configuration"
            else
                # Add configuration section
                sed -i "/\[Containments\]\[[0-9]*\]\[Applets\]\[${applet_num}\]/a\\[Containments][607][Applets][${applet_num}][Configuration][General]\\
${launcher_list}\\
showOnlyCurrentActivity=true\\
showOnlyCurrentDesktop=false\\
showOnlyCurrentScreen=true" "$PLASMA_CONFIG"
                found_section=true
                log success "Added taskbar configuration"
            fi
        fi
    fi

    if [[ "$found_section" == "false" ]]; then
        log warn "Could not find icontasks widget configuration"
        return 1
    fi

    return 0
}

# Get current PWA mapping
get_pwa_mapping() {
    declare -gA PWA_BY_URL
    declare -gA PWA_BY_ID

    while IFS= read -r line; do
        if [[ "$line" =~ ^-\ (.+):\ (.+)\ \(([A-Z0-9]+)\)$ ]]; then
            local name="${BASH_REMATCH[1]}"
            local url="${BASH_REMATCH[2]}"
            local id="${BASH_REMATCH[3]}"

            # Normalize URL
            local norm_url="${url%/}"
            norm_url="${norm_url#https://}"
            norm_url="${norm_url#http://}"
            norm_url="${norm_url#www.}"

            PWA_BY_URL["$norm_url"]="$id|$name"
            PWA_BY_ID["$id"]="$name|$url"
        fi
    done < <(firefoxpwa profile list 2>/dev/null | grep -E "^- ")
}

# Install icon for PWA
install_icon() {
    local id="$1"
    local name="$2"
    local url="$3"

    local temp_file="/tmp/pwa-icon-${id}.download"

    # Try download
    if curl -sL --max-time 5 "$url" -o "$temp_file" 2>/dev/null && [[ -s "$temp_file" ]]; then
        # Convert to PNG
        local png_file="/tmp/pwa-icon-${id}.png"

        if command -v magick >/dev/null 2>&1; then
            magick "$temp_file[0]" -resize 512x512 "$png_file" 2>/dev/null
        elif command -v convert >/dev/null 2>&1; then
            convert "$temp_file[0]" -resize 512x512 "$png_file" 2>/dev/null
        fi

        if [[ -f "$png_file" ]] && [[ -s "$png_file" ]]; then
            # Install in all sizes
            for size in 16 24 32 48 64 128 256 512; do
                local dir="$ICON_DIR/${size}x${size}/apps"
                mkdir -p "$dir"

                if command -v magick >/dev/null 2>&1; then
                    magick "$png_file" -resize ${size}x${size} "$dir/FFPWA-${id}.png" 2>/dev/null
                elif command -v convert >/dev/null 2>&1; then
                    convert "$png_file" -resize ${size}x${size} "$dir/FFPWA-${id}.png" 2>/dev/null
                fi
            done

            rm -f "$temp_file" "$png_file"
            return 0
        fi
    fi

    rm -f "$temp_file"
    return 1
}

# Main sync function
sync_pwas() {
    echo "╔════════════════════════════════════════╗"
    echo "║      PWA Sync - NixOS Edition        ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # Get current PWA mapping
    get_pwa_mapping

    if [[ ${#PWA_BY_ID[@]} -eq 0 ]]; then
        log error "No PWAs installed"
        exit 1
    fi

    log info "Found ${#PWA_BY_ID[@]} installed PWAs"
    echo ""

    # Step 1: Configure taskbar
    configure_taskbar

    # Step 2: Process each installed PWA
    log info "Processing PWAs..."
    echo ""

    local icons_installed=0

    # Define icon URLs for known PWAs
    declare -A ICON_URLS=(
        ["Claude"]="https://claude.ai/apple-touch-icon.png"
        ["ChatGPT"]="https://cdn.oaistatic.com/_next/static/media/apple-touch-icon.82af6fe1.png"
        ["Google Gemini"]="https://www.gstatic.com/lamda/images/gemini_favicon_f069958c85030456e93de685481c559f160ea06b.png"
        ["GitHub"]="https://github.githubassets.com/favicons/favicon-dark.png"
        ["Gmail"]="https://ssl.gstatic.com/ui/v1/icons/mail/rfr/gmail.ico"
        ["ArgoCD"]="https://raw.githubusercontent.com/argoproj/argo-cd/master/docs/assets/logo.png"
        ["Backstage"]="https://backstage.io/logo_assets/png/Icon_Teal.png"
        ["YouTube"]="https://www.youtube.com/s/desktop/12d6b690/img/favicon_144x144.png"
    )

    for id in "${!PWA_BY_ID[@]}"; do
        IFS='|' read -r name url <<< "${PWA_BY_ID[$id]}"

        echo "Processing: $name"

        # Ensure desktop file exists
        local desktop_file="$HOME/.local/share/applications/FFPWA-${id}.desktop"
        if [[ ! -f "$desktop_file" ]]; then
            cat > "$desktop_file" << EOF
[Desktop Entry]
Type=Application
Version=1.4
Name=$name
Comment=Firefox Progressive Web App
Icon=FFPWA-${id}
Exec=firefoxpwa site launch ${id} --protocol %u
Terminal=false
StartupNotify=true
StartupWMClass=FFPWA-${id}
Categories=Network;
EOF
            log success "  Created desktop entry"
        fi

        # Install icon if we have a URL for it
        if [[ -n "${ICON_URLS[$name]:-}" ]]; then
            if install_icon "$id" "$name" "${ICON_URLS[$name]}"; then
                log success "  Icon installed"
                ((icons_installed++))
            else
                log warn "  Icon installation failed"
            fi
        else
            log warn "  No icon URL configured"
        fi

        echo ""
    done

    # Step 3: Update caches
    log info "Updating system caches..."
    update-desktop-database ~/.local/share/applications 2>/dev/null || true
    gtk-update-icon-cache -f -t "$ICON_DIR" 2>/dev/null || true
    kbuildsycoca6 --noincremental 2>/dev/null || true

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║              Summary                   ║"
    echo "╠════════════════════════════════════════╣"
    printf "║  PWAs processed:    %-18s ║\n" "${#PWA_BY_ID[@]}"
    printf "║  Icons installed:   %-18s ║\n" "$icons_installed"
    echo "╚════════════════════════════════════════╝"

    # Step 4: Restart Plasma if changes were made
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        read -p "Restart Plasma Shell to apply changes? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log info "Restarting Plasma Shell..."
            pkill plasmashell 2>/dev/null || true
            sleep 2
            nohup kstart5 plasmashell >/dev/null 2>&1 &
            sleep 2
            log success "Plasma Shell restarted"
        fi
    fi
}

# Show status
show_status() {
    get_pwa_mapping

    echo "╔════════════════════════════════════════╗"
    echo "║         Installed PWAs Status          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    for id in "${!PWA_BY_ID[@]}"; do
        IFS='|' read -r name url <<< "${PWA_BY_ID[$id]}"

        # Check desktop file
        local desktop="❌"
        [[ -f "$HOME/.local/share/applications/FFPWA-${id}.desktop" ]] && desktop="✅"

        # Check icon
        local icon="❌"
        [[ -f "$ICON_DIR/128x128/apps/FFPWA-${id}.png" ]] && icon="✅"

        # Check taskbar
        local pinned="❌"
        grep -q "FFPWA-${id}.desktop" "$PLASMA_CONFIG" 2>/dev/null && pinned="📌"

        echo "$desktop $icon $pinned $name"
        echo "      ID: $id"
        echo "      URL: $url"
    done

    echo ""
    echo "Legend: ✅ = Present, 📌 = Pinned to taskbar"
}

# Main
case "${1:-sync}" in
    sync)
        sync_pwas
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        cat << EOF
PWA Sync - Complete PWA Management for NixOS

Usage: $0 [command]

Commands:
  sync    - Sync icons and configure taskbar (default)
  status  - Show PWA status with icons and pins
  help    - Show this help

This script:
- Handles read-only plasma configs properly
- Installs icons for all PWAs
- Configures taskbar pins automatically
- Updates all system caches
- Optionally restarts Plasma Shell

Environment:
  PWA_CONFIG - Path to config file (default: /etc/nixos/configs/pwas.json)
  DRY_RUN    - Set to 'true' to preview without changes

EOF
        ;;
    *)
        log error "Unknown command: $1"
        exit 1
        ;;
esac
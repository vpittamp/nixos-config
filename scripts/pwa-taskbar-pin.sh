#!/usr/bin/env bash

# Dynamically pin installed PWAs to KDE taskbar
# This script reads actual installed PWAs and updates the taskbar configuration

set -euo pipefail

echo "Configuring PWA taskbar pins..."

# Get currently installed PWAs with their IDs
get_pwa_ids() {
    firefoxpwa profile list 2>/dev/null | grep "^- " | while read -r line; do
        name=$(echo "$line" | sed 's/^- \([^:]*\):.*/\1/' | xargs)
        id=$(echo "$line" | awk -F'[()]' '{print $2}')
        echo "$name:$id"
    done
}

# Define the order of PWAs for taskbar (customize as needed)
PWA_ORDER=(
    "Google"
    "YouTube"
    "Claude"
    "ChatGPT"
    "Google Gemini"
    "GitHub"
    "Gmail"
    "Gitea"
    "Backstage"
    "Kargo"
    "ArgoCD"
    "Headlamp"
)

# Build launcher string based on installed PWAs
build_launchers() {
    local launchers="applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop"

    # Get installed PWAs
    declare -A installed_pwas
    while IFS=: read -r name id; do
        installed_pwas["$name"]="$id"
    done < <(get_pwa_ids)

    # Add PWAs in defined order
    for pwa in "${PWA_ORDER[@]}"; do
        if [[ -n "${installed_pwas[$pwa]:-}" ]]; then
            launchers="${launchers},applications:FFPWA-${installed_pwas[$pwa]}.desktop"
            echo "  Added: $pwa (${installed_pwas[$pwa]})"
        fi
    done

    echo "$launchers"
}

# Update KDE panel configuration
update_panel_config() {
    local config_file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

    if [[ ! -f "$config_file" ]]; then
        echo "KDE panel configuration not found. Please configure your panel first."
        exit 1
    fi

    # Backup current config
    cp "$config_file" "$config_file.backup-$(date +%Y%m%d-%H%M%S)"

    # Get launcher string
    local launchers=$(build_launchers)

    # Update the launchers in ALL icon tasks widgets (there may be multiple panels)
    awk -v launchers="$launchers" '
        /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ {
            in_applet = 1
            applet_section = $0
            print
            next
        }
        in_applet && /^plugin=org\.kde\.plasma\.icontasks$/ {
            is_icontasks = 1
            print
            next
        }
        in_applet && /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]\[Configuration\]\[General\]$/ && is_icontasks {
            in_config = 1
            print
            next
        }
        in_config && /^launchers=/ {
            print "launchers=" launchers
            found_launchers = 1
            next
        }
        in_config && /^\[/ {
            if (!found_launchers && is_icontasks) {
                print "launchers=" launchers
            }
            in_config = 0
            is_icontasks = 0
            in_applet = 0
            found_launchers = 0
            print
            next
        }
        /^\[Containments\]\[[0-9]+\]$/ {
            if (in_config && !found_launchers && is_icontasks) {
                print "launchers=" launchers
            }
            in_applet = 0
            is_icontasks = 0
            in_config = 0
            found_launchers = 0
            print
            next
        }
        { print }
        END {
            if (in_config && !found_launchers && is_icontasks) {
                print "launchers=" launchers
            }
        }
    ' "$config_file" > "$config_file.tmp"

    mv "$config_file.tmp" "$config_file"
    echo "Panel configuration updated"
}

# Restart plasmashell to apply changes
apply_changes() {
    echo "Applying changes to panel..."

    # Try graceful restart first
    if command -v kquitapp5 >/dev/null 2>&1; then
        kquitapp5 plasmashell 2>/dev/null || true
        sleep 2
        kstart5 plasmashell >/dev/null 2>&1 &
    else
        # Fallback: just reload config
        qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell 2>/dev/null || true
    fi

    echo "Panel updated with PWA pins"
}

# Main execution
main() {
    case "${1:-}" in
        --dry-run)
            echo "Dry run mode - showing what would be pinned:"
            build_launchers
            ;;
        --list)
            echo "Currently installed PWAs:"
            get_pwa_ids
            ;;
        *)
            update_panel_config
            apply_changes
            echo ""
            echo "PWAs have been pinned to taskbar!"
            echo "If icons don't appear, try logging out and back in."
            ;;
    esac
}

main "$@"
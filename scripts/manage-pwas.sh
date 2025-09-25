#!/usr/bin/env bash
# PWA Management Script for NixOS
# Provides utilities to manage Firefox PWA installations

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function list_configured() {
    echo -e "${GREEN}Configured PWAs in NixOS:${NC}"
    echo "------------------------"
    
    # Parse the pwa-definitions.nix file for PWA names
    grep -E '^      [a-z]+ = \{$' /etc/nixos/modules/desktop/pwa-definitions.nix | \
        sed 's/      //;s/ = {//' | \
        while read pwa; do
            name=$(grep -A1 "^      $pwa = {" /etc/nixos/modules/desktop/pwa-definitions.nix | \
                   grep "name =" | sed 's/.*name = "//;s/".*//')
            echo "  • $pwa: $name"
        done
}

function list_installed() {
    echo -e "${GREEN}Installed Firefox PWAs:${NC}"
    echo "----------------------"
    
    if ls ~/.local/share/applications/FFPWA-*.desktop &>/dev/null; then
        ls ~/.local/share/applications/FFPWA-*.desktop | while read f; do
            name=$(grep "^Name=" "$f" | cut -d= -f2)
            id=$(basename "$f" | sed 's/FFPWA-//;s/.desktop//')
            url=$(grep "^Comment=" "$f" 2>/dev/null | cut -d= -f2 || echo "No URL")
            echo -e "  • ${name} (${YELLOW}ID:${NC} $id)"
            [ "$url" != "No URL" ] && echo "    URL: $url"
        done
    else
        echo "  No PWAs currently installed"
    fi
}

function install_all() {
    echo -e "${GREEN}Installing all configured PWAs...${NC}"

    # Check if systemd service is available
    if systemctl --user list-unit-files | grep -q "install-pwas.service"; then
        # Start the installation service
        systemctl --user start install-pwas.service
        echo "PWA installation service started."

        # Wait a moment and check status
        sleep 2
        if systemctl --user is-active install-pwas.service >/dev/null; then
            echo "Installation in progress. Check logs with: journalctl --user -u install-pwas -f"
        else
            echo "Installation completed. Check status with: systemctl --user status install-pwas"
        fi
    else
        echo -e "${YELLOW}Systemd service not available. Please run: sudo nixos-rebuild switch${NC}"
        exit 1
    fi
}

function install_single() {
    local pwa_name="$1"
    
    echo -e "${GREEN}Installing PWA: $pwa_name${NC}"
    
    # Find PWA configuration
    if grep -q "^      $pwa_name = {" /etc/nixos/modules/desktop/pwa-definitions.nix; then
        # Extract PWA details
        local name=$(grep -A1 "^      $pwa_name = {" /etc/nixos/modules/desktop/pwa-definitions.nix | \
                     grep "name =" | sed 's/.*name = "//;s/".*//')
        local url=$(grep -A2 "^      $pwa_name = {" /etc/nixos/modules/desktop/pwa-definitions.nix | \
                    grep "url =" | sed 's/.*url = "//;s/".*//')
        local manifest=$(grep -A3 "^      $pwa_name = {" /etc/nixos/modules/desktop/pwa-definitions.nix | \
                        grep "manifest =" | sed 's/.*manifest = "//;s/".*//')
        
        echo "  Name: $name"
        echo "  URL: $url"
        echo "  Manifest: $manifest"
        
        # Install using firefoxpwa
        firefoxpwa site install \
            --name "$name" \
            --start-url "$url" \
            "$manifest" 2>&1 | grep -E "(installed|ERROR)"
    else
        echo -e "${RED}Error: PWA '$pwa_name' not found in configuration${NC}"
        echo "Available PWAs:"
        list_configured
        exit 1
    fi
}

function uninstall() {
    local pwa_id="$1"
    
    if [ -z "$pwa_id" ]; then
        echo -e "${RED}Error: Please provide a PWA ID to uninstall${NC}"
        echo "Use '$0 list' to see installed PWAs with their IDs"
        exit 1
    fi
    
    echo -e "${YELLOW}Uninstalling PWA with ID: $pwa_id${NC}"
    firefoxpwa site uninstall "$pwa_id"
}

function launch() {
    local pwa_name="$1"
    
    if [ -z "$pwa_name" ]; then
        echo -e "${RED}Error: Please provide a PWA name to launch${NC}"
        exit 1
    fi
    
    # Try to find desktop file
    local desktop_file=$(ls ~/.local/share/applications/*"$pwa_name"*.desktop 2>/dev/null | head -1)
    
    if [ -f "$desktop_file" ]; then
        echo -e "${GREEN}Launching $pwa_name...${NC}"
        gtk-launch "$(basename "$desktop_file" .desktop)" &
    else
        echo -e "${RED}Error: PWA '$pwa_name' not found${NC}"
        echo "Installed PWAs:"
        list_installed
        exit 1
    fi
}

function show_taskbar() {
    echo -e "${GREEN}Current taskbar PWAs:${NC}"
    echo "--------------------"
    
    # Extract taskbar launchers from KDE config
    grep "^launchers=" ~/.config/plasma-org.kde.plasma.desktop-appletsrc | \
        sed 's/launchers=//' | tr ',' '\n' | \
        grep "FFPWA" | \
        while read launcher; do
            file=$(echo "$launcher" | sed 's|file://||')
            if [ -f "$file" ]; then
                name=$(grep "^Name=" "$file" | cut -d= -f2)
                echo "  • $name"
            fi
        done
}

function update_taskbar() {
    echo -e "${GREEN}Updating taskbar with installed PWAs...${NC}"
    
    # This would need to modify the KDE panel configuration
    # For now, just show instructions
    echo "To add PWAs to your taskbar:"
    echo "1. Right-click on the taskbar"
    echo "2. Select 'Edit Panel...'"
    echo "3. Right-click on Icon Tasks widget"
    echo "4. Select 'Configure Icon Tasks...'"
    echo "5. Add installed PWAs from ~/.local/share/applications/FFPWA-*.desktop"
    echo ""
    echo "Or manually edit: ~/.config/plasma-org.kde.plasma.desktop-appletsrc"
}

function help() {
    echo "Firefox PWA Manager for NixOS"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  list-configured    Show PWAs configured in NixOS"
    echo "  list              Show installed PWAs"
    echo "  install-all       Install all configured PWAs"
    echo "  install <name>    Install a specific PWA"
    echo "  uninstall <id>    Uninstall a PWA by ID"
    echo "  launch <name>     Launch a PWA"
    echo "  taskbar           Show PWAs on taskbar"
    echo "  update-taskbar    Instructions to update taskbar"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list                    # List installed PWAs"
    echo "  $0 install github          # Install GitHub PWA"
    echo "  $0 launch Claude           # Launch Claude PWA"
    echo "  $0 uninstall 01ABC...      # Uninstall PWA by ID"
}

# Main script logic
case "${1:-help}" in
    list-configured)
        list_configured
        ;;
    list)
        list_installed
        ;;
    install-all)
        install_all
        ;;
    install)
        install_single "$2"
        ;;
    uninstall)
        uninstall "$2"
        ;;
    launch)
        launch "$2"
        ;;
    taskbar)
        show_taskbar
        ;;
    update-taskbar)
        update_taskbar
        ;;
    help|--help|-h)
        help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        help
        exit 1
        ;;
esac

#!/usr/bin/env bash
# Firefox PWA Manager - Helper script for managing Progressive Web Apps
# Usage: pwa-manager.sh [command] [options]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if firefoxpwa is installed
if ! command -v firefoxpwa &> /dev/null; then
    echo -e "${RED}Error: firefoxpwa is not installed${NC}"
    echo "Please enable Firefox PWA support in your NixOS configuration"
    exit 1
fi

# Function to display help
show_help() {
    echo "Firefox PWA Manager"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  list                     List all profiles"
    echo "  install-defaults         Install default PWAs (Interactive)"
    echo "  install [name] [url]     Install a custom PWA (Interactive)"
    echo "  uninstall [id]           Remove a PWA by ID"
    echo "  launch [id]              Launch a PWA by ID"
    echo "  update [id]              Update a PWA by ID"
    echo "  help                     Show this help message"
    echo ""
    echo "Installation Process:"
    echo "  1. Run 'pwa install-defaults' or 'pwa install <name> <url>'"
    echo "  2. Firefox will open with the PWAsForFirefox extension"
    echo "  3. Click the extension icon in Firefox toolbar"
    echo "  4. Click 'Install current site as PWA'"
    echo "  5. Configure the PWA settings and click Install"
    echo ""
    echo "Note: PWAs must be installed through the Firefox extension interface"
}

# Install default PWAs - opens Firefox for each
install_defaults() {
    echo -e "${BLUE}Opening Firefox for PWA Installation${NC}"
    echo ""
    echo -e "${YELLOW}Instructions:${NC}"
    echo "1. Firefox will open to each site"
    echo "2. Click the PWAsForFirefox extension icon (puzzle piece in toolbar)"
    echo "3. Click 'Install current site as PWA'"
    echo "4. Configure and install"
    echo ""

    # YouTube
    echo -e "${GREEN}Opening YouTube...${NC}"
    firefox "https://youtube.com" &
    sleep 2

    # Google AI Studio
    echo -e "${GREEN}Opening Google AI Studio...${NC}"
    firefox "https://aistudio.google.com" &
    sleep 2

    # Gemini
    echo -e "${GREEN}Opening Gemini...${NC}"
    firefox "https://gemini.google.com" &
    sleep 2

    # ChatGPT
    echo -e "${GREEN}Opening ChatGPT...${NC}"
    firefox "https://chat.openai.com" &

    echo ""
    echo -e "${BLUE}All sites opened in Firefox!${NC}"
    echo -e "${YELLOW}Use the PWAsForFirefox extension to install each as a PWA${NC}"
    echo ""
    echo "After installation, use 'pwa list' to see your installed PWAs"
}

# Install custom PWA
install_custom() {
    local name="$1"
    local url="$2"

    if [ -z "$name" ] || [ -z "$url" ]; then
        echo -e "${RED}Error: Both name and URL are required${NC}"
        echo "Usage: $0 install [name] [url]"
        exit 1
    fi

    echo -e "${BLUE}Opening Firefox for PWA Installation: $name${NC}"
    echo ""
    echo -e "${YELLOW}Instructions:${NC}"
    echo "1. Firefox will open to: $url"
    echo "2. Click the PWAsForFirefox extension icon"
    echo "3. Click 'Install current site as PWA'"
    echo "4. Set the name to: $name"
    echo "5. Configure other settings and click Install"
    echo ""

    firefox "$url" &

    echo -e "${GREEN}Firefox opened!${NC}"
    echo "Complete the installation using the PWAsForFirefox extension"
}

# Function to get PWA sites (parse profile list for sites)
get_pwa_sites() {
    # This will need to be parsed from firefoxpwa output
    # For now, just show profiles
    firefoxpwa profile list
}

# Main command handler
case "$1" in
    list)
        echo -e "${BLUE}Available profiles and PWAs:${NC}"
        get_pwa_sites
        echo ""
        echo -e "${YELLOW}Note: Use profile IDs for launching/uninstalling${NC}"
        ;;

    install-defaults)
        install_defaults
        ;;

    install)
        install_custom "$2" "$3"
        ;;

    uninstall|remove)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: PWA ID required${NC}"
            echo "Use 'pwa list' to see available IDs"
            exit 1
        fi
        echo -e "${YELLOW}Uninstalling PWA: $2${NC}"
        firefoxpwa site uninstall "$2" 2>&1 || echo -e "${RED}Failed to uninstall. Check the ID.${NC}"
        ;;

    launch|open)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: PWA ID required${NC}"
            echo "Use 'pwa list' to see available IDs"
            exit 1
        fi
        echo -e "${BLUE}Launching PWA: $2${NC}"
        firefoxpwa site launch "$2" 2>&1 || echo -e "${RED}Failed to launch. Check the ID.${NC}"
        ;;

    update)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: PWA ID required${NC}"
            echo "Use 'pwa list' to see available IDs"
            exit 1
        fi
        echo -e "${YELLOW}Updating PWA: $2${NC}"
        firefoxpwa site update "$2" 2>&1 || echo -e "${RED}Failed to update. Check the ID.${NC}"
        ;;

    help|--help|-h|"")
        show_help
        ;;

    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac
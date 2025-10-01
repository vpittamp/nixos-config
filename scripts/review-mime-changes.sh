#!/usr/bin/env bash
# Script to review MIME association changes and optionally add them to configuration

set -euo pipefail

MIME_LOG_DIR="$HOME/.local/share/home-manager/mime-logs"
LOG_FILE="$MIME_LOG_DIR/changes.log"
FIREFOX_NIX="/etc/nixos/home-modules/tools/firefox.nix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== MIME Association Change Review ===${NC}"
echo

if [ ! -f "$LOG_FILE" ]; then
    echo -e "${GREEN}No MIME association changes detected.${NC}"
    echo "Home-manager configuration is in sync with system."
    exit 0
fi

# Check for recent changes
recent_logs=$(find "$MIME_LOG_DIR" -name "mimeapps.list.user-*" -mtime -7 2>/dev/null | sort -r)

if [ -z "$recent_logs" ]; then
    echo -e "${GREEN}No recent user MIME association changes found.${NC}"
    exit 0
fi

echo -e "${YELLOW}Recent user MIME association files found:${NC}"
echo "$recent_logs" | head -5
echo

# Show the latest user preferences
latest_user_file=$(echo "$recent_logs" | head -1)
echo -e "${BLUE}Latest user associations from: $(basename "$latest_user_file")${NC}"
echo

if [ -f "$latest_user_file" ]; then
    echo "User-specific MIME associations:"
    grep -E "^(text/|application/|x-scheme-handler/)" "$latest_user_file" | head -20 || true
    echo
fi

echo -e "${YELLOW}Options:${NC}"
echo "1. View full diff between user and managed configurations"
echo "2. Show how to add specific associations to firefox.nix"
echo "3. Clean up old log files (older than 30 days)"
echo "4. Exit"
echo

read -p "Select option (1-4): " choice

case $choice in
    1)
        echo -e "\n${BLUE}Differences between managed and user configurations:${NC}"
        if [ -f "$latest_user_file" ]; then
            # Create a temporary file with current managed associations
            current_managed=$(mktemp)
            if [ -L "$HOME/.config/mimeapps.list" ]; then
                readlink -f "$HOME/.config/mimeapps.list" | xargs cat > "$current_managed"
            fi

            diff --unified=2 "$current_managed" "$latest_user_file" || true
            rm -f "$current_managed"
        fi
        ;;

    2)
        echo -e "\n${BLUE}To add user associations to firefox.nix:${NC}"
        echo
        echo "Edit $FIREFOX_NIX and add entries to the xdg.mimeApps.defaultApplications section."
        echo
        echo "Example additions based on recent user changes:"
        if [ -f "$latest_user_file" ]; then
            grep -E "^(application/pdf|image/)" "$latest_user_file" | head -5 | while IFS='=' read -r mime apps; do
                app_list=$(echo "$apps" | tr ';' ' ' | xargs -n1 | sed 's/^/"/;s/$/"/' | tr '\n' ' ' | sed 's/ $//')
                echo "      \"$mime\" = [ $app_list ];"
            done
        fi
        echo
        echo "After editing, rebuild with: sudo nixos-rebuild switch --flake .#$(hostname)"
        ;;

    3)
        echo -e "\n${YELLOW}Cleaning up old log files...${NC}"
        find "$MIME_LOG_DIR" -name "*.user-*" -mtime +30 -delete -print
        old_entries=$(mktemp)
        awk -v d="$(date -d '30 days ago' '+%Y-%m-%d')" '$1 < d' "$LOG_FILE" > "$old_entries"
        if [ -s "$old_entries" ]; then
            grep -v -F -f "$old_entries" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi
        rm -f "$old_entries"
        echo -e "${GREEN}Cleanup complete.${NC}"
        ;;

    4)
        echo -e "${GREEN}Exiting.${NC}"
        exit 0
        ;;

    *)
        echo -e "${RED}Invalid option.${NC}"
        exit 1
        ;;
esac

echo
echo -e "${BLUE}Tip:${NC} Run this script periodically to review MIME association changes."
echo "Any associations set through KDE System Settings will be logged for review."
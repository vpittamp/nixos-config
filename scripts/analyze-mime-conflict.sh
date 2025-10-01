#!/usr/bin/env bash
# Forensic analysis of MIME association conflicts

set -euo pipefail

echo "=== MIME Association Conflict Analysis ==="
echo
echo "This script analyzes what typically causes MIME association conflicts."
echo

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 1. Check KDE's default MIME handlers
echo -e "${BLUE}1. KDE System Settings MIME Handlers:${NC}"
if command -v kreadconfig6 &>/dev/null; then
    echo "Default browser from KDE:"
    kreadconfig6 --file kdeglobals --group General --key BrowserApplication 2>/dev/null || echo "  Not set"
    echo
fi

# 2. Check xdg-settings
echo -e "${BLUE}2. XDG System Default Browser:${NC}"
if command -v xdg-settings &>/dev/null; then
    xdg-settings get default-web-browser 2>/dev/null || echo "  Not set"
    echo
fi

# 3. Check for applications that might modify MIME associations
echo -e "${BLUE}3. Applications that commonly modify MIME associations:${NC}"

# Check for installed applications known to modify MIME
apps_that_modify=(
    "kde-open5"
    "xdg-mime"
    "kioclient"
    "kfmclient"
    "plasma-discover"
    "systemsettings"
)

for app in "${apps_that_modify[@]}"; do
    if command -v "$app" &>/dev/null; then
        echo -e "  ${YELLOW}✓${NC} $app is installed"
    fi
done
echo

# 4. Check recent modifications to MIME files
echo -e "${BLUE}4. Recent MIME file modifications:${NC}"

# Check when files were last modified
for file in ~/.config/mimeapps.list ~/.local/share/applications/mimeapps.list; do
    if [ -e "$file" ]; then
        if [ -L "$file" ]; then
            echo "  $file -> symlink (managed by home-manager)"
            target=$(readlink -f "$file")
            echo "    Points to: $target"
        else
            echo "  $file -> regular file"
            stat_info=$(stat -c "Modified: %y" "$file" 2>/dev/null)
            echo "    $stat_info"
        fi
    fi
done
echo

# 5. Analyze typical conflict patterns
echo -e "${BLUE}5. Common conflict patterns:${NC}"
echo
echo "Based on the home-manager source code and common issues:"
echo
echo -e "${YELLOW}Scenario A: KDE System Settings${NC}"
echo "  When: User changes default applications in System Settings"
echo "  What happens: KDE writes to ~/.config/mimeapps.list directly"
echo "  Conflict: Home-manager wants to manage this as a symlink"
echo
echo -e "${YELLOW}Scenario B: Application Installation${NC}"
echo "  When: Installing apps via Discover or package manager"
echo "  What happens: App registers MIME handlers via xdg-mime"
echo "  Conflict: Creates/modifies mimeapps.list as regular file"
echo
echo -e "${YELLOW}Scenario C: Firefox PWA Installation${NC}"
echo "  When: Installing Progressive Web Apps"
echo "  What happens: firefoxpwa creates .desktop files and MIME entries"
echo "  Conflict: Modifies mimeapps.list to register PWA handlers"
echo

# 6. Simulate what would have caused the original error
echo -e "${BLUE}6. Recreating the original conflict scenario:${NC}"
echo
echo "The error occurred because:"
echo "1. Home-manager tried to create a backup with extension '.backup'"
echo "2. A '.backup' file already existed from a previous conflict"
echo "3. Home-manager refused to overwrite the existing backup"
echo
echo "Most likely sequence of events:"
echo "  1. Initial nixos-rebuild: KDE had modified mimeapps.list"
echo "  2. Home-manager backed it up as mimeapps.list.backup"
echo "  3. Second nixos-rebuild: KDE modified it again"
echo "  4. Home-manager tried to backup again, but .backup already existed"
echo

# 7. Check for PWA or other desktop file modifications
echo -e "${BLUE}7. Recently modified desktop files:${NC}"
find ~/.local/share/applications -name "*.desktop" -mtime -7 2>/dev/null | head -10 | while read -r file; do
    echo "  $(basename "$file") - modified $(stat -c "%y" "$file" | cut -d' ' -f1)"
done

echo
echo -e "${GREEN}Analysis complete.${NC}"
echo
echo "To prevent future conflicts:"
echo "1. Our new configuration uses 'hm-backup' extension instead of 'backup'"
echo "2. Logging system tracks all changes that would be overwritten"
echo "3. Review changes with: /etc/nixos/scripts/review-mime-changes.sh"
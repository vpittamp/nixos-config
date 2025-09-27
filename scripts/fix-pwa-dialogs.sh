#!/usr/bin/env bash

# Fix PWA dialog rendering issues on Wayland
# This script updates PWA desktop files to include Wayland compatibility flags

set -euo pipefail

echo "Fixing PWA dialog rendering issues..."

# Add environment variables for proper Wayland rendering
for desktop in ~/.local/share/applications/FFPWA-*.desktop; do
    if [ -f "$desktop" ]; then
        name=$(basename "$desktop")
        echo "  Updating $name"

        # Backup original
        cp "$desktop" "${desktop}.backup"

        # Check if already has environment variables
        if ! grep -q "^Exec=env" "$desktop"; then
            # Add Wayland environment variables to fix dialog rendering
            sed -i 's|^Exec=|Exec=env MOZ_ENABLE_WAYLAND=1 GTK_USE_PORTAL=1 |' "$desktop"
        fi
    fi
done

echo ""
echo "Creating PWA preferences for better dialog handling..."

# Create user.js with dialog fixes for all PWA profiles
for profile_dir in ~/.local/share/firefoxpwa/profiles/*/; do
    if [ -d "$profile_dir" ]; then
        profile_name=$(basename "$profile_dir")
        echo "  Configuring profile: $profile_name"

        cat > "${profile_dir}/user.js" << 'EOF'
// Fix dialog rendering issues
user_pref("widget.use-xdg-desktop-portal", true);
user_pref("widget.use-xdg-desktop-portal.file-picker", 1);
user_pref("widget.use-xdg-desktop-portal.mime-handler", 1);
user_pref("browser.display.use_system_colors", true);
user_pref("ui.use_native_colors", true);
user_pref("widget.content.gtk-theme-override", "");
user_pref("widget.gtk.overlay-scrollbars.enabled", false);

// Ensure proper window decorations
user_pref("browser.tabs.inTitlebar", 0);
user_pref("browser.tabs.drawInTitlebar", false);

// Fix popup windows
user_pref("dom.disable_open_during_load", false);
user_pref("privacy.popups.policy", 1);
user_pref("dom.popup_maximum", 20);
user_pref("browser.link.open_newwindow.restriction", 0);

// Better modal dialog handling
user_pref("prompts.defaultModalType", 3);
user_pref("prompts.modalType.httpAuth", 3);
user_pref("prompts.modalType.confirmEx", 3);
user_pref("prompts.tab_modal.enabled", false);
EOF
    fi
done

echo ""
echo "Updating desktop database..."
update-desktop-database ~/.local/share/applications 2>/dev/null || true

echo ""
echo "✓ Dialog fixes applied!"
echo ""
echo "Please restart your PWAs for the changes to take effect."
echo "If dialogs are still malformed, try:"
echo "  1. Close all PWAs"
echo "  2. Run: killall firefox firefoxpwa 2>/dev/null"
echo "  3. Relaunch the PWA"
echo ""
echo "For persistent issues, you may need to log out and back in."
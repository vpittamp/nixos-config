# Firefox PWA (Progressive Web Apps) Configuration

This module provides a hybrid approach to PWAs on NixOS, combining declarative configuration with firefoxpwa functionality.

## Architecture

We use a **dual-system approach**:
1. **Declarative desktop files and icons** - Managed by NixOS
2. **PWA profiles and runtime** - Managed by firefoxpwa

## Current PWAs

| App | PWA ID | Icon | URL |
|-----|--------|------|-----|
| Google AI | 01K5SRD32G3CDN8FC5KM8HMQNP | google-ai.png | https://www.google.com/search?udm=50 |
| YouTube | 01K5SC803TS46ABVVPYZ8HYHYK | youtube.svg | https://www.youtube.com |
| ArgoCD | 01K5V5G5BVA6HNRPE7BFGZECKJ | ArgoCD.svg | https://argocd.cnoe.localtest.me:8443 |
| Gitea | 01K5V5GCYQ3JVFZQGDAK57P69E | Gitea.svg | https://gitea.cnoe.localtest.me:8443 |
| Backstage | 01K5V5GD1MCFJJZMWGM5WS1TDK | Backstage.svg | https://backstage.cnoe.localtest.me:8443 |
| Headlamp | 01K5V5GD4YJTD95867CP4W5WXP | Headlamp.svg | https://headlamp.cnoe.localtest.me:8443 |
| Kargo | 01K5V5GD81REQB1T1TZ049BRFR | Kargo.svg | https://kargo.cnoe.localtest.me:8443 |

## Adding a New PWA

### Step 1: Install the PWA
```bash
# Install via firefoxpwa (opens Firefox for interactive install)
firefoxpwa site install "https://example.com" --name "My App"

# Or install from a manifest
firefoxpwa site install "https://example.com/manifest.json" --name "My App"
```

### Step 2: Get the PWA ID
```bash
# List all PWAs to find your new app's ID
firefoxpwa profile list
```

### Step 3: Add Icon
Place your icon in `/etc/nixos/assets/icons/pwas/`:
- **Preferred**: SVG format for perfect scaling
- **Alternative**: PNG at least 512x512px

```bash
# Example: Add icon
cp ~/Downloads/myapp.svg /etc/nixos/assets/icons/pwas/
```

### Step 4: Create Desktop File
Create `~/.local/share/applications/pwa-myapp.desktop`:

```desktop
[Desktop Entry]
Type=Application
Version=1.4
Name=My App
Icon=pwa-myapp
Exec=firefoxpwa site launch YOUR_PWA_ID %u
Terminal=false
StartupNotify=true
StartupWMClass=FFPWA-YOUR_PWA_ID
Categories=Network;WebBrowser;
```

### Step 5: Process Icon
```bash
# For SVG icons (best quality)
rsvg-convert -w 128 -h 128 --background-color=transparent \
  /etc/nixos/assets/icons/pwas/myapp.svg \
  -o ~/.local/share/icons/hicolor/128x128/apps/pwa-myapp.png

# For PNG icons
magick /etc/nixos/assets/icons/pwas/myapp.png \
  -resize 128x128 -background transparent \
  ~/.local/share/icons/hicolor/128x128/apps/pwa-myapp.png
```

### Step 6: Update System
```bash
# Update icon cache
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor

# Update desktop database
update-desktop-database ~/.local/share/applications

# Restart Plasma to show new PWA
systemctl --user restart plasma-plasmashell.service
```

## Icon Management

### Icon Requirements
- **Format**: SVG preferred, PNG accepted
- **Size**: At least 128x128, 512x512 recommended
- **Background**: Transparent
- **Location**: `/etc/nixos/assets/icons/pwas/`

### Fix All Icons Script
Save as `~/fix-pwa-icons.sh`:
```bash
#!/bin/bash
for svg in /etc/nixos/assets/icons/pwas/*.svg; do
  name=$(basename "$svg" .svg | tr '[:upper:]' '[:lower:]')
  rsvg-convert -w 128 -h 128 --background-color=transparent "$svg" \
    -o ~/.local/share/icons/hicolor/128x128/apps/pwa-${name}.png
done
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor
```

## Managing PWAs

### List all PWAs
```bash
firefoxpwa profile list
```

### Launch a PWA
```bash
# Via desktop file (recommended)
gtk-launch pwa-myapp

# Direct launch
firefoxpwa site launch PWA_ID
```

### Uninstall a PWA
```bash
# Uninstall PWA (keeps profile data)
firefoxpwa site uninstall PWA_ID

# Remove desktop file
rm ~/.local/share/applications/pwa-myapp.desktop

# Remove icon
rm ~/.local/share/icons/hicolor/*/apps/pwa-myapp.png
```

## Troubleshooting

### PWA won't launch
1. Check PWA ID matches: `firefoxpwa profile list`
2. Verify desktop file Exec line has correct ID
3. Test direct launch: `firefoxpwa site launch PWA_ID`

### Icon not showing
1. Regenerate icon: `rsvg-convert ...` (see above)
2. Clear cache: `gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor`
3. Restart Plasma: `systemctl --user restart plasma-plasmashell.service`

### White background on icons
- Use `rsvg-convert` with `--background-color=transparent`
- For PNGs, use ImageMagick: `magick input.png -transparent white output.png`

## Files and Locations

| Component | Location |
|-----------|----------|
| Icons (source) | `/etc/nixos/assets/icons/pwas/` |
| Icons (rendered) | `~/.local/share/icons/hicolor/*/apps/pwa-*.png` |
| Desktop files | `~/.local/share/applications/pwa-*.desktop` |
| PWA profiles | `~/.local/share/firefoxpwa/profiles/` |
| Module config | `/etc/nixos/modules/desktop/pwa-declarative.nix` |

## Future Improvements

To make this fully declarative, we would need to:
1. Generate PWA IDs deterministically
2. Create profiles programmatically
3. Handle all icon processing at build time

Current approach works well as a hybrid solution, giving us:
- Declarative icon management
- Manual PWA installation (for flexibility)
- Proper firefoxpwa features (offline support, separate profiles)
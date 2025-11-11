# Quickstart: Unified Workspace Bar Icon System

**Feature**: 057-workspace-bar-icons | **Last Updated**: 2025-11-10

This guide provides quick reference for understanding, troubleshooting, and validating the workspace bar icon system.

---

## Overview

The workspace bar displays icons for applications running on each workspace, using the same icon lookup logic as the Walker launcher. Icons are resolved through a 5-step priority cascade:

1. **Application Registry** → Curated app icon mappings
2. **PWA Registry** → Firefox PWA custom icons
3. **Desktop Files (by ID)** → System `.desktop` files
4. **Desktop Files (by StartupWMClass)** → Window class matching
5. **Icon Theme Lookup** → XDG icon themes (Papirus, Breeze, hicolor)
6. **Fallback** → First uppercase letter of app name

---

## Quick Commands

### Restart Workspace Bar Service

```bash
# Restart Eww workspace bar daemon
systemctl --user restart eww-workspace-bar

# Check service status
systemctl --user status eww-workspace-bar

# View logs
journalctl --user -u eww-workspace-bar -f
```

### Check Icon Resolution for Running App

```bash
# Get window info from Sway
swaymsg -t get_tree | jq '.. | select(.type? == "con" and .name? != null) | {app_id, window_class, window_instance, name}'

# Check application registry for icon
cat ~/.config/i3/application-registry.json | jq '.applications[] | select(.name == "firefox")'

# Check PWA registry for icon
cat ~/.config/i3/pwa-registry.json | jq '.pwas[] | select(.ulid == "01JCYF8Z2M")'

# Find icon path via PyXDG (simulating icon lookup)
python3 -c "from xdg.IconTheme import getIconPath; print(getIconPath('firefox', 48))"
```

### Validate Icon Paths

```bash
# Check if icon file exists
test -f "/path/to/icon.svg" && echo "Icon exists" || echo "Icon missing"

# List all icons in application registry
cat ~/.config/i3/application-registry.json | jq -r '.applications[] | "\(.name): \(.icon)"'

# List all PWA icons
cat ~/.config/i3/pwa-registry.json | jq -r '.pwas[] | "\(.name): \(.icon)"'

# Verify PWA icon files exist
for icon in $(cat ~/.config/i3/pwa-registry.json | jq -r '.pwas[].icon'); do
  if [[ -f "$icon" ]]; then
    echo "✅ $icon"
  else
    echo "❌ $icon (MISSING)"
  fi
done
```

---

## Icon Lookup Precedence

### Priority Order (Highest to Lowest)

| Priority | Source | Index Key | Example |
|----------|--------|-----------|---------|
| **1** | Application Registry | `name` | `"firefox"` → `"firefox"` icon |
| **2** | PWA Registry | `"ffpwa-{ulid}"` | `"ffpwa-01jcyf8z2m"` → `/etc/nixos/assets/pwa-icons/claude.png` |
| **3** | Desktop File (by ID) | Desktop file stem | `firefox.desktop` → `Icon=firefox` |
| **4** | Desktop File (by StartupWMClass) | `StartupWMClass` | `firefox` class → `Icon=firefox` |
| **5** | Icon Theme Lookup (PyXDG) | Icon name | `"firefox"` → `/usr/share/icons/Papirus/48x48/apps/firefox.svg` |
| **6** | Fallback Symbol | First letter | `"firefox"` → `"F"` |

### Example Resolution Traces

**Regular Application (Firefox)**:
```
Window: {app_id: "firefox", class: "firefox", instance: null}
 → Try app registry: ✅ Match "firefox" → icon: "firefox"
 → Resolve icon name: getIconPath("firefox", 48)
 → Result: /usr/share/icons/Papirus/48x48/apps/firefox.svg
```

**PWA (Claude)**:
```
Window: {app_id: "ffpwa-01jcyf8z2m", class: "FFPWA-01JCYF8Z2M", instance: null}
 → Try app registry: ❌ No match
 → Try PWA registry: ✅ Match "ffpwa-01jcyf8z2m" → icon: "/etc/nixos/assets/pwa-icons/claude.png"
 → Result: /etc/nixos/assets/pwa-icons/claude.png (absolute path, no further lookup)
```

**Terminal Application (lazygit)**:
```
Window: {app_id: null, class: "ghostty", instance: "lazygit"}
 → Try app registry: ✅ Match "lazygit" (via instance) → icon: "lazygit"
 → Resolve icon name: getIconPath("lazygit", 48)
 → Result: /usr/share/icons/Papirus/48x48/apps/lazygit.svg
```

**Unknown Application**:
```
Window: {app_id: "unknown-app", class: "UnknownApp", instance: null}
 → Try app registry: ❌ No match
 → Try PWA registry: ❌ No match
 → Try desktop files: ❌ No match
 → Try icon theme: ❌ No icon "unknown-app" found
 → Fallback: Extract first letter → "U"
```

---

## Adding New Application Icons

### Regular Application

**Step 1**: Add entry to application registry

```bash
# Edit registry
vi ~/.config/i3/application-registry.json

# Add application entry
{
  "name": "code",
  "display_name": "VS Code",
  "command": "code",
  "expected_class": "Code",
  "expected_instance": null,
  "icon": "vscode",
  "scope": "scoped",
  "preferred_workspace": 2,
  "preferred_monitor_role": "primary"
}
```

**Step 2**: Verify icon exists in icon theme

```bash
# Check if icon exists
python3 -c "from xdg.IconTheme import getIconPath; print(getIconPath('vscode', 48))"

# If not found, install icon theme with that icon
# Example: Papirus icon theme has "vscode" icon
```

**Step 3**: Rebuild NixOS and restart bar

```bash
# Apply configuration
sudo nixos-rebuild switch --flake .#hetzner-sway

# Restart workspace bar
systemctl --user restart eww-workspace-bar
```

### Terminal Application

**Step 1**: Add entry with `expected_instance` field

```bash
# Edit registry
vi ~/.config/i3/application-registry.json

# Add terminal app entry
{
  "name": "yazi",
  "display_name": "Yazi",
  "command": "ghostty -e yazi",
  "expected_class": "ghostty",
  "expected_instance": "yazi",
  "icon": "yazi",
  "scope": "scoped",
  "preferred_workspace": 8,
  "preferred_monitor_role": null
}
```

**Key Points**:
- `expected_class`: Set to `"ghostty"` (the terminal emulator)
- `expected_instance`: Set to command name (`"yazi"`)
- Icon lookup will match on `window_instance` field from Sway

**Step 2**: Verify icon or add custom icon

```bash
# Check if "yazi" icon exists
python3 -c "from xdg.IconTheme import getIconPath; print(getIconPath('yazi', 48))"

# If not found, add custom SVG to ~/.local/share/icons/
mkdir -p ~/.local/share/icons
cp /path/to/yazi.svg ~/.local/share/icons/yazi.svg

# Update icon cache
gtk-update-icon-cache ~/.local/share/icons
```

### PWA Application

**Step 1**: Install PWA via firefoxpwa (if not already installed)

```bash
# See PWA installation docs
pwa-install-all
```

**Step 2**: Add custom icon to PWA registry (if needed)

```bash
# PWA registry is auto-generated by firefoxpwa
# Icons are stored in /etc/nixos/assets/pwa-icons/

# To customize PWA icon:
# 1. Replace PNG file in assets directory
# 2. Rebuild NixOS
sudo nixos-rebuild switch --flake .#hetzner-sway
```

---

## Troubleshooting

### Issue: Icon Not Displaying (Fallback Letter Shown)

**Symptoms**: Workspace bar shows first letter of app name instead of icon.

**Diagnosis**:

```bash
# Step 1: Check window identifiers
swaymsg -t get_tree | jq '.. | select(.focused? == true) | {app_id, window_class, window_instance, name}'

# Step 2: Check if app in registry
cat ~/.config/i3/application-registry.json | jq '.applications[] | select(.expected_class == "WINDOW_CLASS_HERE")'

# Step 3: Check if icon name resolves
python3 -c "from xdg.IconTheme import getIconPath; print(getIconPath('ICON_NAME_HERE', 48))"
```

**Solutions**:

1. **App not in registry**: Add entry to `application-registry.json`
2. **Icon name wrong**: Fix `icon` field in registry to match actual icon name
3. **Icon missing from theme**: Install icon theme with that icon (e.g., Papirus)
4. **XDG_DATA_DIRS misconfigured**: Verify environment in systemd service:
   ```bash
   systemctl --user show eww-workspace-bar | grep XDG_DATA_DIRS
   ```

### Issue: Wrong Icon Displayed

**Symptoms**: Workspace bar shows different icon than Walker launcher.

**Diagnosis**:

```bash
# Compare XDG_DATA_DIRS between services
systemctl --user show elephant | grep XDG_DATA_DIRS
systemctl --user show eww-workspace-bar | grep XDG_DATA_DIRS

# These MUST be identical
```

**Solutions**:

1. **XDG_DATA_DIRS mismatch**: Update `eww-workspace-bar.nix` to match `walker.nix` environment:
   ```nix
   Environment = [
     "XDG_DATA_DIRS=${config.home.homeDirectory}/.local/share/i3pm-applications:${config.home.homeDirectory}/.local/share:${config.home.profileDirectory}/share:/run/current-system/sw/share"
   ];
   ```

2. **Icon lookup priority different**: Verify both services use same registry files
3. **Cache desync**: Restart both services:
   ```bash
   systemctl --user restart elephant eww-workspace-bar
   ```

### Issue: Terminal App Shows Ghostty Icon

**Symptoms**: lazygit/yazi/btop windows show generic terminal icon instead of app-specific icon.

**Diagnosis**:

```bash
# Check if window_instance is set correctly
swaymsg -t get_tree | jq '.. | select(.window_class? == "ghostty") | {app_id, window_class, window_instance, name}'

# Check if app in registry with expected_instance
cat ~/.config/i3/application-registry.json | jq '.applications[] | select(.expected_instance == "lazygit")'
```

**Solutions**:

1. **Missing registry entry**: Add terminal app to `application-registry.json` with `expected_instance` field
2. **window_instance not set**: Ghostty may not be setting instance correctly - check Ghostty config
3. **Registry name mismatch**: Ensure registry `name` matches `window_instance` exactly (case-sensitive after lowercase conversion)

### Issue: PWA Icon Missing or Generic

**Symptoms**: Firefox PWA shows generic Firefox icon or fallback letter.

**Diagnosis**:

```bash
# Get PWA app_id
swaymsg -t get_tree | jq '.. | select(.app_id? | startswith("ffpwa")) | {app_id, name}'

# Check PWA registry
cat ~/.config/i3/pwa-registry.json | jq '.pwas[] | select(.ulid == "ULID_HERE")'

# Check if icon file exists
ls -lh /etc/nixos/assets/pwa-icons/
```

**Solutions**:

1. **PWA not in registry**: PWA may not be installed via declarative config - check `pwa-sites.nix`
2. **Icon file missing**: Icon PNG not copied to assets directory - rebuild NixOS:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner-sway
   ```
3. **ULID mismatch**: Registry ULID must match `app_id` (lowercase, remove `ffpwa-` prefix)

### Issue: Icons Pixelated or Low Quality

**Symptoms**: Icons appear blurry or pixelated at 20×20 pixel size.

**Diagnosis**:

```bash
# Check icon file format
file /path/to/icon.svg  # Prefer SVG (scalable)
file /path/to/icon.png  # PNG should be ≥48×48 for downscaling

# Check if high-res version available
ls /usr/share/icons/Papirus/*x*/apps/firefox.*
```

**Solutions**:

1. **PNG too small**: Use larger PNG source (≥48×48) or switch to SVG
2. **Wrong icon variant**: Specify exact icon name for high-res variant
3. **Icon theme issue**: Try different icon theme (Papirus recommended for quality)
4. **Eww scaling**: Icon renders at 20×20 but sources 48×48 image for better downscale quality

### Issue: Icon Background Doesn't Integrate with Theme

**Symptoms**: Some icons have backgrounds that clash with the workspace bar's Catppuccin Mocha theme. This is typically caused by unintentional white/default backgrounds, not colored backgrounds per se.

**Good Examples**:
- **Transparent backgrounds**: Firefox, VS Code (no background, integrates seamlessly)
- **Intentional colored backgrounds**: Well-designed icons with colors that complement the theme (e.g., GitHub icon with dark gray #24292E, Reddit with orange #E46231 - see adi1090x/widgets for examples)

**Bad Examples** (unintentional backgrounds that clash):
- **Unintentional white backgrounds**: ChatGPT, Claude PWA icons with default white backgrounds that create jarring visual rectangles
- **Poor color contrast**: Backgrounds that don't coordinate with Catppuccin Mocha palette

**Diagnosis**:

```bash
# Check if icon has transparency (alpha channel)
identify -verbose /etc/nixos/assets/pwa-icons/claude.png | grep -i alpha

# View icon to see background
feh /etc/nixos/assets/pwa-icons/claude.png

# Expected: Alpha channel present, transparent background
# Actual: No alpha or white background
```

**Solutions**:

**Option 1: Replace with transparent version**

```bash
# Find or create transparent version of icon
# Use image editing tool (GIMP, Inkscape, online tools) to:
# 1. Remove white background
# 2. Export with transparency (alpha channel)

# Replace icon file
cp ~/Downloads/claude-transparent.png /etc/nixos/assets/pwa-icons/claude.png

# Rebuild NixOS
sudo nixos-rebuild switch --flake .#hetzner-sway

# Restart workspace bar
systemctl --user restart eww-workspace-bar
```

**Option 2: Use different icon source**

```bash
# Search for alternative icon without background
# Example sources:
# - Icon theme packs (Papirus, Breeze often have transparent versions)
# - Official brand assets (download from company website)
# - Community icon repositories (flaticon, iconfinder)

# Update PWA registry to point to new icon
vi ~/.config/i3/pwa-registry.json
# Change "icon": "/path/to/new/transparent/icon.png"
```

**Option 3: Convert white background to transparent**

```bash
# Use ImageMagick to convert white to transparent
convert /etc/nixos/assets/pwa-icons/claude.png \
  -fuzz 10% -transparent white \
  /etc/nixos/assets/pwa-icons/claude-transparent.png

# Test the result
feh /etc/nixos/assets/pwa-icons/claude-transparent.png

# If good, replace original
mv /etc/nixos/assets/pwa-icons/claude-transparent.png \
   /etc/nixos/assets/pwa-icons/claude.png

# Rebuild and restart
sudo nixos-rebuild switch --flake .#hetzner-sway
systemctl --user restart eww-workspace-bar
```

**Best Practices**:
- **Prefer SVG**: Vector graphics scale perfectly regardless of background style
- **Intentional design wins**: Icons with colored backgrounds (like adi1090x/widgets examples) look great when colors complement the Catppuccin Mocha theme
- **Use brand guidelines**: Many companies provide icon assets designed for dark themes
- **Consistent style**: Match icon style across all apps (minimal, flat, consistent weight)
- **Theme coordination**: If using colored backgrounds, choose colors from or complementary to Catppuccin Mocha palette
- **Test on bar**: View icon against actual workspace bar background to verify integration - both transparent and colored backgrounds can work if designed intentionally

---

## Icon Quality Validation Checklist

Use this checklist to verify icon rendering quality after making changes.

### Test Matrix

| Icon Source | App Example | Test Conditions | Pass Criteria |
|-------------|-------------|-----------------|---------------|
| **App Registry** | firefox | Regular app launch on WS 3 | Icon matches Walker, crisp at 20×20px |
| **PWA Registry** | Claude (FFPWA) | PWA launch on WS 52 | Custom PNG icon displays, no pixelation |
| **Terminal App** | lazygit | `ghostty -e lazygit` on WS 7 | lazygit icon shows (not Ghostty icon) |
| **Desktop File** | System app (e.g., htop) | App not in custom registries | Icon from .desktop file displays |
| **Icon Theme** | Generic app | No registry/desktop match | Icon theme lookup succeeds |
| **Fallback** | Unknown app | No icon found | Single letter displays clearly |

### Visual Inspection Checklist

- [ ] **Hetzner (HEADLESS-1)**: All workspace icons crisp at 1× DPI
- [ ] **M1 (eDP-1)**: All workspace icons crisp at 2× DPI (Retina)
- [ ] **Firefox**: Regular app icon matches Walker launcher
- [ ] **VS Code**: Icon has transparent background (good example)
- [ ] **Claude PWA**: Custom PNG icon displays (not generic Firefox icon)
- [ ] **Icon backgrounds**: Integrate well with theme - either transparent (Firefox, VS Code) OR intentional colored backgrounds (adi1090x/widgets style) - no unintentional white/default backgrounds
- [ ] **PWA icon quality**: Backgrounds either transparent OR designed to complement Catppuccin Mocha theme
- [ ] **lazygit**: Terminal app shows lazygit icon (not Ghostty icon)
- [ ] **Yazi**: Terminal app shows yazi icon
- [ ] **Unknown app**: Fallback letter displays clearly (no blank space)
- [ ] **Icon colors**: Consistent with Catppuccin Mocha palette
- [ ] **Icon spacing**: Even gaps between workspace buttons
- [ ] **Focused workspace**: Icon visible with purple background
- [ ] **Empty workspace**: Fallback letter shows with 40% opacity

### Screenshot Comparison

```bash
# Capture baseline screenshot
grim -o HEADLESS-1 ~/workspace-bar-baseline.png

# After making changes, capture updated screenshot
grim -o HEADLESS-1 ~/workspace-bar-updated.png

# Visual diff (requires ImageMagick)
compare workspace-bar-baseline.png workspace-bar-updated.png diff.png

# View diff
feh diff.png
```

---

## Performance Monitoring

### Check Icon Resolution Latency

```bash
# Enable Python profiling (if implemented)
journalctl --user -u eww-workspace-bar -f | grep "Icon resolution"

# Expected latencies:
# - Cached icon: <50ms
# - Initial lookup: <200ms
# - Workspace update: <500ms end-to-end
```

### Monitor Workspace Bar Updates

```bash
# Watch Sway IPC events
swaymsg -t subscribe -m '["workspace", "window"]' | jq '.change, .container.app_id'

# Watch workspace bar output (Eww deflisten)
# (Requires Eww debug mode or custom logging)
```

---

## Related Documentation

- **Feature Spec**: [spec.md](./spec.md) - Complete feature specification
- **Data Model**: [data-model.md](./data-model.md) - Entity definitions and relationships
- **Research**: [research.md](./research.md) - Technical decisions and alternatives
- **Implementation Tasks**: [tasks.md](./tasks.md) - Step-by-step implementation guide *(generated by /speckit.tasks)*
- **Walker Configuration**: `home-modules/desktop/walker.nix` - Walker launcher icon config (reference)
- **Workspace Panel Daemon**: `home-modules/tools/sway-workspace-panel/workspace_panel.py` - Icon lookup implementation
- **Application Registry**: `~/.config/i3/application-registry.json` - App icon mappings
- **PWA Registry**: `~/.config/i3/pwa-registry.json` - PWA icon mappings

---

## Quick Reference: Key Files

| File Path | Purpose | Edit Frequency |
|-----------|---------|----------------|
| `~/.config/i3/application-registry.json` | App icon mappings | Often (add new apps) |
| `~/.config/i3/pwa-registry.json` | PWA icon paths | Rarely (auto-generated) |
| `home-modules/tools/sway-workspace-panel/workspace_panel.py` | Icon resolution logic | Rarely (feature changes) |
| `home-modules/desktop/eww-workspace-bar.nix` | Bar widget config | Rarely (visual tweaks) |
| `/usr/share/icons/Papirus/` | Icon theme directory | Never (system-managed) |
| `/etc/nixos/assets/pwa-icons/` | PWA custom icons | Rarely (new PWAs) |

---

## FAQ

**Q: How do I change an app's icon?**

A: Edit `~/.config/i3/application-registry.json`, change the `icon` field to a different icon name, then restart the workspace bar service.

**Q: Why does Walker show a different icon than the workspace bar?**

A: XDG_DATA_DIRS mismatch between services. Verify both elephant (Walker) and eww-workspace-bar have identical environment configuration.

**Q: Can I use custom icons not in icon themes?**

A: Yes. Add SVG/PNG files to `~/.local/share/icons/` and reference by filename (without extension) in registry.

**Q: How do I debug which icon resolution step succeeded?**

A: Add logging to `workspace_panel.py` in the `_resolve_icon()` and `lookup()` methods. Check `journalctl --user -u eww-workspace-bar`.

**Q: Do I need to rebuild NixOS for registry changes?**

A: No. Registry files (`application-registry.json`, `pwa-registry.json`) are runtime-loaded. Just restart the workspace bar service.

**Q: How do I test icon changes without restarting services?**

A: Currently requires service restart. Future enhancement could add hot-reload capability (send SIGHUP to daemon).

**Q: Why do some icons look better than others?**

A: Icon integration quality depends on background design, not just transparency. Icons with transparent backgrounds (Firefox, VS Code) OR intentional colored backgrounds that complement Catppuccin Mocha (like adi1090x/widgets examples with GitHub dark gray #24292E, Reddit orange #E46231) both look great. The problem is unintentional white/default backgrounds (some PWA icons) that clash with the dark theme. Replace these with either transparent versions OR designs with theme-complementary colors.

**Q: Should I always use transparent icon backgrounds?**

A: Not necessarily! Both transparent and colored backgrounds can work well if designed intentionally. Transparent backgrounds (Firefox, VS Code) are safe and always integrate. Intentional colored backgrounds (GitHub, Reddit examples from adi1090x/widgets) add visual interest when colors complement the theme. Avoid only unintentional white/default backgrounds that weren't designed for dark themes.

**Q: How do I convert an icon with white background to transparent?**

A: Use ImageMagick: `convert icon.png -fuzz 10% -transparent white icon-transparent.png`. Adjust `-fuzz` percentage if needed. Alternatively, consider replacing with an icon that has an intentional colored background coordinated with Catppuccin Mocha colors. Test the result before replacing the original icon file.

---

**Last Updated**: 2025-11-10 | **Feature**: 057-workspace-bar-icons

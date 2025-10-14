# iTerm2 Setup for NixOS Configuration

## Automatic Declarative Configuration (Recommended)

iTerm2 is configured declaratively via nix-darwin using dynamic profiles. The configuration automatically creates a "NixOS Catppuccin" profile with:

- **Catppuccin Mocha color theme** (matches Starship prompt)
- **Proper terminal type** (`xterm-256color`)
- **MesloLGS Nerd Font** (for icons)
- **Unlimited scrollback**
- **Optimized key bindings**

### Configuration Location

The iTerm2 module is defined in:
- **Module**: `home-modules/terminal/iterm2.nix`
- **Enabled in**: `home-modules/profiles/darwin-home.nix`

### Customization Options

Edit `darwin-home.nix` to customize:

```nix
programs.iterm2 = {
  enable = true;
  profileName = "NixOS Catppuccin";  # Profile name
  font = {
    name = "MesloLGS-NF-Regular";    # Nerd Font name
    size = 14;                        # Font size
  };
  unlimitedScrollback = true;         # Unlimited history
  transparency = 0.0;                 # 0.0 = opaque, 1.0 = transparent
  blur = false;                       # Background blur effect
};
```

### Apply Configuration

```bash
# Rebuild to create/update iTerm2 profile
sudo darwin-rebuild switch --flake .#darwin

# Restart iTerm2 or create new tab
# Profile will appear in: Profiles → NixOS Catppuccin
```

The dynamic profile is automatically created at:
`~/Library/Application Support/iTerm2/DynamicProfiles/nixos-catppuccin.json`

## Manual Setup (Alternative)

If you prefer manual configuration or need to import the theme separately:

### Download Theme

```bash
# Download Catppuccin Mocha theme
curl -sL https://raw.githubusercontent.com/catppuccin/iterm/main/colors/catppuccin-mocha.itermcolors -o ~/catppuccin-mocha.itermcolors
```

### Import Theme

1. Open iTerm2
2. Go to **Preferences** (⌘,)
3. Navigate to **Profiles** → **Colors**
4. Click **Color Presets...** dropdown (bottom right)
5. Select **Import...**
6. Navigate to `~/catppuccin-mocha.itermcolors`
7. Click **Import**
8. Select **catppuccin-mocha** from the Color Presets dropdown

### Configure Terminal Type

1. In the same profile, go to **Terminal** tab
2. Set **Report Terminal Type** to: `xterm-256color`
3. Check **Enable 24-bit (true color) support** (usually enabled by default)

### Font Settings

1. Go to **Profiles** → **Text**
2. Set font to a Nerd Font (e.g., "MesloLGS Nerd Font" size 14)
3. Make sure **Use ligatures** is checked

### Additional Settings

**Profiles → Keys:**
- Set **Left Option key** to: `Esc+` (for better bash/vim compatibility)

**Profiles → Terminal:**
- **Scrollback lines**: 10000 (or unlimited)
- Check **Unlimited scrollback**

**General → tmux:**
- Check **tmux Integration**

## Verifying Colors Work

After applying the theme and rebuilding:

```bash
# Rebuild Darwin configuration
sudo darwin-rebuild switch --flake .#darwin

# Start new shell
exec bash -l

# Test colors
~/nixos-config/scripts/test-colors.sh
```

You should see:
- Beautiful pastel colors in the prompt
- Username in pink/rosewater
- Hostname in blue/sapphire
- Directory in green
- Git branch in peach/orange
- Git status in yellow

## Troubleshooting

### Colors still look wrong

1. **Check minimum contrast**: Preferences → Profiles → Colors → Minimum contrast slider should be at 0
2. **Verify COLORTERM**: Run `echo $COLORTERM` - should show `truecolor`
3. **Check tmux**: Inside tmux, run `echo $TERM` - should show `tmux-256color` or `screen-256color`

### RGB colors not working

```bash
# Test RGB support directly
printf "\e[38;2;255;100;0mTRUECOLOR\e[0m\n"
```

If this shows an orange "TRUECOLOR", RGB works. If it's a basic color or broken, iTerm2's true color support isn't enabled.

### Prompt looks different in tmux

This is expected if you just rebuilt - tmux sessions keep old environment. Fix:

```bash
# Kill all tmux sessions (saves work first!)
tmux kill-server

# Or just exit tmux and start fresh
exit
tmux
```

## Alternative: Use Tango Dark (Built-in)

If you prefer not to import a custom theme:

1. Go to **Preferences** → **Profiles** → **Colors**
2. Select **Tango Dark** from Color Presets
3. Adjust these colors manually:
   - Background: `#1e1e2e` (Catppuccin base)
   - Foreground: `#cdd6f4` (Catppuccin text)

This provides good contrast with Starship's Catppuccin colors.

## Notes

- **Terminal.app**: Does NOT support RGB colors well, causing the washed-out appearance
- **iTerm2**: Full RGB support, better tmux integration, recommended for development
- **SSH/Remote**: Terminal.app works fine for SSH because the remote system renders colors

---

Related: See `CLAUDE.md` for nix-darwin system management commands.

# Module Contract: services.i3wm

**Feature**: Lightweight X11 Desktop Environment for Hetzner Cloud
**Module Path**: `modules/desktop/i3wm.nix`
**Date**: 2025-10-16

## Purpose

NixOS module for declarative configuration of the i3 window manager. Generates i3 configuration files from structured options and manages i3-related packages.

## Module Options

### Core Configuration

#### `services.i3wm.enable`
- **Type**: `bool`
- **Default**: `false`
- **Description**: Whether to enable the i3 window manager.
- **Example**: `true`

#### `services.i3wm.package`
- **Type**: `package`
- **Default**: `pkgs.i3`
- **Description**: The i3 package to use.
- **Example**: `pkgs.i3-gaps`

#### `services.i3wm.modifier`
- **Type**: `string`
- **Default**: `"Mod4"`
- **Description**: Modifier key for i3 keybindings. Mod1 = Alt, Mod4 = Super/Windows key.
- **Allowed Values**: `"Mod1"`, `"Mod4"`
- **Example**: `"Mod4"`

### Keybindings

#### `services.i3wm.keybindings`
- **Type**: `attrsOf string`
- **Default**: `{}` (uses i3 defaults)
- **Description**: Custom keybindings. Attribute name is the key combination, value is the i3 command.
- **Example**:
```nix
{
  "${modifier}+Return" = "exec ${pkgs.alacritty}/bin/alacritty";
  "${modifier}+d" = "exec ${pkgs.dmenu}/bin/dmenu_run";
  "${modifier}+Shift+q" = "kill";
}
```

### Workspaces

#### `services.i3wm.workspaces`
- **Type**: `listOf (submodule)`
- **Default**: `[ ]` (uses i3 default 10 numbered workspaces)
- **Description**: Workspace configuration.
- **Submodule Options**:
  - `number` (int, required): Workspace number (1-10)
  - `name` (string, optional): Workspace name
  - `defaultLayout` (enum, default: `"default"`): `"default"` | `"stacking"` | `"tabbed"`
  - `output` (string, optional): Monitor assignment for multi-monitor setups
- **Example**:
```nix
[
  { number = 1; name = "Main"; defaultLayout = "tabbed"; }
  { number = 2; name = "Code"; defaultLayout = "default"; }
  { number = 3; name = "Web"; }
]
```

#### `services.i3wm.defaultWorkspace`
- **Type**: `int`
- **Default**: `1`
- **Description**: Workspace to show on i3 startup.
- **Allowed Range**: 1-10
- **Example**: `1`

### Appearance

#### `services.i3wm.fonts`
- **Type**: `listOf string`
- **Default**: `[ "monospace 8" ]`
- **Description**: Fonts for window titles and status bar. Format: "Font Name Size"
- **Example**: `[ "DejaVu Sans Mono 10" "FontAwesome 10" ]`

#### `services.i3wm.colors`
- **Type**: `submodule` (ColorScheme)
- **Default**: i3 default colors
- **Description**: Color scheme for window decorations.
- **Submodule Structure**:
```nix
{
  focused = {
    border = "#4c7899";
    background = "#285577";
    text = "#ffffff";
    indicator = "#2e9ef4";
    childBorder = "#285577";
  };
  focusedInactive = { /* ... */ };
  unfocused = { /* ... */ };
  urgent = { /* ... */ };
  placeholder = { /* ... */ };
  background = "#ffffff";
}
```

#### `services.i3wm.gaps`
- **Type**: `submodule` (GapsConfig)
- **Default**: `{ inner = 0; outer = 0; smartGaps = false; smartBorders = false; }`
- **Description**: Window gap configuration (requires i3-gaps).
- **Submodule Options**:
  - `inner` (int): Gap between adjacent windows in pixels
  - `outer` (int): Gap between windows and screen edge in pixels
  - `smartGaps` (bool): Only show gaps when multiple windows visible
  - `smartBorders` (bool): Only show borders when multiple windows visible
- **Example**:
```nix
{
  inner = 5;
  outer = 5;
  smartGaps = true;
  smartBorders = true;
}
```

#### `services.i3wm.borders`
- **Type**: `submodule` (BorderConfig)
- **Default**: `{ width = 2; style = "normal"; hideEdgeBorders = "none"; }`
- **Description**: Window border configuration.
- **Submodule Options**:
  - `width` (int): Border width in pixels
  - `style` (enum): `"normal"` | `"pixel"` | `"none"`
  - `hideEdgeBorders` (enum): `"none"` | `"vertical"` | `"horizontal"` | `"both"` | `"smart"`
- **Example**:
```nix
{
  width = 2;
  style = "pixel";
  hideEdgeBorders = "smart";
}
```

### Status Bar

#### `services.i3wm.bar.enable`
- **Type**: `bool`
- **Default**: `true`
- **Description**: Whether to enable the i3 status bar.
- **Example**: `true`

#### `services.i3wm.bar.position`
- **Type**: `enum`
- **Default**: `"bottom"`
- **Allowed Values**: `"top"` | `"bottom"`
- **Description**: Position of the status bar.
- **Example**: `"bottom"`

#### `services.i3wm.bar.statusCommand`
- **Type**: `string`
- **Default**: `"${pkgs.i3status}/bin/i3status"`
- **Description**: Command to generate status bar content.
- **Example**: `"${pkgs.i3blocks}/bin/i3blocks"` or custom script

#### `services.i3wm.bar.fonts`
- **Type**: `listOf string`
- **Default**: `services.i3wm.fonts`
- **Description**: Fonts for the status bar.
- **Example**: `[ "DejaVu Sans Mono 10" ]`

#### `services.i3wm.bar.workspaceButtons`
- **Type**: `bool`
- **Default**: `true`
- **Description**: Whether to show workspace buttons on the bar.
- **Example**: `true`

#### `services.i3wm.bar.colors`
- **Type**: `submodule` (BarColorScheme)
- **Default**: i3 default bar colors
- **Description**: Color scheme for the status bar.
- **Submodule Structure**:
```nix
{
  background = "#000000";
  statusline = "#ffffff";
  separator = "#666666";
  focusedWorkspace = {
    border = "#4c7899";
    background = "#285577";
    text = "#ffffff";
  };
  # ... other workspace states
}
```

### Startup Commands

#### `services.i3wm.startup`
- **Type**: `listOf (submodule)`
- **Default**: `[ ]`
- **Description**: Commands to execute when i3 starts.
- **Submodule Options**:
  - `command` (string, required): Command to execute
  - `always` (bool, default: `false`): Run on every i3 restart (not just session start)
  - `notification` (bool, default: `true`): Show startup notification
- **Example**:
```nix
[
  { command = "${pkgs.nitrogen}/bin/nitrogen --restore"; }
  { command = "${pkgs.dunst}/bin/dunst"; always = true; }
]
```

### Additional Packages

#### `services.i3wm.extraPackages`
- **Type**: `listOf package`
- **Default**: `with pkgs; [ dmenu i3status i3lock ]`
- **Description**: Additional packages to install alongside i3.
- **Example**: `with pkgs; [ rofi i3blocks dunst nitrogen ]`

### Raw Configuration

#### `services.i3wm.extraConfig`
- **Type**: `lines`
- **Default**: `""`
- **Description**: Raw i3 configuration to append to generated config. Use for advanced features not covered by module options.
- **Example**:
```nix
''
  # Custom i3 configuration
  for_window [class="Spotify"] move to workspace 10
  bindsym $mod+p exec "rofi -show run"
''
```

## Generated Files

The module generates the following configuration files:

### `/etc/i3/config`
- **Source**: All module options combined
- **Permissions**: 0644 (world-readable)
- **Owner**: root:root
- **Purpose**: Main i3 configuration file
- **Used By**: i3 window manager on startup

### `/etc/i3status.conf`
- **Source**: Generated if `bar.statusCommand` uses i3status
- **Permissions**: 0644 (world-readable)
- **Owner**: root:root
- **Purpose**: i3status configuration
- **Used By**: i3status when launched by i3bar

## System Integration

### X11 Integration

The module automatically configures:
```nix
services.xserver = {
  enable = true;
  windowManager.i3.enable = true;
};

services.displayManager.defaultSession = "none+i3";
```

### Package Installation

The following packages are automatically installed:
- `services.i3wm.package` (default: `pkgs.i3`)
- All packages in `services.i3wm.extraPackages`

### Environment Variables

Sets the following environment variables for i3 sessions:
- `XDG_CURRENT_DESKTOP=i3`
- `XDG_SESSION_TYPE=x11`

## Validation Rules

The module performs the following validation:

### Workspace Validation
```nix
assertions = [
  {
    assertion = all (ws: ws.number >= 1 && ws.number <= 10) cfg.workspaces;
    message = "i3 workspace numbers must be between 1 and 10";
  }
  {
    assertion = (length cfg.workspaces) == (length (unique (map (ws: ws.number) cfg.workspaces)));
    message = "i3 workspace numbers must be unique";
  }
];
```

### Color Validation
```nix
# All colors must match hex format: #RRGGBB or #RRGGBBAA
assertion = all (c: match "#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?" c != null) allColors;
message = "All colors must be in hex format: #RRGGBB or #RRGGBBAA";
```

### Font Validation
```nix
# Fonts must be non-empty strings
assertion = all (f: stringLength f > 0) cfg.fonts;
message = "Font specifications cannot be empty";
```

## Usage Example

Complete example configuration in `configurations/hetzner.nix`:

```nix
{ config, pkgs, ... }:

{
  services.i3wm = {
    enable = true;
    package = pkgs.i3;
    modifier = "Mod4";

    workspaces = [
      { number = 1; name = "Main"; defaultLayout = "tabbed"; }
      { number = 2; name = "Code"; }
      { number = 3; name = "Web"; }
      { number = 4; name = "Chat"; }
    ];

    fonts = [ "DejaVu Sans Mono 10" ];

    gaps = {
      inner = 5;
      outer = 5;
      smartGaps = true;
      smartBorders = true;
    };

    borders = {
      width = 2;
      style = "pixel";
      hideEdgeBorders = "smart";
    };

    bar = {
      enable = true;
      position = "bottom";
      statusCommand = "${pkgs.i3status}/bin/i3status";
      workspaceButtons = true;
    };

    startup = [
      { command = "${pkgs.nitrogen}/bin/nitrogen --restore"; }
      { command = "${pkgs.dunst}/bin/dunst"; always = true; }
    ];

    extraPackages = with pkgs; [
      rofi          # Application launcher
      i3status      # Status bar
      i3lock        # Screen locker
      nitrogen      # Wallpaper manager
      dunst         # Notification daemon
    ];

    keybindings = let
      mod = config.services.i3wm.modifier;
    in {
      # Terminals
      "${mod}+Return" = "exec ${pkgs.alacritty}/bin/alacritty";

      # Launchers
      "${mod}+d" = "exec ${pkgs.rofi}/bin/rofi -show drun";

      # Window management
      "${mod}+Shift+q" = "kill";
      "${mod}+f" = "fullscreen toggle";

      # Layouts
      "${mod}+s" = "layout stacking";
      "${mod}+w" = "layout tabbed";
      "${mod}+e" = "layout toggle split";

      # Focus
      "${mod}+Left" = "focus left";
      "${mod}+Down" = "focus down";
      "${mod}+Up" = "focus up";
      "${mod}+Right" = "focus right";

      # Move
      "${mod}+Shift+Left" = "move left";
      "${mod}+Shift+Down" = "move down";
      "${mod}+Shift+Up" = "move up";
      "${mod}+Shift+Right" = "move right";

      # Workspaces
      "${mod}+1" = "workspace number 1";
      "${mod}+2" = "workspace number 2";
      "${mod}+3" = "workspace number 3";
      "${mod}+4" = "workspace number 4";

      # Move to workspace
      "${mod}+Shift+1" = "move container to workspace number 1";
      "${mod}+Shift+2" = "move container to workspace number 2";
      "${mod}+Shift+3" = "move container to workspace number 3";
      "${mod}+Shift+4" = "move container to workspace number 4";

      # Reload/restart
      "${mod}+Shift+c" = "reload";
      "${mod}+Shift+r" = "restart";
    };
  };
}
```

## Dependencies

### Required NixOS Options
- `services.xserver.enable = true` - X11 must be enabled
- `services.displayManager.defaultSession` - Should be set to `"none+i3"`

### Optional Dependencies
- `services.xrdp` - For remote desktop access
- `hardware.pulseaudio` - For audio support
- Desktop applications (Firefox, terminals, etc.)

## Testing

### Validate Configuration
```bash
# Check i3 config syntax (after rebuild)
nix-build '<nixpkgs/nixos>' -A config.environment.etc."i3/config".source

# Validate generated config
i3 -C -c /etc/i3/config
```

### Test in VM
```bash
nixos-rebuild build-vm --flake .#hetzner-i3
./result/bin/run-nixos-vm
```

## Migration from Other Window Managers

### From KDE Plasma
1. Add i3wm module alongside KDE
2. Configure XRDP to offer session choice
3. Test i3 configuration
4. Remove KDE module once validated

### From Manual i3 Configuration
1. Copy keybindings from `~/.config/i3/config` to `services.i3wm.keybindings`
2. Copy colors to `services.i3wm.colors`
3. Convert exec commands to `services.i3wm.startup`
4. Rebuild and validate

## See Also

- [data-model.md](../data-model.md) - Complete data model documentation
- [quickstart.md](../quickstart.md) - Quick start guide for users
- [i3 User Guide](https://i3wm.org/docs/userguide.html) - Official i3 documentation

# NixOS Module Options Contract: MangoWC Desktop Environment

**Date**: 2025-10-16
**Branch**: `003-create-a-new`

This document defines the public API contract for the MangoWC NixOS modules. These options are guaranteed to remain stable across updates.

## Module: `services.mangowc`

Main configuration module for MangoWC Wayland compositor.

### `services.mangowc.enable`

**Type**: `boolean`
**Default**: `false`
**Description**: Enable MangoWC Wayland compositor service

**Example**:
```nix
services.mangowc.enable = true;
```

### `services.mangowc.package`

**Type**: `package`
**Default**: `pkgs.mangowc`
**Description**: MangoWC package to use. Can be overridden to use custom builds.

**Example**:
```nix
services.mangowc.package = inputs.mangowc.packages.${pkgs.system}.mango;
```

### `services.mangowc.user`

**Type**: `string`
**Default**: `"vpittamp"`
**Description**: System user to run MangoWC compositor

**Constraints**:
- User must exist in `users.users`
- Cannot be `"root"` (assertion enforced)

**Example**:
```nix
services.mangowc.user = "myuser";
```

### `services.mangowc.resolution`

**Type**: `string`
**Default**: `"1920x1080"`
**Description**: Virtual display resolution for headless mode

**Format**: `"{width}x{height}"`

**Example**:
```nix
services.mangowc.resolution = "2560x1440";
```

### `services.mangowc.extraEnvironment`

**Type**: `attribute set of strings`
**Default**: `{}`
**Description**: Additional environment variables for MangoWC compositor

**Example**:
```nix
services.mangowc.extraEnvironment = {
  WLR_NO_HARDWARE_CURSORS = "1";
  WLR_RENDERER = "pixman";  # Force software rendering
};
```

### `services.mangowc.config`

**Type**: `multi-line string`
**Default**: `""` (uses built-in defaults)
**Description**: Complete MangoWC configuration (config.conf content). If provided, replaces default configuration entirely.

**Example**:
```nix
services.mangowc.config = ''
  # Custom keybindings
  bind=SUPER,Return,spawn,alacritty
  bind=SUPER,d,spawn,wofi --show drun

  # Custom colors
  rootcolor=0x000000ff
  focuscolor=0xff0000ff
'';
```

### `services.mangowc.autostart`

**Type**: `multi-line string`
**Default**: `""` (no autostart commands)
**Description**: Shell commands to execute when MangoWC session starts

**Example**:
```nix
services.mangowc.autostart = ''
  swaybg -i ~/.wallpaper.png &
  waybar &
  mako &
'';
```

### `services.mangowc.workspaces`

**Type**: `list of workspace definition submodules`
**Default**: 9 workspaces with IDs 1-9
**Description**: Workspace/tag configuration

#### Workspace Submodule Options:

- **`id`**: `integer (1-9)` - Workspace identifier
- **`layout`**: `enum` - Default layout: `"tile"`, `"scroller"`, `"monocle"`, `"grid"`, `"deck"`, `"center_tile"`, `"vertical_tile"`, `"vertical_grid"`, `"vertical_scroller"`
- **`name`**: `null or string` - Optional human-readable name

**Example**:
```nix
services.mangowc.workspaces = [
  { id = 1; layout = "tile"; name = "Main"; }
  { id = 2; layout = "scroller"; name = "Code"; }
  { id = 3; layout = "monocle"; name = "Focus"; }
  { id = 4; layout = "tile"; }
  { id = 5; layout = "tile"; }
  { id = 6; layout = "tile"; }
  { id = 7; layout = "tile"; }
  { id = 8; layout = "tile"; }
  { id = 9; layout = "tile"; }
];
```

### `services.mangowc.keybindings`

**Type**: `attribute set of strings`
**Default**: `{}` (uses defaults, see data-model.md)
**Description**: Custom keybindings to add or override. Keys are keybind specifications, values are actions.

**Format**: `{ "{MOD},{KEY}" = "{ACTION},{ARGS}"; }`

**Supported Modifiers**: `SUPER`, `ALT`, `CTRL`, `SHIFT`, `NONE` (can combine with `+`)

**Example**:
```nix
services.mangowc.keybindings = {
  "SUPER,Return" = "spawn,alacritty";
  "SUPER,d" = "spawn,wofi --show drun";
  "SUPER+SHIFT,q" = "killclient,";
  "SUPER,1" = "view,1,0";
};
```

### `services.mangowc.appearance`

**Type**: `attribute set (submodule)`
**Default**: See individual options below
**Description**: Visual appearance settings

#### `services.mangowc.appearance.borderWidth`

**Type**: `unsigned integer`
**Default**: `4`
**Description**: Window border width in pixels

**Example**:
```nix
services.mangowc.appearance.borderWidth = 2;
```

#### `services.mangowc.appearance.borderRadius`

**Type**: `unsigned integer`
**Default**: `6`
**Description**: Window corner radius in pixels

**Example**:
```nix
services.mangowc.appearance.borderRadius = 10;
```

#### `services.mangowc.appearance.rootColor`

**Type**: `string (hex color)`
**Default**: `"0x201b14ff"`
**Description**: Root/background color in RGBA hex format

**Format**: `"0xRRGGBBAA"`

**Example**:
```nix
services.mangowc.appearance.rootColor = "0x1e1e1eff";  # Dark gray
```

#### `services.mangowc.appearance.focusColor`

**Type**: `string (hex color)`
**Default**: `"0xc9b890ff"`
**Description**: Focused window border color in RGBA hex format

**Example**:
```nix
services.mangowc.appearance.focusColor = "0x00ff00ff";  # Green
```

#### `services.mangowc.appearance.unfocusedColor`

**Type**: `string (hex color)`
**Default**: `"0x444444ff"`
**Description**: Unfocused window border color in RGBA hex format

**Example**:
```nix
services.mangowc.appearance.unfocusedColor = "0x333333ff";
```

---

## Module: `services.wayvnc`

VNC remote desktop server for Wayland compositors (requires MangoWC).

### `services.wayvnc.enable`

**Type**: `boolean`
**Default**: `false`
**Description**: Enable WayVNC remote desktop server

**Requires**: `services.mangowc.enable = true`

**Example**:
```nix
services.wayvnc.enable = true;
```

### `services.wayvnc.package`

**Type**: `package`
**Default**: `pkgs.wayvnc`
**Description**: WayVNC package to use

**Example**:
```nix
services.wayvnc.package = pkgs.wayvnc.overrideAttrs (old: {
  # Custom build configuration
});
```

### `services.wayvnc.user`

**Type**: `string`
**Default**: `config.services.mangowc.user` (inherits from MangoWC)
**Description**: User to run wayvnc (must match compositor user)

**Example**:
```nix
services.wayvnc.user = "myuser";
```

### `services.wayvnc.address`

**Type**: `string (IP address)`
**Default**: `"0.0.0.0"` (listen on all interfaces)
**Description**: IP address to bind VNC server

**Example**:
```nix
services.wayvnc.address = "127.0.0.1";  # Localhost only
```

### `services.wayvnc.port`

**Type**: `port (16-bit unsigned integer)`
**Default**: `5900`
**Description**: VNC port to listen on

**Example**:
```nix
services.wayvnc.port = 5901;  # Alternate VNC port
```

### `services.wayvnc.enablePAM`

**Type**: `boolean`
**Default**: `true`
**Description**: Enable PAM authentication (integrates with system authentication, including 1Password)

**Example**:
```nix
services.wayvnc.enablePAM = true;
```

### `services.wayvnc.enableAuth`

**Type**: `boolean`
**Default**: `true`
**Description**: Enable authentication requirement

**Note**: If `false`, VNC server allows unauthenticated connections (insecure)

**Example**:
```nix
services.wayvnc.enableAuth = true;
```

### `services.wayvnc.maxFPS`

**Type**: `positive integer`
**Default**: `120`
**Description**: Maximum frame rate for screen capture. Note: Effective FPS is typically half of maxFPS setting.

**Example**:
```nix
services.wayvnc.maxFPS = 60;  # Actual ~30 FPS
```

### `services.wayvnc.enableGPU`

**Type**: `boolean`
**Default**: `true`
**Description**: Enable GPU-accelerated H.264 encoding if available

**Note**: Falls back to CPU encoding if GPU unavailable (common in QEMU VMs)

**Example**:
```nix
services.wayvnc.enableGPU = false;  # Force CPU encoding
```

### `services.wayvnc.extraConfig`

**Type**: `multi-line string`
**Default**: `""`
**Description**: Additional wayvnc configuration (appended to generated config)

**Example**:
```nix
services.wayvnc.extraConfig = ''
  # Enable TLS encryption
  certificate_file=/etc/wayvnc/cert.pem
  private_key_file=/etc/wayvnc/key.pem
'';
```

---

## Module: `services.pipewire.networkAudio`

Network audio extension for PipeWire (remote desktop audio redirection).

### `services.pipewire.networkAudio.enable`

**Type**: `boolean`
**Default**: `false`
**Description**: Enable PipeWire network audio for remote desktop

**Requires**: `services.pipewire.enable = true`

**Example**:
```nix
services.pipewire.networkAudio.enable = true;
```

### `services.pipewire.networkAudio.port`

**Type**: `port (16-bit unsigned integer)`
**Default**: `4713`
**Description**: PulseAudio protocol port for network audio

**Example**:
```nix
services.pipewire.networkAudio.port = 4713;
```

### `services.pipewire.networkAudio.address`

**Type**: `string (IP address)`
**Default**: `"0.0.0.0"` (listen on all interfaces)
**Description**: IP address to bind audio server

**Example**:
```nix
services.pipewire.networkAudio.address = "192.168.1.100";
```

---

## Module Interactions

### Dependency Graph

```
services.mangowc (compositor)
    ↓ required by
services.wayvnc (remote desktop)

services.pipewire (audio system)
    ↓ extends
services.pipewire.networkAudio (network audio)
```

### Typical Configuration

```nix
{ config, pkgs, ... }:

{
  # Enable MangoWC compositor
  services.mangowc = {
    enable = true;
    user = "vpittamp";
    resolution = "1920x1080";

    workspaces = [
      { id = 1; layout = "tile"; }
      { id = 2; layout = "scroller"; }
      { id = 3; layout = "monocle"; }
    ];

    keybindings = {
      "SUPER,Return" = "spawn,foot";
      "SUPER,d" = "spawn,rofi -show drun";
    };

    appearance = {
      borderWidth = 4;
      focusColor = "0xc9b890ff";
    };
  };

  # Enable remote desktop
  services.wayvnc = {
    enable = true;
    port = 5900;
    enablePAM = true;
    maxFPS = 120;
  };

  # Enable network audio
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  services.pipewire.networkAudio = {
    enable = true;
    port = 4713;
  };

  # Open firewall ports
  networking.firewall.allowedTCPPorts = [ 5900 4713 ];
}
```

---

## Assertions and Validation

The modules enforce the following constraints:

1. **wayvnc requires MangoWC**:
   ```
   assertion: services.wayvnc.enable -> services.mangowc.enable
   ```

2. **Compositor user cannot be root**:
   ```
   assertion: services.mangowc.user != "root"
   ```

3. **Workspace IDs must be 1-9**:
   ```
   assertion: all (ws: ws.id >= 1 && ws.id <= 9) services.mangowc.workspaces
   ```

4. **wayvnc user must match compositor user**:
   ```
   assertion: services.wayvnc.user == services.mangowc.user
   ```

5. **Network audio requires PipeWire**:
   ```
   assertion: services.pipewire.networkAudio.enable -> services.pipewire.enable
   ```

---

## Backward Compatibility

**Version**: 1.0.0 (initial release)

Future versions will maintain backward compatibility for all options marked above. Deprecated options will be marked with warnings before removal in major version bumps.

**Breaking changes**: Any breaking change to this contract requires a major version increment and migration guide.

---

## Testing Contract

All modules must pass:

1. **Build test**: `nixos-rebuild dry-build --flake .#hetzner-mangowc`
2. **Activation test**: `nixos-rebuild test --flake .#hetzner-mangowc`
3. **Connection test**: Successful VNC connection with authentication
4. **Audio test**: Audio playback redirects to client
5. **Workspace test**: Switch between all 9 workspaces without errors

**Test command**:
```bash
sudo nixos-rebuild dry-build --flake .#hetzner-mangowc --show-trace
```

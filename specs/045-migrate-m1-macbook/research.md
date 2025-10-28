# Research: Sway Migration for M1 MacBook Pro

**Date**: 2025-10-27
**Feature**: 045-migrate-m1-macbook
**Purpose**: Technical research for migrating M1 from KDE Plasma to Sway with i3pm daemon integration

## Research Questions

1. Sway i3 IPC protocol compatibility with i3ipc-python library
2. Wayland display scaling best practices for Retina + external monitors
3. Replacing X11 xprop calls with Sway IPC queries
4. wayvnc configuration and comparison with XRDP
5. Walker/Elephant native Wayland mode configuration
6. Multi-monitor workspace distribution compatibility

---

## 1. Sway i3 IPC Compatibility

### Decision
**Sway provides 100% i3 IPC protocol compatibility**. The i3ipc-python library supports both i3 and Sway natively.

### Rationale
- i3ipc-python official description: "An improved Python library to control i3wm and sway"
- Sway uses same magic string "i3-ipc" for protocol identification
- Sway sets both `SWAYSOCK` and `I3SOCK` environment variables for compatibility
- All IPC message types (GET_TREE, GET_WORKSPACES, GET_OUTPUTS, COMMAND, SUBSCRIBE) work identically

### Known Differences
Only property naming differs:
- **i3**: Uses `window_properties` dict with X11 WM_CLASS
- **Sway**: Uses `app_id` field for Wayland apps, `window_properties` for XWayland apps

### Code Changes
Minimal - check `app_id` first, fall back to `window_properties`:
```python
window_class = container.app_id or container.window_properties.get('class')
```

### Alternatives Considered
None - Sway's i3 compatibility is a design goal, alternatives would require complete rewrite.

---

## 2. Wayland Display Scaling for Retina M1

### Decision
Use **per-output integer scaling**: 2.0 for built-in Retina display, 1.0 for external monitors.

### Rationale
- Sway supports both integer and fractional scaling per output
- Integer scaling (2.0) avoids text blur on XWayland apps
- Fractional scaling (1.5, 1.75) causes pixel-stretching artifacts on non-Wayland apps
- M1 MacBook Pro 13" native resolution: 2560x1600 at 2x = 1280x800 logical

### Configuration
```nix
wayland.windowManager.sway.config.output = {
  "eDP-1" = {  # Built-in Retina display
    scale = "2.0";
    resolution = "2560x1600@60Hz";
  };
  "HDMI-A-1" = {  # External monitor
    scale = "1.0";
    resolution = "1920x1080@60Hz";
  };
};
```

### Alternatives Considered
- **Fractional scaling (1.5, 1.75)**: Rejected due to XWayland blur
- **Client-side scaling only**: Rejected as not all apps support it
- **BetterDisplay**: macOS-only, not applicable to NixOS

---

## 3. xprop Replacement with Sway IPC

### Decision
Replace all `subprocess.run(["xprop", ...])` calls with direct i3ipc container property access.

### Rationale
- Sway includes PID, app_id, and window properties in IPC tree data (no external commands needed)
- Eliminates subprocess overhead and timeout issues
- Works identically on both i3 and Sway (protocol-agnostic)
- More reliable than X11 xprop (which can hang or fail)

### Implementation
**Current (X11 xprop)**:
```python
result = subprocess.run(
    ["xprop", "-id", str(window_id), "_NET_WM_PID"],
    capture_output=True,
    text=True,
    timeout=2.0
)
pid = parse_xprop_output(result.stdout)
```

**Replacement (Sway IPC)**:
```python
# PID is directly available in i3ipc container
pid = container.ipc_data.get('pid')

# Window class: check app_id first, then window_properties
def get_window_class(container):
    if hasattr(container, 'app_id') and container.app_id:
        return container.app_id  # Wayland native app
    return container.window_properties.get('class', 'unknown')  # XWayland
```

### Files Requiring Changes
- `handlers.py` (1 xprop call for PID)
- `window_filter.py` (xprop logic for window properties)
- `window_filtering.py` (xprop logic for PID/class)

Total: ~50-80 lines across 3 files.

### Alternatives Considered
- **swaymsg JSON parsing**: Rejected as redundant (already have i3ipc connection)
- **Keep xprop via XWayland**: Rejected as adds X11 dependency and subprocess overhead

---

## 4. wayvnc Configuration for Remote Access

### Decision
**Implement wayvnc with PAM authentication and TLS encryption** as VNC replacement for XRDP.

### Rationale
- wayvnc is the standard VNC server for wlroots compositors (Sway)
- Available in nixpkgs with systemd service support
- User explicitly approved VNC as acceptable (per spec requirements)
- Provides secure remote access with authentication

### Configuration
```nix
systemd.user.services.wayvnc = {
  description = "VNC server for Sway";
  after = [ "graphical-session.target" ];
  wantedBy = [ "graphical-session.target" ];

  serviceConfig = {
    Type = "notify";
    ExecStart = "${pkgs.wayvnc}/bin/wayvnc 0.0.0.0 5900 --config=/home/user/.config/wayvnc/config";
    Restart = "on-failure";
  };
};
```

wayvnc config (`~/.config/wayvnc/config`):
```toml
enable_auth=true
enable_pam=true
port=5900
# Optional TLS for encryption
certificate_file=/home/user/.config/wayvnc/tls_cert.pem
private_key_file=/home/user/.config/wayvnc/tls_key.pem
```

### Comparison with XRDP

| Feature | XRDP (X11) | wayvnc (Wayland) |
|---------|------------|------------------|
| Protocol | RDP | VNC (RFC 6143) |
| Audio | ✅ Yes | ❌ No (VNC limitation) |
| Clipboard | ✅ Bidirectional | ✅ Bidirectional (wl-clipboard) |
| Multi-session | ✅ Separate X sessions | ❌ Shares active Wayland session |
| File Transfer | ✅ Drive mapping | ❌ No native support |
| Encryption | ✅ TLS 1.2+ | ⚠️ Optional (VeNCrypt) |
| Windows Client | ✅ Native RDP | ⚠️ Requires VNC client |

### Limitations
- **Single session**: wayvnc shares the active Wayland session (can't create separate sessions per user like XRDP)
- **No audio**: VNC protocol doesn't support audio forwarding
- **No file transfer**: Requires separate mechanism (scp/rsync)
- **Client requirement**: Windows/macOS users need VNC client (TigerVNC, RealVNC)

### Alternatives Considered
- **waypipe**: SSH-based Wayland forwarding, but requires SSH access (not pure remote desktop)
- **XRDP via XWayland**: Possible but not recommended (adds X11 layer, defeats Wayland benefits)
- **weston-rdp**: Experimental RDP for Wayland, unstable

---

## 5. Walker/Elephant Native Wayland Mode

### Decision
**Remove X11 compatibility mode** (`as_window = true`, `GDK_BACKEND=x11`) and **enable clipboard provider** for native Wayland operation.

### Rationale
- Walker is Wayland-native by default (GTK4-based)
- Current X11 mode (`as_window = true`) was workaround for XRDP compatibility
- Wayland mode enables clipboard provider (was disabled due to X11 limitations)
- Native Wayland provides better layer shell integration and HiDPI scaling

### Configuration Changes

**walker.nix (~/.config/walker/config.toml)**:
```toml
# Remove X11 compatibility mode
# as_window = true  # ❌ DELETE THIS LINE

# Enable clipboard provider (now works with wl-clipboard)
[modules]
applications = true
calc = true
clipboard = true  # ✅ CHANGED from false
files = true
menus = true
runner = true
symbols = true
websearch = true
```

**Elephant Service (walker.nix systemd service)**:
```nix
systemd.user.services.elephant = {
  Service = {
    ExecStart = "${inputs.elephant.packages.${pkgs.system}.default}/bin/elephant";

    Environment = [
      "PATH=${config.home.homeDirectory}/.local/bin:..."
      "XDG_DATA_DIRS=${i3pmAppsDir}"
      "XDG_RUNTIME_DIR=%t"
      "WAYLAND_DISPLAY=wayland-1"  # ✅ ADD for Wayland
    ];

    # Remove DISPLAY PassEnvironment (X11-only)
    # PassEnvironment = [ "DISPLAY" ];  # ❌ DELETE
  };
};
```

**Keybinding (sway.nix)**:
```bash
# Remove GDK_BACKEND override
bindsym $mod+d exec walker  # ✅ Native Wayland (no env override)
```

**Dependencies**:
```nix
home.packages = with pkgs; [
  wl-clipboard  # Required for clipboard provider
];
```

### Benefits
- ✅ Native Wayland layer shell (appears above all windows)
- ✅ Clipboard history works (wl-clipboard integration)
- ✅ Proper HiDPI scaling without blur
- ✅ Better keyboard focus handling
- ✅ No compatibility layer overhead

### Alternatives Considered
- **Keep X11 mode**: Rejected as defeats purpose of Wayland migration
- **Mixed mode with feature flags**: Rejected per Forward-Only Development principle (Constitution XII)

---

## 6. Multi-Monitor Workspace Distribution

### Decision
**No code changes required** - current i3pm monitor detection works identically with Sway via i3 IPC protocol.

### Rationale
- Sway supports identical output events (`output::added`, `output::removed`, `output::changed`)
- Workspace assignment commands use same syntax (`swaymsg "workspace 1 output eDP-1"`)
- i3ipc `get_outputs()` works identically on both window managers
- Current i3pm implementation (Feature 033) uses i3 IPC, which is protocol-compatible with Sway

### Compatibility Validation
```python
# Current code works unchanged
outputs = await conn.get_outputs()
for output in outputs:
    print(f"{output.name}: {output.active}")
    # Sway: eDP-1, HDMI-A-1
    # i3:   eDP-1, DP-1
```

Workspace assignment (identical syntax):
```python
await conn.command("workspace 1 output eDP-1")
```

### Only Action Required
Update workspace-monitor-mapping.json with Sway output names after testing:
```bash
# Get Sway output names
swaymsg -t get_outputs | jq '.[] | {name, active}'
```

Expected output names on M1:
- `eDP-1`: Built-in Retina display
- `HDMI-A-1` or `DP-1`: External monitor via USB-C

### Optional Enhancement
**kanshi** for automatic profile switching:
```nix
services.kanshi = {
  enable = true;
  profiles = {
    docked = {
      outputs = [
        { criteria = "eDP-1"; status = "disable"; }
        { criteria = "HDMI-A-1"; mode = "1920x1080@60Hz"; }
      ];
    };
    mobile = {
      outputs = [
        { criteria = "eDP-1"; scale = 2.0; }
      ];
    };
  };
};
```

### Alternatives Considered
- **Manual xrandr-style config**: Not needed, Sway IPC provides programmatic access
- **Rewrite monitor detection**: Not needed due to protocol compatibility

---

## Summary of Implementation Decisions

### Confirmed Compatibility (No Changes)
1. ✅ **i3 IPC Protocol**: Sway 100% compatible via i3ipc-python
2. ✅ **Multi-Monitor Detection**: Current i3pm code works unchanged
3. ✅ **Python Daemon Tests**: Protocol-agnostic, no test changes needed

### Required Changes
1. **xprop Replacement**: 3 files, ~50-80 lines
   - Use `container.ipc_data['pid']` instead of subprocess xprop
   - Check `app_id` first, then `window_properties.class`

2. **Walker Wayland Mode**: 1 file, ~20 lines
   - Remove `as_window = true`
   - Enable `clipboard = true`
   - Update Elephant service environment (WAYLAND_DISPLAY)
   - Remove GDK_BACKEND=x11 from keybinding

3. **Display Scaling**: New Sway configuration
   - Per-output scaling (2.0 for Retina, 1.0 for external)
   - Resolution configuration

4. **wayvnc Service**: New module
   - Systemd user service
   - PAM authentication
   - Optional TLS encryption

### Trade-offs Accepted
- **VNC instead of RDP**: No audio/file transfer, single-session (approved by user)
- **No fractional scaling**: Avoids XWayland blur (integer scaling only)
- **No kanshi auto-switching**: Manual monitor configuration sufficient (can add later)

---

## Implementation Priority

**Phase 1 (Core Functionality)**:
1. Create Sway configuration modules (system + home-manager)
2. Replace xprop calls in Python daemon
3. Configure display scaling for Retina + external monitors
4. Update Walker for native Wayland

**Phase 2 (Remote Access)**:
5. Add wayvnc service module
6. Test VNC connectivity

**Phase 3 (Validation)**:
7. Test multi-monitor workspace distribution
8. Validate i3pm daemon functionality
9. Run pytest test suite

**Phase 4 (Documentation)**:
10. Update CLAUDE.md with M1 Sway build instructions
11. Create quickstart guide for Sway-specific commands

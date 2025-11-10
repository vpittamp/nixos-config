# Quickstart: Declarative Workspace-to-Monitor Assignment with Floating Window Configuration

**Feature**: 001-declarative-workspace-monitor
**Date**: 2025-11-10

## Overview

This feature allows you to declare which monitor (primary/secondary/tertiary) each application should appear on by adding a `preferred_monitor_role` field to your application and PWA definitions. Additionally, you can configure applications to float by default with size presets. The system automatically handles fallback logic when monitors disconnect.

---

## Quick Start (5 minutes)

### 1. Add Monitor Role to Application

Edit `/etc/nixos/home-modules/desktop/app-registry-data.nix`:

```nix
(mkApp {
  name = "code";
  display_name = "VS Code";
  command = "code";
  parameters = "--new-window $PROJECT_DIR";
  scope = "scoped";
  expected_class = "Code";
  preferred_workspace = 2;
  preferred_monitor_role = "primary";  # NEW: Assign to primary monitor
  # ... other fields
})
```

### 2. Add Monitor Role to PWA

Edit `/etc/nixos/shared/pwa-sites.nix`:

```nix
{
  name = "YouTube";
  url = "https://www.youtube.com";
  ulid = "01K666N2V6BQMDSBMX3AY74TY7";
  preferred_workspace = 50;
  preferred_monitor_role = "secondary";  # NEW: Assign to secondary monitor
  app_scope = "scoped";
  # ... other fields
}
```

### 3. Configure Floating Window (Optional)

```nix
(mkApp {
  name = "btop";
  display_name = "btop";
  command = "ghostty";
  parameters = "-e btop";
  scope = "global";
  preferred_workspace = 7;
  floating = true;              # NEW: Enable floating mode
  floating_size = "medium";     # NEW: 1200×800 centered window
  # ... other fields
})
```

### 4. Rebuild and Apply

```bash
# Test configuration
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Apply changes
sudo nixos-rebuild switch --flake .#hetzner-sway

# Restart i3pm daemon to load new config
systemctl --user restart i3-project-event-listener
```

---

## Monitor Roles Explained

### Three Monitor Roles

| Role | Purpose | Default Workspaces | Fallback |
|------|---------|-------------------|----------|
| `primary` | Main monitor | 1-2 | (always available) |
| `secondary` | Second monitor | 3-5 | → primary |
| `tertiary` | Third monitor | 6+ | → secondary → primary |

### How Fallback Works

**3 monitors connected**:
- Primary: HEADLESS-1 (workspaces 1-2)
- Secondary: HEADLESS-2 (workspaces 3-5)
- Tertiary: HEADLESS-3 (workspaces 6+)

**2 monitors connected** (tertiary disconnected):
- Primary: HEADLESS-1 (workspaces 1-2)
- Secondary: HEADLESS-2 (workspaces 3-5, 6+)  ← tertiary falls back to secondary

**1 monitor connected**:
- Primary: HEADLESS-1 (all workspaces)  ← everything falls back to primary

---

## Floating Window Configuration

### Size Presets

| Preset | Dimensions | Use Case |
|--------|------------|----------|
| `scratchpad` | 1200×600 | Quick terminals, calculators |
| `small` | 800×500 | System monitors, lightweight tools |
| `medium` | 1200×800 | Medium-sized apps, settings |
| `large` | 1600×1000 | Full-featured apps |
| (omitted) | Natural size | Application decides |

### Floating Window Behavior

**Scoped vs Global**:
- **Scoped** (`scope = "scoped"`): Hides when you switch projects
- **Global** (`scope = "global"`): Stays visible across all projects

**Example - Scoped Floating Terminal**:
```nix
(mkApp {
  name = "floating-terminal";
  command = "ghostty";
  scope = "scoped";           # Hides on project switch
  preferred_workspace = 1;
  floating = true;
  floating_size = "scratchpad";  # 1200×600
})
```

**Example - Global System Monitor**:
```nix
(mkApp {
  name = "btop";
  command = "ghostty";
  parameters = "-e btop";
  scope = "global";           # Always visible
  preferred_workspace = 7;
  floating = true;
  floating_size = "medium";   # 1200×800
})
```

---

## Configuration Reference

### Application Registry Fields (app-registry-data.nix)

```nix
(mkApp {
  name = "app-identifier";                      # Required: unique name
  display_name = "App Display Name";            # Required: shown in launcher
  command = "executable";                       # Required: command to run
  parameters = "--flag $PROJECT_DIR";           # Optional: command args
  scope = "scoped";                             # Required: scoped | global
  expected_class = "WindowClass";               # Required: for validation
  preferred_workspace = 5;                      # Required: workspace 1-70
  preferred_monitor_role = "secondary";         # NEW: primary | secondary | tertiary
  floating = false;                             # NEW: enable floating mode
  floating_size = "medium";                     # NEW: scratchpad | small | medium | large
  # ... other fields (icon, nix_package, etc.)
})
```

### PWA Sites Fields (pwa-sites.nix)

```nix
{
  name = "PWA Name";                            # Required: display name
  url = "https://example.com";                  # Required: PWA URL
  ulid = "01JCYF8Z2M7R4N6QW9XKPHVTB5";         # Required: unique ID
  preferred_workspace = 52;                     # Required: workspace 50-70
  preferred_monitor_role = "tertiary";          # NEW: primary | secondary | tertiary
  app_scope = "scoped";                         # Required: scoped | global
  # ... other fields (domain, icon, etc.)
}
```

---

## CLI Commands

### Monitor Role Status

```bash
# View current monitor role assignments
i3pm monitors status

# Example output:
# Monitor Roles:
#   primary   → HEADLESS-1 (1920×1080)
#   secondary → HEADLESS-2 (1920×1080)
#   tertiary  → HEADLESS-3 (1920×1080)
#
# Workspace Assignments:
#   WS 1  → HEADLESS-1 (primary)   [terminal]
#   WS 2  → HEADLESS-1 (primary)   [code]
#   WS 3  → HEADLESS-2 (secondary) [firefox]
#   WS 50 → HEADLESS-2 (secondary) [youtube-pwa]
```

### Manual Reassignment

```bash
# Manually trigger workspace reassignment (useful after monitor changes)
i3pm monitors reassign

# View monitor configuration
i3pm monitors config

# Example output:
# Active Outputs: 3
#   HEADLESS-1: 1920×1080 (scale: 1.0)
#   HEADLESS-2: 1920×1080 (scale: 1.0)
#   HEADLESS-3: 1920×1080 (scale: 1.0)
#
# Role Assignments:
#   primary   → HEADLESS-1 (no fallback)
#   secondary → HEADLESS-2 (no fallback)
#   tertiary  → HEADLESS-3 (no fallback)
```

### Floating Window Management

```bash
# List all floating windows
swaymsg -t get_tree | jq '.nodes[].nodes[] | select(.type=="floating_con")'

# Toggle floating for current window
swaymsg floating toggle

# Resize floating window to preset
swaymsg resize set 1200 800  # medium preset
```

---

## Troubleshooting

### Workspace Not on Expected Monitor

**Problem**: VS Code appears on wrong monitor despite `preferred_monitor_role = "primary"`

**Solution**:
1. Check current assignments: `i3pm monitors status`
2. Verify daemon is running: `systemctl --user status i3-project-event-listener`
3. Check daemon logs: `journalctl --user -u i3-project-event-listener -f`
4. Manually reassign: `i3pm monitors reassign`

**Common causes**:
- Daemon not restarted after config change
- Monitor disconnected (fallback applied)
- Conflicting workspace assignments (multiple apps on same workspace with different roles)

### Floating Window Not Floating

**Problem**: Application doesn't float despite `floating = true`

**Solution**:
1. Check Sway window rules: `cat ~/.config/sway/window-rules.json | jq '.rules[] | select(.floating==true)'`
2. Verify app_id matches: `swaymsg -t get_tree | jq '.. | select(.app_id?) | .app_id'`
3. Reload Sway config: `swaymsg reload`

**Common causes**:
- `expected_class` mismatch (window class doesn't match config)
- Sway config not regenerated after Nix rebuild
- Window rules JSON syntax error

### Monitor Fallback Not Working

**Problem**: Workspaces don't reassign when monitor disconnects

**Solution**:
1. Check output events: `i3pm daemon events --type=output`
2. Verify monitor detection: `swaymsg -t get_outputs`
3. Check fallback logic: `i3pm monitors config`

**Common causes**:
- Daemon not subscribed to output events
- State file corrupted: delete `~/.config/sway/monitor-state.json` and reassign
- Multiple rapid connect/disconnect events (debouncing active)

---

## Hot-Reload Workflow

Changes to application monitor roles require a Nix rebuild, but the daemon will detect and apply changes automatically:

```bash
# 1. Edit app-registry-data.nix or pwa-sites.nix
vim /etc/nixos/home-modules/desktop/app-registry-data.nix

# 2. Rebuild (generates new workspace-assignments.json)
sudo nixos-rebuild switch --flake .#hetzner-sway

# 3. Daemon auto-detects change (500ms debounce)
# Watch logs to confirm:
journalctl --user -u i3-project-event-listener -f

# 4. Verify new assignments
i3pm monitors status
```

**No manual intervention required** - the system auto-applies changes within ~1 second of rebuild completion.

---

## Advanced Usage

### Custom Output Preferences

If you want specific physical outputs for roles (e.g., HDMI-A-1 always primary):

Edit daemon config (future enhancement):
```json
{
  "output_preferences": {
    "primary": ["HDMI-A-1", "eDP-1"],
    "secondary": ["DP-1"],
    "tertiary": ["HDMI-A-2"]
  }
}
```

**Note**: Not implemented in initial version. Currently uses connection order.

### Manual Workspace-to-Output Assignment

Override automatic assignment for specific workspace:

```bash
# Manually assign workspace 5 to HEADLESS-3
swaymsg 'workspace 5 output HEADLESS-3'

# Assignment persists until next automatic reassignment
```

**Note**: Manual assignments are temporary and will be overridden on next monitor change event.

---

## Integration with Existing Features

### Feature 049: Automatic Workspace Distribution

- ✅ **Replaced**: Hardcoded distribution rules removed
- ✅ **Extended**: Now reads from app registry instead of Python constants
- ✅ **Preserved**: Same performance (<1s reassignment on monitor changes)

### Feature 047: Dynamic Config Management

- ✅ **Integrated**: Uses same hot-reload mechanism
- ✅ **Validated**: JSON schema validation before applying
- ✅ **Version Controlled**: Auto-commits to Git on successful changes

### Feature 062: Scratchpad Terminal

- ✅ **Compatible**: Scratchpad terminal uses same floating window system
- ✅ **Size Preset**: `scratchpad` preset based on Feature 062's 1200×600 dimensions

### Project Filtering

- ✅ **Preserved**: Floating windows respect `scope` field
- ✅ **Scoped floating**: Hides on project switch (like tiling windows)
- ✅ **Global floating**: Remains visible across projects

---

## Next Steps

1. **Configure your applications**: Add `preferred_monitor_role` to app definitions
2. **Set floating preferences**: Add `floating` and `floating_size` for floating apps
3. **Test multi-monitor**: Connect/disconnect monitors to verify fallback behavior
4. **Check daemon logs**: Monitor automatic reassignments in real-time
5. **Customize workflows**: Adjust monitor roles based on your workspace layout

---

## Related Documentation

- **Spec**: [spec.md](spec.md) - Feature requirements and user stories
- **Plan**: [plan.md](plan.md) - Implementation plan and architecture
- **Data Model**: [data-model.md](data-model.md) - Data structures and validation
- **Research**: [research.md](research.md) - Technology decisions and best practices
- **Feature 049**: `/etc/nixos/specs/049-intelligent-automatic-workspace/quickstart.md`
- **Feature 047**: `/etc/nixos/specs/047-create-a-new/quickstart.md`
- **Feature 062**: `/etc/nixos/specs/062-project-scratchpad-terminal/quickstart.md`

---

**Status**: Documentation complete. Ready for implementation (`/speckit.tasks` command).

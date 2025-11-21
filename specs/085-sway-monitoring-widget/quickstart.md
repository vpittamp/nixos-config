# Quickstart: Live Window/Project Monitoring Panel

**Feature**: 085-sway-monitoring-widget
**Status**: ✅ MVP + User Story 2 COMPLETE - 2025-11-20
**Target Platforms**: Hetzner Cloud ✅ Deployed, M1 MacBook Pro (Pending)

**Latest Update**: User Story 2 implemented - project labels and scope visual distinction added

---

## What is This?

A **global-scoped Eww widget** that provides real-time visibility into your window/project state across all workspaces. Think of it as a live system monitor showing:
- **Monitors** → **Workspaces** → **Windows** hierarchy
- Project associations (which windows belong to which projects)
- Window states (floating, hidden, focused)
- Updates automatically within 100ms when windows change

**Key Features**:
- ⚡ **Fast**: <100ms update latency, <200ms toggle latency
- 🎨 **Themed**: Catppuccin Mocha styling (consistent with Features 057, 060)
- 🔄 **Auto-updates**: Event-driven + periodic fallback
- 🌐 **Global scope**: Visible across all projects (not hidden on project switch)
- ⌨️ **Toggle**: Single keybinding (`Mod+m`) to show/hide
- 🏷️ **Project labels**: Scoped windows show (project-name), visual distinction with colored borders

---

## Quick Commands

```bash
# Toggle monitoring panel
Mod+m                    # Show/hide panel (keybinding)

# Check service status
systemctl --user status eww-monitoring-panel

# Restart panel
systemctl --user restart eww-monitoring-panel

# View backend script output (debugging)
python3 -m monitoring_data | jq .

# Check Eww daemon logs
journalctl --user -u eww --since "1 hour ago" | grep monitoring
```

---

## Installation

### Enable the Module

**File**: `home-vpittamp.nix` or `configurations/hetzner-sway.nix`

```nix
{
  programs.eww-monitoring-panel = {
    enable = true;
    # Optional: customize keybinding (default: Mod+m)
    toggleKey = "${mod}+m";
  };
}
```

### Apply Configuration

```bash
# Test configuration
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Apply changes
sudo nixos-rebuild switch --flake .#hetzner-sway

# For M1 (requires --impure for Asahi firmware)
sudo nixos-rebuild switch --flake .#m1 --impure
```

### Verify Installation

```bash
# Check Eww service
systemctl --user status eww-monitoring-panel
# Expected: Active (running)

# Check backend script
which python3-monitoring-data
# Expected: /nix/store/.../bin/python3-monitoring-data

# Test toggle script
toggle-monitoring-panel
# Expected: Panel opens/closes
```

---

## Usage

### Toggle Panel

**Keybinding**: `Mod+m` (Win/Super + M)

**Behavior**:
- **Panel closed** → Opens centered on focused monitor
- **Panel open** → Closes panel
- **Rapid toggles** → Handled gracefully (no duplicate panels)

### Navigate Panel

**Scrolling**:
- **Mouse wheel**: Scroll through window list
- **Touchpad**: Two-finger scroll

**Visual Indicators**:
- **Active monitor**: Teal left border
- **Focused workspace**: Blue background
- **Floating windows**: ⚓ icon prefix, yellow border
- **Hidden windows**: Italicized, 50% opacity
- **Project association**: `(project-name)` label on scoped windows

### Hierarchy Levels

```
Monitor (eDP-1, HEADLESS-1)
  └─ Workspace (1: Terminal, 2: Code)
       └─ Window (ghostty, firefox, code)
            ├─ App name (terminal, browser)
            ├─ Title (bash, GitHub)
            └─ Project (nixos, dotfiles, or "global")
```

**Indentation**:
- Monitors: No indent
- Workspaces: 12px left margin
- Windows: 24px left margin (12px additional)

---

## Configuration

### Keybinding

**File**: `home-modules/desktop/eww-monitoring-panel.nix`

```nix
{
  toggleKey = "${mod}+m";  # Default
  # Or customize:
  toggleKey = "${mod}+Shift+m";  # Alternative
}
```

### Panel Size

**File**: Eww config in module

```yuck
(defwindow monitoring-panel
  :geometry (geometry
    :anchor "center"
    :x "0px"
    :y "0px"
    :width "800px"    ; Adjust width
    :height "600px")) ; Adjust height
```

### Update Interval

**Defpoll fallback** (default: 10s):
```yuck
(defpoll monitoring_data :interval "10s" ...)
```

**Event-driven** (primary updates):
- Controlled by i3pm daemon
- No configuration needed (automatically <100ms)

---

## Troubleshooting

### Panel Flashes When Closing (FIXED 2025-11-20)

**Symptoms**: Panel briefly flashes open/close when pressing `Mod+m` to close

**Status**: ✅ **FIXED** - This issue was resolved in the 2025-11-20 deployment

**Fix**: Changed toggle detection from checking Sway window tree to using `eww active-windows` command, which correctly detects overlay windows.

**If still experiencing**:
```bash
# Verify you have the latest version
cat /etc/profiles/per-user/vpittamp/bin/toggle-monitoring-panel | grep "active-windows"
# Should show: if eww --config ... active-windows | grep -q "monitoring-panel"

# If not, rebuild:
sudo nixos-rebuild switch --flake .#hetzner-sway
```

---

### All Windows Show "unknown" / No Project Labels (FIXED 2025-11-20)

**Symptoms**:
- All windows display "unknown" as app name
- Project labels never show (all windows treated as global)

**Status**: ✅ **FIXED** - Resolved in User Story 2 implementation (2025-11-20)

**Fixes Applied**:
1. **App Name Extraction**: Backend now extracts from `class` or `app_id` fields (not `app_name`)
2. **Scope Detection**: Backend derives scope from Sway marks checking for "scoped:" prefix

**Verification**:
```bash
# Test backend directly - should show real app names and scoped windows
monitoring-data-backend | jq -r '.monitors[0].workspaces[0].windows[0] | {app_name, scope, project}'

# Expected output for scoped window:
# {
#   "app_name": "com.mitchellh.ghostty",  # Real class name, not "unknown"
#   "scope": "scoped",                     # Not "global"
#   "project": "085-sway-monitoring-widget"
# }

# Restart Eww if needed
systemctl --user restart eww-monitoring-panel
```

---

### Panel Won't Open

**Symptoms**: Press `Mod+m`, nothing happens

**Diagnosis**:
```bash
# Check Eww service
systemctl --user status eww-monitoring-panel
# If inactive: systemctl --user start eww-monitoring-panel

# Check Eww daemon
pgrep -x eww || echo "Eww daemon not running"

# Check toggle script
toggle-monitoring-panel
# Should print error if script fails
```

**Solutions**:
- Restart Eww service: `systemctl --user restart eww-monitoring-panel`
- Check keybinding: `swaymsg -t get_binding_state` (ensure `Mod+m` is bound)
- Verify Sway config reload: `swaymsg reload`

### Panel Shows No Windows

**Symptoms**: Panel opens but displays "0 windows" or empty list

**Diagnosis**:
```bash
# Test backend script directly
python3 -m monitoring_data | jq .

# Check for errors:
# - "status": "error" → Daemon issue
# - "status": "ok" but empty → No windows actually open

# Check i3pm daemon
systemctl --user status i3-project-event-listener
# Expected: Active (running)
```

**Solutions**:
- Restart i3pm daemon: `systemctl --user restart i3-project-event-listener`
- Verify windows exist: `swaymsg -t get_tree | jq '[.. | .nodes? // empty | .[]]'`
- Check daemon socket: `ls /run/user/$UID/i3-project-daemon/ipc.sock`

### Panel Updates Slowly

**Symptoms**: Window changes take >1 second to appear in panel

**Diagnosis**:
```bash
# Check defpoll interval
grep "defpoll monitoring_data" ~/.config/eww-monitoring-panel/eww.yuck
# Should be :interval "10s" (fallback only)

# Check event-driven updates
journalctl --user -u i3-project-event-listener | grep "MonitoringPanelPublisher"
# Should see "Publishing panel state" on window events
```

**Solutions**:
- Verify event-driven updates enabled (check daemon logs)
- If using defpoll only: Lower interval to "1s" (increases CPU usage)
- Restart i3pm daemon to reset event subscriptions

### Panel Styling Broken

**Symptoms**: Wrong colors, missing indentation, or broken layout

**Diagnosis**:
```bash
# Check CSS file
cat ~/.config/eww-monitoring-panel/style.css | grep monitoring-panel

# Check Catppuccin theme variables
grep '$base:' ~/.config/eww-monitoring-panel/style.css
```

**Solutions**:
- Rebuild configuration: `sudo nixos-rebuild switch --flake .#<target>`
- Force Eww reload: `systemctl --user restart eww-monitoring-panel`
- Check for CSS syntax errors: `eww --config ~/.config/eww-monitoring-panel debug`

---

## Performance

### Expected Latency

| Action | Latency | Target |
|--------|---------|--------|
| Toggle panel | 50-100ms | <200ms ✅ |
| Window create event → panel update | 45-50ms | <100ms ✅ |
| Project switch → panel update | 45-50ms | <100ms ✅ |
| Defpoll fallback update | 35-59ms | <50ms ✅ (typical) |

### Memory Usage

| Windows | Memory |
|---------|--------|
| 10      | ~15 MB |
| 30      | ~30 MB |
| 50      | ~45 MB |
| 100     | ~80 MB |

**Target**: <50MB for typical workload (20-30 windows) ✅

### CPU Usage

- **Event-driven updates**: <0.1% idle, 1-5% during events
- **Defpoll fallback** (10s interval): ~0.09-0.18% average
- **Total**: <1% average, <5% peak

---

## Integration with Other Features

### Feature 042: Workspace Mode Navigation

**Works together**: Panel shows current workspace, workspace mode changes focus

**Example Flow**:
1. Open panel (`Mod+m`)
2. See workspace list
3. Enter workspace mode (`CapsLock` on M1, `Ctrl+0` on Hetzner)
4. Navigate to workspace 15
5. Panel updates to show WS 15 focused

### Feature 062: Scratchpad Terminal

**Works together**: Panel shows scratchpad terminals with "hidden" indicator

**Example**:
- Scratchpad terminal hidden → Panel shows terminal with italic text, 50% opacity
- Scratchpad terminal visible → Panel shows terminal normally

### Feature 072: All-Windows Switcher

**Complementary**: Panel is read-only monitoring, switcher is interactive navigation

**Difference**:
- **Panel**: Always visible, hierarchical view, auto-updates
- **Switcher**: On-demand, flat list, keyboard-driven selection

---

## Testing

### Manual Test Checklist

- [ ] **Toggle**: Press `Mod+m` → Panel opens
- [ ] **Toggle again**: Press `Mod+m` → Panel closes
- [ ] **Window create**: Open new window → Panel updates within 100ms
- [ ] **Window close**: Close window → Panel updates within 100ms
- [ ] **Project switch**: Switch project → Panel updates within 100ms
- [ ] **Floating indicator**: Open pavucontrol (floating) → Panel shows ⚓ icon
- [ ] **Multi-monitor**: Check panel shows all monitors
- [ ] **Scrolling**: Open 50+ windows → Panel scrollbar appears, smooth scrolling
- [ ] **Styling**: Verify Catppuccin Mocha colors (teal, blue, yellow accents)

### Automated Tests

**Location**: `tests/085-sway-monitoring-widget/`

```bash
# Run Sway Test Framework tests
deno task test:085

# Expected: 3 tests pass (toggle, state updates, project switch)
```

---

## FAQ

### Q: Why is there a 10-second defpoll if updates are event-driven?

**A**: The defpoll is a **fallback safety net** for edge cases:
- Daemon restarts (event subscriptions lost)
- Sway IPC hiccups (missed events)
- Initial panel load (populate data before first event)

Event-driven updates handle 99% of cases with <100ms latency.

### Q: Can I change the keybinding?

**A**: Yes! Edit `home-modules/desktop/eww-monitoring-panel.nix`:
```nix
programs.eww-monitoring-panel.toggleKey = "${mod}+Shift+m";
```
Then rebuild: `sudo nixos-rebuild switch --flake .#<target>`

### Q: Does the panel work with i3wm (not Sway)?

**A**: No. This feature is designed for **Sway only** because:
- Relies on Sway IPC `GET_TREE` format
- Uses Sway window marks for identification
- Integrates with i3pm daemon (Sway-specific)

### Q: Why not use Feature 025's `i3pm windows --live` TUI?

**A**: Different use cases:
- **TUI**: On-demand debugging tool, terminal-based, interactive
- **Eww panel**: Always-available monitoring, GTK-based, read-only

The Eww panel reuses the backend logic from Feature 025 but presents it differently.

### Q: Can I filter windows by project in the panel?

**A**: Not in this feature (085). The panel shows **all windows** globally.

For project-specific window views, use:
- `i3pm windows --json | jq '.[] | select(.project == "nixos")'`
- Feature 072: All-Windows Switcher (filtered by project via search)

---

## Related Commands

```bash
# Query window state (Feature 025)
i3pm windows --tree          # Tree view
i3pm windows --table         # Table view
i3pm windows --live          # Live TUI

# Query project state
i3pm project current         # Current project
i3pm project list            # All projects

# Daemon diagnostics
i3pm daemon status           # Daemon health
i3pm daemon events           # Event stream

# Sway window queries
swaymsg -t get_tree | jq .   # Full window tree
swaymsg -t get_outputs       # Monitor list
swaymsg -t get_workspaces    # Workspace list
```

---

## References

- **spec.md**: Feature requirements and success criteria
- **plan.md**: Implementation plan and architecture
- **research.md**: Technical decisions and alternatives considered
- **data-model.md**: JSON schemas for data structures
- **contracts/**: API contracts for daemon queries and Eww defpoll

**Related Features**:
- Feature 025: Window State Visualization (`i3pm windows`)
- Feature 057: Unified Bar System (Eww + Catppuccin theme)
- Feature 060: Eww Top Bar (defpoll patterns)
- Feature 072: All-Windows Switcher (hierarchical display)
- Feature 076: Mark-Based App Identification

---

## Support

**Issues**:
- Check `i3pm diagnose health` for daemon issues
- Check `journalctl --user -u eww-monitoring-panel` for panel logs
- Check `journalctl --user -u i3-project-event-listener` for daemon logs

**Questions**:
- Review this quickstart guide
- Check spec.md for detailed requirements
- Review research.md for technical context

**Feature Requests**:
- File issue with tag `feature-085-enhancement`
- Include use case and expected behavior

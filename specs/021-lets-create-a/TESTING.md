# Testing Guide: Dynamic Window Management System

**Feature**: 021-lets-create-a
**Status**: User Story 1 Complete (MVP Core)
**Date**: 2025-10-21

## What Was Implemented

### User Story 1: Pattern-Based Window Classification Without Rebuilds ✅

All 12 tasks complete (T017-T028):

1. **File Watcher** (T022)
   - Watches `~/.config/i3/window-rules.json` for changes
   - Auto-reloads within 100ms (debounced)
   - No daemon restart needed

2. **Daemon Integration** (T023)
   - 4-level precedence classification system
   - Automatic workspace assignment
   - Source attribution for debugging

3. **IPC Methods** (T025-T026)
   - `get_window_rules` - List rules with filtering
   - `classify_window` - Debug classification

4. **CLI Commands** (T027-T028)
   - `i3pm rules` - View window rules
   - `i3pm classify` - Test classification

## Testing After NixOS Rebuild

### Step 1: Verify Daemon is Running

```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Should show: Active: active (running)
```

### Step 2: Create Example Window Rules

Create `~/.config/i3/window-rules.json`:

```json
[
  {
    "pattern_rule": {
      "pattern": "glob:FFPWA-*",
      "scope": "global",
      "priority": 200,
      "description": "Firefox PWAs - All global"
    },
    "workspace": 4
  },
  {
    "pattern_rule": {
      "pattern": "Code",
      "scope": "scoped",
      "priority": 250,
      "description": "VS Code - Project scoped"
    },
    "workspace": 2
  },
  {
    "pattern_rule": {
      "pattern": "Ghostty",
      "scope": "scoped",
      "priority": 240,
      "description": "Ghostty terminal"
    },
    "workspace": 1
  },
  {
    "pattern_rule": {
      "pattern": "firefox",
      "scope": "global",
      "priority": 150,
      "description": "Firefox browser - Always global"
    },
    "workspace": 3
  }
]
```

### Step 3: Test CLI Commands

```bash
# List all window rules
i3pm rules

# List only scoped rules
i3pm rules --scope scoped

# List only global rules
i3pm rules --scope global

# Test classification for Code
i3pm classify Code

# Test classification for Code in nixos project
i3pm classify Code --project nixos

# Test classification for Firefox PWA
i3pm classify FFPWA-01ABC

# Test with window title
i3pm classify Ghostty --window-title "Yazi: /etc/nixos"
```

Expected output:
- Rules should display with color-coded scopes
- Classification should show scope, source, and workspace
- Source should indicate which level matched (project, window_rule, app_classes, default)

### Step 4: Test Dynamic Reload (No Rebuild!)

1. Edit `~/.config/i3/window-rules.json` and add a new rule:

```json
{
  "pattern_rule": {
    "pattern": "k9s",
    "scope": "global",
    "priority": 150,
    "description": "K9s Kubernetes"
  },
  "workspace": 8
}
```

2. Wait 1 second

3. Query rules again:

```bash
i3pm rules
```

**Expected**: New rule appears immediately, no daemon restart needed!

### Step 5: Test Window Classification (Live)

1. Switch to a project:

```bash
i3pm switch nixos
```

2. Launch VS Code:

```bash
code /etc/nixos
```

**Expected**:
- Window should appear on workspace 2 (per rule)
- Window should be marked with `project:nixos` (project takes precedence)

3. Launch firefox:

```bash
firefox
```

**Expected**:
- Window should appear on workspace 3 (per rule)
- Window should be global (not project-scoped)

### Step 6: Test Error Handling

1. Corrupt the JSON file:

```bash
echo "{ invalid json" > ~/.config/i3/window-rules.json
```

2. Check daemon logs:

```bash
journalctl --user -u i3-project-event-listener -n 20
```

**Expected**:
- Error logged
- Desktop notification shown
- Previous rules retained (daemon keeps working)

3. Fix the file:

```bash
# Restore valid JSON
```

**Expected**:
- Rules reload automatically
- No manual intervention needed

## Verification Checklist

- [ ] Daemon starts successfully after rebuild
- [ ] `i3pm rules` command works and displays rules
- [ ] `i3pm classify` command shows correct classification
- [ ] Editing window-rules.json reloads within 1 second
- [ ] New windows are classified correctly
- [ ] Workspace assignment works (windows move to correct workspace)
- [ ] Project precedence works (project scoped_classes override rules)
- [ ] Error handling works (invalid JSON doesn't crash daemon)
- [ ] Desktop notifications appear on config errors

## Test Results

### Classification Tests (Pre-Build)

All unit tests passed:

```
✓ Project scoped_classes (Priority 1000)
✓ Window rules (Priority 200-500)
✓ App classification lists (Priority 50)
✓ Default classification
✓ Precedence hierarchy
✓ JSON serialization
✓ File reload functionality
✓ Integration test with example rules
```

### Integration Tests

Tested scenarios:
1. Code in project → scoped from project ✓
2. FFPWA-01ABC → global from window_rule, workspace 4 ✓
3. firefox → global from window_rule, workspace 3 ✓
4. Ghostty in project → scoped from project ✓
5. yazi-fm (glob match) → scoped from window_rule, workspace 5 ✓
6. k9s → global from window_rule, workspace 8 ✓
7. RandomApp → global from default ✓

## Known Issues

None! All pre-build tests passed.

## Next Steps

After testing User Story 1:

1. **User Story 2**: PWA detection via title patterns (T029-T034)
2. **User Story 3**: Terminal app detection (T035-T038)
3. **User Story 4**: Multi-monitor workspace distribution (T039-T048)
4. **User Story 5**: Workspace metadata (names, icons) (T049-T053)
5. **User Story 6**: Advanced rule syntax (GLOBAL, DEFAULT, ON_CLOSE) (T054-T063)

## Files Modified

- `home-modules/desktop/i3-project-event-daemon/config.py` - File watcher
- `home-modules/desktop/i3-project-event-daemon/daemon.py` - Integration
- `home-modules/desktop/i3-project-event-daemon/handlers.py` - Classification
- `home-modules/desktop/i3-project-event-daemon/ipc_server.py` - IPC methods
- `home-modules/tools/i3_project_manager/cli/commands.py` - CLI commands
- `home-modules/desktop/i3-project-daemon.nix` - Added watchdog dependency

## Example Configuration

See `/tmp/test-window-rules.json` for a working example with 6 rules covering:
- Firefox PWAs (glob pattern)
- VS Code (project-scoped)
- Ghostty (project-scoped)
- Yazi (glob pattern)
- Firefox browser (global)
- K9s (global)

Copy this to `~/.config/i3/window-rules.json` to get started!

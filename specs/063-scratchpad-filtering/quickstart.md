# Quickstart: Scratchpad Terminal Filtering Reliability

**Feature**: 063-scratchpad-filtering
**Status**: Implementation Phase
**Target**: NixOS with Sway (hetzner-sway, m1 configurations)

## Overview

This feature fixes scratchpad terminal filtering reliability by ensuring **consistent window filtering across all code paths** in the i3pm daemon. After this feature, scratchpad terminals will **always hide/show correctly** during project switches with 100% reliability.

## What This Feature Fixes

**Before**:
- ❌ Scratchpad terminals sometimes stayed visible when switching projects
- ❌ Duplicate scratchpad terminals could be created for the same project
- ❌ Filtering logic inconsistent across 3 different code paths
- ❌ No automated tests to verify filtering behavior

**After**:
- ✅ Scratchpad terminals hide 100% reliably when switching away from their project
- ✅ Scratchpad terminals show 100% reliably when switching back to their project
- ✅ Only one scratchpad terminal per project (enforced)
- ✅ Consistent filtering logic across all code paths
- ✅ Automated test suite with 100% pass rate

## Quick Commands

### Testing Scratchpad Filtering

```bash
# Run automated test suite (recommended)
cd /etc/nixos/specs/063-scratchpad-filtering/
bash checklists/test_scratchpad_workflow.sh

# Manual testing protocol
# 1. Clean slate
pkill -f "ghostty.*I3PM_SCRATCHPAD" || true
i3pm scratchpad status --all  # Should show no terminals

# 2. Create scratchpad terminal for project A
i3pm project switch nixos
i3pm scratchpad toggle  # Creates terminal
sleep 2

# 3. Verify terminal is visible
swaymsg -t get_tree | jq '.. | select(.marks[]? | contains("scratchpad:nixos")) | {id, visible, marks}'
# Should show: visible: true

# 4. Switch to different project
i3pm project switch stacks
sleep 2

# 5. Verify terminal is hidden
swaymsg -t get_tree | jq '.. | select(.marks[]? | contains("scratchpad:nixos")) | {id, visible, marks}'
# Should show: visible: false

# 6. Switch back to project A
i3pm project switch nixos
sleep 2

# 7. Verify terminal is visible again
swaymsg -t get_tree | jq '.. | select(.marks[]? | contains("scratchpad:nixos")) | {id, visible, marks}'
# Should show: visible: true
```

### Debugging Filtering Issues

```bash
# Check scratchpad terminal status
i3pm scratchpad status --all
# Output: Lists all scratchpad terminals with PID, window ID, project, state

# Check window environment variables
swaymsg -t get_tree | jq -r '.. | select(.marks[]? | contains("scratchpad:nixos")) | .pid'
# Copy the PID, then:
cat /proc/<PID>/environ | tr '\0' '\n' | grep I3PM_

# Expected output:
# I3PM_SCRATCHPAD=true
# I3PM_PROJECT_NAME=nixos
# I3PM_APP_NAME=scratchpad-terminal
# I3PM_SCOPE=scoped

# Monitor daemon events
i3pm daemon events --type=tick | grep -i scratchpad
# Watch for filtering decisions in real-time

# Check daemon logs
journalctl --user -u i3-project-event-listener -f | grep -i scratchpad
```

### Duplicate Prevention Testing

```bash
# 1. Create scratchpad terminal
i3pm project switch nixos
i3pm scratchpad toggle
sleep 2

# 2. Try to create another (should show existing instead)
i3pm scratchpad toggle  # Should toggle (hide), not create duplicate
sleep 1

# 3. Verify only one terminal exists
i3pm scratchpad status --all | grep -c "nixos"
# Should output: 1

# 4. Clean up
i3pm scratchpad close nixos
```

## Key Concepts

### Environment Variable-Based Identification

**Why**: Window properties (class, instance, title) can change. Environment variables **never change** after process creation.

**How**: All scratchpad terminals launched with `I3PM_SCRATCHPAD=true` in `/proc/<pid>/environ`.

**Example**:
```bash
# Regular Ghostty terminal
I3PM_APP_NAME=ghostty
I3PM_SCOPE=scoped
I3PM_PROJECT_NAME=nixos

# Scratchpad terminal (same app, different environment)
I3PM_SCRATCHPAD=true  # ← CRITICAL difference
I3PM_APP_NAME=scratchpad-terminal
I3PM_SCOPE=scoped
I3PM_PROJECT_NAME=nixos
```

### Window Mark Persistence

**Why**: Marks persist across scratchpad show/hide cycles, enabling fast filtering without environment lookups.

**How**: Sway applies mark `scratchpad:{project}` on terminal creation.

**Example**:
```bash
# Create terminal
i3pm scratchpad toggle  # Creates terminal for project "nixos"

# Check mark
swaymsg -t get_tree | jq '.. | select(.app_id == "ghostty") | .marks'
# Output: ["scratchpad:nixos"]

# Hide to scratchpad
swaymsg '[con_mark="scratchpad:nixos"] move scratchpad'

# Mark still present (even when hidden)
swaymsg -t get_tree | jq '.. | select(.app_id == "ghostty") | {visible, marks}'
# Output: {visible: false, marks: ["scratchpad:nixos"]}
```

### Filtering Decision Priority

1. **Mark-based** (fast, ~1ms): Check window.marks for `scratchpad:{project}`
2. **Environment-based** (slow, ~5ms): Read `/proc/<pid>/environ` for `I3PM_*` variables
3. **Default**: Global window (always visible)

## Architecture

### Three Filtering Code Paths

All three paths MUST produce identical filtering decisions:

| Path | File | Entry Point | Trigger |
|------|------|-------------|---------|
| 1 | `handlers.py` | `_switch_project()` | Tick event `project:switch:NAME` |
| 2 | `window_filter.py` | `filter_windows_by_project()` | Called by path 1 |
| 3 | `ipc_server.py` | `_switch_project()` | JSON-RPC `switch_project` method |

**Consistency**: All paths call `WindowFilterCriteria.should_hide()` helper function (single source of truth).

### Data Models

- **WindowEnvironment**: Parsed I3PM_* variables from `/proc/<pid>/environ`
- **WindowFilterCriteria**: Unified criteria for hide/show decisions
- **FilteringDecision**: Audit trail for debugging

See `data-model.md` for full details.

## Common Issues

### Issue: Terminal stays visible after project switch

**Symptoms**:
- Switch from project A to project B
- Project A's scratchpad terminal remains visible

**Debug**:
```bash
# Check terminal mark
swaymsg -t get_tree | jq '.. | select(.app_id == "ghostty" and .marks != []) | {pid, marks, visible}'

# Check environment variables
cat /proc/<PID>/environ | tr '\0' '\n' | grep I3PM_SCRATCHPAD
```

**Fixes**:
- If mark missing: Run `i3pm scratchpad cleanup` to remove invalid terminals
- If environment missing: Terminal not launched via scratchpad manager (close and recreate)
- If mark present but filtering not working: Daemon may need restart

### Issue: Multiple terminals for same project

**Symptoms**:
- `i3pm scratchpad status --all` shows 2+ terminals for same project
- Duplicate Ghostty windows with same mark

**Debug**:
```bash
# List all terminals
i3pm scratchpad status --all

# Check window tree
swaymsg -t get_tree | jq '.. | select(.marks[]? | startswith("scratchpad:")) | {id, pid, marks}'
```

**Fixes**:
```bash
# Remove duplicates
i3pm scratchpad cleanup

# If cleanup doesn't work, manually close terminals
i3pm scratchpad close <project-name>

# Recreate single terminal
i3pm scratchpad toggle
```

### Issue: Terminal window exists but status shows "not found"

**Symptoms**:
- Can see Ghostty window with scratchpad mark
- `i3pm scratchpad status nixos` says "No scratchpad terminal for project"

**Debug**:
```bash
# Check daemon state
i3pm daemon status | head -10

# Check if daemon recognizes terminal
journalctl --user -u i3-project-event-listener | tail -50 | grep scratchpad
```

**Fixes**:
```bash
# Restart daemon (resyncs state with Sway)
systemctl --user restart i3-project-event-listener
sleep 2

# Check status again
i3pm scratchpad status --all
```

## Testing

### Automated Test Suite

**Location**: `/etc/nixos/specs/063-scratchpad-filtering/checklists/test_scratchpad_workflow.sh`

**Run**:
```bash
cd /etc/nixos/specs/063-scratchpad-filtering/
bash checklists/test_scratchpad_workflow.sh
```

**Tests**:
- ✅ Basic hide/show during project switching
- ✅ Duplicate prevention (only one terminal per project)
- ✅ Environment variable validation
- ✅ Multiple projects with independent terminals
- ✅ Terminal state persistence across switches

**Expected Output**:
```
=== Setup Phase ===
✓ Clean state verified

=== Test Case 1: Basic Hide/Show ===
✓ nixos scratchpad should be visible
✓ nixos scratchpad should be hidden
✓ nixos scratchpad should be visible again

=== Test Case 2: Duplicate Prevention ===
✓ Should still have exactly 1 nixos scratchpad

=== Test Case 3: Environment Variables ===
Scratchpad PID: 12345
✓ Environment variable I3PM_SCRATCHPAD = true
✓ Environment variable I3PM_PROJECT_NAME = nixos
✓ Environment variable I3PM_APP_NAME = scratchpad-terminal
✓ Environment variable I3PM_SCOPE = scoped

=== Test Case 4: Multiple Projects ===
✓ stacks scratchpad should be visible
✓ nixos scratchpad should still be hidden
✓ nixos scratchpad should be visible
✓ stacks scratchpad should be hidden

=== Cleanup Phase ===
✓ Clean state verified

✓✓✓ All tests passed ✓✓✓
```

### Manual Verification

**Test Checklist**:
1. ☐ Clean state (no existing scratchpad terminals)
2. ☐ Create scratchpad terminal for project A
3. ☐ Terminal is visible on project A
4. ☐ Switch to project B
5. ☐ Terminal is hidden (not visible)
6. ☐ Switch back to project A
7. ☐ Terminal is visible again
8. ☐ Attempt to create duplicate → shows existing instead
9. ☐ Close terminal → status shows no terminals
10. ☐ Multiple projects can have independent terminals

## Performance

**Targets** (from spec.md success criteria):
- Visibility change latency: < 200ms (median)
- Filtering logic execution: < 100ms per code path
- Daemon CPU usage: < 1% during normal operation

**Measurement**:
```bash
# Measure project switch latency
time (i3pm project switch nixos && sleep 0.5)

# Monitor daemon CPU
ps aux | grep i3_project_daemon
```

## Files Modified

**Implementation**:
- `/etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon/ipc_server.py` - Added scratchpad filtering to `_hide_windows()`
- `/etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon/window_filter.py` - Added scratchpad mark detection
- `/etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon/handlers.py` - Uses `window_filter.py` helper
- `/etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon/models.py` - Added `WindowEnvironment` model

**Tests**:
- `/etc/nixos/tests/i3pm/unit/test_environment.py` - Unit tests for environment parsing
- `/etc/nixos/tests/i3pm/integration/test_filtering_consistency.py` - Cross-path consistency tests
- `/etc/nixos/specs/063-scratchpad-filtering/checklists/test_scratchpad_workflow.sh` - End-to-end test script

## Related Features

- **Feature 062**: Project-scoped scratchpad terminal (base functionality)
- **Feature 037**: Window filtering and scoping (original filtering system)
- **Feature 038**: Window state preservation (hide/restore logic)

## Next Steps

1. **Implementation**: Apply changes from `tasks.md` (generated by `/speckit.tasks`)
2. **Testing**: Run automated test suite until 100% pass rate
3. **Validation**: Manual testing with real-world usage (20+ project switches)
4. **Documentation**: Update `CLAUDE.md` with new filtering behavior

## Support

**Debugging Help**:
- Daemon logs: `journalctl --user -u i3-project-event-listener -f`
- Daemon status: `i3pm daemon status`
- Window state: `swaymsg -t get_tree | jq '.. | select(.marks != []) | {id, marks, visible}'`
- Environment: `cat /proc/<PID>/environ | tr '\0' '\n' | grep I3PM_`

**Test Failures**:
- See test script output for specific failure details
- Check daemon logs for errors during test execution
- Verify Sway IPC is responding: `swaymsg -t get_tree > /dev/null && echo OK`

**Contact**:
- GitHub Issues: https://github.com/vpittamp/nixos-config/issues
- Spec: `/etc/nixos/specs/063-scratchpad-filtering/spec.md`
- Implementation Plan: `/etc/nixos/specs/063-scratchpad-filtering/plan.md`

---

**Last Updated**: 2025-11-07
**Version**: 1.0.0
**Status**: Ready for implementation

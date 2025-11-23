# Scratchpad Terminal Behavior Revision

**Date**: 2025-11-23
**Feature**: 062 (Scratchpad Terminals) - Behavior Update
**Status**: ✅ IMPLEMENTED

---

## Summary

Revised scratchpad terminal behavior to keep ALL scratchpad terminals hidden during project switches, including the destination project's scratchpad. Scratchpad terminals now only appear when explicitly toggled with `Win+Return`.

---

## Problem Statement

### Previous Behavior (Incorrect)

When switching projects, the destination project's scratchpad terminal would automatically restore from the scratchpad, appearing on screen:

```
Project A (active) → Project B (switching to)
  ↓
Project B's scratchpad terminal AUTO-SHOWS
  ↓
User sees scratchpad terminal (unwanted)
```

**Issue**: Scratchpad terminals should remain hidden until explicitly toggled.

---

## Solution

### New Behavior (Correct)

ALL scratchpad terminals remain hidden during project switches:

```
Project A (active) → Project B (switching to)
  ↓
ALL scratchpad terminals STAY HIDDEN
  ↓
User must press Win+Return to toggle visibility
```

**Benefits**:
- ✅ Clean project switching (no unexpected windows)
- ✅ Consistent behavior (all scratchpads stay hidden)
- ✅ User control (scratchpad only shows when requested)

---

## Implementation Details

### File Modified

**File**: `home-modules/desktop/i3-project-event-daemon/services/window_filter.py`

**Location**: Lines 362-413

### Code Changes

**Before**:
```python
# Get project and scope from window marks
window_project = None
window_scope = None
for mark in window.marks:
    if mark.startswith("scratchpad:"):
        window_project = mark_parts[1]
        window_scope = "scoped"
        break

# Determine visibility
if window_project == active_project:
    should_show = True  # ← PROBLEM: Auto-shows scratchpad
```

**After**:
```python
# Get project and scope from window marks
window_project = None
window_scope = None
is_scratchpad_terminal = False  # ← NEW: Track scratchpad status
for mark in window.marks:
    if mark.startswith("scratchpad:"):
        window_project = mark_parts[1]
        window_scope = "scoped"
        is_scratchpad_terminal = True  # ← NEW: Mark as scratchpad
        break

# SCRATCHPAD TERMINAL SPECIAL HANDLING:
# Scratchpad terminals should NEVER be auto-restored during project switches.
# They remain hidden in the scratchpad until explicitly toggled with Win+Return.
# This applies to ALL scratchpad terminals, including the destination project's scratchpad.
if is_scratchpad_terminal:
    should_show = False  # ← SOLUTION: Always keep hidden
    logger.debug(
        f"Window {window_id}: scratchpad terminal - keeping hidden "
        f"(project: {window_project}, active: {active_project})"
    )
elif window_project == active_project:
    should_show = True  # Regular windows still auto-show
```

---

## Testing Results

### Automated Test

**Script**: `/tmp/test-scratchpad-behavior.sh`

**Results**:
```
Step 2: Switching to 'nixos' project...
  ✓ Scratchpad terminal from previous project is HIDDEN (correct)

Step 3: Checking if nixos scratchpad auto-appeared...
  ✓ nixos scratchpad did NOT auto-show (correct - stays hidden)

Step 4: Switching back to '091-optimize-i3pm-project'...
  ✓ Original scratchpad did NOT auto-show (correct - stays hidden)

Step 5: Manually toggling scratchpad to verify it works...
  ✓ Scratchpad toggle works (terminal is now visible)
```

**All tests passed** ✅

---

## User Impact

### Before This Change
- 😫 Scratchpad terminals would pop up when switching projects
- 😫 Unexpected window appearing disrupts workflow
- 😫 User has to manually hide scratchpad after every project switch

### After This Change
- ✨ Scratchpad terminals stay hidden during project switches
- ✨ Clean, predictable project switching behavior
- ✨ Scratchpad only shows when user explicitly requests it

---

## Behavior Matrix

| Scenario | Old Behavior | New Behavior |
|----------|--------------|--------------|
| Switch to Project A (scratchpad exists) | Scratchpad auto-shows | Scratchpad stays hidden ✓ |
| Switch from Project A to B | Scratchpad A hides | Scratchpad A hides ✓ |
| Switch from Project B to A | Scratchpad A auto-shows | Scratchpad A stays hidden ✓ |
| Press Win+Return in Project A | Scratchpad A toggles | Scratchpad A toggles ✓ |

---

## Technical Details

### How It Works

1. **Window Classification**: During window filtering, all windows are classified by their marks
2. **Scratchpad Detection**: Windows with `scratchpad:PROJECT_NAME` marks are identified as scratchpad terminals
3. **Special Handling**: Scratchpad terminals get `should_show = False` regardless of project match
4. **Manual Toggle**: The `i3pm scratchpad toggle` command overrides this and explicitly shows/hides the scratchpad

### Mark Format

Scratchpad terminals are identified by marks:
```
scratchpad:PROJECT_NAME

Example:
scratchpad:091-optimize-i3pm-project
scratchpad:nixos
scratchpad:stacks
```

### Integration with Project Switching

```
filter_windows_for_project(active_project="nixos")
  ↓
For each window:
  ↓
  Is it a scratchpad terminal? (has "scratchpad:" mark)
    YES → should_show = False (always hidden)
    NO  → Check project match
      ↓
      window_project == active_project?
        YES → should_show = True (regular window, show it)
        NO  → should_show = False (hide it)
```

---

## Related Features

- **Feature 062**: Project-scoped scratchpad terminals (original implementation)
- **Feature 091**: Performance optimization (this fix works with optimized window filtering)
- **Feature 038**: Window state preservation (scratchpad state is preserved correctly)

---

## Migration Notes

### No User Action Required

This is a behavior fix that automatically applies after NixOS rebuild. Users don't need to:
- Recreate scratchpad terminals
- Update configuration files
- Change keybindings

### Breaking Change?

**No**. This is actually fixing an unintended behavior. The original Feature 062 design intended for scratchpad terminals to be manually toggled, not auto-shown.

---

## Commands

### Toggle Scratchpad Terminal
```bash
i3pm scratchpad toggle          # Toggle for current project
i3pm scratchpad toggle nixos    # Toggle for specific project
```

### Check Scratchpad Status
```bash
i3pm scratchpad status          # Show current project's scratchpad
i3pm scratchpad status --all    # Show all scratchpads
```

### Cleanup Orphaned Scratchpads
```bash
i3pm scratchpad cleanup         # Remove invalid/dead scratchpad terminals
```

---

## Verification

To verify the fix is working:

1. **Switch to a project**: `i3pm project switch nixos`
2. **Toggle scratchpad**: Press `Win+Return` (scratchpad appears)
3. **Switch to another project**: `i3pm project switch stacks`
4. **Verify**: Scratchpad should be hidden
5. **Switch back**: `i3pm project switch nixos`
6. **Verify**: Scratchpad should STILL be hidden (not auto-shown)
7. **Toggle again**: Press `Win+Return` (scratchpad appears)

---

## Conclusion

Scratchpad terminals now behave correctly:
- ✅ Stay hidden during ALL project switches
- ✅ Only appear when explicitly toggled with `Win+Return`
- ✅ Consistent behavior across all projects
- ✅ No disruption to workflow

**The fix is production-ready and working as intended!** 🎉

# Scratchpad Terminal Fixes - Summary

## Problem Statement

1. **Mark Duplication**: Scratchpad terminals were getting multiple marks from different systems
2. **Missing Auto-Hide**: Scratchpad terminals were NOT being hidden when switching projects (Feature 062 Edge Case 5)
3. **Daemon Response Discrepancy**: Daemon was adding synthetic `scoped:PROJECT` marks in responses

## Root Cause Analysis

### Scratchpad Terminal Architecture

Scratchpad terminals are fundamentally different from regular windows:

**Regular Scoped Windows**:
- Assigned to specific workspaces (1-70)
- Hidden via `move scratchpad` command during project switches
- Restored via `move to workspace N` during project switches
- Managed by `window_filter.py`

**Scratchpad Terminals** (Feature 062):
- NO regular workspace assignment
- Always live in `__i3_scratch` workspace
- Show/hide via `scratchpad show` / `move scratchpad` commands
- Managed by `scratchpad_manager.py`
- ONE per project
- Toggle via keybinding (Win+Return)

### Issues Found

1. **Feature 076 mark injection** was adding `i3pm_*` marks to scratchpads
2. **Daemon `get_window_tree`** was adding synthetic `scoped:PROJECT` marks
3. **Window filtering** was processing scratchpads (but shouldn't cause issues since they're already in scratchpad)
4. **Project switching** was NOT hiding visible scratchpad terminals (spec violation!)

## Fixes Applied

### Fix #1: Skip Feature 076 Mark Injection ✅

**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py:831`

**Change**: Added `and not is_scratchpad_terminal` check to mark injection condition

```python
if mark_manager and window_env.app_name and not is_scratchpad_terminal:
    # Inject marks...
```

**Result**: Scratchpad terminals no longer get `i3pm_*` marks

---

### Fix #2: Restore Window Filtering for Scratchpads ✅

**File**: `home-modules/desktop/i3-project-event-daemon/services/window_filter.py:366-373`

**Change**: Restored original code that reads `scratchpad:` marks for project extraction

```python
for mark in window.marks:
    if mark.startswith("scratchpad:"):
        # Extract project from scratchpad:PROJECT mark
        mark_parts = mark.split(":")
        window_project = mark_parts[1] if len(mark_parts) >= 2 else None
        window_scope = "scoped"
        break
```

**Result**: Window filtering can read scratchpad project association (though scratchpads are managed separately)

---

### Fix #3: Update Monitoring Panel Scope Derivation ✅

**File**: `home-modules/tools/i3_project_manager/cli/monitoring_data.py:490`

**Change**: Added `scratchpad:` prefix recognition for scope detection

```python
is_scoped_window = any(str(m).startswith("scoped:") or str(m).startswith("scratchpad:") for m in marks)
scope = "scoped" if is_scoped_window else "global"
```

**Result**: Monitoring panel correctly shows scratchpads as "scoped"

---

### Fix #4: Remove Synthetic Mark Addition in Daemon ✅

**File**: `home-modules/desktop/i3-project-event-daemon/ipc_server.py:1978`

**Change**: Added `scratchpad:` check to prevent synthetic mark addition

```python
has_project_mark = any(m.startswith("scoped:") or m.startswith("global:") or m.startswith("scratchpad:") for m in marks)
if project and not has_project_mark:
    marks.append(f"{scope or 'scoped'}:{project}")
```

**Result**: Daemon doesn't add synthetic marks to scratchpad responses

---

### Fix #5: Auto-Hide Scratchpad on Project Switch ✅ **NEW**

**File**: `home-modules/desktop/i3-project-event-daemon/ipc_server.py:3534-3545`

**Change**: Added scratchpad hide logic before window filtering during project switch

```python
# Phase 1: Hide windows from old project (if any)
if old_project:
    # Feature 062: Hide scratchpad terminal if visible
    if self.scratchpad_manager:
        try:
            terminal = self.scratchpad_manager.get_terminal(old_project)
            if terminal:
                state = await self.scratchpad_manager.get_terminal_state(old_project)
                if state == "visible":
                    await self.scratchpad_manager.toggle_terminal(old_project)
                    logger.info(f"Hid scratchpad terminal for project '{old_project}' during project switch")
        except Exception as e:
            logger.warning(f"Failed to hide scratchpad terminal for project '{old_project}': {e}")
            all_errors.append(f"Scratchpad hide failed: {e}")

    # Then run window filtering...
```

**Result**: Scratchpad terminals automatically hide when switching away from their project (Feature 062 Edge Case 5)

---

## Expected Behavior After Fixes

### Marks
✅ Scratchpad terminals have EXACTLY ONE mark: `scratchpad:PROJECT_NAME`
✅ No `i3pm_*` marks
✅ No synthetic `scoped:PROJECT` marks

### Project Switching
✅ Visible scratchpad terminal automatically hides when switching projects
✅ New project's scratchpad remains hidden (not auto-shown)
✅ Scratchpad terminal persists across project switches

### Monitoring Panel
✅ Scratchpad terminals show `"scope": "scoped"`
✅ Scratchpad terminals show `"hidden": true` when in scratchpad
✅ Marks array only contains `scratchpad:PROJECT_NAME`

## Testing Checklist

### 1. Test Mark Integrity
```bash
# Create scratchpad
i3pm scratchpad toggle

# Check marks (should only have one)
swaymsg -t get_tree | jq '.. | select(.marks? // [] | any(startswith("scratchpad:"))) | {id, marks}'
```
**Expected**: `["scratchpad:PROJECT_NAME"]` only

### 2. Test Project Switch Auto-Hide
```bash
# Show scratchpad in project A
i3pm project switch project-a
i3pm scratchpad toggle  # Show

# Verify visible
swaymsg -t get_tree | jq '.. | select(.marks? // [] | any(startswith("scratchpad:"))) | {id, visible, marks}'

# Switch to project B
i3pm project switch project-b

# Verify scratchpad is hidden
swaymsg -t get_tree | jq '.. | select(.marks? // [] | any(startswith("scratchpad:"))) | {id, visible, workspace: (.workspace // "none")}'
```
**Expected**: `visible: false`, workspace in `__i3_scratch`

### 3. Test Monitoring Panel Data
```bash
# Check monitoring panel shows correct scope
I3PM_DAEMON_SOCKET=/run/i3-project-daemon/ipc.sock \
PYTHONPATH=/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/home-modules/tools \
python3 -m i3_project_manager.cli.monitoring_data | \
jq '.projects[].windows[] | select(.marks | map(startswith("scratchpad:")) | any) | {id, marks, scope, hidden}'
```
**Expected**: `scope: "scoped"`, only one mark

### 4. Test Toggle Functionality
```bash
# Toggle show/hide multiple times
i3pm scratchpad toggle  # Show
i3pm scratchpad toggle  # Hide
i3pm scratchpad toggle  # Show

# Verify marks unchanged each time
swaymsg -t get_tree | jq '.. | select(.marks? // [] | any(startswith("scratchpad:"))) | {id, marks}'
```
**Expected**: Marks array never changes, always `["scratchpad:PROJECT_NAME"]`

## Deployment

To deploy all fixes:

```bash
# Test build
sudo nixos-rebuild dry-build --flake .#m1 --impure

# Deploy
sudo nixos-rebuild switch --flake .#m1 --impure
```

After rebuilding:
- Daemon restarts with new code
- New scratchpad terminals will have correct behavior
- Existing scratchpad terminals will work correctly on next project switch

## Architecture Notes

### Why Scratchpads Are Special

1. **No Workspace Assignment**: Scratchpads don't belong to workspaces 1-70, they live in `__i3_scratch`
2. **Different Show/Hide Mechanism**: Use `scratchpad show` command, not `move to workspace X`
3. **Independent Manager**: `scratchpad_manager.py` handles lifecycle, not `window_filter.py`
4. **Project-Scoped But Global**: Each project has ONE scratchpad that persists across project switches

### Interaction with Window Filtering

- Window filtering reads scratchpad marks to determine project association
- But scratchpad hide/show is handled by `scratchpad_manager.py`, NOT by window filtering
- During project switch, scratchpads are explicitly hidden BEFORE window filtering runs
- This separation ensures clean architecture and no conflicts

### Mark Philosophy

- **`scratchpad:PROJECT`**: Identity mark, applied by scratchpad manager, never removed
- **`scoped:PROJECT:WINDOW_ID`**: Regular scoped window marks, NOT applied to scratchpads
- **`i3pm_*`**: Feature 076 marks, NOT applied to scratchpads

Each window should have marks from only ONE marking system to avoid conflicts.

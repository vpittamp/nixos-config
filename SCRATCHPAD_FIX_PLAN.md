# Scratchpad Terminal Mark Duplication Fix Plan

## Root Cause

Scratchpad terminals are getting TWO different marking systems applied:

1. **Scratchpad Manager Mark**: `scratchpad:PROJECT_NAME` (correct ✓)
2. **Feature 076 i3pm Marks**: `i3pm_app:scratchpad-terminal`, `i3pm_scope:scoped`, etc. (should be skipped ✗)
3. **Regular Project Mark**: `scoped:PROJECT:WINDOW_ID` (should be skipped ✗)

The issue is in `handlers.py:on_window_new()`:
- Line 813-820: Detects scratchpad terminal and sets `is_scratchpad_terminal = True`
- Line 829-847: **Feature 076 mark injection happens WITHOUT checking `is_scratchpad_terminal`!**
- Line 991-996: Correctly skips normal project marking for scratchpad terminals ✓

## Required Fixes

### Fix 1: Skip Feature 076 Mark Injection for Scratchpad Terminals

**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py`
**Location**: Lines 829-847 (after parsing window_env)

**Current code** (lines 829-847):
```python
# Feature 076 T014-T015: Inject marks for app identification
if mark_manager and window_env.app_name:
    try:
        mark_metadata = await mark_manager.inject_marks(
            window_id=window_id,
            app_name=window_env.app_name,
            project=window_env.project_name if window_env.scope == "scoped" else None,
            workspace=workspace_number,
            scope=window_env.scope,
        )
        logger.info(
            f"Injected marks for window {window_id} ({window_env.app_name}): "
            f"{', '.join(mark_metadata.to_sway_marks())}"
        )
    except Exception as e:
        # T015: Graceful degradation - log error but don't fail window creation
        logger.warning(
            f"Failed to inject marks for window {window_id} ({window_env.app_name}): {e}"
        )
```

**Fixed code**:
```python
# Feature 076 T014-T015: Inject marks for app identification
# Feature 062: Skip mark injection for scratchpad terminals (managed by ScratchpadManager)
if mark_manager and window_env.app_name and not is_scratchpad_terminal:
    try:
        mark_metadata = await mark_manager.inject_marks(
            window_id=window_id,
            app_name=window_env.app_name,
            project=window_env.project_name if window_env.scope == "scoped" else None,
            workspace=workspace_number,
            scope=window_env.scope,
        )
        logger.info(
            f"Injected marks for window {window_id} ({window_env.app_name}): "
            f"{', '.join(mark_metadata.to_sway_marks())}"
        )
    except Exception as e:
        # T015: Graceful degradation - log error but don't fail window creation
        logger.warning(
            f"Failed to inject marks for window {window_id} ({window_env.app_name}): {e}"
        )
elif is_scratchpad_terminal:
    logger.info(
        f"Skipping Feature 076 mark injection for scratchpad terminal {window_id} "
        f"(will be marked by scratchpad manager with 'scratchpad:PROJECT')"
    )
```

### Fix 2: Ensure Window Filtering Skips Scratchpad Terminals

**File**: `home-modules/desktop/i3-project-event-daemon/services/window_filter.py`
**Location**: Lines 359-400 (window classification loop)

Add an early check to skip scratchpad terminals entirely:

**Location**: After line 360 (inside the `for window in windows:` loop)

**Add this code**:
```python
for window in windows:
    window_id = window.id

    # Feature 062: Skip scratchpad terminals - they're managed by ScratchpadManager, not window filtering
    has_scratchpad_mark = any(mark.startswith("scratchpad:") for mark in window.marks)
    if has_scratchpad_mark:
        logger.debug(f"Skipping window {window_id} - scratchpad terminal (managed by ScratchpadManager)")
        continue

    # Get project and scope from window marks
    window_project = None
    window_scope = None
    for mark in window.marks:
        ...
```

This ensures that scratchpad terminals are NEVER processed by window filtering logic, avoiding any potential mark duplication.

### Fix 3: Update Monitoring Data Scope Derivation

**File**: `home-modules/tools/i3_project_manager/cli/monitoring_data.py`
**Location**: Lines 487-489

**Current code**:
```python
# Derive scope from marks - check if any mark starts with "scoped:"
marks = window.get("marks", [])
scope = "scoped" if any(str(m).startswith("scoped:") for m in marks) else "global"
```

**Fixed code**:
```python
# Derive scope from marks - check if any mark starts with "scoped:" OR "scratchpad:"
# Feature 062: Scratchpad terminals are project-scoped (scoped:PROJECT not global)
marks = window.get("marks", [])
is_scoped_window = any(str(m).startswith("scoped:") or str(m).startswith("scratchpad:") for m in marks)
scope = "scoped" if is_scoped_window else "global"
```

This ensures that scratchpad terminals are correctly identified as "scoped" regardless of whether they have the `scoped:` mark or just the `scratchpad:` mark.

## Testing Plan

After applying the fixes:

1. **Test scratchpad creation**:
   ```bash
   i3pm scratchpad toggle
   swaymsg -t get_tree | jq '..|select(.marks?)|select(.marks | length > 0)|{id,marks}'
   ```
   **Expected**: Only `scratchpad:PROJECT_NAME` mark (no `i3pm_*` or `scoped:*` marks)

2. **Test scratchpad show/hide**:
   ```bash
   i3pm scratchpad toggle  # Show
   # Check marks - should still be only scratchpad:PROJECT_NAME
   i3pm scratchpad toggle  # Hide
   # Check marks - should STILL be only scratchpad:PROJECT_NAME (no dual marks!)
   ```

3. **Test project switching**:
   ```bash
   pcurrent  # Check current project
   pswitch other-project
   # Scratchpad should hide automatically
   # Check marks on scratchpad window - should still be only scratchpad:PROJECT_NAME
   ```

4. **Test monitoring panel**:
   ```bash
   python3 -m i3_project_manager.cli.monitoring_data | jq '.projects[].windows[] | select(.marks | map(startswith("scratchpad:")) | any)'
   ```
   **Expected**: Scratchpad windows show `"scope": "scoped"` even with only `scratchpad:PROJECT_NAME` mark

## Implementation Order

1. **Fix 1**: Skip Feature 076 mark injection (highest priority - prevents duplicate i3pm_* marks)
2. **Fix 2**: Skip window filtering for scratchpads (prevents any future dual-mark issues)
3. **Fix 3**: Update scope derivation (ensures correct UI display)

## Verification

After all fixes are applied:
- Scratchpad terminals should have EXACTLY ONE mark: `scratchpad:PROJECT_NAME`
- Scope should always be "scoped" in monitoring panel
- Window filtering should never touch scratchpad terminals
- Project switching should work correctly (scratchpads hide when switching projects)

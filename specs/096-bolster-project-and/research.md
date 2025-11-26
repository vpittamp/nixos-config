# Phase 0 Research: Bolster Project & Worktree CRUD Operations

**Date**: 2025-11-26
**Feature**: 096-bolster-project-and
**Researcher**: Claude Code Agent

## Executive Summary

The user reported that CRUD actions "cannot be submitted" in the Projects tab of the eww monitoring widget. Investigation reveals the following root causes:

1. **Conflict Detection Bug**: The shell script exits with error when conflict is detected, but the conflict detection logic itself is buggy and always returns `true`
2. **Successful Saves Are Incorrectly Reported as Errors**: Edits actually succeed on disk, but the UI shows an error due to false conflict detection
3. **Shell Scripts Work Correctly**: The `project-edit-save` script is properly installed and executes correctly

## Investigation Details

### Verification Tests Performed

| Test | Result | Notes |
|------|--------|-------|
| Python CLI `list` command | ✅ Works | Returns 10 projects correctly |
| Python CLI `edit` command | ✅ Works | Edit applied to disk, returns `conflict: true` |
| Shell script installed | ✅ Works | `/etc/profiles/per-user/vpittamp/bin/project-edit-save` exists |
| Eww service running | ✅ Active | With "Scope not in graph" warnings |
| File written to disk | ✅ Works | Changes persist in `~/.config/i3/projects/*.json` |

### Root Cause Analysis

#### Issue 1: Conflict Detection Always Returns True

**Location**: `home-modules/tools/i3_project_manager/services/project_editor.py:162-169`

**Current Code**:
```python
# Get file modification time before read (for conflict detection)
file_mtime_before = project_file.stat().st_mtime

# ... read and write file ...

# Check for conflict (file modified between read and write)
file_mtime_after = project_file.stat().st_mtime
has_conflict = (file_mtime_after != file_mtime_before and
              file_mtime_before != file_mtime_after)
```

**Problem**: The code compares mtime before read and after write. After writing the file, mtime will ALWAYS be different (because we just modified it). This means `conflict: true` is returned for EVERY successful edit.

**Correct Approach**: Store mtime before read, compare mtime BEFORE write, only detect conflict if file changed between read and write (by another process).

#### Issue 2: Shell Script Treats Conflict as Hard Error

**Location**: `home-modules/desktop/eww-monitoring-panel.nix:240-248`

**Current Code**:
```bash
if [ "$STATUS" = "success" ]; then
  # Check for conflicts (T041)
  if [ "$CONFLICT" = "true" ]; then
    ERROR_MSG="Conflict: File was modified externally. Please reload and try again."
    $EWW update edit_form_error="$ERROR_MSG"
    echo "Conflict detected: $ERROR_MSG" >&2
    exit 1  # <-- This prevents success handling
  fi
  # Success handling never reached...
```

**Problem**: Combined with Issue 1, this means every edit shows an error message and the form stays open, even though the edit was successfully written to disk.

### Secondary Observations

#### Eww "Scope not in graph" Errors

The eww daemon logs show repeated `Scope not in graph` errors. This is a known Eww issue with dynamically created widgets but doesn't directly cause the CRUD failure. Should be monitored but is lower priority than the conflict detection bug.

#### Project Create Script Not Tested

The `project-create-save` script was not directly tested. It likely has similar conflict detection issues. The worktree scripts (`worktree-create`, `worktree-delete`, `worktree-edit-save`) may also be affected.

## Decisions

### Decision 1: Fix Conflict Detection Logic

**Decision**: Implement correct conflict detection by comparing mtime before read vs mtime immediately before write (not after write).

**Rationale**: The current logic has a fundamental logical error. Proper conflict detection should only trigger when another process modified the file between our read and write operations.

**Alternatives Considered**:
- Remove conflict detection entirely: Rejected - it's a useful safety feature
- Use file locking: Overkill for single-user system with local files
- Use etag/checksum-based comparison: More complex, not needed for this use case

### Decision 2: Make Conflict Detection Non-Blocking

**Decision**: When conflict is detected, warn the user but don't prevent the save from completing. Show a notification rather than blocking the form.

**Rationale**: For a single-user system with local files, conflicts are rare. When they do occur, the user's latest edit (the one they just made in the UI) should take precedence. The warning informs them but doesn't block workflow.

**Alternatives Considered**:
- Keep conflict as blocking error: Rejected - too disruptive for rare edge case
- Show diff and ask user to choose: Too complex for MVP, consider for future

### Decision 3: Add Visual Feedback for Save States

**Decision**: Add clear visual indicators for:
- Save in progress (loading spinner)
- Save succeeded (green success toast, auto-dismiss)
- Save failed (red error toast, persist until dismissed)

**Rationale**: User reported not knowing if actions succeeded. Visual feedback is critical for UX trust.

## Technology Choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Backend | Existing Python CLI handler | Already works, just needs conflict fix |
| Shell scripts | Existing Nix-generated scripts | Correctly pass Eww vars to Python |
| Notification | Eww toast/revealer | Consistent with existing monitoring panel UX |
| Conflict detection | mtime-based before write | Simple, sufficient for single-user system |

## Outstanding Questions

1. **Worktree CRUD**: Do the worktree scripts have similar issues? (Need to test)
2. **Create flow**: Does project-create-save work? (Need to test)
3. **Delete flow**: Does project-delete work? (Need to test)

## Implementation Priority

1. **P1**: Fix conflict detection logic in `project_editor.py`
2. **P1**: Update shell script to not exit on conflict
3. **P1**: Add success notification to shell scripts
4. **P2**: Add loading state during save
5. **P2**: Verify and fix worktree scripts
6. **P3**: Address "Scope not in graph" Eww warnings

## References

- Feature 094 spec: `/specs/094-enhance-project-tab/spec.md`
- Project editor service: `home-modules/tools/i3_project_manager/services/project_editor.py`
- Shell scripts: `home-modules/desktop/eww-monitoring-panel.nix` (lines 200-320)
- Monitoring panel: `home-modules/tools/monitoring-panel/project_crud_handler.py`

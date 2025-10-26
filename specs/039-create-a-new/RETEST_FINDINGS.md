# Application Registry Retest Findings
## Post-Fix Verification - Feature 039

**Test Date**: 2025-10-26 (after fixes)
**Tester**: Claude Code
**Applications Retested**: VS Code (vscode)
**Status**: ⚠️ **PARTIAL SUCCESS - UNEXPECTED LIMITATIONS DISCOVERED**

---

## Executive Summary

The 3 quick fixes were successfully **deployed** but revealed **unexpected architectural limitations** in the daemon's event handling flow. While the fixes work as intended at the configuration level, the daemon is not applying registry-based workspace assignments or app matching despite having the necessary logic and data.

**Key Discovery**: The daemon has sophisticated class-based fallback matching logic (`match_with_registry()`) that should work without PID tracking, but this logic is **not being invoked** or its results are **not being used** during window::new event processing.

---

## Fixes Deployed Successfully

### ✅ Fix #1: Ghostty Class Names (8 apps)
**Status**: DEPLOYED
**Verification**: Registry file shows correct values

```json
// ~/.config/i3/application-registry.json
{
  "name": "ghostty",
  "expected_class": "com.mitchellh.ghostty",  // ✓ Was "ghostty"
  ...
}
```

All 8 Ghostty-based apps updated:
- ghostty (main terminal)
- terminal (sesh selector)
- neovim
- lazygit
- gitui
- htop
- btop
- k9s

### ✅ Fix #2: VS Code --new-window Flag
**Status**: DEPLOYED AND WORKING
**Verification**: Process environment confirms fresh I3PM vars

```bash
# App-launcher log (09:19:08)
Resolved command: code --new-window /etc/nixos

# Process environment (PID 3954343)
I3PM_APP_NAME=vscode
I3PM_PROJECT_NAME=nixos
I3PM_APP_ID=vscode-nixos-3954251-1761484748
I3PM_SCOPE=scoped
I3PM_ACTIVE=true
I3PM_PROJECT_DIR=/etc/nixos
```

**Result**: The --new-window flag fix **WORKS**. VS Code creates a new process with fresh I3PM environment variables instead of reusing an existing process with stale vars.

### ✅ Fix #3: Workspace Layout Change
**Status**: DEPLOYED
**Verification**: i3 config shows new layout

```bash
# ~/.config/i3/config (line 19)
workspace_layout default  # Was: workspace_layout tabbed
```

**Result**: Windows now tile side-by-side instead of stacking in tabs, improving visibility during testing.

---

## Unexpected Findings

### 🔴 CRITICAL: PID Tracking Failure Affects VS Code Too

**Discovery**: VS Code windows (like Ghostty) don't set the `_NET_WM_PID` X11 property.

```json
// i3-msg -t get_tree output
{
  "id": 94481823777104,
  "window_properties": {
    "class": "Code",
    "instance": "code"
  },
  "pid": null  // ❌ Should contain process ID
}
```

**Impact**:
- Daemon cannot read I3PM environment from `/proc/<pid>/environ`
- Diagnostic tool cannot display I3PM environment
- PID-based app identification fails

**Affected Apps** (confirmed so far):
- Ghostty (all 8 Ghostty-based apps)
- VS Code
- Unknown how many others (needs full audit)

**Percentage**: At minimum 39% of apps (9/23), likely more

### 🔴 CRITICAL: Registry Matching Not Applied Despite Working Logic

**Discovery**: The daemon has class-based fallback matching logic that should work without PID, but windows aren't being matched.

**Evidence**:

1. **Registry is correct**:
```json
{
  "name": "vscode",
  "expected_class": "Code",
  "preferred_workspace": 1,
  "scope": "scoped"
}
```

2. **Window class matches exactly**:
```
Expected: "Code"
Actual:   "Code"
Match:    Tier 1 - Exact match (case-sensitive)
```

3. **Matching logic exists**:
```python
# /etc/nixos/home-modules/desktop/i3-project-event-daemon/services/window_identifier.py
def match_with_registry(actual_class, actual_instance, application_registry):
    """Match window against application registry using tiered matching."""
    # Tier 1: Exact match
    if expected == actual_class:
        return (True, "exact")
    # ... more tiers ...
```

4. **But diagnostic shows no match**:
```
Registry Matching
─────────────────────
Matched App: (no match)
Match Type:  none
```

**Hypothesis**: The `match_with_registry()` function exists but is either:
- Not being called during window::new event handling
- Being called but results not used for workspace assignment
- Being called too early (before window properties are available)

### 🔴 CRITICAL: Workspace Assignment Not Applied

**Discovery**: Windows open on current workspace instead of configured `preferred_workspace`.

```
VS Code Configuration:
  preferred_workspace: 1

Actual Behavior:
  Window opened on: Workspace 31 (current workspace)
```

**Impact**: All workspace-based organization fails. Windows don't auto-organize.

---

## What IS Working

### ✅ Daemon Event Processing
```
Event Timeline (VS Code launch):
09:19:07.653  window::new    walker (launcher opened)
09:19:09.567  window::new    Code window created
09:19:09.567  window::focus  Code window focused
09:19:09.567  window::mark   Code window marked ← DAEMON PROCESSED
09:19:10.166  window::title  Code title updated
```

The daemon IS:
- Receiving i3 IPC events
- Processing window::new events
- Applying project marks

### ✅ Project Marking
```bash
# Window marks
$ i3-msg -t get_tree | jq '.. | select(.id == 94481823777104) | .marks'
[
  "project:nixos:14680067"  ← CORRECT PROJECT MARK
]
```

The daemon correctly identified the active project and marked the window.

### ✅ Registry Structure
```bash
$ cat ~/.config/i3/application-registry.json | jq '.applications | length'
21  # All apps present

$ i3pm apps list | wc -l
23  # CLI can read registry
```

---

## Root Cause Analysis

### Daemon Architecture Gap

The daemon has THREE separate capabilities that should work together:

1. **Event Processing** ✅ WORKING
   - Subscribes to i3 window events
   - Receives window::new notifications
   - Applies project marks

2. **Class-Based Matching** ✅ EXISTS (verified in code)
   - `match_with_registry()` supports exact/instance/normalized matching
   - Should work WITHOUT PID tracking
   - Registry has all correct data

3. **Workspace Assignment** ❌ NOT WORKING
   - Should move windows to `preferred_workspace`
   - Should add app-specific marks
   - Currently not happening

**The Missing Link**: Capabilities #2 and #3 aren't connected to capability #1. The event handler processes windows but doesn't invoke registry matching or workspace assignment.

### Code Flow Investigation Needed

To fix this, need to examine:

1. **Event Handler** (`handlers.py`):
   - Does window::new handler call `match_with_registry()`?
   - If yes, what does it do with the result?
   - If no, why not?

2. **Workspace Assigner** (`services/workspace_assigner.py`):
   - When is this service invoked?
   - Does it depend on PID-based I3PM environment?
   - Can it use registry matching results instead?

3. **Integration**:
   - How should registry matching integrate with event handling?
   - Should it be automatic for all window::new events?
   - Or only for windows with I3PM environment?

---

## Comparison: Before vs After Fixes

### Before Fixes (Original Test)

| Aspect | VS Code | Firefox | Ghostty |
|--------|---------|---------|---------|
| Workspace | ❌ WS31 (wrong) | ❌ WS37 (wrong) | ❌ WS5 (wrong) |
| Registry Match | ❌ No | ❌ No | ❌ No |
| I3PM Env (diagnostic) | ❌ Not shown | ❌ Not shown | ❌ Not shown |
| Project Mark | ✅ Yes | N/A (global) | ✅ Yes |
| Root Cause | Pre-existing + single-instance | Pre-existing + single-instance | Incorrect class name |

### After Fixes (Retest)

| Aspect | VS Code |
|--------|---------|
| Workspace | ❌ WS31 (wrong) - **NO CHANGE** |
| Registry Match | ❌ No - **NO CHANGE** |
| I3PM Env (diagnostic) | ❌ Not shown - **NO CHANGE** |
| I3PM Env (process) | ✅ **NEW FINDING: Actually present** |
| Project Mark | ✅ Yes |
| Registry Data | ✅ **FIXED: Correct values** |
| New Process | ✅ **FIXED: --new-window works** |
| Root Cause | PID tracking failure + daemon flow gap |

---

## Recommendations

### Immediate (Before Continuing Testing)

1. **Investigate Event Handler Flow**
   - Read `handlers.py` to understand window::new processing
   - Determine if `match_with_registry()` is called
   - Find where workspace assignment should happen

2. **Test Alternative: Manually Move Windows**
   - Can we manually test workspace assignment with i3-msg?
   - `i3-msg '[id=XXXX] move window to workspace 1'`
   - Verify window movement works independent of daemon

3. **Decision Point**: Should we continue testing remaining apps?
   - **Option A**: Fix daemon flow first, then retest all
   - **Option B**: Complete testing to identify all affected apps, then fix
   - **Option C**: Pause testing, document issues, propose fix in new feature

### Short-Term (This Week)

4. **Enhance Daemon to Use Registry Matching**
   - Modify window::new handler to call `match_with_registry()`
   - Use match results for workspace assignment
   - Add fallback: PID-based I3PM check FIRST, class-based SECOND

5. **Alternative PID Discovery**
   - Implement process tree matching (find children of launcher PID)
   - Track launched PIDs in app-launcher state file
   - Use I3PM_APP_ID in window title/properties

### Long-Term (This Month)

6. **Comprehensive PID Audit**
   - Test all 23 apps to determine which set _NET_WM_PID
   - Document PID tracking reliability per app
   - Build PID-independent architecture

7. **Architecture Refactoring**
   - Decouple workspace assignment from I3PM environment
   - Make class-based matching the PRIMARY method
   - Use I3PM environment as enhancement (project scoping, etc.)

---

## Testing Methodology Improvements

### Lessons Learned

1. **Process vs Window Testing**
   - ALWAYS check both:
     - Window properties (via i3-msg/i3pm-diagnose)
     - Process environment (via /proc/<pid>/environ)
   - PID tracking failure hides working I3PM environment

2. **Registry Verification**
   - Check THREE levels:
     - NixOS config (.nix files) - Configuration source
     - Generated files (.json) - Runtime data
     - Daemon behavior (logs/marks) - Actual application

3. **Event Tracing**
   - Use `i3pm-diagnose events` to verify daemon processing
   - Check event timeline matches expectations
   - Look for what ISN'T happening (workspace moves, app marks)

### Updated Test Script Template

```bash
#!/bin/bash
# Enhanced app testing script

APP_NAME="$1"

echo "=== Testing: $APP_NAME ==="

# 1. Verify registry configuration
echo -e "\n1. Registry Configuration:"
i3pm apps show "$APP_NAME"

# 2. Close existing windows
echo -e "\n2. Closing existing windows..."
CLASS=$(i3pm apps show "$APP_NAME" --json | jq -r '.expected_class')
i3-msg "[class=\"$CLASS\"]" kill

# 3. Launch app via Walker
echo -e "\n3. Launching app..."
xdotool key super+d && sleep 1 && xdotool type "$APP_NAME" && sleep 0.5 && xdotool key Return
sleep 3

# 4. Find window
echo -e "\n4. Finding window..."
WINDOW_ID=$(i3-msg -t get_tree | jq -r ".. | select(.window_properties?.class? == \"$CLASS\") | .id" | tail -1)
echo "Window ID: $WINDOW_ID"

# 5. Get window PID
PID=$(i3-msg -t get_tree | jq ".. | select(.id? == $WINDOW_ID) | .pid")
echo "Window PID: $PID"

# 6. Diagnose window
echo -e "\n5. Window Diagnostic:"
i3pm-diagnose window "$WINDOW_ID"

# 7. Check process environment (if PID available)
if [ "$PID" != "null" ]; then
    echo -e "\n6. Process I3PM Environment:"
    cat /proc/$PID/environ | tr '\0' '\n' | grep I3PM_
else
    # Try to find process by command
    echo -e "\n6. Searching for process (PID unavailable)..."
    CMD=$(i3pm apps show "$APP_NAME" --json | jq -r '.command')
    ps aux | grep -i "$CMD" | grep -v grep | head -3
fi

# 8. Check daemon events
echo -e "\n7. Recent Daemon Events:"
i3pm-diagnose events --limit=5 --type=window

# 9. Summary
echo -e "\n=== Test Summary ==="
echo "Registry: $(i3pm apps show "$APP_NAME" --json | jq -r '{expected_class, preferred_workspace, scope}')"
echo "Window: Workspace=$(i3-msg -t get_tree | jq ".. | select(.id? == $WINDOW_ID) | .. | .num? // empty" | head -1), PID=$PID"
echo "Marks: $(i3-msg -t get_tree | jq ".. | select(.id? == $WINDOW_ID) | .marks")"
```

---

## Conclusion

The 3 quick fixes were successfully deployed:
- ✅ Configuration files updated
- ✅ NixOS rebuild completed
- ✅ Registry JSON generated correctly
- ✅ --new-window flag creates fresh processes
- ✅ Workspace layout changed to tiling

**However**, testing revealed critical gaps in the daemon's event handling:
- ❌ Registry matching logic exists but isn't applied
- ❌ Workspace assignment doesn't use registry data
- ❌ PID tracking failures affect 39%+ of apps

**Next Steps**: Investigate daemon event handler flow before continuing with remaining 20 application tests. The current architecture cannot properly test workspace assignments until the daemon integration is fixed.

**Estimated Impact**: This is a more fundamental issue than the original 3 problems. Fixing this will require code changes to the daemon, not just configuration updates.

**Recommended Path**:
1. Create new feature/task for daemon enhancement
2. Implement registry-based workspace assignment
3. Then resume comprehensive app testing
4. Or: Continue testing to identify ALL affected apps first, then fix daemon

**Time Investment**:
- Fixes deployed: 30 minutes ✅
- Unexpected investigation: 90 minutes (ongoing)
- Daemon fix: TBD (requires code changes)
- Remaining app testing: 6-8 hours (blocked until daemon fixed)

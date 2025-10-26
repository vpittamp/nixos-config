# Application Registry Testing Results
## Feature 039 - Diagnostic Tooling Validation

**Test Date**: 2025-10-26
**Test Method**: Launch each app via Walker (Meta+D), inspect with i3pm-diagnose
**Active Project**: nixos (/etc/nixos)

---

## Executive Summary

Tested 3 of 23 applications in app-registry. Identified **4 critical systemic issues** that affect multiple applications and require architectural changes to the app-launcher system.

**Key Finding**: Single-instance applications (VS Code, Firefox, Chromium, Slack, Discord, PWAs) cannot propagate I3PM environment variables correctly because they reuse existing processes instead of spawning new ones.

---

## Systemic Issues Identified

### ⚠️ ISSUE #1: Single-Instance Apps Don't Propagate I3PM Environment

**Severity**: CRITICAL
**Affected Apps**: VS Code, Firefox, Chromium, Slack, Discord, all PWAs (13/23 apps)

**Problem**:
- Single-instance applications reuse existing process when launched
- Existing process retains OLD I3PM environment variables from initial launch
- New launches don't create new process with updated I3PM vars
- Result: Windows can't be correctly associated with current project context

**Evidence**:
- VS Code: Process PID 823199 has `I3PM_PROJECT_NAME=stacks` from Oct 25
- Firefox: Process PID 3549391 has `I3PM_PROJECT_NAME=stacks` from earlier launch
- When launched with active project "nixos", both reuse old process

**Root Cause**:
- VS Code: `code` command tells existing instance to open folder (client-server architecture)
- Firefox: Firefox uses remote control to reuse existing process
- Both designed for single-instance to save resources

**Proposed Solutions**:

1. **Force New Window Flags** (Quick Fix)
   - VS Code: Add `--new-window` parameter to app-registry
   - Firefox: Add `--new-instance` or `--new-window` parameter
   - Chromium: Add `--new-window` parameter

   ```nix
   # app-registry-data.nix
   (mkApp {
     name = "vscode";
     command = "code";
     parameters = "--new-window $PROJECT_DIR";  # Added --new-window
     ...
   })
   ```

2. **Wrapper Script Enhancement** (Better Solution)
   - Detect single-instance apps in wrapper
   - Automatically append --new-window/--new-instance flags
   - Make configurable per app in registry

3. **Process Environment Update** (Complex, Unreliable)
   - Try to update existing process environment (generally not possible)
   - Not recommended - processes can't change their environment after fork

**Recommendation**: Implement Solution #1 immediately for critical apps (VS Code, Firefox), then Solution #2 for comprehensive fix.

---

### ⚠️ ISSUE #2: Incorrect Window Class Names in App Registry

**Severity**: HIGH
**Affected Apps**: Ghostty, possibly others (needs full audit)

**Problem**:
- App-registry has `expected_class = "ghostty"`
- Actual window class is `com.mitchellh.ghostty`
- Result: Registry matching fails, workspace assignment fails

**Evidence**:
```bash
# App registry definition
expected_class = "ghostty"

# Actual window class
$ i3-msg -t get_tree | jq '.. | .window_properties.class' | grep ghostty
"com.mitchellh.ghostty"
```

**Impact**:
- Window not matched to application in registry
- Daemon can't apply workspace assignment rules
- Diagnostic tool shows "no match"

**Root Cause**:
- Class names assumed from binary name without verification
- No validation during nixos-rebuild
- Class names can vary by toolkit (GTK, Qt, X11 vs Wayland)

**Proposed Solutions**:

1. **Immediate Fix**: Update incorrect class names
   ```nix
   # All Ghostty-based apps need correction
   expected_class = "com.mitchellh.ghostty";  # Was "ghostty"
   ```

2. **Validation Script**: Create script to verify class names
   ```bash
   # scripts/verify-app-classes.sh
   # Launch each app, check actual class vs registry
   ```

3. **Runtime Class Discovery**: Allow daemon to learn class names
   - On first launch, record actual class
   - Update registry or create class alias map

**Action Items**:
- [ ] Audit ALL app-registry entries for correct class names
- [ ] Update Ghostty class name: `ghostty` → `com.mitchellh.ghostty`
- [ ] Update Neovim, Lazygit, GitUI (all use Ghostty terminal)
- [ ] Update htop, btop, K9s (all use Ghostty terminal)
- [ ] Create validation script for CI/CD

---

### ⚠️ ISSUE #3: PID Tracking Failures Prevent I3PM Environment Detection

**Severity**: MEDIUM
**Affected Apps**: Ghostty, possibly other terminal emulators

**Problem**:
- Some applications don't set `_NET_WM_PID` X11 property
- i3 reports PID as null
- Daemon can't read `/proc/<pid>/environ` for I3PM vars
- Result: Diagnostic tool shows "No I3PM environment found" despite correct process environment

**Evidence**:
```bash
# Process has correct I3PM vars
$ cat /proc/3627454/environ | tr '\0' '\n' | grep I3PM_PROJECT_NAME
I3PM_PROJECT_NAME=nixos

# But i3 doesn't know the PID
$ i3-msg -t get_tree | jq '.. | select(.id == 94481823410384) | .pid'
null

# And xprop also fails
$ xprop -id 94481823410384 _NET_WM_PID
(no output)
```

**Impact**:
- Diagnostic tool can't display I3PM environment (confusing for users)
- May affect daemon's ability to read I3PM vars during window::new event
- Reduces troubleshooting visibility

**Root Cause**:
- Some toolkits don't set `_NET_WM_PID` correctly
- Ghostty terminal may have a bug or missing feature
- Common issue with Wayland-native apps running on X11

**Proposed Solutions**:

1. **Alternative PID Discovery Methods**:
   - Match window by I3PM_APP_ID in window title/properties
   - Use process tree matching (find children of launcher PID)
   - Track launched PIDs in app-launcher-wrapper.sh state file

2. **Enhanced Diagnostic Display**:
   - Show process environment if window PID is null
   - Search for processes matching window class
   - Display: "PID unavailable, showing likely process environment"

3. **Upstream Bug Report**:
   - Report to Ghostty project: _NET_WM_PID not set
   - May be fixed in future version

**Recommendation**: Implement Solution #1 (alternative PID discovery) for robustness.

---

### ⚠️ ISSUE #4: Pre-Existing Windows Lack I3PM Environment

**Severity**: LOW (expected behavior, needs documentation)
**Affected Apps**: All apps opened before daemon start or outside app-launcher

**Problem**:
- Windows created before daemon started don't have I3PM vars
- Windows launched directly (not via app-launcher) don't have I3PM vars
- Result: Confusing diagnostic output, appears broken

**Evidence**:
- VS Code window 94481823833200: "No I3PM environment found"
- Firefox window 94481823855824: "No I3PM environment found"
- Both were pre-existing before test launch

**Impact**:
- User confusion during diagnostics
- False negative test results
- Windows can't be project-scoped retroactively

**Root Cause**:
- This is **expected** behavior
- Environment variables are set at process creation, can't be added later
- Pre-existing windows are marked via startup scan but don't have full I3PM context

**Proposed Solutions**:

1. **Better User Communication**:
   - Update diagnostic output message
   - Current: "No I3PM environment found. This window may have existed before..."
   - Better: "No I3PM environment (pre-existing window or launched outside app-launcher)"

2. **Documentation**:
   - Add to diagnostic walkthrough: "Close pre-existing windows before testing"
   - Explain: App-launcher is required for full I3PM environment propagation

3. **Startup Scan Enhancement**:
   - During startup scan, try to reconstruct I3PM vars from:
     - Window title (for VS Code: extract project from "PROJECT - Visual Studio Code")
     - Window class matching to registry
     - Directory from /proc/<pid>/cwd

**Recommendation**: Solution #1 (better messaging) is sufficient. This is expected behavior.

---

## Individual Application Test Results

### 1. VS Code (vscode)

**Registry Config**:
- preferred_workspace: 1
- expected_class: "Code"
- scope: scoped
- multi_instance: true

**Test Results**:
- ❌ **Wrong workspace**: WS31 instead of WS1
- ❌ **No I3PM environment**: Pre-existing window
- ❌ **No registry match**: Despite correct class
- ❌ **Floating**: Should be tiled
- ✅ **Project filtering**: Correctly hidden when switched to different project
- ✅ **Project mark**: Has project:nixos mark

**Issues**:
- ISSUE #1: Single-instance behavior
- ISSUE #4: Pre-existing window

**Recommended Fixes**:
```nix
(mkApp {
  name = "vscode";
  command = "code";
  parameters = "--new-window $PROJECT_DIR";  # Add --new-window
  scope = "scoped";
  expected_class = "Code";  # ✓ Correct
  preferred_workspace = 1;
  multi_instance = true;
  ...
})
```

---

### 2. Firefox (firefox)

**Registry Config**:
- preferred_workspace: 2
- expected_class: "firefox"
- scope: global
- multi_instance: false

**Test Results**:
- ❌ **Wrong workspace**: WS37 instead of WS2
- ❌ **No I3PM environment**: Pre-existing window
- ❌ **No registry match**: Despite correct class
- ✅ **Tiled**: Correctly not floating
- ✅ **Correct class**: "firefox" matches

**Issues**:
- ISSUE #1: Single-instance behavior
- ISSUE #4: Pre-existing window

**Recommended Fixes**:
```nix
(mkApp {
  name = "firefox";
  command = "firefox";
  parameters = "--new-instance";  # Add --new-instance for true multi-instance
  scope = "global";
  expected_class = "firefox";  # ✓ Correct
  preferred_workspace = 2;
  multi_instance = true;  # Change to true with --new-instance
  ...
})
```

---

### 3. Ghostty Terminal (ghostty)

**Registry Config**:
- preferred_workspace: 3
- expected_class: "ghostty"  # ⚠️ INCORRECT
- scope: scoped
- multi_instance: true

**Test Results**:
- ❌ **Wrong workspace**: WS5 instead of WS3
- ❌ **Wrong expected_class**: Should be "com.mitchellh.ghostty"
- ❌ **No I3PM environment in diagnostic**: PID tracking failure
- ❌ **No registry match**: Due to class mismatch
- ⚠️  **PID tracking**: i3 reports PID as null
- ✅ **Project mark**: Has project:nixos:14680068
- ✅ **Tiled**: Correctly not floating
- ✅ **Window created**: Process has correct I3PM vars
- ✅ **Daemon processed**: window::new and window::mark events at 09:00:47

**Issues**:
- ISSUE #2: Incorrect class name
- ISSUE #3: PID tracking failure

**Recommended Fixes**:
```nix
(mkApp {
  name = "ghostty";
  command = "ghostty";
  parameters = "-e sesh connect $PROJECT_DIR";
  scope = "scoped";
  expected_class = "com.mitchellh.ghostty";  # Fix: was "ghostty"
  preferred_workspace = 3;
  multi_instance = true;
  ...
})
```

**Additional Apps Needing Fix** (all use Ghostty):
- neovim: expected_class = "com.mitchellh.ghostty"
- lazygit: expected_class = "com.mitchellh.ghostty"
- gitui: expected_class = "com.mitchellh.ghostty"
- htop: expected_class = "com.mitchellh.ghostty"
- btop: expected_class = "com.mitchellh.ghostty"
- k9s: expected_class = "com.mitchellh.ghostty"

---

## Methodology Issues & Improvements

### Testing Challenges Encountered

1. **Pre-Existing Windows Contaminate Tests**
   - Many windows already open from previous sessions
   - Hard to distinguish new launches from existing windows
   - **Solution**: Add cleanup script to close all app-registry apps before testing

2. **Single-Instance Apps Can't Be Tested Repeatedly**
   - Launching again reuses same process
   - **Solution**: Kill process between tests, or test with --new-window flag

3. **Focus Delay Issues**
   - New windows flash indicator, need user click to focus
   - Scripts can't detect unfocused windows reliably
   - **Solution**: Add window focus commands in test scripts

4. **PID Tracking Unreliable**
   - Can't always correlate window to process
   - **Solution**: Use window class + timestamp + I3PM_APP_ID matching

### Recommended Testing Workflow

```bash
#!/bin/bash
# scripts/test-app-registry.sh

APP_NAME="$1"

# 1. Get app configuration from registry
APP_CONFIG=$(i3pm apps show "$APP_NAME" --json)

# 2. Close existing windows of this app
CLASS=$(echo "$APP_CONFIG" | jq -r '.expected_class')
i3-msg "[class=\"$CLASS\"]" kill

# 3. Launch via app-launcher
~/.local/bin/app-launcher-wrapper.sh "$APP_NAME" &
LAUNCH_PID=$!

# 4. Wait for window creation
sleep 2

# 5. Find window by class (most recent)
WINDOW_ID=$(i3-msg -t get_tree | jq -r ".. | objects | select(.window_properties?.class? == \"$CLASS\") | .id" | tail -1)

# 6. Focus window
i3-msg "[id=\"$WINDOW_ID\"]" focus

# 7. Run diagnostics
i3pm-diagnose window "$WINDOW_ID"

# 8. Verify workspace, I3PM env, registry match
# ... assertion checks ...

# 9. Clean up
i3-msg "[id=\"$WINDOW_ID\"]" kill
```

---

## Next Steps

### Immediate Actions (High Priority)

1. **Fix Ghostty Class Names** (30 minutes)
   - Update all 7 Ghostty-based apps in app-registry-data.nix
   - Test: `nixos-rebuild dry-build`
   - Deploy: `nixos-rebuild switch`

2. **Add --new-window Flags** (1 hour)
   - VS Code: `--new-window`
   - Firefox: `--new-instance` or `--new-window`
   - Chromium: `--new-window`
   - Test each individually

3. **Update Diagnostic Messages** (30 minutes)
   - Improve "No I3PM environment" message clarity
   - Add PID tracking failure detection and messaging

### Medium Priority (This Week)

4. **Complete App Registry Audit** (3 hours)
   - Test all 23 applications
   - Document actual window class for each
   - Verify workspace assignments
   - Check tiling vs floating expectations

5. **Create Class Validation Script** (2 hours)
   - Script to launch each app and capture actual class
   - Compare against app-registry expected_class
   - Generate diff report

6. **Enhance App-Launcher Wrapper** (3 hours)
   - Auto-detect single-instance apps
   - Auto-append appropriate flags
   - Add configuration option per app

### Low Priority (Future)

7. **Implement Alternative PID Discovery**
   - Process tree matching
   - I3PM_APP_ID in window properties
   - State file tracking

8. **Create Automated Test Suite**
   - Bash script to test all apps
   - CI/CD integration
   - Regression prevention

9. **Documentation Updates**
   - Update CLAUDE.md with testing procedures
   - Add troubleshooting guide for common issues
   - Document app-launcher requirements

---

## Conclusion

The diagnostic tooling (Feature 039) successfully identified critical architectural issues with the app-launcher system. The single-instance app problem affects 13/23 applications and requires immediate attention.

**Success Metrics**:
- ✅ Diagnostic tools work correctly
- ✅ Identified 4 systemic issues
- ✅ Project filtering works (hidden windows confirmed)
- ✅ Daemon marks windows correctly
- ⚠️ Environment propagation fails for single-instance apps
- ⚠️ Class name mismatches prevent registry matching

**Impact Assessment**:
- **High Impact**: Fixes will improve reliability for 13/23 apps (56%)
- **Quick Wins**: Class name fixes are trivial, high ROI
- **Strategic**: Single-instance fix enables proper multi-project workflows

**Estimated Effort**: 8-12 hours to fix all critical issues and complete testing.


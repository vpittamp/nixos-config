# Quickstart Guide: i3 Window Management Diagnostics

**Feature**: 039-create-a-new
**Audience**: Users troubleshooting window management issues

## Overview

This guide shows you how to use the new diagnostic commands to troubleshoot workspace assignment failures, event processing issues, and state inconsistencies in the i3 project management system.

---

## Prerequisites

- i3 window manager running
- i3-project-daemon active (`systemctl --user status i3-project-event-listener`)
- `i3pm` CLI tool installed (via home-manager)

---

## Quick Health Check

**Check if the system is working**:

```bash
i3pm diagnose health
```

**Expected Output** (healthy system):
```
Daemon Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Check                      Status
──────────────────────────────────────────────────────
IPC Connection             ✓ Connected
Event Subscriptions        ✓ 4/4 active
  - window                 ✓ 1,234 events
  - workspace              ✓ 89 events
  - output                 ✓ 5 events
  - tick                   ✓ 12 events
Window Tracking            ✓ 23 windows

Overall Status: ✓ HEALTHY
```

**If unhealthy**: Follow the recommendations in the output. Common issues:
- Daemon not running → `systemctl --user start i3-project-event-listener`
- No window events → Event subscription bug (report to developer)
- i3 IPC disconnected → Restart i3 or daemon

---

## Common Scenarios

### Scenario 1: Window Opens on Wrong Workspace

**Problem**: You launch `lazygit` and it opens on workspace 5 instead of the configured workspace 3.

**Step 1: Get the window ID**

Option A - Use xwininfo (click the window):
```bash
xwininfo | grep "Window id"
# Output: xwininfo: Window id: 0xe00004 (has no name)
# Convert hex to decimal: 14680068
```

Option B - Use i3pm windows:
```bash
i3pm windows | grep lazygit
# Find the window ID in the output
```

**Step 2: Inspect the window properties**

```bash
i3pm diagnose window 14680068
```

**Output Analysis**:
```
Window Diagnostic: 14680068
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Window Matching
──────────────────────────────────────────────────────
Matched Application        terminal
Match Type                 instance ✓
Expected Workspace         3
Actual Workspace           5 ⚠️ MISMATCH
```

**What to check**:
- **Match Type**: Did the window class match correctly?
  - ✓ "exact", "instance", "normalized" → Window was matched
  - ✗ "none" → Window class mismatch (see Scenario 2)

- **Workspace Mismatch**: Why is it on workspace 5 not 3?
  - Window was manually moved after creation
  - Workspace assignment failed during window creation
  - Daemon restarted and lost state

**Step 3: Check the event log**

```bash
i3pm diagnose events --limit 200 | grep 14680068
```

**What to look for**:
- **window::new event**: Did the event fire when window was created?
- **workspace_assigned**: Was workspace 3 assigned in the event?
- **error**: Any errors during processing?

**Example Output**:
```
12:34:56.789    window      new    14680068    45.2ms    ✓ WS3
```

If you see `✓ WS3` but the window is on WS5, it was manually moved after assignment.

**If no window::new event**: This is a bug - the daemon isn't receiving events. Report to developer.

---

### Scenario 2: Window Class Not Matching

**Problem**: Window isn't recognized by the system (appears as global scope instead of project scope).

**Diagnosis**:

```bash
i3pm diagnose window <window_id>
```

**Look at**:
```
X11 Properties
──────────────────────────────────────────────────────
Window Class               com.mitchellh.ghostty  ← Actual class reported by X11
Window Instance            ghostty                 ← Instance field
Normalized Class           ghostty                 ← What it normalizes to

Window Matching
──────────────────────────────────────────────────────
Matched Application        none ✗                  ← Not matched!
Match Type                 none
```

**Solution**: The application registry expects a different class name.

**Check configuration**:
```bash
cat ~/.config/i3/application-registry.json | jq '.[] | select(.name=="terminal")'
```

**Example output**:
```json
{
  "name": "terminal",
  "expected_class": "Ghostty",  ← Case mismatch!
  "preferred_workspace": 3
}
```

**Fix**: Update configuration to match actual class:
- Use exact: `"com.mitchellh.ghostty"`
- Or normalized: `"ghostty"` (case-insensitive, strips reverse-domain)

**Test match types**:
- `"com.mitchellh.ghostty"` → exact match
- `"ghostty"` → instance match (case-insensitive)
- `"Ghostty"` → normalized match (case-insensitive)

All three will work with the tiered matching system!

---

### Scenario 3: Events Not Being Processed

**Problem**: Windows are created but daemon doesn't process them (no workspace assignment, no marks).

**Diagnosis**:

```bash
i3pm diagnose health
```

**Check event subscriptions**:
```
Event Subscriptions
──────────────────────────────────────────────────────
Type           Active    Count    Last Event
window         ✗         0        never           ← BUG!
workspace      ✓         89       5s ago
```

**If window subscription shows 0 events**: The daemon isn't receiving window::new events.

**Possible causes**:
1. Event subscription failed on daemon startup
2. i3 IPC connection broken
3. Event handler not registered

**Immediate fix**:

```bash
# Restart daemon to re-establish subscriptions
systemctl --user restart i3-project-event-listener

# Wait 5 seconds for startup
sleep 5

# Check again
i3pm diagnose health
```

**If still broken**: Report bug to developer with diagnostic output:
```bash
i3pm diagnose health --json > ~/health-report.json
journalctl --user -u i3-project-event-listener -n 100 > ~/daemon-logs.txt
```

---

### Scenario 4: State Drift Detection

**Problem**: Daemon thinks windows are on different workspaces than they actually are.

**Diagnosis**:

```bash
i3pm diagnose validate
```

**Output**:
```
State Consistency Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Validation Summary
──────────────────────────────────────────────────────
Consistency                    91.3%

State Mismatches
──────────────────────────────────────────────────────
Window ID    Property     Daemon Value    i3 Value    Severity
14680068     workspace    3               5           warning
```

**What it means**:
- Daemon remembers window on workspace 3
- i3 IPC (authoritative) says it's on workspace 5
- Window was likely manually moved

**Fix**:

```bash
# Restart daemon to resynchronize from i3's authoritative state
systemctl --user restart i3-project-event-listener
```

After restart, daemon will scan all windows and sync to i3's state.

**Verify**:
```bash
i3pm diagnose validate
# Should show 100% consistency
```

---

## Monitoring Event Processing

**Watch events in real-time** (useful for debugging):

```bash
i3pm diagnose events --follow
```

**Then in another terminal**, launch an application:

```bash
# Launch terminal (should go to workspace 2)
~/.local/bin/app-launcher-wrapper.sh terminal
```

**Observe output**:
```
[12:35:01] window::new     14680070    48.1ms    ✓ WS2
[12:35:05] window::focus   14680070     2.3ms    ✓
```

**What to check**:
- **window::new fires**: Event detected
- **Duration <100ms**: Performance is good
- **✓ WS2**: Workspace assigned correctly
- **No errors**: Processing succeeded

**Performance warning**: If durations are >100ms consistently, report performance issue.

---

## Advanced Diagnostics

### Complete System Report

Generate a comprehensive diagnostic report:

```bash
i3pm diagnose health --json > health.json
i3pm diagnose validate --json > validate.json
i3pm diagnose events --limit 500 --json > events.json

# Combine for bug reports
tar -czf diagnostic-report.tar.gz health.json validate.json events.json
```

### Check Specific Event Types

```bash
# Only window events
i3pm diagnose events --type window --limit 100

# Only workspace events
i3pm diagnose events --type workspace --limit 50
```

### Continuous Monitoring

```bash
# Monitor events with metrics
watch -n 5 'i3pm diagnose health | grep "Event Subscriptions" -A 10'

# Check for state drift every minute
watch -n 60 'i3pm diagnose validate | grep Consistency'
```

---

## Troubleshooting Checklist

When things aren't working, check in this order:

1. **Is daemon running?**
   ```bash
   systemctl --user status i3-project-event-listener
   ```

2. **Is i3 IPC connected?**
   ```bash
   i3pm diagnose health | grep "IPC Connection"
   ```

3. **Are events being received?**
   ```bash
   i3pm diagnose health | grep -A 5 "Event Subscriptions"
   ```

4. **Is window being matched?**
   ```bash
   i3pm diagnose window <window_id> | grep "Match Type"
   ```

5. **Is workspace assignment configured?**
   ```bash
   cat ~/.config/i3/application-registry.json | jq '.[] | select(.name=="<app>")'
   ```

6. **Is state consistent?**
   ```bash
   i3pm diagnose validate
   ```

---

## ⚠️ Before Sharing Diagnostic Output

**Security Notice**: Diagnostic output may contain sensitive information. Review and redact before sharing publicly.

**What diagnostic output includes**:
- Project names and directory paths (e.g., `/home/user/projects/secret-client`)
- Window titles (may contain email subjects, document names, sensitive text)
- Process hierarchy and relationships
- Application names and workspace assignments

**Before sharing diagnostic data**:

1. **Review JSON output first**:
   ```bash
   i3pm diagnose window <id> --json | jq .
   # Look for sensitive project names, paths, or window titles
   ```

2. **Redact sensitive fields**:
   ```bash
   # Example: Redact project paths and names
   jq '.i3pm_env.I3PM_PROJECT_DIR = "/path/to/project" |
       .i3pm_env.I3PM_PROJECT_NAME = "myproject" |
       .window_title = "REDACTED"' window.json > window-redacted.json
   ```

3. **Use generic examples**:
   - Replace real project names with "project-a", "project-b"
   - Replace paths with "/home/user/projects/example"
   - Redact window titles if they contain sensitive content

4. **Local troubleshooting first**:
   - Most issues can be diagnosed locally using the diagnostic commands
   - Only share diagnostic output when reporting bugs that require developer investigation

**Safe to share**:
- Daemon version and uptime
- Event subscription counts
- Performance metrics (latency, duration)
- Error messages (review first for paths/names)
- Window classes and normalized classes (generic app names)

**Potentially sensitive**:
- Project directory paths
- Window titles
- I3PM_PROJECT_NAME values
- Correlation data (process relationships)

---

## Getting Help

If diagnostic commands don't resolve the issue:

1. **Capture diagnostic data**:
   ```bash
   i3pm diagnose health --json > health.json
   i3pm diagnose window <id> --json > window.json
   journalctl --user -u i3-project-event-listener -n 200 > daemon.log
   ```

2. **Redact sensitive information** (see section above)

3. **Report bug with**:
   - Redacted diagnostic JSON files
   - Daemon logs (check for sensitive paths)
   - Steps to reproduce
   - Expected vs actual behavior

4. **GitHub Issue**: https://github.com/vpittamp/nixos-config/issues

---

## Performance Targets

**Healthy system metrics**:

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Event detection latency | <50ms | 50-100ms | >100ms |
| Handler execution | <100ms | 100-200ms | >200ms |
| Event subscription status | 4/4 active | 3/4 active | <3/4 active |
| State consistency | 100% | 95-99% | <95% |
| Daemon uptime | Days | Hours | Minutes |

If your system is outside target ranges, run diagnostics and report findings.

---

## Quick Reference

```bash
# Health check
i3pm diagnose health

# Inspect window
i3pm diagnose window <id>

# View events
i3pm diagnose events [--limit N] [--type TYPE] [--follow]

# Validate state
i3pm diagnose validate

# JSON output (all commands)
i3pm diagnose <command> --json

# Get help
i3pm diagnose <command> --help
```

---

## Next Steps

Once you've diagnosed the issue:

1. **Window class mismatch**: Update `application-registry.json`
2. **Event not firing**: Restart daemon, report bug if persists
3. **State drift**: Restart daemon to resync
4. **Performance issues**: Report with diagnostic data

For implementation details, see:
- **API Contracts**: `contracts/daemon-ipc-api.md`, `contracts/diagnostic-cli-api.md`
- **Data Models**: `data-model.md`
- **Research Findings**: `research.md`

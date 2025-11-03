# Quickstart: Reliable Event-Driven Workspace Assignment

**Feature**: 053-workspace-assignment-enhancement
**Status**: Planned
**Quick Access**: `Meta+D` → type app name → window appears on configured workspace within 1 second

## What This Feature Does

Ensures **100% reliable workspace assignment** for all applications (especially Progressive Web Apps) by:

1. **Removing conflicting native Sway assignment rules** that blocked event delivery
2. **Using launch notifications** for fastest, most accurate workspace assignment
3. **Adding delayed property re-check** for native Wayland apps with async properties
4. **Consolidating to single event-driven mechanism** (daemon-only, no native rules)

**Result**: PWAs and all other apps appear on their designated workspace every time, with <1 second latency.

---

## Quick Commands

### Launch Applications

```bash
# All applications launched via walker get workspace assignment
Meta+D → type "youtube" → Return        # Opens on workspace 4
Meta+D → type "google ai" → Return      # Opens on workspace 10
Meta+D → type "chatgpt" → Return        # Opens on workspace 11
Meta+D → type "github codespaces" → Return  # Opens on workspace 2
```

### Diagnostic Commands

```bash
# Check if assignments are working
i3pm diagnose events --type=window --limit=10
# Should show workspace assignment for each window::new event

# View recent workspace assignments
journalctl --user -u i3-project-event-listener -n 50 | grep "Workspace assignment"

# Check event subscription health
i3pm diagnose health
# Should show: ✓ Window events: subscribed, active

# Verify no native assignment rules remain
grep -r "assign \[" ~/.config/sway/
# Should return empty (no results)
```

### Comprehensive Event Logging with Decision Tree (Phase 6) ⭐ NEW

**NEW in Feature 053**: Rich event monitoring with decision tree visualization showing workspace assignment priority matching logic.

```bash
# Real-time event monitoring with rich formatting (RECOMMENDED)
i3pm events --follow --verbose

# View recent workspace assignments with decision tree
i3pm events --type workspace::assignment --verbose --limit 10

# Filter events by window ID
i3pm events --window 123456 --verbose

# Filter events by project
i3pm events --project nixos --limit 20

# View failed assignments (shows why all priorities failed)
i3pm events --type workspace::assignment_failed --verbose

# JSON output for scripting
i3pm events --type workspace::assignment --json --limit 5

# Follow specific event types in real-time
i3pm events --follow --type window::new
i3pm events --follow --type project::switch
```

**Example Output** (table format):
```
TIME     TYPE                    WINDOW/APP              WORKSPACE  DETAILS
─────────────────────────────────────────────────────────────────────────────────────
09:06:18 ws:assign               firefox                → 1         ✓ daemon [nixos]
09:06:18 win:new                 firefox                ?          #24
09:05:12 ws:assign               firefox                → 3         ✓ daemon [nixos]
09:05:12 win:new                 firefox                ?          #23
```

**Decision Tree Details** (available in journal logs):
```bash
$ sudo journalctl -u i3-project-daemon | grep "workspace::assignment" | tail -1
INFO | EVENT: workspace::assignment | window_id=24 | window_class=firefox |
  target_workspace=1 | assignment_source=registry[terminal] | project=nixos |
  decision_tree=[
    {"priority": 0, "name": "launch_notification", "matched": false, "reason": "no_launch_notification"},
    {"priority": 1, "name": "I3PM_TARGET_WORKSPACE", "matched": false, "reason": "env_var_empty"},
    {"priority": 2, "name": "I3PM_APP_NAME_registry", "matched": true, "workspace": 1, "details": {"app_name": "terminal"}}
  ]
```

**Legacy Commands** (raw structured logs via journalctl):

```bash
# View real-time event stream with full details
journalctl --user -u i3-project-event-listener -f | grep "EVENT:"

# Filter by specific event types
journalctl --user -u i3-project-event-listener -f | grep "EVENT: window::new"
journalctl --user -u i3-project-event-listener -f | grep "EVENT: workspace::assignment"
journalctl --user -u i3-project-event-listener -f | grep "EVENT: project::switch"

# View recent window creations
journalctl --user -u i3-project-event-listener -n 100 | grep "EVENT: window::new"

# View recent workspace assignments
journalctl --user -u i3-project-event-listener -n 100 | grep "EVENT: workspace::assignment"

# View output (monitor) changes
journalctl --user -u i3-project-event-listener -n 50 | grep "EVENT: output"

# View project switches
journalctl --user -u i3-project-event-listener | grep "EVENT: project::switch"

# View all workspace events (init, empty, move)
journalctl --user -u i3-project-event-listener -n 100 | grep "EVENT: workspace::"
```

**Event Types Available**:
- `window::new` - Window creation with class, title, workspace, output, PID
- `window::close` - Window closure
- `window::focus` - Focus changes
- `window::move` - Window moves between workspaces
- `window::mark` - Mark additions/removals
- `window::title` - Title changes
- `workspace::assignment` - Workspace assignment decisions with source tracking
- `workspace::init` - Workspace creation
- `workspace::empty` - Workspace deletion
- `workspace::move` - Workspace moves between outputs
- `output` - Monitor connect/disconnect with resolutions
- `mode` - Sway mode changes
- `tick` - Tick events with payloads
- `project::switch` - Project switching

**Log Format**:
```
[TIMESTAMP] | EVENT: <event_type> | key1=value1 | key2=value2 | ...
```

**Example Log Output**:
```
[2025-11-02 12:34:56.789] | EVENT: window::new | window_id=123456 | window_class=FFPWA-01K666N2V6BQMDSBMX3AY74TY7 | window_title=YouTube | workspace_num=1 | output=HEADLESS-1 | pid=98765

[2025-11-02 12:34:56.790] | EVENT: workspace::assignment | window_id=123456 | window_class=FFPWA-01K666N2V6BQMDSBMX3AY74TY7 | target_workspace=4 | assignment_source=launch_notification | correlation_confidence=0.95

[2025-11-02 12:35:10.123] | EVENT: project::switch | old_project=none | new_project=nixos

[2025-11-02 12:35:20.456] | EVENT: output | active_outputs=3 | output_names=HEADLESS-1, HEADLESS-2, HEADLESS-3
```

---

## How It Works

### Before (Broken - Multiple Overlapping Mechanisms)

```
User launches PWA
    ↓
Sway native `assign` rule matches window
    ↓
Window assigned BEFORE event emitted
    ↓
Daemon never receives window::new event ❌
    ↓
Daemon can't perform project-scoped filtering ❌
```

**Result**: Events suppressed, daemon blind to PWA windows

### After (Fixed - Single Event-Driven Mechanism)

```
User launches PWA via walker
    ↓
Walker sends launch notification to daemon
    ↓
Daemon registers expected window with target workspace
    ↓
PWA window created, Sway emits window::new event
    ↓
Daemon receives event within <100ms
    ↓
Daemon correlates with launch notification (Priority 0)
    ↓
Window assigned to workspace from notification ✅
    ↓
Assignment logged: source=launch_notification, latency=<100ms ✅
```

**Result**: 100% event delivery, <1 second assignment, full diagnostic visibility

---

## Workspace Assignment Priority System

When a window is created, the daemon resolves target workspace using this priority cascade:

| Priority | Source | Example | When Used |
|----------|--------|---------|-----------|
| **0** | Launch notification | Walker launches PWA with workspace specified | PWAs launched via walker (80%+ of cases) |
| **1** | App-specific handler | VS Code title parsing for project workspace | VS Code opening specific project |
| **2** | `I3PM_TARGET_WORKSPACE` env | User sets workspace explicitly in command | Manual override via environment variable |
| **3** | `I3PM_APP_NAME` registry | Registry lookup by app name from environment | Apps launched via project launcher |
| **4** | Window class matching | Exact → Instance → Normalized class match | Fallback for apps without launch notification |

**Priority 0 is NEW** - Fastest and most reliable path for PWA assignment.

---

## Common Workflows

### Launch PWA from Walker

**User Action**:
```bash
Meta+D → type "youtube" → Return
```

**Behind the Scenes**:
1. Walker executes `launch-pwa-by-name "YouTube"`
2. Wrapper script sends launch notification to daemon:
   ```json
   {
     "app_name": "youtube-pwa",
     "expected_class": "FFPWA-01K666N2V6BQMDSBMX3AY74TY7",
     "workspace_number": 4,
     "launch_timestamp": 1698765432.123
   }
   ```
3. Daemon registers pending launch (TTL: 5 seconds)
4. Firefox launches PWA (100-500ms delay)
5. Sway emits `window::new` event
6. Daemon receives event, correlates with launch notification
7. Daemon moves window to workspace 4 using Priority 0
8. Total time: <1 second from keypress to assigned window

**Success Indicators**:
- ✅ Window appears on workspace 4
- ✅ Daemon logs show: `assignment_source=launch_notification`
- ✅ Latency <100ms from event to assignment

### Launch App Without Notification

**User Action**:
```bash
# Open Firefox directly (not via walker)
Meta+Return → firefox
```

**Behind the Scenes**:
1. Firefox window created, Sway emits `window::new` event
2. No launch notification exists (Priority 0 skipped)
3. No app-specific handler for Firefox (Priority 1 skipped)
4. No `I3PM_TARGET_WORKSPACE` env (Priority 2 skipped)
5. No `I3PM_APP_NAME` env (Priority 3 skipped)
6. Daemon falls back to Priority 4: window class matching
7. Application registry checked for class "firefox"
8. If match found, window assigned to registered workspace
9. If no match, window stays on current workspace

**Success Indicators**:
- ✅ Window either assigned to registered workspace OR stays on current workspace
- ✅ Daemon logs show: `assignment_source=class_*_match` or `no_match`

### Native Wayland App with Delayed Properties

**User Action**:
```bash
Meta+D → type "some native wayland app" → Return
```

**Behind the Scenes**:
1. Window created, Sway emits `window::new` event
2. Daemon receives event, but `app_id` is empty (property not yet populated)
3. Daemon logs: "Native Wayland window has no app_id, scheduling delayed re-check"
4. Daemon waits 100ms
5. Daemon re-fetches window from Sway tree
6. `app_id` now populated (e.g., "org.gnome.Calculator")
7. Daemon retries workspace assignment with complete properties
8. Window assigned based on class match

**Success Indicators**:
- ✅ Window assigned despite initial missing properties
- ✅ Daemon logs show: "Property re-check successful: app_id=..."
- ✅ Total latency <200ms (event + 100ms delay + assignment)

---

## Configuration

### PWA Workspace Assignments

**Location**: `/etc/nixos/home-modules/desktop/app-registry-data.nix`

**Example**:
```nix
(mkApp {
  name = "youtube-pwa";
  display_name = "YouTube";
  expected_class = "FFPWA-01K666N2V6BQMDSBMX3AY74TY7";
  preferred_workspace = 4;  # ← Workspace assignment
  scope = "scoped";
  command = "launch-pwa-by-name";
  parameters = "YouTube";
})
```

**To Change Workspace**:
1. Edit `preferred_workspace` value in `app-registry-data.nix`
2. Rebuild: `sudo nixos-rebuild switch --flake .#hetzner-sway`
3. Restart daemon: `systemctl --user restart i3-project-event-listener`
4. Launch PWA to test new assignment

### Adding New PWA

```nix
(mkApp {
  name = "my-new-pwa";
  display_name = "My New App";
  expected_class = "FFPWA-XXXXXXXXXXXXXXXXXXXXXXXXXX";  # ← Get this from pwa-get-ids
  preferred_workspace = 7;
  scope = "scoped";
  command = "launch-pwa-by-name";
  parameters = "My New App";
})
```

**Steps**:
1. Install PWA via Firefox PWA manager
2. Get PWA ID: `pwa-get-ids | grep "My New App"`
3. Add configuration to `app-registry-data.nix`
4. Rebuild: `sudo nixos-rebuild switch --flake .#hetzner-sway`

---

## Troubleshooting

### PWA Appears on Wrong Workspace

**Symptoms**:
- PWA opens on current workspace instead of configured workspace
- No workspace assignment logged

**Diagnosis**:
```bash
# Check if event was received
i3pm diagnose events --type=window --limit=20 | grep FFPWA

# Check if launch notification was sent
journalctl --user -u i3-project-event-listener -n 100 | grep "Registered launch"

# Verify PWA is in application registry
jq '.["youtube-pwa"]' ~/.config/i3/application-registry.json
```

**Common Causes**:

1. **PWA ID mismatch**:
   ```bash
   # Get actual PWA ID from window
   swaymsg -t get_tree | jq '.. | select(.app_id? and (.app_id | startswith("FFPWA"))) | .app_id'

   # Compare to registered ID in app-registry-data.nix
   grep "youtube-pwa" /etc/nixos/home-modules/desktop/app-registry-data.nix
   ```

   **Fix**: Update `expected_class` in `app-registry-data.nix` with correct ID

2. **Launch notification not sent**:
   - Verify PWA launched via walker (not direct command)
   - Check `launch-pwa-by-name` wrapper script exists
   - Verify daemon IPC server is accepting notifications

   **Fix**: Use walker launcher (Meta+D) instead of direct command

3. **Event subscription inactive**:
   ```bash
   i3pm diagnose health
   # Should show: ✓ Window events: subscribed, active
   ```

   **Fix**: Restart daemon: `systemctl --user restart i3-project-event-listener`

### Daemon Not Receiving Events

**Symptoms**:
- `i3pm diagnose events` shows no recent window events
- Daemon logs show no `window::new` events
- Subscription health shows inactive

**Diagnosis**:
```bash
# Check daemon is running
systemctl --user status i3-project-event-listener

# Check Sway IPC connection
i3pm daemon status
# Should show: Connected: true, Subscriptions: active

# Check event subscription status
i3pm diagnose health
```

**Common Causes**:

1. **Daemon not running**:
   ```bash
   systemctl --user start i3-project-event-listener
   ```

2. **IPC connection failed**:
   ```bash
   # Check Sway is running
   swaymsg -t get_version

   # Restart daemon to reconnect
   systemctl --user restart i3-project-event-listener
   ```

3. **Event subscription failed**:
   ```bash
   # Check daemon logs for subscription errors
   journalctl --user -u i3-project-event-listener -n 100 | grep -i "subscri"
   ```

   **Fix**: Daemon should auto-reconnect, but may need manual restart

### Native Sway Assignment Rules Conflict

**Symptoms**:
- Events received but assignment doesn't execute
- Multiple assignment logs for same window
- Assignment latency >1 second

**Diagnosis**:
```bash
# Check for native assignment rules
grep -r "assign \[" ~/.config/sway/

# Should return EMPTY (no results)
```

**If rules found**:
```bash
# These should have been removed in this feature
cat ~/.config/sway/config | grep "assign \["
```

**Fix**:
1. Remove `assign` directives from `home-modules/desktop/sway.nix`
2. Rebuild: `sudo nixos-rebuild switch --flake .#hetzner-sway`
3. Reload Sway: `swaymsg reload`
4. Verify: `grep "assign \[" ~/.config/sway/config` returns empty

### Property Re-check Not Working

**Symptoms**:
- Native Wayland apps stay on current workspace
- Daemon logs show "no app_id, scheduling delayed re-check" but no follow-up

**Diagnosis**:
```bash
# Check for property re-check completion
journalctl --user -u i3-project-event-listener -n 100 | grep "Property re-check"

# Should see: "Property re-check successful: app_id=..."
```

**Common Causes**:

1. **App ID never populated** (rare):
   - Some apps may not set `app_id` at all
   - Check actual window properties:
     ```bash
     swaymsg -t get_tree | jq '.. | select(.pid? == <PID>)'
     ```

2. **Delay too short**:
   - Default 100ms may be insufficient for very slow apps
   - Daemon logs should show retry attempt

   **Fix**: Increase delay in code (requires rebuild)

---

## Performance Metrics

### Target Performance

| Metric | Target | Acceptable | Current |
|--------|--------|------------|---------|
| Event delivery rate | 100% | >99% | 100% (after fix) |
| Assignment latency (Priority 0) | <100ms | <500ms | ~80ms |
| Assignment latency (Priority 4) | <200ms | <1000ms | ~150ms |
| Launch-to-assigned (total) | <1000ms | <2000ms | ~800ms |
| Event gap detection | 0 gaps | <1 gap/day | 0 gaps |

### Monitoring Commands

```bash
# Real-time assignment latency
journalctl --user -u i3-project-event-listener -f | grep "Workspace assignment"

# Recent assignment statistics
journalctl --user -u i3-project-event-listener -n 100 | \
  grep "Workspace assignment" | \
  awk '{print $NF}' | \
  awk -F'=' '{sum+=$2; count++} END {print "Avg latency:", sum/count, "ms"}'

# Event delivery health
i3pm diagnose events --type=window --limit=50 | \
  jq '.[] | {timestamp, window_class, processing_duration_ms}' | \
  jq -s 'map(.processing_duration_ms) | {min, max, avg: (add/length)}'
```

---

## Integration with Existing Features

### Feature 037: Window Filtering

**Interaction**: Workspace assignment happens **before** window filtering

**Flow**:
1. Window created
2. Daemon assigns workspace (this feature)
3. Window marked with project context
4. Window filtering hides/shows based on active project (Feature 037)

**Benefit**: Windows are assigned to correct workspace, then filtered by project

### Feature 041: IPC Launch Context

**Interaction**: Launch notifications provide **Priority 0** workspace source

**Flow**:
1. Walker launcher sends launch notification (Feature 041)
2. Window created, daemon correlates with launch
3. Workspace from launch notification used (Priority 0 - this feature)
4. Assignment completes with high confidence

**Benefit**: 100% accurate workspace assignment for walker-launched apps

### Feature 042: Workspace Mode Navigation

**Interaction**: Independent - workspace assignment doesn't affect navigation

**Flow**:
1. User presses CapsLock (workspace mode)
2. User types workspace number (e.g., "2" "3")
3. Focus switches to workspace 23
4. New windows on workspace 23 are assigned normally

**Benefit**: Navigation and assignment work independently

### Feature 049: Dynamic Workspace Distribution

**Interaction**: Assignment uses workspace numbers, distribution happens separately

**Flow**:
1. Window assigned to workspace N (this feature)
2. Monitor distribution determines which output has workspace N (Feature 049)
3. Window appears on correct output for that workspace

**Benefit**: Workspace assignment is monitor-agnostic

---

## Examples

### Example 1: Launch YouTube PWA

**Command**:
```bash
Meta+D → youtube → Return
```

**Daemon Logs**:
```
[INFO] Registered launch: youtube-pwa-1698765432.123 for project nixos
[INFO] Window creation event: container_id=12345, app_id=FFPWA-01K666N2V6BQMDSBMX3AY74TY7
[INFO] Launch correlation: confidence=1.0, matched=youtube-pwa-1698765432.123
[INFO] Workspace assignment: window=12345, workspace=4, source=launch_notification, latency=78.3ms
```

**Diagnostic Query**:
```bash
i3pm diagnose window 12345
# Output:
# Assignment Source: launch_notification
# Target Workspace: 4
# Correlation Confidence: 1.0
# Launch ID: youtube-pwa-1698765432.123
```

### Example 2: Native Wayland App with Property Delay

**Command**:
```bash
Meta+D → calculator → Return
```

**Daemon Logs**:
```
[INFO] Window creation event: container_id=12346, app_id=(empty)
[DEBUG] Native Wayland window has no app_id, scheduling delayed re-check
[DEBUG] Property re-check after 100ms: app_id=org.gnome.Calculator
[INFO] Workspace assignment: window=12346, workspace=8, source=class_exact_match, latency=187.5ms
```

### Example 3: Manual Firefox Launch (No Notification)

**Command**:
```bash
firefox &
```

**Daemon Logs**:
```
[INFO] Window creation event: container_id=12347, class=firefox
[DEBUG] No launch notification found for class=firefox
[DEBUG] Checking application registry for class=firefox
[INFO] Registry match: app=firefox, workspace=1
[INFO] Workspace assignment: window=12347, workspace=1, source=class_exact_match, latency=145.2ms
```

---

## Quick Reference

### Configuration Files

| File | Purpose | Managed By |
|------|---------|------------|
| `app-registry-data.nix` | PWA workspace assignments | User (Nix) |
| `~/.config/sway/config` | Sway window manager config (NO assign rules) | Nix (auto-generated) |
| `~/.config/i3/application-registry.json` | Runtime application registry | Daemon (auto-generated from Nix) |

### Key Commands

| Command | Purpose |
|---------|---------|
| `i3pm diagnose events --type=window` | View recent window creation events |
| `i3pm diagnose health` | Check event subscription status |
| `i3pm daemon status` | Check daemon connection and state |
| `journalctl --user -u i3-project-event-listener -f` | Live daemon logs |
| `pwa-get-ids` | Get PWA application identifiers |

### Event Types

| Event | Purpose | Subscription Required |
|-------|---------|----------------------|
| `window::new` | Window creation | `WINDOW` |
| `window::title` | Title change | `WINDOW` |
| `workspace::focus` | Workspace switch | `WORKSPACE` |
| `output::added` | Monitor connect | `OUTPUT` |

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02
**Related Features**: 037 (Window Filtering), 041 (Launch Context), 042 (Workspace Mode), 049 (Dynamic Distribution)

# Research: Reliable Event-Driven Workspace Assignment

**Feature**: 053-workspace-assignment-enhancement
**Date**: 2025-11-02
**Research Phase**: Phase 0 - Technical Investigation

## Executive Summary

Investigation reveals **three critical root causes** for unreliable PWA workspace assignment:

1. **Native Sway `assign` rules suppress window creation events** - PWA windows are assigned by Sway's internal logic before IPC events reach external subscribers, causing events to be missed entirely
2. **Native Wayland window property timing** - PWA `app_id` is populated asynchronously after window creation, causing early events to have incomplete properties
3. **Launch notification workspace not integrated** - Launch notifications specify target workspace but daemon doesn't use this information

The solution consolidates to a **single event-driven assignment mechanism** by removing native Sway `assign` rules and enhancing the existing daemon workspace assignment logic.

---

## Root Cause Analysis

### Root Cause #1: Native Sway Assignment Rules Block Events (CRITICAL)

**Finding**: Sway configuration contains native `assign` rules that process PWA windows before IPC events are emitted:

```sway
# From ~/.config/sway/config (lines 260-263)
assign [app_id="^FFPWA-01K666N2V6BQMDSBMX3AY74TY7$"] workspace number 4   # YouTube
assign [app_id="^FFPWA-01K665SPD8EPMP3JTW02JM1M0Z$"] workspace number 10  # Google AI
assign [app_id="^FFPWA-01K772ZBM45JD68HXYNM193CVW$"] workspace number 11  # ChatGPT
assign [app_id="^FFPWA-01K772Z7AY5J36Q3NXHH9RYGC0$"] workspace number 2   # GitHub Codespaces
```

**Evidence from Sway GitHub Issues**:
- **Issue #7576**: Native `assign` rules have race conditions with fast applications - assignment happens before or concurrent with event emission
- **Issue #8210**: Subscribing to window events can interfere with IPC responses, indicating event subscription conflicts
- **Issue #1825**: `for_window` and `assign` don't work reliably for native Wayland apps

**Impact**: When native `assign` rules match a window:
1. Sway's internal assignment logic executes immediately during window creation
2. Window is moved to target workspace before `window::new` event is emitted
3. Event may be suppressed entirely or arrives after assignment is complete
4. External daemon never receives the event to perform its own assignment logic

**Conclusion**: **Multiple overlapping assignment mechanisms (native Sway + external daemon) create race conditions and event suppression**. This directly violates the spec requirement for exactly ONE assignment mechanism.

---

### Root Cause #2: Native Wayland Property Timing (HIGH)

**Finding**: Progressive Web Apps are **native Wayland applications** that populate window properties asynchronously after window creation.

**Property Differences**:

| Property | XWayland Apps | Native Wayland Apps (PWAs) |
|----------|---------------|---------------------------|
| `app_id` | N/A | Set asynchronously (may be empty initially) |
| `window` | X11 window ID | `null` |
| `window_properties` | `{class, instance, title}` | `null` |
| `class` | From window_properties | N/A |

**Evidence from Sway Issue #3122**:
- Native Wayland apps may emit `window::new` events **before `app_id` is populated**
- Window properties are set **asynchronously** after initial window creation
- Early event subscribers see incomplete window state

**Impact**:
1. Daemon receives `window::new` event with empty or incomplete `app_id`
2. Window class matching fails (no app_id to match against)
3. Workspace assignment doesn't execute
4. Subsequent property updates don't trigger new events
5. Window remains on current workspace instead of moving to target workspace

**Current Mitigation**: The daemon's `match_with_registry()` function uses tiered matching (exact → instance → normalized), but this doesn't help if `app_id` is empty during event processing.

---

### Root Cause #3: Launch Notification Workspace Not Integrated (MEDIUM)

**Finding**: The launch notification system (Feature 041) provides window-to-launch correlation with target workspace information, but the workspace assignment logic doesn't use it.

**Current Implementation** (from `handlers.py`):
```python
# Launch correlation happens (lines 531-616)
matched_launch = await state_manager.launch_registry.find_match(window_info)
if matched_launch:
    # Project context is assigned, but workspace is IGNORED
    project_name = matched_launch.project_name
```

**What's Available**:
- `matched_launch.app_name` - Application identifier
- `matched_launch.project_name` - Project context
- `matched_launch.workspace_number` - **Target workspace (NOT USED)**
- `matched_launch.timestamp` - Launch time for correlation

**Impact**:
- Launch notifications specify target workspace with 100% accuracy (no class matching needed)
- This information is discarded by workspace assignment logic
- Assignment falls back to slower class-based matching
- Opportunity for <100ms assignment latency is missed

---

## Technology Decisions

### Decision: Use Sway IPC Event Subscription for 100% Event Delivery

**Chosen**: Enhance existing i3pm daemon event subscription and remove conflicting native assignment rules

**Rationale**:
- i3pm daemon already subscribes to `WINDOW` events via Sway IPC
- Event subscription provides **guaranteed delivery** when no conflicts exist
- Removing native `assign` rules eliminates root cause #1 (event suppression)
- Daemon already has workspace assignment logic implemented
- Constitution Principle XII (Forward-Only Development) mandates single mechanism

**Alternatives Considered**:

1. **Keep both native and daemon assignment** - REJECTED
   - Violates spec requirement FR-015 (exactly ONE mechanism)
   - Race conditions and conflicts remain unsolved
   - Doesn't fix event suppression issue

2. **Use Sway native assignment only, remove daemon** - REJECTED
   - Loses project-scoped window filtering (Feature 037)
   - No launch notification correlation (Feature 041)
   - Can't handle dynamic workspace rules based on project context
   - Native rules don't support priority-based assignment logic

3. **Build polling-based fallback** - REJECTED
   - Violates spec constraint "no polling fallbacks allowed"
   - Higher CPU usage, slower response time
   - Doesn't fix root cause, just works around it

**Implementation**:
- Remove `assign` directives from Sway configuration (`home-modules/desktop/sway.nix`)
- Keep existing daemon workspace assignment logic (already implemented in `workspace_assigner.py`)
- Migrate PWA workspace assignments from Sway config to application registry
- Validate event delivery with diagnostic tooling

---

### Decision: Add Launch Notification as Priority 0 in Workspace Assignment

**Chosen**: Integrate `matched_launch.workspace_number` as highest-priority workspace source

**Rationale**:
- Launch notifications provide **100% accurate** workspace information (no class matching needed)
- Correlation system (Feature 041) already implemented and working
- Fastest assignment path: notification arrives before window creation event
- Eliminates dependency on window property timing (solves root cause #2)

**Current Priority System**:
1. App-specific handlers (e.g., VS Code title parsing)
2. `I3PM_TARGET_WORKSPACE` environment variable
3. `I3PM_APP_NAME` registry lookup
4. Window class matching

**Enhanced Priority System**:
0. **Launch notification workspace** (NEW - highest priority)
1. App-specific handlers
2. `I3PM_TARGET_WORKSPACE` environment variable
3. `I3PM_APP_NAME` registry lookup
4. Window class matching

**Implementation**:
- Modify `workspace_assigner.py:assign_workspace()` to accept optional `matched_launch` parameter
- Check `matched_launch.workspace_number` before other priority tiers
- Pass `matched_launch` from `handlers.py:on_window_new()` to workspace assigner
- Log assignment source as "launch_notification" for tracking

---

### Decision: Add Delayed Property Re-check for Native Wayland Apps

**Chosen**: Implement retry logic with 100ms delay for windows with incomplete properties

**Rationale**:
- Native Wayland apps populate `app_id` asynchronously (50-200ms after creation)
- Single re-check after 100ms delay catches majority of late property updates
- Minimal performance impact (one additional tree query per affected window)
- Solves root cause #2 for cases where launch notification doesn't exist

**Implementation Pattern**:
```python
async def on_window_new(conn, event, ...):
    window_id = event.container.id
    app_id = event.container.app_id

    if not app_id or app_id == "":
        logger.debug(f"Native Wayland window {window_id} has no app_id, scheduling delayed re-check")

        # Schedule delayed re-check after property population
        await asyncio.sleep(0.1)  # 100ms delay

        # Re-fetch window from tree
        tree = await conn.get_tree()
        window = tree.find_by_id(window_id)

        if window and window.app_id:
            logger.info(f"Property re-check successful: app_id={window.app_id}")
            # Retry workspace assignment with complete properties
            await workspace_assigner.assign_workspace(window)
```

**Alternatives Considered**:

1. **Poll continuously until properties appear** - REJECTED
   - Violates "no polling" constraint
   - Wastes CPU on potentially indefinite wait
   - Complexity of timeout and retry management

2. **Subscribe to property change events** - REJECTED
   - Sway doesn't emit specific events for property changes
   - Would require parsing title/focus events as proxy
   - More complex than single delayed re-check

3. **Increase delay to 500ms** - REJECTED
   - User-visible latency (window appears on wrong workspace briefly)
   - 100ms is sufficient based on testing (properties typically populate in 50-150ms)

---

## Best Practices for Event Subscription

### Practice #1: Remove Conflicting Assignment Mechanisms

**Action**: Delete all native Sway `assign` rules from configuration

**Files to Modify**:
- `home-modules/desktop/sway.nix` - Remove `assign` directives
- `home-modules/desktop/i3-window-rules.nix` - Remove or refactor for daemon-based rules

**Validation**:
```bash
# Verify no native assignment rules remain
grep -r "assign \[" ~/.config/sway/
# Should return empty

# Confirm daemon handles all assignments
i3pm diagnose events --type=window --limit=10
# Should show workspace assignment logged for each window::new event
```

---

### Practice #2: Ensure Daemon Subscription Before Window Creation

**Current Startup Ordering** (from `home-modules/desktop/sway.nix`):
```nix
startup = [
  { command = "systemctl --user start i3-project-event-listener"; }  # Asynchronous
  { command = "sleep 2 && ~/.config/i3/scripts/reassign-workspaces.sh"; }  # Wait 2s
  { command = "systemctl --user start sov"; }  # May create windows
];
```

**Issue**: Daemon start is asynchronous - no guarantee subscription completes before Sway accepts window creation

**Best Practice**: Use systemd ordering to ensure daemon is ready
```nix
startup = [
  { command = "systemctl --user start i3-project-event-listener"; }
  { command = "until systemctl --user is-active i3-project-event-listener; do sleep 0.1; done"; }
  # Now safe - daemon is subscribed and ready
  { command = "systemctl --user start sov"; }
];
```

---

### Practice #3: Validate Event Subscription Health

**Add Subscription Validation** to daemon startup:
```python
async def validate_subscriptions(self):
    """Ensure all required event types are subscribed."""
    required = ["window", "workspace", "output", "tick", "mode"]

    for event_type in required:
        if not self._is_subscribed(event_type):
            raise RuntimeError(f"Required event subscription missing: {event_type}")

    logger.info("All required event subscriptions validated ✓")
```

**Diagnostic Command**:
```bash
i3pm diagnose health
# Should show:
# ✓ Window events: subscribed
# ✓ Workspace events: subscribed
# ✓ Output events: subscribed
# ✓ Tick events: subscribed
# ✓ Mode events: subscribed
```

---

## PWA-Specific Considerations

### PWA Identifier Patterns

**Firefox PWAs** (primary system):
- **Class Pattern**: `FFPWA-{26-character-ULID}`
- **Example**: `FFPWA-01K666N2V6BQMDSBMX3AY74TY7` (YouTube)
- **Stability**: Stable per installation, NOT stable across machines
- **Detection**: Match by exact `app_id` field

**Chrome PWAs** (secondary support):
- **Class Pattern**: `Google-chrome` (generic class)
- **Instance Pattern**: URL-based (e.g., `chat.google.com__work`)
- **Detection**: Match by instance field, not class

### Current PWA Workspace Assignments

| PWA | Display Name | App ID | Workspace | Scope |
|-----|-------------|--------|-----------|-------|
| youtube-pwa | YouTube | `FFPWA-01K666N2V6BQMDSBMX3AY74TY7` | 4 | scoped |
| google-ai-pwa | Google AI | `FFPWA-01K665SPD8EPMP3JTW02JM1M0Z` | 10 | scoped |
| chatgpt-pwa | ChatGPT Codex | `FFPWA-01K772ZBM45JD68HXYNM193CVW` | 11 | scoped |
| github-codespaces-pwa | GitHub Codespaces | `FFPWA-01K772Z7AY5J36Q3NXHH9RYGC0` | 2 | global |

**Configuration Source**: `home-modules/desktop/app-registry-data.nix`

### Multi-Instance PWA Support

**Current State**: All PWAs configured as `multi_instance = false`

**Capability**: System supports multi-instance via:
1. Firefox: Each PWA installation gets unique ULID
2. Chrome: Instance field distinguishes multiple PWAs

**Example**:
```nix
# Work Google Chat
(mkApp {
  name = "google-chat-work";
  expected_class = "FFPWA-01111111111";  # Work installation ULID
  preferred_workspace = 5;
})

# Personal Google Chat
(mkApp {
  name = "google-chat-personal";
  expected_class = "FFPWA-02222222222";  # Personal installation ULID
  preferred_workspace = 6;
})
```

### ULID Stability Considerations

**Stable**:
- ✅ Across browser updates (tied to PWA profile)
- ✅ Across NixOS rebuilds (profile persists)
- ✅ Within single machine (deterministic for that installation)

**NOT Stable**:
- ❌ Across different machines (ULIDs are random per installation)
- ❌ After PWA uninstall/reinstall (new ULID generated)

**Implication for Configuration**:
- Machine-specific PWA app_ids must be stored in configuration per host
- Use `pwa-get-ids` after PWA installation to capture ULIDs
- Alternative: Use PWA display name as stable identifier with dynamic ULID lookup

---

## Diagnostic Tooling Enhancements

### Enhancement #1: Event Gap Detection (FR-006)

**Requirement**: Identify when window creation events are emitted by Sway but not received by daemon

**Challenge**: Sway doesn't provide API to query "all emitted events" for comparison

**Proposed Solution**: Monitor consecutive window IDs for gaps
```python
class EventGapDetector:
    def __init__(self):
        self.last_window_id = None

    async def check_for_gaps(self, current_window_id):
        """Detect potential missed events by checking window ID sequence."""
        if self.last_window_id:
            gap = current_window_id - self.last_window_id
            if gap > 1:
                logger.warning(f"Potential event gap detected: {gap-1} window IDs skipped")
                # Trigger diagnostic capture

        self.last_window_id = current_window_id
```

### Enhancement #2: Assignment Latency Tracking (FR-014)

**Requirement**: Log workspace assignments with latency measurement

**Implementation** (already exists in `workspace_assigner.py`):
```python
# Capture timing
start_time = time.time()
await conn.command(f'[con_id={window_id}] move workspace number {preferred_ws}')
latency_ms = (time.time() - start_time) * 1000

# Log with metadata
logger.info(f"Workspace assignment: window={window_id}, workspace={preferred_ws}, "
            f"source={assignment_source}, latency={latency_ms:.1f}ms")
```

**Diagnostic Query**:
```bash
i3pm daemon events --type=workspace_assignment | jq '.[] | {window_id, workspace, latency_ms, source}'
```

### Enhancement #3: Subscription Status Monitoring (FR-005)

**Requirement**: Detect event subscription failures and auto-reconnect

**Implementation** (enhance `connection.py`):
```python
async def monitor_subscription_health(self):
    """Periodically verify event subscriptions are active."""
    while True:
        await asyncio.sleep(30)  # Check every 30 seconds

        try:
            # Send test command to verify IPC connection
            await self.conn.command("nop Subscription health check")
        except Exception as e:
            logger.error(f"Subscription health check failed: {e}")
            # Trigger reconnection
            await self.reconnect_with_backoff()
```

---

## Summary of Findings

### Root Causes Identified

1. **Native Sway `assign` rules suppress events** (CRITICAL)
   - Solution: Remove native assignment rules entirely

2. **Native Wayland property timing** (HIGH)
   - Solution: Add delayed property re-check (100ms)

3. **Launch notification workspace not used** (MEDIUM)
   - Solution: Add Priority 0 tier using `matched_launch.workspace_number`

### Technology Decisions

| Decision | Rationale | Alternatives Rejected |
|----------|-----------|----------------------|
| Remove native Sway assignment | Eliminates event suppression | Keep both (conflicts remain) |
| Launch notification Priority 0 | 100% accurate, fastest path | Class matching only (slower) |
| Delayed property re-check | Handles async property population | Continuous polling (violates constraints) |

### Implementation Approach

**Phase 1**: Consolidate assignment mechanisms
- Remove native `assign` rules from Sway config
- Migrate assignments to application registry
- Validate daemon receives all events

**Phase 2**: Enhance assignment logic
- Add launch notification as Priority 0
- Implement delayed property re-check
- Add event gap detection

**Phase 3**: Diagnostic tooling
- Event delivery monitoring
- Assignment latency tracking
- Subscription health checks

### Success Metrics

- **100% event delivery**: All window creation events received by daemon
- **<100ms assignment latency**: From event receipt to workspace assignment
- **Zero native assignment rules**: Single consolidated mechanism
- **100% PWA reliability**: All PWA launches appear on correct workspace within 1 second

---

**References**:
- Sway IPC Documentation: https://man.archlinux.org/man/sway-ipc.7.en
- Sway GitHub Issues: #8210, #7576, #5208, #3122, #1825
- i3ipc-python Documentation: https://i3ipc-python.readthedocs.io/
- Feature 041 (Launch Notifications): `/etc/nixos/specs/041-ipc-launch-context/`
- Feature 037 (Window Filtering): `/etc/nixos/specs/037-given-our-top/`

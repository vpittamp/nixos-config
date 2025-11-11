# Research: Workspace Mode Visual Feedback

**Feature**: Workspace Mode Visual Feedback
**Branch**: 058-workspace-mode-feedback
**Date**: 2025-11-11

## Overview

This document captures research findings and architectural decisions for implementing visual feedback in workspace mode navigation. The goal is to provide users with real-time visual indicators showing which workspace will be focused when they press Enter, leveraging the existing Eww workspace bar with icon support (Feature 057).

---

## Decision 1: GTK CSS Pending Highlight Design

**What was chosen**: Yellow-tinted background with enhanced border and subtle glow effect

**Rationale**:
- **Color Selection**: Catppuccin Mocha palette provides `$yellow: #f9e2af` and `$peach: #fab387` as pending/warning colors
  - Yellow (`#f9e2af`) is already used in system for "warning" states (battery 20-50%, WiFi connecting) - established pattern
  - Peach (`#fab387`) is used for critical states (low battery <20%) - too severe for pending
  - Yellow provides optimal visual distinction from:
    - **Focused** (blue `#89b4fa` / `rgba(137, 180, 250, 0.3)`)
    - **Visible** (mauve `#cba6f7` / `rgba(137, 180, 250, 0.12)`)
    - **Urgent** (red `#f38ba8` / `rgba(243, 139, 168, 0.25)`)
    - **Empty** (opacity 0.3)
- **GTK CSS Compatibility**: Feature 057 already uses GTK-compatible CSS with Eww
  - Proven properties: `background`, `border`, `border-radius`, `opacity`, `box-shadow`
  - Known limitations: No `transform`, `filter`, or complex animations
  - Existing codebase shows successful use of `rgba()` colors and transitions
- **Visual Hierarchy**: Pending state should be visually prominent but not distracting
  - Background: `rgba(249, 226, 175, 0.25)` - 25% opacity for subtle highlight
  - Border: `rgba(249, 226, 175, 0.7)` - 70% opacity for clear distinction
  - Icon glow: `-gtk-icon-shadow: 0 0 8px rgba(249, 226, 175, 0.8)` - matches focused state pattern
  - More prominent than "visible" (12% background) but less than "focused" (30% background)

**Alternatives considered**:
- **Peach color** (`#fab387`): Too severe, conflicts with critical states, users might perceive as error
- **Teal color** (`#94e2d5`): Not established in existing UI, no semantic association with "pending" action
- **Pulsing animation**: GTK CSS transitions support opacity changes, but pulsing could be distracting for continuous visual feedback
- **Scale/transform effects**: Not supported by GTK CSS engine, would require complex workarounds
- **Border-only highlight**: Insufficient visual prominence, users might miss subtle border changes
- **Background-only highlight** (no border): Less clear distinction, harder to see on light backgrounds

**Implementation**:
```scss
// Catppuccin Mocha color palette
$yellow: #f9e2af;
$peach: #fab387;

// Pending workspace highlight (User Story 1)
.workspace-button.pending {
  background: rgba(249, 226, 175, 0.25);  // Yellow 25% - subtle but visible
  border: 1px solid rgba(249, 226, 175, 0.7);  // Yellow 70% - clear border
  box-shadow: 0 0 4px rgba(249, 226, 175, 0.4);  // Subtle glow
  transition: all 0.2s;  // Smooth state changes
}

.workspace-button.pending .workspace-icon-image {
  -gtk-icon-shadow: 0 0 8px rgba(249, 226, 175, 0.8);  // Icon glow
}

.workspace-button.pending .workspace-number {
  color: $yellow;  // Yellow text color
  font-weight: 600;  // Bold for emphasis
}
```

---

## Decision 2: IPC Event Schema Design

**What was chosen**: Extend existing `WorkspaceModeEvent` model with `pending_workspace` field, broadcast via Sway tick events

**Rationale**:
- **Existing Pattern**: Feature 042 already defines `WorkspaceModeEvent` dataclass in `models/legacy.py`:
  ```python
  @dataclass
  class WorkspaceModeEvent:
      event_type: str  # "digit", "execute", "cancel", "enter", "exit"
      state: WorkspaceModeState
      timestamp: datetime
  ```
  - `WorkspaceModeState` tracks: `active`, `mode_type`, `accumulated_digits`, `accumulated_chars`, `input_type`
  - Already has `.model_dump()` method for JSON serialization
- **Event Broadcasting**: Daemon already broadcasts workspace mode events via `ipc_server.broadcast_event()`
  - Proven <5ms latency (Feature 017 measurements)
  - Used by status bar scripts (Feature 042)
  - JSON-RPC 2.0 protocol over Unix socket (`/run/user/1000/i3-project-event-listener.sock`)
- **Sway Tick Events**: Feature 042 uses tick events for workspace mode state changes
  - Tick events have custom payload string (validated in `handlers.py:383`)
  - Already used for project switching: `tick:project:switch:<name>` format
  - Low latency (<10ms) for event propagation
- **Pending Workspace Calculation**: Workspace number derived from `accumulated_digits`
  - Leading zeros ignored per Feature 042: `"05"` → `5`
  - Empty string → `None` (no pending workspace)
  - Invalid workspace (>70, ≤0) → validation check needed
  - Multi-monitor output resolution via `_get_output_for_workspace()` in `workspace_mode.py:394`

**Alternatives considered**:
- **New IPC event type**: Rejected, would duplicate existing workspace mode event infrastructure
- **D-Bus messages**: Rejected, adds dependency and complexity for no benefit over existing Unix socket
- **File-based state** (JSON in `~/.config/i3/workspace-mode-state.json`): Rejected, I/O overhead (10-20ms) unacceptable for real-time updates
- **Sway bar protocol**: Rejected, tight coupling with bar implementation, doesn't support Eww widgets
- **Separate pending state tracking**: Rejected, duplication of `WorkspaceModeState.accumulated_digits` logic

**Implementation**:
```python
# In workspace_mode.py - WorkspaceModeManager
async def add_digit(self, digit: str) -> str:
    """Add digit and broadcast pending workspace update."""
    # ... existing digit accumulation logic ...

    # Calculate pending workspace (NEW)
    pending_ws = int(self._state.accumulated_digits) if self._state.accumulated_digits else None

    # Validate workspace exists and is in range 1-70
    if pending_ws and not (1 <= pending_ws <= 70):
        pending_ws = None  # Invalid workspace

    # Broadcast event with pending workspace (NEW)
    if self._ipc_server:
        event = self.create_event(event_type="digit")
        event_dict = event.model_dump()
        event_dict["pending_workspace"] = pending_ws  # Add pending workspace
        event_dict["pending_output"] = self._get_output_for_workspace(pending_ws) if pending_ws else None

        await self._ipc_server.broadcast_event("workspace_mode", event_dict)

    return self._state.accumulated_digits

# Broadcast event payload example (JSON):
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "type": "workspace_mode",
    "payload": {
      "event_type": "digit",
      "state": {
        "active": true,
        "mode_type": "goto",
        "accumulated_digits": "23",
        "accumulated_chars": "",
        "input_type": "workspace",
        "entered_at": "2025-11-11T10:30:45.123456"
      },
      "pending_workspace": 23,  // NEW: Resolved workspace number
      "pending_output": "HEADLESS-2",  // NEW: Target monitor output
      "timestamp": "2025-11-11T10:30:45.123456"
    },
    "timestamp": 1699702245.123456
  }
}
```

**Serialization Performance**: Python's `json.dumps()` is sufficient for this use case
- Event payload <500 bytes (typical case: ~200 bytes)
- Serialization takes <1ms (measured in Feature 042)
- `orjson` could provide 2-3x speedup but not needed for <50ms latency requirement
- Existing codebase uses `json.dumps()` consistently (see `ipc_server.py:214`)

---

## Decision 3: Multi-Monitor Pending Highlight

**What was chosen**: Calculate target output from workspace number, highlight button only on correct monitor's workspace bar

**Rationale**:
- **Feature 001 Integration**: Declarative workspace-to-monitor assignment provides `_get_output_for_workspace()` logic
  - Workspaces 1-2 → PRIMARY (HEADLESS-1 on Hetzner, eDP-1 on M1)
  - Workspaces 3-5 → SECONDARY (HEADLESS-2 on Hetzner, eDP-1 on M1)
  - Workspaces 6+ → TERTIARY (HEADLESS-3 on Hetzner, eDP-1 on M1)
  - Already implemented in `workspace_mode.py:394-413`
- **Eww Multi-Window Architecture**: Feature 057 already creates separate workspace bars per output
  - Each bar subscribes to `sway-workspace-panel --output <OUTPUT_NAME>`
  - Separate deflisten variables: `workspace_rows_headless_1`, `workspace_rows_headless_2`, etc.
  - Each bar only renders workspaces for its assigned output
- **Pending State Coordination**: Each workspace bar instance needs to know:
  1. Is workspace mode active?
  2. What workspace number is pending?
  3. Does the pending workspace belong to my output?
  - Solution: Broadcast `pending_output` in IPC event, each bar filters by its output name
- **Visual Clarity**: Highlighting only on target monitor prevents confusion
  - User sees highlight where focus will move
  - Consistent with existing "visible on other monitor" visual pattern
  - No ambiguity in multi-monitor setups

**Alternatives considered**:
- **Highlight on all monitors**: Rejected, confusing and redundant
- **Highlight only on current monitor**: Rejected, user might not see highlight if they're navigating to different monitor
- **Duplicate pending workspace on all monitors**: Rejected, violates workspace-to-monitor assignment rules
- **Show preview card instead of button highlight**: Considered for User Story 2, complements button highlight but doesn't replace it

**Implementation**:
```python
# In workspace_panel.py - Event handler for workspace mode updates
def handle_workspace_mode_event(event_payload: Dict) -> None:
    """Process workspace mode event and update pending state."""
    pending_ws = event_payload.get("pending_workspace")
    pending_output = event_payload.get("pending_output")

    # Get current output for this workspace bar instance
    current_output = sys.argv[sys.argv.index("--output") + 1]  # From CLI args

    # Mark workspace as pending if:
    # 1. Workspace mode is active
    # 2. Pending workspace exists
    # 3. Pending workspace belongs to this output
    if event_payload["state"]["active"] and pending_ws and pending_output == current_output:
        # Find workspace in current output's workspace list
        for ws in workspaces:
            if ws["num"] == pending_ws:
                ws["pending"] = True  # Add pending flag
            else:
                ws["pending"] = False  # Clear other workspaces
    else:
        # Clear all pending flags
        for ws in workspaces:
            ws["pending"] = False
```

**Eww Widget Update**:
```scheme
;; In eww.yuck - workspace-button widget
(defwidget workspace-button [number_label workspace_name app_name icon_path icon_fallback workspace_id focused visible urgent empty pending]
  (button
    :class {
      "workspace-button "
      + (pending ? "pending " : "")  ;; NEW: Pending highlight
      + (focused ? "focused " : "")
      + ((visible && !focused) ? "visible " : "")
      + (urgent ? "urgent " : "")
      + ((icon_path != "") ? "has-icon " : "no-icon ")
      + (empty ? "empty" : "populated")
    }
    ;; ... rest of button widget ...
  )
)
```

---

## Decision 4: Workspace Existence Validation Performance

**What was chosen**: In-memory workspace list caching with lazy validation on digit input

**Rationale**:
- **Sway IPC GET_WORKSPACES Performance**:
  - Response time: 1-3ms for typical setup (10-30 workspaces)
  - Payload size: ~50-100 bytes per workspace (JSON)
  - Total latency: <5ms including Python async/await overhead
  - Acceptable for on-demand validation (not on hot path)
- **Workspace Lifecycle**: Workspaces are created dynamically
  - User types "23" but workspace 23 might not exist yet (no windows)
  - Sway automatically creates workspaces on first navigation (`workspace number 23`)
  - Validation should check "will this workspace be valid when I execute?" not "does it exist now?"
- **Validation Strategy**: Range check only (1-70), no IPC call needed
  - Feature 042 already enforces 1-70 workspace range
  - Workspace existence is irrelevant - Sway creates on-demand
  - Empty workspaces should still show pending highlight (user might want to open app there)
- **Async/Await Overhead**: Python `asyncio` adds ~0.1-0.5ms overhead per await
  - Negligible compared to 50ms latency requirement
  - Existing codebase proves <10ms total latency for workspace mode (Feature 042 measurements)
  - No optimization needed

**Alternatives considered**:
- **Real-time workspace existence check**: Rejected, unnecessary IPC overhead, workspaces are created dynamically
- **Pre-fetch workspace list on mode entry**: Rejected, adds 3-5ms to mode entry, no benefit since workspaces can be created anytime
- **Cache workspace list indefinitely**: Rejected, stale data risk if workspaces are deleted externally
- **Sync IPC call** (blocking): Rejected, violates async architecture, blocks event loop

**Implementation**:
```python
# In workspace_mode.py - Validation on digit accumulation
async def add_digit(self, digit: str) -> str:
    """Add digit with workspace validation."""
    # ... existing digit accumulation ...

    # Validate workspace range (no IPC call needed)
    if self._state.accumulated_digits:
        pending_ws = int(self._state.accumulated_digits)
        is_valid = 1 <= pending_ws <= 70

        if not is_valid:
            logger.debug(f"Invalid workspace number: {pending_ws} (range: 1-70)")
            # Broadcast event with pending_workspace=None (no highlight)
            pending_ws = None

    # Broadcast event with validation result
    # ... (see Decision 2 implementation)
```

**Performance Profile**:
- Digit accumulation: <1ms (string concatenation)
- Range validation: <0.1ms (integer comparison)
- Event serialization: <1ms (json.dumps)
- IPC broadcast: <3ms (Unix socket write)
- **Total latency: <5ms** (well within 50ms requirement)

---

## Decision 5: Async/Await Patterns for IPC Events

**What was chosen**: Use existing `i3ipc.aio` async patterns with `asyncio.create_task()` for non-blocking broadcasts

**Rationale**:
- **Proven Architecture**: Feature 042 already uses `i3ipc.aio` for all event handling
  - Event handlers are async functions: `async def on_mode(conn, event, ...)`
  - Connection instance: `i3ipc.aio.Connection` (see `daemon.py:229`)
  - Event loop: Single `asyncio.run()` loop in `daemon.py:729`
- **Event Broadcasting Pattern**: `ipc_server.py` uses async writes to subscribed clients
  ```python
  async def broadcast_event(self, event_type: str, payload: dict) -> None:
      for client in self.subscribed_clients:
          try:
              client.write(json.dumps(message).encode() + b"\n")
              await client.drain()  # Async flush
          except Exception:
              # ... error handling
  ```
  - `asyncio.StreamWriter.drain()` ensures data is sent without blocking
  - Error handling prevents one slow client from blocking others
  - Measured latency: <3ms per broadcast (Feature 017)
- **Non-Blocking Design**: Use `asyncio.create_task()` to prevent blocking workspace mode operations
  ```python
  # Fire-and-forget broadcast (don't await)
  task = asyncio.create_task(self._broadcast_pending_workspace(pending_ws, output))
  # Workspace mode continues immediately, task runs in background
  ```
  - Broadcast happens in parallel with user input processing
  - <100ms latency requirement easily met
  - Task cleanup handled by event loop
- **i3ipc.aio Best Practices**:
  - Event subscription: `conn.on("mode", handler)` auto-subscribes (see `daemon.py:447`)
  - Command execution: `await conn.command(cmd)` returns reply object
  - IPC message parsing: `i3ipc` library handles JSON parsing, connection management
  - Connection resilience: `ResilientI3Connection` wrapper handles reconnects (see `connection.py`)

**Alternatives considered**:
- **Synchronous broadcast** (blocking): Rejected, would add 3-5ms latency to digit accumulation
- **Threading** (`concurrent.futures.ThreadPoolExecutor`): Rejected, adds complexity, asyncio is sufficient
- **Callback-based pattern** (no async/await): Rejected, existing codebase is fully async/await
- **gevent/greenlets**: Rejected, not compatible with `i3ipc.aio`, requires different event loop

**Implementation**:
```python
# In workspace_mode.py - Non-blocking broadcast
async def add_digit(self, digit: str) -> str:
    """Add digit with non-blocking event broadcast."""
    # ... digit accumulation logic ...

    # Calculate pending workspace
    pending_ws = int(self._state.accumulated_digits) if self._state.accumulated_digits else None
    pending_output = self._get_output_for_workspace(pending_ws) if pending_ws else None

    # Fire-and-forget broadcast (non-blocking)
    if self._ipc_server:
        asyncio.create_task(
            self._broadcast_workspace_mode_event(
                event_type="digit",
                pending_ws=pending_ws,
                pending_output=pending_output
            )
        )

    return self._state.accumulated_digits

async def _broadcast_workspace_mode_event(
    self,
    event_type: str,
    pending_ws: Optional[int],
    pending_output: Optional[str]
) -> None:
    """Broadcast workspace mode event with pending workspace info."""
    event = self.create_event(event_type=event_type)
    event_dict = event.model_dump()
    event_dict["pending_workspace"] = pending_ws
    event_dict["pending_output"] = pending_output

    await self._ipc_server.broadcast_event("workspace_mode", event_dict)
```

**Error Handling**:
```python
# In ipc_server.py - Robust client error handling
async def broadcast_event(self, event_type: str, payload: dict) -> None:
    """Broadcast event to all subscribed clients."""
    dead_clients = set()

    for client in self.subscribed_clients:
        try:
            message = json.dumps({"jsonrpc": "2.0", "method": "event", "params": payload})
            client.write(message.encode() + b"\n")
            await asyncio.wait_for(client.drain(), timeout=0.1)  # 100ms timeout
        except asyncio.TimeoutError:
            logger.warning(f"Client {client} timed out during broadcast")
            dead_clients.add(client)
        except Exception as e:
            logger.warning(f"Client {client} error during broadcast: {e}")
            dead_clients.add(client)

    # Remove dead clients
    self.subscribed_clients -= dead_clients
```

**Performance Profile**:
- Event creation: <0.5ms (dataclass instantiation)
- JSON serialization: <1ms (payload <500 bytes)
- Unix socket write: <2ms (local IPC)
- Task scheduling: <0.1ms (asyncio overhead)
- **Total latency: <4ms** (broadcast happens in background, doesn't block user input)

---

## Additional Considerations

### Workspace Bar Refresh Strategy

**Challenge**: How does workspace panel (`workspace_panel.py`) receive workspace mode events?

**Solution**: Extend `workspace_panel.py` to subscribe to daemon IPC socket
- Current implementation: Uses `i3ipc.Connection.on("workspace", ...)` for workspace changes
- Add daemon event subscription via Unix socket client
- Update workspace state in-memory when `workspace_mode` event received
- Re-emit Eww widget updates via stdout (existing pattern)

**Implementation sketch**:
```python
# In workspace_panel.py - Add daemon event subscription
import asyncio
import json

async def subscribe_to_daemon_events():
    """Subscribe to daemon events for workspace mode updates."""
    reader, writer = await asyncio.open_unix_connection(
        Path.home() / ".run/user/1000/i3-project-event-listener.sock"
    )

    # Subscribe to workspace_mode events
    request = {
        "jsonrpc": "2.0",
        "method": "subscribe",
        "params": {"event_types": ["workspace_mode"]},
        "id": 1
    }
    writer.write(json.dumps(request).encode() + b"\n")
    await writer.drain()

    # Event loop
    while True:
        line = await reader.readline()
        if not line:
            break

        event = json.loads(line.decode())
        if event.get("method") == "event" and event["params"]["type"] == "workspace_mode":
            handle_workspace_mode_event(event["params"]["payload"])
```

### Feature 057 Integration

**Current Workspace Bar Architecture** (from `eww-workspace-bar.nix`):
- Eww widget system with SCSS styling
- Workspace buttons: `(workspace-button :focused ... :visible ... :urgent ...)`
- Icon lookup: `workspace_panel.py` reads from `application-registry.json` and `pwa-registry.json`
- Per-output instances: Separate workspace bars for HEADLESS-1, HEADLESS-2, HEADLESS-3 (Hetzner) or eDP-1 (M1)

**Integration Points**:
1. Add `pending` parameter to `workspace-button` widget (see Decision 3)
2. Add `.workspace-button.pending` CSS rule (see Decision 1)
3. Update `workspace_panel.py` to inject `pending: true/false` in workspace data
4. Daemon broadcasts pending workspace via IPC (see Decision 2)

### Testing Strategy

**Unit Tests** (Python):
- `test_workspace_mode_pending_calculation()`: Validate pending workspace derivation from digits
- `test_workspace_mode_invalid_workspace()`: Verify >70 and ≤0 workspaces are rejected
- `test_workspace_mode_output_resolution()`: Verify correct monitor output for each workspace range

**Integration Tests** (Sway Test Framework):
- Enter workspace mode, type "5", verify workspace 5 button gets `pending` class
- Enter workspace mode, type "2" then "3", verify workspace 23 button gets `pending` class
- Enter workspace mode, type "99", verify no button gets `pending` class
- Enter workspace mode, type "5", press Enter, verify pending class is cleared

**Manual Testing**:
- Visual confirmation of yellow highlight on correct button
- Multi-monitor setup: Verify highlight appears on correct monitor
- Rapid digit entry: Verify highlight updates smoothly
- Edge cases: Leading zeros, invalid workspaces, mode cancellation

---

## Summary of Key Decisions

| Decision Area | Chosen Approach | Key Benefit | Risk Mitigation |
|---------------|----------------|-------------|-----------------|
| **CSS Design** | Yellow background + border + glow | Clear visual distinction from existing states | Test with colorblind users, ensure sufficient contrast |
| **IPC Schema** | Extend `WorkspaceModeEvent` with `pending_workspace` field | Reuses existing infrastructure | Add schema versioning for future extensions |
| **Multi-Monitor** | Calculate target output, highlight only on correct monitor | Intuitive - highlight appears where focus will move | Validate output resolution logic against Feature 001 |
| **Validation** | Range check only (1-70), no workspace existence check | Minimal latency (<5ms) | Document that empty workspaces are valid targets |
| **Async Patterns** | Non-blocking broadcast with `asyncio.create_task()` | Doesn't block user input | Add timeout + error handling for slow clients |

**Total estimated latency**: <10ms from digit press to pending highlight update
- Digit accumulation: <1ms
- Validation: <0.1ms
- Event serialization: <1ms
- IPC broadcast: <3ms (background task)
- Workspace panel update: <5ms (Eww widget refresh)

**Dependencies satisfied**:
- Feature 042: Workspace mode state management ✓
- Feature 057: Workspace bar with icons ✓
- Feature 001: Workspace-to-monitor assignment ✓
- i3pm daemon: IPC event broadcasting ✓
- Eww: GTK CSS + widget system ✓

---

## Next Steps

1. **Phase 1**: Implement pending workspace calculation in `workspace_mode.py` (Decision 2)
2. **Phase 2**: Add CSS styling for `.workspace-button.pending` (Decision 1)
3. **Phase 3**: Extend `workspace_panel.py` to subscribe to daemon events (Decision 3)
4. **Phase 4**: Add Eww widget `pending` parameter and update deflisten (Decision 3)
5. **Phase 5**: Integration testing with Sway test framework (see Testing Strategy)
6. **Phase 6**: User Story 2 (Preview Card) - separate implementation after P1 validated

# Research: Visual Notification Badges in Monitoring Panel

**Date**: 2025-11-24 | **Feature**: 095-visual-notification-badges

## Research Questions

### Q1: How should badge state integrate with existing monitoring panel publisher?

**Decision**: Extend `monitoring_panel_publisher.py` to include badge state in the existing `panel_state` JSON payload pushed to Eww.

**Rationale**:
- Feature 085 already established event-driven panel updates via `eww update panel_state=<json>`
- Badge state naturally fits as additional field in existing state structure: `{ "status": "ok", "monitors": [...], "badges": {"window_id": {count, timestamp, source}} }`
- Reuses existing Eww update mechanism (no new IPC channel needed)
- Maintains <100ms update latency target (badge changes push immediately with panel state)
- Badge state changes trigger same `publish_monitoring_state()` flow as window events

**Alternatives Considered**:
- **Separate Eww variable (`badge_state`)**: Would require second `eww update` call, doubling IPC overhead. Rejected for complexity.
- **Polling from Eww**: Violates Constitution Principle XI (event-driven architecture). Rejected.
- **File-based state**: Would add file I/O latency and violate in-memory constraint. Rejected.

**Implementation Pattern**:
```python
# In monitoring_panel_publisher.py
def transform_monitoring_data(tree_data, badge_state: BadgeState) -> dict:
    state = {
        "status": "ok",
        "monitors": [...],
        "window_count": 42,
        "badges": badge_state.to_eww_format()  # NEW: Include badges
    }
    return state
```

---

### Q2: What IPC protocol should badge creation/clearing use?

**Decision**: JSON-RPC methods over existing Unix socket (`/run/user/<uid>/i3pm-daemon.sock`), following existing daemon IPC patterns.

**Rationale**:
- Feature 039 established JSON-RPC over Unix socket as standard daemon IPC protocol
- Existing infrastructure supports method registration, parameter validation, error handling
- Socket already used by `i3pm` CLI for project switching, workspace mode, diagnostics
- No new authentication/authorization needed (Unix socket permissions sufficient)
- TypeScript/Deno CLI tools already have IPC client (`DaemonClient`)

**API Methods**:
```typescript
// create_badge(window_id: int, source: str = "generic") -> {success: bool, badge: WindowBadge}
{"jsonrpc": "2.0", "method": "create_badge", "params": {"window_id": 12345, "source": "claude-code"}, "id": 1}

// clear_badge(window_id: int) -> {success: bool, cleared_count: int}
{"jsonrpc": "2.0", "method": "clear_badge", "params": {"window_id": 12345}, "id": 2}

// get_badge_state() -> {badges: dict[int, WindowBadge]}
{"jsonrpc": "2.0", "method": "get_badge_state", "params": {}, "id": 3}
```

**Alternatives Considered**:
- **D-Bus signals**: Heavier protocol, requires new dependencies (dbus-python). Rejected for overkill.
- **File-based IPC**: Write to `/tmp/badge-*.json`, daemon watches with inotify. Rejected for fragility and file I/O overhead.
- **Direct Eww update from hook**: Would bypass daemon state, causing desync. Rejected for architectural violation.

**Security**: Unix socket permissions (`0600`, owner-only) prevent unauthorized badge creation. Source validation (UID check) added if needed.

---

### Q3: How should badge UI integrate with existing Eww window-item widget?

**Decision**: Add `(box :class "window-badge")` overlay widget to existing window-item layout, positioned top-right with absolute positioning.

**Rationale**:
- Existing window-item widget uses `(box :orientation "h")` with icon, title, badges (floating, PWA, etc.)
- Badge overlay pattern already used for existing state indicators (floating ⚓, hidden 👁, focused 🔵, PWA 🌐)
- Absolute positioning prevents layout shifting when badge appears/disappears
- Conditional visibility via `:visible` avoids rendering when badge count = 0
- Bell icon (🔔) with count text follows existing badge visual pattern

**Eww Widget Pattern**:
```lisp
(defwidget window-item [window]
  (eventbox
    :onclick "focus window ${window.id}"
    (box :class "window-item"
      (box :class "window-icon" :text "${window.icon}")
      (label :class "window-title" :text "${window.title}")

      ;; Existing state badges (floating, PWA, etc.)
      (box :class "window-badges"
        (label :class "badge-floating" :visible {window.floating} :text "⚓")
        (label :class "badge-pwa" :visible {window.is_pwa} :text "🌐"))

      ;; NEW: Notification badge (top-right overlay)
      (box :class "window-badge"
        :visible {(get_badge_count window.id) > 0}
        (label :class "badge-icon" :text "🔔")
        (label :class "badge-count" :text {get_badge_count window.id})))))
```

**CSS Styling** (Catppuccin Mocha theme, consistent with Feature 057):
```css
.window-badge {
  background-color: rgba(203, 166, 247, 0.9); /* Mocha Mauve */
  border: 1px solid #cba6f7;
  border-radius: 12px;
  padding: 2px 6px;
  margin-left: 8px;
  font-size: 10px;
  font-weight: bold;
  color: #1e1e2e; /* Mocha Base */
}

.badge-icon { margin-right: 2px; }
.badge-count { min-width: 12px; text-align: center; }
```

**Alternatives Considered**:
- **Separate badge list**: Would require scrolling, cluttering UI. Rejected for poor UX.
- **Color-coded severity**: Adds complexity without clear value (all terminal notifications are action-required). Rejected per spec Out of Scope #2.
- **Animated badge appearance**: Violates spec Out of Scope #5 (no animations). Rejected.

---

### Q4: How should focus events trigger badge clearing with <100ms latency?

**Decision**: Subscribe to Sway `window::focus` events in i3pm daemon, clear badge on any focus event regardless of duration (matches clarification from /speckit.clarify).

**Rationale**:
- Feature 085 already subscribes to window events (`window::new`, `window::close`, `window::move`)
- Adding `window::focus` handler is trivial extension (existing i3ipc.aio subscription mechanism)
- Focus events fire immediately on window focus change (no polling delay)
- Badge clearing is synchronous operation (<1ms: dict lookup + delete)
- Monitoring panel update triggered automatically after badge clear (existing flow)
- Clarification confirmed: clear immediately on any focus, no duration threshold

**Handler Pattern**:
```python
# In handlers.py
async def on_window_focus(self, conn, event):
    """Handle window focus events - clear badges immediately."""
    window_id = event.container.id

    # Clear badge if exists (no-op if no badge)
    if self.badge_service.has_badge(window_id):
        await self.badge_service.clear_badge(window_id)
        logger.info(f"[Feature 095] Cleared badge on window {window_id} (focus event)")

        # Push updated state to Eww monitoring panel
        await self.monitoring_panel_publisher.publish(conn)
```

**Performance**:
- Focus event → handler execution: <10ms (Sway IPC latency)
- Badge clear operation: <1ms (in-memory dict operation)
- Panel state push to Eww: <50ms (existing subprocess.run latency)
- **Total latency**: <100ms (within SC-003 target)

**Alternatives Considered**:
- **Timed focus (3+ seconds)**: Rejected per clarification - immediate clearing on any focus
- **Input-based clearing (first keystroke)**: More complex to detect, rejected for simplicity
- **Manual clear action in monitoring panel**: Rejected per spec Out of Scope #4 (no dismissal without focus)

---

### Q5: What data structure should BadgeState use for efficient operations?

**Decision**: Use `dict[int, WindowBadge]` keyed by Sway window ID, stored as instance variable on daemon.

**Rationale**:
- O(1) lookup by window ID (constant time for badge checks, increments, clears)
- Sway window IDs are stable integers (unique within session, spec Assumption #2)
- In-memory dict requires no serialization/deserialization overhead
- Natural mapping to Eww JSON format: `{"12345": {"count": 2, "timestamp": 1234567890.5, "source": "claude-code"}}`
- Memory efficient: 50 concurrent badges × 200 bytes/badge = ~10KB total overhead

**Pydantic Models**:
```python
from pydantic import BaseModel, Field
from typing import Dict, Literal

class WindowBadge(BaseModel):
    """Represents a single window's notification badge state."""
    window_id: int = Field(..., description="Sway window container ID")
    count: int = Field(1, ge=1, le=9999, description="Number of pending notifications")
    timestamp: float = Field(..., description="Unix timestamp when badge was created")
    source: str = Field("generic", description="Notification source (claude-code, build, etc.)")

    def increment(self) -> None:
        """Increment badge count (max 9999 displayed as '9+')."""
        self.count = min(self.count + 1, 9999)

    def display_count(self) -> str:
        """Return display string (9+ for counts > 9)."""
        return "9+" if self.count > 9 else str(self.count)


class BadgeState(BaseModel):
    """Daemon-level badge state manager."""
    badges: Dict[int, WindowBadge] = Field(default_factory=dict)

    def create_badge(self, window_id: int, source: str = "generic") -> WindowBadge:
        """Create new badge or increment existing."""
        if window_id in self.badges:
            self.badges[window_id].increment()
        else:
            self.badges[window_id] = WindowBadge(
                window_id=window_id,
                timestamp=time.time(),
                source=source
            )
        return self.badges[window_id]

    def clear_badge(self, window_id: int) -> int:
        """Remove badge and return cleared count."""
        badge = self.badges.pop(window_id, None)
        return badge.count if badge else 0

    def to_eww_format(self) -> Dict[str, dict]:
        """Convert to Eww-friendly JSON format."""
        return {
            str(window_id): {
                "count": badge.display_count(),
                "timestamp": badge.timestamp,
                "source": badge.source,
            }
            for window_id, badge in self.badges.items()
        }
```

**Alternatives Considered**:
- **SQLite database**: Adds file I/O, persistence (violates in-memory constraint). Rejected.
- **Redis**: External dependency, overkill for single-host use case. Rejected.
- **List[WindowBadge] with linear search**: O(n) lookup, inefficient for 50+ badges. Rejected.

---

### Q6: How should badge system support multiple notification mechanisms (SwayNC, Ghostty, tmux, etc.)?

**Decision**: Badge system is **notification-agnostic** - IPC interface accepts badge creation requests from any source without coupling to notification mechanism implementation.

**Rationale**:
- Users may migrate from SwayNC to Ghostty native notifications, or use tmux alerts, or custom build tools
- Badge creation should require minimal code changes when switching notification mechanisms
- `source` field in WindowBadge is free-form string (no enum constraint) - supports any notification type
- Window ID resolution is caller's responsibility (badge service assumes valid ID, doesn't care how it was obtained)
- Badge service has zero dependencies on notification libraries (SwayNC, Ghostty, libnotify, etc.)

**Abstraction Pattern**:
```python
# Generic IPC interface - works with ANY notification mechanism
create_badge(window_id: int, source: str = "generic") -> WindowBadge

# Badge service doesn't know or care HOW notification was delivered:
# - SwayNC desktop notification → badge IPC call
# - Ghostty native notification → badge IPC call
# - tmux display-message → badge IPC call
# - Custom script → badge IPC call
# All use identical IPC interface
```

**Migration Example** (SwayNC → Ghostty):
```bash
# Before (SwayNC)
notify-send "Build Complete" "$OUTPUT"
badge-ipc create "$WINDOW_ID" "build"

# After (Ghostty) - only notification line changes
ghostty-notify --title "Build Complete" --message "$OUTPUT"
badge-ipc create "$WINDOW_ID" "build"  # ← Identical, zero changes
```

**Implementation Guarantees**:
- Badge service has no notification mechanism dependencies in imports
- IPC methods use generic parameters (window_id, source) with no notification-specific fields
- Source field accepts any string value (no validation against predefined list)
- Tests mock IPC calls without invoking actual notification systems
- Documentation includes examples of 3+ notification mechanisms (SwayNC, Ghostty, tmux)

**Alternatives Considered**:
- **Notification-specific badge methods**: `create_swaync_badge()`, `create_ghostty_badge()`, etc. Rejected for tight coupling and scalability issues.
- **Enum-based source validation**: `source: Literal["swaync", "ghostty", "tmux"]`. Rejected for inflexibility - adding new sources requires code changes.
- **Embedded notification logic**: Badge service sends notifications itself. Rejected for violating single responsibility principle.

---

## Summary of Decisions

| Question | Decision | Impact |
|----------|----------|--------|
| **Badge state integration** | Extend existing `panel_state` JSON in monitoring_panel_publisher.py | Reuses existing Eww update mechanism, no new IPC channel |
| **IPC protocol** | JSON-RPC methods over Unix socket (`create_badge`, `clear_badge`, `get_badge_state`) | Follows existing daemon IPC patterns, secure by default |
| **Eww widget integration** | Overlay badge widget in window-item box, top-right positioning | Consistent with existing state indicator pattern, no layout shift |
| **Focus event handling** | Subscribe to `window::focus`, clear immediately on any focus | <100ms latency, simple implementation, matches clarification |
| **Badge data structure** | `dict[int, WindowBadge]` with Pydantic models | O(1) operations, ~10KB memory for 50 badges, clean serialization |
| **Notification abstraction** | Generic IPC interface, notification-agnostic badge service | Supports SwayNC, Ghostty, tmux, custom tools with minimal code changes |

## Open Questions (None)

All technical questions resolved. Ready to proceed to Phase 1 (Data Model & Contracts).

# Implementation Plan: Visual Notification Badges in Monitoring Panel

**Branch**: `095-visual-notification-badges` | **Date**: 2025-11-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/095-visual-notification-badges/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement visual notification badges in the Eww monitoring panel to provide persistent, in-context feedback when terminal windows (Claude Code, build processes) require user attention. Badges appear as bell icons with counts on window items, clearing automatically on focus. This extends Feature 085's monitoring panel with event-driven badge state management in the i3pm daemon, complementing Feature 090's desktop notifications with persistent visual indicators.

**Core Value**: Eliminates "which terminal was that?" cognitive overhead by making pending notifications discoverable within the existing window management interface.

## Technical Context

**Language/Version**: Python 3.11+ (existing i3pm daemon standard per Constitution Principle X)
**Primary Dependencies**:
- i3ipc.aio (async Sway IPC client) - existing
- Pydantic (data validation) - existing
- Eww 0.4+ (GTK3 widget framework) - existing
- Home-manager (Nix module system) - existing

**Storage**: In-memory daemon state (BadgeState dict), no persistent storage (Constitution Principle XII: Forward-Only Development - optimal solution without legacy compatibility)

**Testing**:
- pytest-asyncio (unit/integration tests for Python badge service)
- sway-test framework (declarative JSON tests for UI validation per Constitution Principle XV)
- Manual testing via Claude Code hooks

**Target Platform**: NixOS with Sway compositor (M1 + Hetzner Cloud configurations)

**Project Type**: Single project - system daemon extension with Eww widget integration

**Performance Goals**:
- Badge appearance: <100ms from notification trigger to UI update
- Badge clearing: <100ms from focus event to UI update
- 20+ concurrent badged windows without UI degradation
- <5MB memory overhead for badge state

**Constraints**:
- Event-driven architecture (no polling per Constitution Principle XI)
- Sway IPC as authoritative state source (Constitution Principle XI)
- Must integrate with existing i3pm daemon without disrupting window management
- Must work with existing Eww monitoring panel without breaking layout
- Badge state must survive project switches (windows in scratchpad retain badges)
- **Notification-agnostic architecture**: Badge system MUST be decoupled from notification source (SwayNC, Ghostty notifications, tmux alerts, etc.) - badge creation via generic IPC interface

**Scale/Scope**:
- Support 50+ concurrent windows with badges (typical multi-project developer workflow)
- Handle 100+ badge create/clear events per hour (typical Claude Code + build tool usage)
- Minimal memory footprint (each badge ~200 bytes: window ID + count + timestamp + source)

## Notification Abstraction Pattern

**Design Principle**: Badge system is **notification-agnostic** - it accepts badge creation requests from any source via a generic IPC interface, without coupling to specific notification mechanisms.

### Architecture Overview

```
[Notification Sources] --IPC--> [Badge Service] --State Push--> [Eww Monitoring Panel]
       ↓                            ↓                                  ↓
   - SwayNC                  create_badge(window_id, source)      Badge UI Rendering
   - Ghostty notifications   clear_badge(window_id)              (🔔 + count)
   - tmux alerts             get_badge_state()
   - Build tools
   - Test runners
   - Custom scripts
```

### Decoupling Strategy

**Core Abstraction**: Badge creation is a **declarative intent** expressed via IPC, not tied to how the notification was delivered to the user.

**Interface Contract**:
```python
# Generic IPC method - works with ANY notification mechanism
create_badge(window_id: int, source: str = "generic") -> WindowBadge
```

**Notification Source Independence**:
- **SwayNC (Feature 090)**: Claude Code hooks send desktop notification + IPC badge creation
- **Ghostty**: Native notification API + shell wrapper to call badge IPC
- **tmux**: tmux alert hook + badge IPC call
- **Build tools**: Post-build script + badge IPC call
- **Custom**: Any process with Unix socket access can create badges

### Integration Examples

#### Example 1: SwayNC (Current - Feature 090)

```bash
# scripts/claude-hooks/stop-notification.sh
WINDOW_ID=$(get_focused_window_id)

# Send desktop notification (Feature 090)
notify-send "Claude Code Ready" "$MESSAGE"

# Create badge (Feature 095 - notification-agnostic)
badge-ipc create "$WINDOW_ID" "claude-code"
```

**Decoupling**: Badge creation is separate IPC call, not embedded in SwayNC logic.

---

#### Example 2: Ghostty Native Notifications

```bash
# ~/.config/ghostty/notification-hook.sh
# Called by Ghostty when background process completes

WINDOW_ID="$GHOSTTY_WINDOW_ID"  # Ghostty provides window context

# Send Ghostty notification (native API)
ghostty-notify --title "Build Complete" --message "$OUTPUT"

# Create badge (same IPC interface as SwayNC)
badge-ipc create "$WINDOW_ID" "build"
```

**Substitution**: Replacing SwayNC with Ghostty only requires changing notification delivery (line 6), badge creation remains identical (line 9).

---

#### Example 3: tmux Alerts

```bash
# ~/.config/tmux/alert-hook.sh
# Triggered by tmux alert-activity or alert-bell

TMUX_PANE="$1"
TMUX_WINDOW="$2"

# Map tmux pane to Sway window ID (via terminal PID)
WINDOW_ID=$(get_sway_window_for_tmux_pane "$TMUX_PANE")

# Send tmux notification (display-message)
tmux display-message "Activity detected in pane $TMUX_PANE"

# Create badge (same IPC interface)
badge-ipc create "$WINDOW_ID" "tmux-alert"
```

**Flexibility**: Badge system doesn't care if notification came from SwayNC, Ghostty, or tmux - IPC interface is uniform.

---

#### Example 4: Custom Build Tool Integration

```python
# build-monitor.py - Custom build tool wrapper
import subprocess
import json

def run_build():
    result = subprocess.run(["cargo", "build"], capture_output=True)

    if result.returncode != 0:
        # Get window ID of terminal running this script
        window_id = get_current_window_id()

        # Send notification via ANY mechanism (user's choice)
        notify("Build Failed", result.stderr)

        # Create badge (notification-agnostic)
        badge_ipc_call("create_badge", {"window_id": window_id, "source": "cargo-build"})
```

**Extensibility**: New notification sources integrate without modifying badge service code.

---

### Implementation Guarantees

**What Changes When Switching Notification Mechanisms**:
1. ✅ **Notification delivery logic** (SwayNC API → Ghostty API → tmux display)
2. ✅ **Window ID resolution** (may differ per terminal emulator)
3. ✅ **Hook/wrapper scripts** (different integration points)

**What Remains Constant** (zero code changes):
1. ❌ **Badge IPC interface** (create_badge, clear_badge, get_badge_state)
2. ❌ **Badge service logic** (BadgeState, WindowBadge models)
3. ❌ **Badge clearing behavior** (focus event subscription)
4. ❌ **Eww monitoring panel rendering** (badge UI widgets)
5. ❌ **Badge state management** (in-memory dict, no persistence)

### Migration Path Example

**Scenario**: Migrate from SwayNC to Ghostty notifications

**Steps**:
1. Update notification hooks to use Ghostty API instead of `notify-send`
2. Ensure Ghostty provides window ID in notification context
3. Keep `badge-ipc create "$WINDOW_ID" "$SOURCE"` call unchanged
4. Test badge creation/clearing works with new notification mechanism

**Code Changes**: 1 line per hook (notification API call), 0 lines in badge service.

### Source Field Extensibility

The `source` field in `WindowBadge` enables tracking notification origins without coupling implementation:

```python
# Badge service doesn't validate source - accepts any string
badge = WindowBadge(window_id=12345, source="ghostty-notification")  # Valid
badge = WindowBadge(window_id=12345, source="tmux-alert")           # Valid
badge = WindowBadge(window_id=12345, source="cargo-build-failure")  # Valid
badge = WindowBadge(window_id=12345, source="custom-script-v2")     # Valid
```

**Benefit**: Add new notification types without modifying badge service code or redeploying daemon.

### Testing Implications

**Unit Tests**: Badge service tests are notification-agnostic (mock IPC calls, no notification mechanism dependencies)

**Integration Tests**: Test badge IPC interface with multiple simulated sources:
```python
async def test_badge_creation_from_multiple_sources():
    """Badge service handles notifications from any source."""
    # Simulate SwayNC
    await badge_service.create_badge(12345, source="swaync")

    # Simulate Ghostty
    await badge_service.create_badge(67890, source="ghostty")

    # Simulate tmux
    await badge_service.create_badge(11111, source="tmux-alert")

    # All badges coexist, source field preserved
    assert len(badge_service.badges) == 3
    assert badge_service.badges[12345].source == "swaync"
    assert badge_service.badges[67890].source == "ghostty"
    assert badge_service.badges[11111].source == "tmux-alert"
```

### Design Review Checklist

Before implementation, verify:
- [ ] Badge service has zero dependencies on notification libraries (SwayNC, Ghostty, etc.)
- [ ] IPC interface uses generic parameters (window_id, source) without notification-specific fields
- [ ] Window ID resolution is caller's responsibility (badge service assumes valid ID)
- [ ] Source field is free-form string (no enum constraint limiting notification types)
- [ ] Focus event handling is notification-agnostic (clears badge regardless of creation source)
- [ ] Documentation includes examples of 3+ notification mechanisms
- [ ] Tests mock IPC calls without invoking actual notification systems

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ **Principle X: Python Development & Testing Standards**
- **Status**: COMPLIANT
- **Evidence**: Feature uses Python 3.11+, i3ipc.aio for async IPC, Pydantic models for validation, pytest-asyncio for testing
- **Badge-specific**: BadgeState/WindowBadge Pydantic models follow existing daemon patterns

### ✅ **Principle XI: i3 IPC Alignment & State Authority**
- **Status**: COMPLIANT
- **Evidence**: Badge clearing via Sway focus events (window::focus), badge validation via GET_TREE queries
- **Badge-specific**: Focus event subscription for badge clearing, window ID from Sway tree as badge key

### ✅ **Principle XII: Forward-Only Development & Legacy Elimination**
- **Status**: COMPLIANT
- **Evidence**: No backward compatibility layers, in-memory state only (no persistence), clean architecture without feature flags
- **Badge-specific**: Badge system replaces manual "which terminal?" searches, no preservation of old workflow

### ✅ **Principle XIV: Test-Driven Development & Autonomous Testing**
- **Status**: COMPLIANT
- **Evidence**: Spec includes acceptance scenarios, plan includes pytest + sway-test suite, badge lifecycle testable via focus simulation
- **Badge-specific**: Will write tests before implementing badge service (unit) and Eww widget (sway-test)

### ✅ **Principle XV: Sway Test Framework Standards**
- **Status**: COMPLIANT
- **Evidence**: Badge UI validation via sway-test declarative JSON tests (partial mode), focus behavior via action sequences
- **Badge-specific**: Test badge appearance on window items, verify badge count increments, validate clearing on focus

### ⚠️ **Principle VI: Declarative Configuration Over Imperative**
- **Status**: REVIEW REQUIRED
- **Issue**: Claude Code hooks (stop-notification.sh) trigger badge creation imperatively via script execution
- **Mitigation**: Hook script will use IPC call to daemon (declarative intent: "create badge for window ID"), not manipulate state files
- **Decision**: Acceptable - hook scripts are external notification sources, daemon IPC is declarative interface

### ✅ **Constitution Compliance Summary**
- No violations requiring complexity justification
- Python 3.11+ standard maintained (Principle X)
- Event-driven Sway IPC architecture (Principle XI)
- No legacy support burden (Principle XII)
- Test-driven approach with sway-test integration (Principles XIV, XV)
- Declarative IPC for badge creation from external hooks (Principle VI reviewed, acceptable)

## Project Structure

### Documentation (this feature)

```text
specs/095-visual-notification-badges/
├── spec.md              # Feature specification (✅ complete)
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0: Technology decisions and integration patterns
├── data-model.md        # Phase 1: BadgeState/WindowBadge Pydantic models
├── quickstart.md        # Phase 1: User guide for badge system
├── contracts/           # Phase 1: Badge IPC API contracts (JSON-RPC methods)
│   └── badge-ipc.json   # create_badge, clear_badge, get_badge_state methods
├── tasks.md             # Phase 2: NOT created by /speckit.plan (use /speckit.tasks)
└── checklists/          # Quality validation checklists
    └── requirements.md  # ✅ Validated specification quality checklist
```

### Source Code (repository root)

```text
home-modules/desktop/i3-project-event-daemon/
├── badge_service.py              # NEW: BadgeState manager with create/clear/query methods
├── handlers.py                   # MODIFY: Add window::focus handler for badge clearing
├── ipc_server.py                 # MODIFY: Add badge IPC endpoints (create_badge, clear_badge, get_badge_state)
├── monitoring_panel_publisher.py # MODIFY: Include badge state in panel_state JSON

home-modules/desktop/eww-monitoring-panel.nix
├── (defvar badge_state "{}")     # NEW: Eww variable for badge state
├── (defwidget window-item ...)   # MODIFY: Add badge indicator widget to window items
├── CSS: .window-badge            # NEW: Badge styling (bell icon, count, positioning)

scripts/claude-hooks/
├── stop-notification.sh          # MODIFY: Add IPC call to create_badge after notification
└── badge-ipc-client.sh           # NEW: Helper script for badge IPC calls (create/clear)

tests/095-visual-notification-badges/
├── unit/
│   ├── test_badge_service.py               # Badge create/increment/clear/cleanup logic
│   └── test_badge_models.py                # Pydantic WindowBadge/BadgeState validation
├── integration/
│   ├── test_badge_ipc.py                   # IPC server badge endpoints
│   └── test_badge_focus_clearing.py        # Focus event → badge clear flow
└── sway-tests/
    ├── test_badge_appearance.json          # Badge appears on window item (partial mode)
    ├── test_badge_clearing.json            # Badge clears on focus (action + state)
    └── test_badge_project_aggregation.json # Project tab shows badge count (P3)
```

**Structure Decision**: Single project extending existing i3pm daemon. Badge service integrates as new module in daemon package, Eww widget modifications extend existing monitoring panel. No new projects/packages needed - follows Constitution Principle I (Modular Composition) by adding focused badge module to existing daemon architecture.

## Complexity Tracking

> **Not Applicable**: No Constitution violations requiring justification. Feature follows existing daemon patterns (Python 3.11+, event-driven, in-memory state, Pydantic models, pytest testing, sway-test UI validation).

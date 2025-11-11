# Implementation Plan: Workspace Mode Visual Feedback

**Branch**: `058-workspace-mode-feedback` | **Date**: 2025-11-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/etc/nixos/specs/058-workspace-mode-feedback/spec.md`

## Summary

Provide real-time visual feedback for workspace mode navigation by highlighting workspace buttons in the Eww workspace bar when digits are typed, and displaying a preview card showing the target workspace details (number, icon, application name). Additionally, display Apple-style circular notification badges on workspace buttons when workspaces have urgent windows, using Eww's native overlay widget for clean layering. This eliminates the current "blind navigation" problem where users cannot see which workspace they'll navigate to until after pressing Enter, and makes urgent workspace states more visually prominent.

**Technical Approach**: Extend the existing i3pm daemon `WorkspaceModeManager` to emit IPC events containing pending workspace state (`pending_workspace_number`, `accumulated_digits`, `mode_type`). The `sway-workspace-panel` Python daemon consumes these events via a new IPC subscription and emits updated Eww markup with pending highlight state. The Eww workspace bar CSS applies a distinct "pending" visual style (yellow color from Catppuccin Mocha palette). For notification badges, refactor workspace buttons to use Eww's native `overlay` widget, layering an 8px circular red dot on the top-right corner when workspace has urgent windows.

## Technical Context

**Language/Version**: Python 3.11+ (matching existing i3pm daemon and sway-workspace-panel)
**Primary Dependencies**: i3ipc.aio (async Sway IPC), Pydantic (data models), orjson (JSON serialization)
**Storage**: In-memory state in `WorkspaceModeManager`, no persistent storage required
**Testing**: pytest with pytest-asyncio, sway-test framework (TypeScript/Deno) for end-to-end UI validation
**Target Platform**: NixOS with Sway/Wayland compositor (M1 Mac and Hetzner Cloud headless)
**Project Type**: Single project (Nix home-manager modules + Python daemons)
**Performance Goals**: <50ms latency per keystroke (workspace mode digit → visual feedback), <10ms IPC event emission, <300ms preview card animations
**Constraints**: GTK CSS limitations (no `transform`, `filter`, `backdrop-filter`, `@keyframes`, `display:flex`), must use Eww-compatible CSS only
**Scale/Scope**: 70 workspaces max, 3 monitors, 2 daemons (i3pm + sway-workspace-panel), 1 Eww widget system

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ **Principle X: Python Development & Testing Standards**
- Python 3.11+ with async/await patterns for Sway IPC communication ✅
- Pydantic models for workspace mode state validation ✅
- pytest-asyncio for testing workspace mode event emission ✅
- i3ipc.aio for event-driven IPC subscriptions ✅

### ✅ **Principle XI: i3 IPC Alignment & State Authority**
- Workspace mode state emitted via i3pm daemon IPC events ✅
- sway-workspace-panel subscribes to workspace mode events via IPC ✅
- Pending workspace validation against Sway GET_WORKSPACES ✅
- Event-driven architecture (<100ms latency) ✅

### ✅ **Principle XII: Forward-Only Development & Legacy Elimination**
- No backwards compatibility needed - new feature ✅
- Existing workspace mode remains unchanged, only adds visual feedback ✅

### ✅ **Principle XIV: Test-Driven Development & Autonomous Testing**
- Unit tests for pending workspace calculation logic ✅
- Integration tests for IPC event emission and subscription ✅
- End-to-end tests using sway-test framework for UI validation ✅
- State verification via Sway IPC GET_TREE queries ✅

### ✅ **Principle XV: Sway Test Framework Standards**
- TypeScript/Deno sway-test for declarative workspace mode UI tests ✅
- Partial mode state comparison (focusedWorkspace, pending highlight CSS class) ✅
- Test definitions in JSON with autonomous execution ✅

### ⚠️ **Potential Violations** (None currently - monitoring for complexity)
- **No new module abstractions** - reuses existing WorkspaceModeManager, sway-workspace-panel
- **No new dependencies** - uses existing i3ipc.aio, Pydantic, Eww
- **No new daemons** - extends existing i3pm daemon and sway-workspace-panel

**Pre-Research Gate**: ✅ **PASS** - All relevant principles satisfied, no violations requiring justification

## Project Structure

### Documentation (this feature)

```text
specs/058-workspace-mode-feedback/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (GTK CSS constraints, IPC event design)
├── data-model.md        # Phase 1 output (WorkspaceModeEvent, PendingWorkspaceState)
├── quickstart.md        # Phase 1 output (user guide for visual feedback)
├── contracts/           # Phase 1 output (IPC event schema, Eww widget API)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Daemon Extensions (Python 3.11+)
home-modules/desktop/i3-project-event-daemon/
├── workspace_mode.py                  # EXISTING - Extend WorkspaceModeManager to emit IPC events
├── models.py                          # EXISTING - Add PendingWorkspaceState Pydantic model
└── ipc/
    └── workspace_mode_publisher.py    # NEW - IPC event publisher for workspace mode state

# Workspace Panel Daemon (Python 3.11+)
home-modules/tools/sway-workspace-panel/
├── workspace_panel.py                 # EXISTING - Subscribe to workspace mode IPC events
├── models.py                          # NEW - WorkspaceModeEvent model
└── formatters/
    └── workspace_yuck.py              # EXISTING - Extend Yuck formatter to include pending state

# Eww Workspace Bar (Nix + GTK CSS)
home-modules/desktop/
├── eww-workspace-bar.nix              # EXISTING - Add pending CSS class to workspace buttons
└── eww-workspace-bar-styles.scss      # EXISTING - Add "pending" visual style (yellow/peach)

# Tests
tests/workspace-mode-feedback/
├── unit/
│   ├── test_pending_workspace_calculation.py  # Unit test for workspace number resolution
│   └── test_ipc_event_emission.py             # Unit test for IPC event structure
├── integration/
│   ├── test_workspace_mode_ipc_flow.py        # Integration test: daemon → panel
│   └── test_panel_yuck_output.py              # Integration test: panel → Eww markup
└── sway-tests/
    ├── test_workspace_button_highlight.json   # End-to-end: button highlights on digit input
    └── test_multi_digit_accumulation.json     # End-to-end: 2 → 23 button transition
```

**Structure Decision**: Single project structure (default) with Python daemon extensions and Nix configuration files. No new executables or binaries - all code integrated into existing daemons (i3pm, sway-workspace-panel) via home-manager modules.

## Phase 0: Research & Unknowns

### Research Tasks

1. **GTK CSS Pending Highlight Design**
   - **Unknown**: What GTK-compatible CSS properties create a visually distinct "pending" state without using forbidden properties (transform, filter, etc.)?
   - **Investigate**: Eww CSS engine limitations, Catppuccin Mocha color palette (yellow/peach options), opacity/box-shadow alternatives
   - **Decision Criteria**: Must be visually distinct from focused (blue), visible-on-other-monitor (mauve), urgent (red), and empty states

2. **IPC Event Schema Design**
   - **Unknown**: What event structure efficiently communicates pending workspace state from i3pm daemon to sway-workspace-panel?
   - **Investigate**: Existing i3pm IPC event patterns, Sway tick event payload structure, orjson serialization performance
   - **Decision Criteria**: <10ms serialization time, minimal payload size (<500 bytes), backwards-compatible with existing IPC clients

3. **Multi-Monitor Pending Highlight**
   - **Unknown**: How does pending highlight handle multi-monitor workspace-to-monitor assignment (Feature 001)?
   - **Investigate**: Workspace-to-monitor mapping rules (WS 1-2 → primary, 3-5 → secondary, 6+ → tertiary), Eww multi-window coordination
   - **Decision Criteria**: Pending highlight appears on correct monitor's workspace bar, no cross-monitor visual conflicts

4. **Preview Card Implementation Strategy** (P2 - Future Enhancement)
   - **Unknown**: Should preview card be an Eww floating window, Sway layer-shell overlay, or notification?
   - **Investigate**: Eww floating window positioning API, Sway layer-shell protocol, notification daemon integration (mako/dunst)
   - **Decision Criteria**: <300ms fade animations, positioned near workspace bar, no Z-index conflicts

5. **Workspace Existence Validation Performance**
   - **Unknown**: Can pending workspace validation against Sway IPC (GET_WORKSPACES) complete within <50ms latency budget?
   - **Investigate**: Sway IPC GET_WORKSPACES response time with 70 workspaces, async/await overhead, caching strategies
   - **Decision Criteria**: 95th percentile latency <50ms, handles rapid digit entry (>10 keystrokes/second)

### Best Practices Research

1. **Async/Await Patterns for IPC Events**
   - Research: i3ipc.aio event subscription patterns, asyncio task scheduling, concurrent event processing
   - Goal: Ensure <100ms latency from workspace mode digit input to Eww markup update

2. **Eww Widget State Management**
   - Research: Eww `deflisten` variable update mechanisms, Yuck literal content interpolation, performance with 70+ workspaces
   - Goal: Real-time UI updates without flicker or visual artifacts

3. **GTK CSS Transition Performance**
   - Research: GTK CSS `transition` property support in Eww, opacity animation performance, box-shadow rendering cost
   - Goal: Smooth pending highlight transitions (<16ms frame time for 60fps)

## Phase 1: Design & Contracts

### Data Model (data-model.md)

**Entities**:

1. **PendingWorkspaceState**
   - Fields: `workspace_number` (int), `accumulated_digits` (str), `mode_type` (str: "goto" | "move"), `exists` (bool), `target_output` (str | null)
   - Validation: `workspace_number` range 1-70, `accumulated_digits` matches /^[0-9]{1,2}$/
   - Relationships: Derived from WorkspaceModeState.accumulated_digits
   - State Transitions: None (stateless DTO)

2. **WorkspaceModeEvent**
   - Fields: `event_type` (str: "enter" | "digit" | "cancel" | "execute"), `pending_workspace` (PendingWorkspaceState | null), `timestamp` (float)
   - Validation: `event_type` enum, `timestamp` > 0
   - Relationships: Published by WorkspaceModeManager, consumed by sway-workspace-panel
   - State Transitions: enter → digit → digit → execute | cancel

3. **WorkspaceButtonState** (Eww widget state)
   - Fields: `workspace_number` (int), `focused` (bool), `visible` (bool), `urgent` (bool), `pending` (bool), `empty` (bool)
   - Validation: Only one of `focused`, `pending` can be true (mutual exclusion)
   - Relationships: Mapped from Sway workspace + PendingWorkspaceState
   - State Transitions: normal → pending (on digit input), pending → focused (on execute), pending → normal (on cancel)

4. **NotificationBadge** (Eww overlay widget)
   - Fields: `visible` (bool), `workspace_number` (int)
   - Validation: `visible` true when workspace has urgent windows
   - Relationships: Layered on top of WorkspaceButtonState via Eww overlay widget
   - State Transitions: hidden → visible (on urgent window), visible → hidden (on urgent clear, <200ms fade-out)
   - Visual Specs: 8px diameter circle, Catppuccin Mocha Red (#f38ba8) background, 2px white border, border-radius: 50%

### API Contracts (contracts/)

**IPC Event Schema** (`workspace_mode_event.json`):

```json
{
  "event_type": "digit",
  "pending_workspace": {
    "workspace_number": 23,
    "accumulated_digits": "23",
    "mode_type": "goto",
    "exists": true,
    "target_output": "eDP-1"
  },
  "timestamp": 1699727482.5432
}
```

**Eww Yuck Widget API** (`workspace_button_yuck.edn`):

```lisp
; Refactored to use overlay widget for notification badge layering
(defwidget workspace-button [number_label workspace_name app_name icon_path workspace_id focused visible urgent pending empty]
  (overlay
    ; Base button (first child determines size)
    (button
      :class {
        "workspace-button "
        + (focused ? "focused " : "")
        + ((visible && !focused) ? "visible " : "")
        + (urgent ? "urgent " : "")
        + (pending ? "pending " : "")  ; NEW: Pending highlight
        + ((icon_path != "") ? "has-icon " : "no-icon ")
        + (empty ? "empty" : "populated")
      }
      :tooltip { app_name != "" ? (number_label + " · " + app_name) : workspace_name }
      :onclick { "swaymsg workspace \"" + replace(workspace_name, "\"", "\\\"") + "\"" }
      (box :class "workspace-pill" :orientation "h" :space-evenly false :spacing 3
        (image :class "workspace-icon-image" :path icon_path :image-width 16 :image-height 16)
        (label :class "workspace-number" :text number_label)))

    ; Notification badge overlay (only visible when urgent)
    (box
      :class "notification-badge-container"
      :valign "start"
      :halign "end"
      :visible urgent  ; NEW: Badge visibility tied to urgent state
      (label :class "notification-badge" :text ""))))  ; Empty label, styled as circular dot
```

**GTK CSS Contract** (`workspace_button_styles.scss`):

```scss
/* Pending state: Distinct yellow highlight */
.workspace-button.pending {
  background: rgba(249, 226, 175, 0.25);  /* Catppuccin Mocha Yellow */
  border: 1px solid rgba(249, 226, 175, 0.7);
  transition: all 0.2s;  /* Smooth transitions */
}

.workspace-button.pending .workspace-icon-image {
  -gtk-icon-shadow: 0 0 8px rgba(249, 226, 175, 0.8);
}

/* Mutual exclusion: pending overrides focused on same button */
.workspace-button.pending.focused {
  background: rgba(249, 226, 175, 0.25);  /* Pending takes priority */
  border: 1px solid rgba(249, 226, 175, 0.7);
}

/* Notification badge: Apple-style circular red dot */
.notification-badge-container {
  margin: 2px 2px 0 0;  /* Position in top-right corner */
}

.notification-badge {
  min-width: 8px;
  min-height: 8px;
  background: #f38ba8;  /* Catppuccin Mocha Red */
  border: 2px solid white;
  border-radius: 50%;  /* Perfect circle */
  opacity: 1;
  transition: opacity 0.2s;  /* Smooth fade-out */
}

/* Badge coexists with pending highlight (both can be visible) */
.workspace-button.pending + .notification-badge {
  /* No style override needed - both indicators independent */
}
```

### Integration Points

1. **WorkspaceModeManager → IPC Publisher**
   - Method: `_emit_workspace_mode_event(event_type: str, pending_workspace: PendingWorkspaceState | None)`
   - Called from: `add_digit()`, `execute()`, `cancel()`, `enter_mode()`
   - Latency budget: <5ms per emit

2. **IPC Publisher → sway-workspace-panel**
   - Transport: Sway tick event with JSON payload in `first` field
   - Subscription: sway-workspace-panel subscribes to `tick` events with `payload` filter `"workspace_mode:*"`
   - Processing: Parse JSON, update pending workspace state, regenerate Yuck markup

3. **sway-workspace-panel → Eww**
   - Output: Yuck markup with `pending` boolean field
   - Delivery: `deflisten` variable updates trigger Eww widget re-render
   - Latency budget: <20ms from IPC event to Eww markup emission

4. **Eww → GTK CSS Rendering**
   - Trigger: Yuck `literal` content update
   - CSS class: `.workspace-button.pending` applied to button widget
   - Rendering: GTK CSS engine applies peach background + border
   - Latency budget: <16ms for 60fps frame rendering

## Constitution Re-Check Post-Design

*Re-evaluate after Phase 1 design completion*

### ✅ **Principle X: Python Development & Testing Standards**
- Added `PendingWorkspaceState` Pydantic model with validation ✅
- Async IPC event emission via `asyncio.create_task()` ✅
- pytest-asyncio integration tests for IPC event flow ✅

### ✅ **Principle XI: i3 IPC Alignment & State Authority**
- Pending workspace validated against Sway IPC `GET_WORKSPACES` ✅
- Event-driven architecture via Sway `tick` events ✅
- No custom state tracking - derives from WorkspaceModeManager ✅

### ✅ **Principle XIV: Test-Driven Development**
- Unit tests for pending workspace calculation ✅
- Integration tests for IPC event emission ✅
- End-to-end tests using sway-test framework ✅

**Post-Design Gate**: ✅ **PASS** - Design aligns with all Constitution principles, no new violations introduced

## Complexity Tracking

> **No violations requiring justification** - All implementation reuses existing patterns and infrastructure.


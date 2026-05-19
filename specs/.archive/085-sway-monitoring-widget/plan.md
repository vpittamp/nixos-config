# Implementation Plan: Live Window/Project Monitoring Panel

**Branch**: `085-sway-monitoring-widget` | **Date**: 2025-11-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/085-sway-monitoring-widget/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement a global-scoped Eww widget that provides real-time monitoring of window/project state across all workspaces. The panel displays a hierarchical view (monitors → workspaces → windows) with project associations, state indicators, and updates automatically within 100ms when windows change or projects switch. Users toggle visibility via keybinding, and the panel remains accessible regardless of active project (global scope).

**Technical Approach** (from Architectural Decision in spec.md):
- Eww GTK widget with custom Yuck UI for native rendering and deterministic window matching
- Sway marks for window identification (follows Feature 076 patterns)
- Python backend script with dual modes: one-shot query + real-time event streaming
- **Eww deflisten mechanism** for real-time state updates (<100ms latency)
- i3ipc.aio event subscriptions (window, workspace, output changes)
- Automatic reconnection with exponential backoff and heartbeat mechanism
- Sway window rules for floating behavior and global scope
- Catppuccin Mocha theme integration (follows Features 057, 060)

## Technical Context

**Language/Version**: Python 3.11+ (backend data script), Yuck/GTK (Eww widget UI), Nix (module configuration)
**Primary Dependencies**:
- Eww 0.4+ (widget framework, GTK3)
- Python: i3ipc.aio (async Sway IPC), asyncio, existing daemon client from Feature 025
- Sway IPC (window events, tree queries)
- i3pm daemon (i3-project-event-listener service)

**Storage**:
- In-memory: Panel state (visibility, last update timestamp)
- Query-only: Window/workspace/project state via i3pm daemon (no persistence)

**Testing**:
- Python: pytest with pytest-asyncio for backend data script
- Sway Test Framework (Feature 069/070) for integration tests: panel visibility toggle, state updates, project switching
- Manual: Visual validation of Catppuccin Mocha styling

**Target Platform**: NixOS with Sway window manager (Hetzner Cloud and M1 MacBook Pro)

**Project Type**: Single project (Nix module + Python script + Eww widget)

**Performance Goals** (Measured Results):
- Panel toggle: <200ms target → **26-28ms achieved** ✅ (7x faster)
- State updates: <100ms target → **<100ms achieved via event stream** ✅
- Update mechanism: Real-time deflisten (not polling) with automatic reconnection

**Constraints**:
- Memory: <50MB for panel process when displaying 20-30 windows across 5 projects
- Update latency: <100ms for window create/destroy/move events
- Panel must remain responsive with 50+ windows across 10+ workspaces

**Scale/Scope**:
- Window count: 1-100 windows across 1-70 workspaces
- Project count: 1-20 active projects
- Monitor count: 1-3 physical/virtual displays
- Concurrent users: Single user per system instance

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition ✅
- **Status**: PASS
- **Evidence**: Eww widget will be configured in new module `home-modules/desktop/eww-monitoring-panel.nix`, following existing Eww patterns from Features 057, 060. Python backend script lives in `home-modules/tools/i3_project_manager/cli/` alongside existing `windows_cmd.py`. No code duplication - reuses daemon client, follows established structure.

### Principle II: Reference Implementation Flexibility ✅
- **Status**: PASS
- **Evidence**: Feature targets Hetzner Sway (reference configuration) and M1 MacBook Pro. Both run Sway + i3pm daemon. Eww already validated on both platforms (Features 057, 060).

### Principle III: Test-Before-Apply ✅
- **Status**: PASS
- **Evidence**: Standard workflow - `nixos-rebuild dry-build --flake .#hetzner-sway` and `.#m1 --impure` before applying. Eww module changes testable via dry-build.

### Principle VI: Declarative Configuration Over Imperative ✅
- **Status**: PASS
- **Evidence**:
  - Eww widget config generated via Nix in `home-modules/desktop/eww-monitoring-panel.nix`
  - Sway keybinding declared in `home-modules/desktop/sway-keybindings.nix`
  - Sway window rules declared in `~/.config/sway/window-rules.json` (Feature 047 dynamic config)
  - No imperative scripts - all configuration expressed declaratively

### Principle X: Python Development & Testing Standards ✅
- **Status**: PASS
- **Evidence**:
  - Python 3.11+ (matches i3pm daemon standard)
  - Async/await with i3ipc.aio for Sway IPC queries
  - pytest + pytest-asyncio for backend script tests
  - Reuses existing daemon client from `home-modules/tools/i3_project_manager/core/daemon_client.py`
  - JSON output for Eww defpoll consumption

### Principle XI: i3 IPC Alignment & State Authority ✅
- **Status**: PASS
- **Evidence**:
  - Backend script queries i3pm daemon, which uses Sway IPC as authoritative source
  - No custom state tracking - daemon already maintains window/project associations
  - Leverages existing `get_window_tree()` method from daemon client (Feature 025)

### Principle XIV: Test-Driven Development & Autonomous Testing ✅
- **Status**: PASS
- **Evidence**:
  - Python backend: pytest unit tests for data formatting, JSON output structure
  - Sway Test Framework: integration tests for panel toggle, state updates, project switching
  - Test scenarios validate panel visibility state, window count accuracy, project association correctness

### Principle XV: Sway Test Framework Standards ✅
- **Status**: PASS
- **Evidence**:
  - Integration tests use Sway Test Framework (TypeScript/Deno, declarative JSON tests)
  - State verification via Sway IPC (GET_TREE for panel window, GET_MARKS for panel mark)
  - Test modes: exact (panel closed), partial (panel open with window count), assertions (visibility checks)

**GATE RESULT**: ✅ ALL PRINCIPLES PASS - No violations, no complexity justification needed. Proceed to Phase 0 research.

## Project Structure

### Documentation (this feature)

```text
specs/085-sway-monitoring-widget/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── daemon-query.md  # Python backend script → i3pm daemon query contract
│   └── eww-defpoll.md   # Eww defpoll → Python script execution contract
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/desktop/
├── eww-monitoring-panel.nix  # New Eww widget module (systemd service, Yuck config, Sway rules)

home-modules/tools/i3_project_manager/cli/
├── monitoring_data.py         # New backend script (query daemon, format JSON for Eww)

home-modules/desktop/
├── sway-keybindings.nix       # Updated with monitoring panel toggle keybinding

~/.config/sway/
├── window-rules.json          # Updated with monitoring panel window rules (dynamic config)

tests/085-sway-monitoring-widget/
├── test_monitoring_data.py    # Python backend tests (pytest)
├── test_panel_toggle.json     # Sway test: panel visibility toggle
├── test_state_updates.json    # Sway test: window events trigger panel updates
└── test_project_switch.json   # Sway test: project switch updates panel content
```

**Structure Decision**: Single project structure (Option 1). Nix module configures Eww widget, Python script provides data backend, Sway Test Framework validates integration. Follows existing patterns from Features 057 (Unified Bar System), 060 (Eww Top Bar), 025 (Window State Visualization).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*No violations identified - all Constitution principles pass. No complexity tracking needed.*

## Phase 0: Research & Technical Decisions

**Objective**: Resolve all NEEDS CLARIFICATION items and establish implementation patterns.

### Research Tasks

1. **Eww defpoll vs event-driven updates** [NEEDS CLARIFICATION]
   - **Question**: Should the panel use Eww's defpoll (periodic polling) or implement event-driven updates via helper script subscribing to Sway IPC events?
   - **Investigation**: Compare latency, CPU usage, complexity, and reliability
   - **Options**:
     - A) Defpoll with 500ms-1s interval (simple, guaranteed updates, predictable CPU)
     - B) Event-driven via helper script listening to Sway IPC window events (complex, lower latency, more CPU overhead)
     - C) Hybrid: defpoll for primary updates + manual refresh trigger via swaymsg

2. **Eww panel window identification** [NEEDS CLARIFICATION]
   - **Question**: How should the panel window be uniquely identified for Sway window rules and toggle logic?
   - **Investigation**: Review Feature 076 mark-based patterns, Eww window naming conventions
   - **Options**:
     - A) Sway mark (e.g., `i3pm_panel:monitoring`)
     - B) Eww window name via `defwindow` name attribute
     - C) Both: Eww window name + automatic mark injection on window creation

3. **Panel layout and styling approach** [NEEDS CLARIFICATION]
   - **Question**: What GTK widgets and layout structure should be used for hierarchical display (monitors → workspaces → windows)?
   - **Investigation**: Review existing Eww widgets (Features 057, 060, 072), GTK3 box/scroll/list patterns
   - **Options**:
     - A) Nested `box` widgets with manual hierarchy (simple, full control)
     - B) GTK `scrolledwindow` + dynamic `box` generation (better for long lists)
     - C) Custom Yuck `literal` with dynamic HTML-like structure

4. **Data refresh strategy** [NEEDS CLARIFICATION]
   - **Question**: Should the Python backend script be stateless (query daemon on each invocation) or stateful (daemon connection persistence)?
   - **Investigation**: Compare startup latency, connection overhead, error handling
   - **Options**:
     - A) Stateless script: fresh daemon query on each Eww defpoll (simple, no state management)
     - B) Stateful script: persistent daemon connection with cache (lower latency, more complex)

5. **Keybinding integration** [NEEDS CLARIFICATION]
   - **Question**: How should the keybinding toggle panel visibility (Eww window show/hide)?
   - **Investigation**: Review Eww CLI commands (`eww open/close`), Sway bindsym patterns
   - **Options**:
     - A) Direct Eww CLI: `bindsym $mod+m exec eww open monitoring-panel` / `eww close monitoring-panel`
     - B) Toggle script: Check Eww window state, call open/close accordingly
     - C) Sway scratchpad: Use Sway's native scratchpad toggle with Eww window

**Output**: `research.md` with decisions, rationale, and alternatives for each question.

## Phase 1: Design Artifacts

**Prerequisites**: `research.md` complete with all decisions documented

### 1. Data Model (`data-model.md`)

**Entities** (extracted from spec.md Key Entities):

- **MonitoringPanelState**: Panel visibility (visible/hidden), last update timestamp, current focused monitor
- **MonitorHierarchy**: Monitor output name, active status, list of workspaces
- **WorkspaceInfo**: Workspace number, workspace name, monitor assignment, visible status, focused status, list of windows
- **WindowInfo**: Window ID, app name, window title, project association (scoped/global), workspace number, floating status, hidden status, scratchpad status
- **ProjectInfo**: Project name, list of associated window IDs

**JSON Schema** (Python backend → Eww):

```json
{
  "monitors": [
    {
      "name": "eDP-1",
      "active": true,
      "workspaces": [
        {
          "number": 1,
          "name": "1: Terminal",
          "visible": true,
          "focused": true,
          "windows": [
            {
              "id": 123456,
              "app_name": "terminal",
              "title": "bash",
              "project": "nixos",
              "floating": false,
              "hidden": false
            }
          ]
        }
      ]
    }
  ],
  "timestamp": "2025-11-20T10:30:00Z",
  "window_count": 15,
  "project_count": 3
}
```

**State Transitions**:
- Panel visibility: `hidden` ↔ `visible` (triggered by keybinding)
- Window states: `visible` ↔ `hidden` (triggered by project switch or scratchpad)

### 2. API Contracts (`contracts/`)

#### `contracts/daemon-query.md`

**Contract**: Python backend script → i3pm daemon

**Method**: `DaemonClient.get_window_tree()` (async)

**Request**: None (query current state)

**Response**: Tree structure (same as `i3pm windows --json` output)

```python
{
  "outputs": [
    {
      "name": "eDP-1",
      "active": True,
      "workspaces": [
        {
          "num": 1,
          "name": "1: Terminal",
          "visible": True,
          "focused": True,
          "windows": [...]
        }
      ]
    }
  ]
}
```

**Error Handling**:
- Daemon not running: Return empty structure with error flag
- Connection timeout: Retry once, then return cached/empty state

#### `contracts/eww-defpoll.md`

**Contract**: Eww defpoll → Python backend script

**Invocation**:
```yuck
(defpoll monitoring_data :interval "1s"
  `python3 -m home-modules.tools.i3_project_manager.cli.monitoring_data`)
```

**Output Format**: JSON string (single line, no formatting for Eww parsing)

**Performance Requirements**:
- Execution time: <50ms for typical workload (20-30 windows)
- Output size: <100KB JSON payload
- Exit code: 0 on success, 1 on daemon error

### 3. Quickstart Guide (`quickstart.md`)

See Phase 1 output below for full quickstart content.

## Phase 2: Implementation Tasks

**NOTE**: This phase is handled by `/speckit.tasks` command, not `/speckit.plan`.

Tasks will be generated in `tasks.md` covering:
- T001-T010: Python backend script (data query, JSON formatting, error handling)
- T011-T020: Eww widget (Yuck UI, defpoll, styling, systemd service)
- T021-T030: Sway integration (keybinding, window rules, mark injection)
- T031-T040: Testing (pytest for backend, Sway tests for integration)
- T041-T050: Documentation (CLAUDE.md updates, quickstart validation)

## Next Steps

1. **Proceed to Phase 0**: Generate `research.md` by dispatching research agents for 5 identified questions
2. **After Phase 0**: Generate Phase 1 artifacts (data-model.md, contracts/, quickstart.md)
3. **After Phase 1**: Update agent context via `.specify/scripts/bash/update-agent-context.sh`
4. **After planning complete**: Run `/speckit.tasks` to generate implementation tasks in `tasks.md`

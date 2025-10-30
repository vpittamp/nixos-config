# Research: Intelligent Automatic Workspace-to-Monitor Assignment

**Feature**: 049-intelligent-automatic-workspace
**Date**: 2025-10-29
**Research Phase**: Phase 0

## Overview

This document consolidates research findings for implementing automatic workspace redistribution across Sway monitors. All technical unknowns from the spec have been resolved through analysis of existing codebase patterns and Sway IPC capabilities.

## Research Topics

### 1. Sway Output Event Detection and Debouncing

**Research Question**: How should we detect monitor connect/disconnect events and debounce rapid changes?

**Decision**: Use Sway's native `output` event subscription via i3ipc protocol with asyncio task-based debouncing

**Rationale**:
- Sway implements i3 IPC protocol, including `output` event type for monitor changes
- Existing i3pm daemon already has event subscription infrastructure in handlers.py
- Debounce pattern already implemented for tick events (handlers.py:1400) - can reuse pattern
- asyncio task cancellation provides clean debounce implementation without race conditions

**Implementation Pattern** (from existing tick event handler):
```python
self._pending_reassignment_task = None

async def _on_output_event(self, i3: Connection, event: OutputEvent):
    if self._pending_reassignment_task:
        self._pending_reassignment_task.cancel()

    self._pending_reassignment_task = asyncio.create_task(
        self._debounced_reassignment()
    )

async def _debounced_reassignment(self):
    await asyncio.sleep(0.5)  # 500ms debounce
    # Perform reassignment logic
```

**Alternatives Considered**:
- Polling GET_OUTPUTS periodically: Rejected - violates event-driven principle (Constitution Principle XI)
- xrandr monitoring: Rejected - not Wayland-native, Sway IPC is authoritative source
- No debouncing: Rejected - would cause flapping during rapid monitor changes

**References**:
- Existing tick event handler: home-modules/desktop/i3-project-event-daemon/handlers.py:1400
- i3ipc-python output events: https://i3ipc-python.readthedocs.io/en/latest/events.html

---

### 2. Monitor Role Assignment Strategy

**Research Question**: How should we assign monitor roles (primary, secondary, tertiary) consistently?

**Decision**: Use Sway's output preferences if available, fallback to connection order based on Sway GET_OUTPUTS response order

**Rationale**:
- Sway GET_OUTPUTS returns outputs in a consistent order (primary first by default)
- Existing workspace_manager.py already queries outputs via i3 IPC (GET_OUTPUTS)
- User can set primary monitor via Sway config: `output HDMI-1 primary`
- Fallback to connection order ensures deterministic behavior even without explicit preferences

**Implementation Pattern**:
```python
async def assign_monitor_roles(self) -> dict[str, str]:
    outputs = await self.i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    roles = {}
    role_names = ["primary", "secondary", "tertiary"]
    for i, output in enumerate(active_outputs[:3]):
        roles[output.name] = role_names[i] if i < 3 else "overflow"

    return roles
```

**Alternatives Considered**:
- User-configurable preferences file: Rejected - adds configuration complexity, monitor order is sufficient
- Physical position detection: Rejected - Sway doesn't expose reliable position metadata
- MAC address/EDID tracking: Rejected - overcomplicated, connection order is deterministic enough

**References**:
- Existing monitor detection: home-modules/desktop/i3-project-event-daemon/workspace_manager.py

---

### 3. Workspace Distribution Algorithm

**Research Question**: What algorithm should we use to calculate workspace-to-monitor distribution?

**Decision**: Hardcoded distribution rules based on monitor count (1/2/3/4+ monitors)

**Rationale**:
- Simple, predictable distribution rules from spec are sufficient
- No configuration complexity - works out of the box
- Matches existing manual distribution expectations (WS 1-2 primary, WS 3-5 secondary, etc.)
- Easy to test and validate

**Distribution Rules** (from spec):
- 1 monitor: All workspaces (1-70) on primary
- 2 monitors: WS 1-2 primary, WS 3-70 secondary
- 3 monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-70 tertiary
- 4+ monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-9 tertiary, WS 10-70 overflow to remaining monitors

**Implementation Pattern**:
```python
def calculate_workspace_distribution(monitor_count: int, monitor_roles: dict) -> dict[int, str]:
    distribution = {}

    if monitor_count == 1:
        primary = next(name for name, role in monitor_roles.items() if role == "primary")
        for ws in range(1, 71):
            distribution[ws] = primary
    elif monitor_count == 2:
        primary = next(name for name, role in monitor_roles.items() if role == "primary")
        secondary = next(name for name, role in monitor_roles.items() if role == "secondary")
        for ws in range(1, 3):
            distribution[ws] = primary
        for ws in range(3, 71):
            distribution[ws] = secondary
    # ... etc for 3+ monitors

    return distribution
```

**Alternatives Considered**:
- Dynamic load balancing based on window count: Rejected - unpredictable, users expect consistent layout
- User-configurable distribution: Rejected - adds complexity, hardcoded rules are sufficient for MVP
- Evenly distribute workspaces: Rejected - users prefer primary monitor for core workspaces

---

### 4. Window Migration Approach

**Research Question**: How should we migrate windows from disconnected monitors?

**Decision**: Move workspaces (not individual windows) to new outputs using Sway IPC commands

**Rationale**:
- Sway's `workspace number N output OUTPUT_NAME` command reassigns entire workspace
- Preserves workspace numbers (WS 5 stays WS 5, just on different output)
- Simpler than moving individual windows, fewer IPC commands
- Maintains window relationships and layout within workspace

**Implementation Pattern**:
```python
async def migrate_windows_from_disconnected_monitors(self, old_outputs: set, new_distribution: dict):
    workspaces = await self.i3.get_workspaces()
    tree = await self.i3.get_tree()

    for ws in workspaces:
        if ws.output in old_outputs:  # Workspace on disconnected monitor
            # Find windows on this workspace
            windows = find_windows_on_workspace(tree, ws.num)

            if windows:
                # Move entire workspace to new output
                new_output = new_distribution[ws.num]
                await self.i3.command(f"workspace number {ws.num} output {new_output}")
```

**Alternatives Considered**:
- Move individual windows: Rejected - more complex, breaks workspace layout, more IPC calls
- Use scratchpad as intermediate: Rejected - unnecessary complexity, direct workspace move is cleaner
- Focus each workspace before moving: Rejected - causes visual flicker, workspace move works without focus

**References**:
- Existing window filtering: home-modules/desktop/i3-project-event-daemon/window_filter.py (scratchpad patterns)

---

### 5. State Persistence and Sway Config Manager Integration

**Research Question**: How should we persist monitor state and integrate with Sway Config Manager?

**Decision**: Persist to `~/.config/sway/monitor-state.json`, update `workspace-assignments.json` for Sway Config Manager

**Rationale**:
- Existing pattern: Sway Config Manager reads `workspace-assignments.json` for workspace rules
- Monitor state persistence enables preference tracking (User Story 4)
- JSON format matches existing configuration patterns
- File location matches Sway config directory convention

**Monitor State Schema**:
```json
{
  "version": "1.0",
  "last_updated": "2025-10-29T12:00:00Z",
  "active_monitors": [
    {"name": "HEADLESS-1", "role": "primary"},
    {"name": "HEADLESS-2", "role": "secondary"},
    {"name": "HEADLESS-3", "role": "tertiary"}
  ],
  "workspace_assignments": {
    "1": "HEADLESS-1",
    "2": "HEADLESS-1",
    "3": "HEADLESS-2"
    // ... etc
  }
}
```

**Workspace Assignments File** (updated by feature):
```json
[
  {"workspace": 1, "output": "HEADLESS-1"},
  {"workspace": 2, "output": "HEADLESS-1"},
  {"workspace": 3, "output": "HEADLESS-2"}
  // ... etc
]
```

**Alternatives Considered**:
- Separate config file for preferences: Rejected - adds another config file, integrate with Sway Config Manager instead
- SQLite database: Rejected - overcomplicated for simple key-value state
- No persistence: Rejected - loses preference tracking for User Story 4

**References**:
- Sway Config Manager template: Feature 047 specs/047-create-a-new/quickstart.md

---

### 6. Legacy Code Removal

**Research Question**: What legacy code must be removed per Forward-Only Development principle?

**Decision**: Remove `MonitorConfigManager` class and `workspace-monitor-mapping.json` completely in same commit

**Rationale**:
- Constitution Principle XII: Forward-Only Development & Legacy Elimination
- MonitorConfigManager class is replaced by simpler DynamicWorkspaceManager
- workspace-monitor-mapping.json is replaced by monitor-state.json
- No backwards compatibility required per assumptions

**Files to Delete**:
- `home-modules/desktop/i3-project-event-daemon/monitor_config_manager.py` (entire file)
- `~/.config/i3/workspace-monitor-mapping.json` (legacy state file)

**References to Remove**:
- handlers.py: Remove MonitorConfigManager imports and instantiation
- workspace_manager.py: Remove MonitorConfigManager usage
- ipc_server.py: Remove IPC commands that call MonitorConfigManager
- models.py: Remove WorkspaceMonitorConfig, MonitorDistribution, ConfigValidationResult Pydantic models

**Alternatives Considered**:
- Keep as "deprecated but working": Rejected - violates Principle XII
- Gradual migration with feature flag: Rejected - adds complexity, violates Principle XII
- Preserve for rollback: Rejected - NixOS generations provide rollback, no need for code preservation

---

### 7. Testing Strategy

**Research Question**: What testing approach should we use to validate monitor change scenarios?

**Decision**: Pytest with mocked i3 IPC responses, scenario-based tests simulating connect/disconnect workflows

**Rationale**:
- Python Development Standards (Principle X) require pytest with pytest-asyncio
- Mocking i3 IPC allows headless testing without real Sway session
- Scenario tests validate complete workflows (User Stories 1-2)
- Integration tests validate event handler debouncing and state persistence

**Test Structure**:
```
tests/i3-project-daemon/
├── unit/
│   ├── test_dynamic_workspace_manager.py    # Test distribution algorithm
│   └── test_workspace_distribution.py       # Test role assignment
├── integration/
│   └── test_output_event_handler.py         # Test debounce and migration
└── scenarios/
    └── test_monitor_changes.py              # End-to-end workflows
```

**Test Scenarios** (from User Stories):
1. Connect 3 monitors → verify distribution (WS 1-2 primary, 3-5 secondary, 6-9 tertiary)
2. Disconnect secondary monitor → verify windows migrate to remaining monitors
3. Rapid connect/disconnect → verify only one reassignment after debounce
4. 50 windows across 9 workspaces, disconnect 2 monitors → verify all windows accessible

**Mock Pattern**:
```python
@pytest.fixture
async def mock_i3_connection():
    conn = AsyncMock(spec=Connection)
    conn.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-2", active=True),
        Mock(name="HEADLESS-3", active=True)
    ]
    return conn
```

**Alternatives Considered**:
- Real Sway session testing: Rejected - requires GUI, not headless-friendly for CI/CD
- Manual testing only: Rejected - violates Python Development Standards
- Integration tests only: Rejected - need unit tests for algorithm validation

**References**:
- Existing test patterns: Python Development Standards (Constitution Principle X)

---

## Technology Stack Summary

| Component | Technology | Justification |
|-----------|-----------|---------------|
| Language | Python 3.11+ | Matches existing i3pm daemon, async/await support |
| IPC Library | i3ipc-python (i3ipc.aio) | Standard for Sway/i3 IPC communication |
| Async Framework | asyncio | Native Python async, used throughout daemon |
| Data Validation | Pydantic | Existing pattern in daemon for state models |
| Testing | pytest + pytest-asyncio | Python Development Standards requirement |
| State Persistence | JSON files | Matches existing configuration patterns |
| Event Handling | i3 IPC subscriptions | Event-driven architecture (Principle XI) |

---

## Implementation Risks and Mitigations

### Risk 1: Debounce timing too short/long
- **Impact**: Either flapping (too short) or slow responsiveness (too long)
- **Mitigation**: 500ms debounce is proven in existing tick event handler, tunable if needed

### Risk 2: Window migration race conditions
- **Impact**: Windows lost or duplicated during migration
- **Mitigation**: Sequential processing of workspaces, await IPC command completion before next

### Risk 3: Sway Config Manager conflict
- **Impact**: Manual Sway reload overwrites dynamic assignments
- **Mitigation**: Update workspace-assignments.json so `swaymsg reload` preserves distribution

### Risk 4: Performance degradation with 100+ windows
- **Impact**: Reassignment takes >2 seconds
- **Mitigation**: Batch IPC commands, profile with pytest-benchmark, optimize if needed

---

## Open Questions Resolved

**Q1**: Should we support manual workspace assignments persisting across reassignments?
**A**: Yes - User Story 4 (P3) requires preference persistence. Implement via monitor-state.json.

**Q2**: How do we handle monitors reconnecting with different names?
**A**: Use monitor roles (primary/secondary/tertiary) instead of names in distribution logic. Names only used for IPC commands.

**Q3**: Should we provide a CLI command to trigger manual reassignment?
**A**: No - automatic reassignment eliminates need for manual trigger. Remove Win+Shift+M binding.

**Q4**: How do we handle overflow workspaces (WS 10-70) with 4+ monitors?
**A**: Distribute evenly across monitors beyond tertiary. Simple round-robin assignment.

---

## Next Steps (Phase 1)

1. Generate data-model.md from entities in spec (MonitorState, WorkspaceDistribution, etc.)
2. Generate API contracts in /contracts/ (IPC commands, state file schemas)
3. Generate quickstart.md with usage examples and troubleshooting
4. Update agent context with new technology (none new - all existing stack)

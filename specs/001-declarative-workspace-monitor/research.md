# Research: Declarative Workspace-to-Monitor Assignment with Floating Window Configuration

**Feature**: 001-declarative-workspace-monitor
**Date**: 2025-11-10
**Status**: Complete

## Research Questions

This document addresses all "NEEDS CLARIFICATION" items from the Technical Context and provides best practices for key technology choices.

---

## 1. Monitor Role Resolution Strategy

### Decision: Three-Tier Role System with Fallback Chain

**Rationale**:
- Monitor roles provide logical abstraction: `primary`, `secondary`, `tertiary`
- Physical outputs (HDMI-A-1, eDP-1, etc.) are runtime-resolved via Sway IPC GET_OUTPUTS
- Fallback chain: `tertiary → secondary → primary` when monitors disconnect

**Implementation Approach**:
```python
class MonitorRoleResolver:
    """Resolves monitor roles to physical outputs with fallback logic."""

    def resolve_role(self, role: MonitorRole, available_outputs: List[Output]) -> Output:
        """
        Resolution strategy:
        1. If output_preferences configured, use preferred output for role
        2. Otherwise, assign by connection order: first=primary, second=secondary, third=tertiary
        3. Apply fallback chain if preferred role unavailable
        """
        pass
```

**Alternatives Considered**:
- **Hard-coded output names**: Rejected due to lack of portability (HDMI-A-1 on one system may be DP-1 on another)
- **Workspace ranges**: Rejected as less flexible than per-application configuration

**Best Practices**:
- Query Sway IPC GET_OUTPUTS to get active monitors at runtime
- Cache output list and update on `output` event subscriptions
- Validate role assignments against active outputs before applying
- Log warnings when fallback rules applied

---

## 2. Hot-Reload Integration with Feature 047

### Decision: Extend Feature 047's Template-Based Dynamic Configuration

**Rationale**:
- Feature 047 provides proven hot-reload mechanism for window rules (<100ms latency)
- Template-based approach avoids home-manager conflicts
- Git version control provides rollback capability

**Implementation Approach**:
- Add new dynamic config file: `~/.config/sway/workspace-assignments.json`
- Schema:
  ```json
  {
    "version": "1.0",
    "assignments": [
      {
        "workspace": 2,
        "app_name": "code",
        "monitor_role": "primary",
        "source": "app-registry"
      }
    ]
  }
  ```
- Daemon watches file via inotify (500ms debounce)
- On change: validate JSON → apply via Sway IPC commands → git commit
- Regenerate from Nix on rebuild: parse app-registry-data.nix → write JSON

**Alternatives Considered**:
- **Static Sway config with `workspace N output X`**: Rejected due to inability to hot-reload without Sway restart
- **Database storage**: Rejected as over-engineered; JSON files sufficient for ~100 assignments

**Best Practices**:
- JSON schema validation before applying changes
- Atomic file writes (write to .tmp, rename)
- Git auto-commit on successful validation
- Rollback via `swayconfig rollback` command (Feature 047 pattern)

---

## 3. Floating Window Size Presets

### Decision: Four Size Presets + Natural Size Fallback

**Rationale**:
- Based on Feature 062 scratchpad terminal (1200×600 centered positioning)
- Presets cover common use cases without requiring per-app pixel tuning

**Size Presets**:
| Preset | Dimensions | Use Case |
|--------|------------|----------|
| `scratchpad` | 1200×600 | Quick terminals, calculators, small utilities |
| `small` | 800×500 | System monitors, lightweight tools |
| `medium` | 1200×800 | Medium-sized apps, settings dialogs |
| `large` | 1600×1000 | Full-featured apps, development tools |
| (omitted) | Natural size | Application decides (default GTK/Qt window size) |

**Implementation via Sway Window Rules**:
```python
# Generate Sway for_window rules
for app in apps_with_floating:
    if app.floating_size:
        width, height = SIZE_PRESETS[app.floating_size]
        rule = f'for_window [app_id="{app.expected_class}"] floating enable, resize set {width} {height}, move position center'
    else:
        rule = f'for_window [app_id="{app.expected_class}"] floating enable, move position center'
```

**Alternatives Considered**:
- **Pixel-perfect custom dimensions**: Rejected as too complex for initial implementation
- **Percentage-based sizing**: Rejected due to inconsistent behavior across different monitor resolutions

**Best Practices**:
- Always center floating windows on current monitor
- Respect monitor boundaries (don't overflow)
- Allow manual resizing after initial positioning
- Persist manual size changes to window-rules.json (Feature 047 pattern)

---

## 4. Project Filtering Integration for Floating Windows

### Decision: Reuse Existing `scope` Field Logic

**Rationale**:
- `scope` field already differentiates scoped vs global applications
- Floating windows should follow same visibility rules as tiling windows
- No separate filtering logic needed

**Behavior**:
- **Scoped floating windows** (scope="scoped"): Hide to scratchpad on project switch, restore on project reactivation
- **Global floating windows** (scope="global"): Remain visible across all projects

**Implementation**:
```python
class FloatingWindowManager:
    def handle_project_switch(self, old_project: str, new_project: str):
        """Apply same filtering logic as tiling windows."""
        for window in get_floating_windows():
            if window.scope == "scoped" and window.project != new_project:
                sway_command(f'[con_id={window.id}] move scratchpad')
            elif window.scope == "scoped" and window.project == new_project:
                sway_command(f'[con_id={window.id}] scratchpad show')
```

**Alternatives Considered**:
- **Separate floating_scope field**: Rejected as redundant; existing scope field sufficient
- **Always-visible floating windows**: Rejected; defeats purpose of project isolation

**Best Practices**:
- Mark floating windows with Sway marks for tracking (e.g., `mark floating:btop`)
- Query via Sway IPC GET_TREE to find floating windows (`window.type == "floating_con"`)
- Respect manual workspace moves (user overrides persist until window closes)

---

## 5. Workspace Assignment Priority Resolution

### Decision: Explicit > Inferred > Default Hierarchy

**Priority Order**:
1. **Explicit `preferred_monitor_role`**: If app defines role, use it (highest priority)
2. **Inferred from workspace number**: If no role specified, infer from workspace distribution rules:
   - WS 1-2 → primary
   - WS 3-5 → secondary
   - WS 6+ → tertiary
3. **Default fallback**: If no workspace or role, assign to primary

**Conflict Resolution**:
- If multiple apps assign same workspace with different roles: last declaration wins, log warning
- PWA preferences override regular app preferences (PWAs more specific)

**Implementation**:
```python
def resolve_workspace_monitor_role(app: AppConfig, workspaces_map: Dict[int, str]) -> str:
    """Resolve monitor role for workspace assignment."""
    if app.preferred_monitor_role:
        return app.preferred_monitor_role.lower()

    # Infer from workspace number
    ws_num = app.preferred_workspace
    if ws_num in [1, 2]:
        return "primary"
    elif ws_num in [3, 4, 5]:
        return "secondary"
    else:
        return "tertiary"
```

**Best Practices**:
- Validate role names at Nix evaluation time (restrict to primary/secondary/tertiary)
- Case-insensitive comparison: "Primary" → "primary"
- Log all role assignments at INFO level for debugging
- Detect conflicts at configuration parse time, not runtime

---

## 6. State File Format Extension

### Decision: Extend Feature 049's `monitor-state.json` with Role Metadata

**Current Format (Feature 049)**:
```json
{
  "version": "1.0",
  "workspaces": {
    "1": "HEADLESS-1",
    "2": "HEADLESS-1",
    "3": "HEADLESS-2"
  }
}
```

**Extended Format (Feature 001)**:
```json
{
  "version": "2.0",
  "monitor_roles": {
    "primary": "HEADLESS-1",
    "secondary": "HEADLESS-2",
    "tertiary": "HEADLESS-3"
  },
  "workspaces": {
    "1": {
      "output": "HEADLESS-1",
      "role": "primary",
      "app_name": "terminal",
      "source": "app-registry"
    },
    "2": {
      "output": "HEADLESS-1",
      "role": "primary",
      "app_name": "code",
      "source": "app-registry"
    },
    "50": {
      "output": "HEADLESS-1",
      "role": "primary",
      "app_name": "youtube-pwa",
      "source": "pwa-sites"
    }
  }
}
```

**Migration Strategy**:
- Check version field on load
- If version 1.0, convert to 2.0 format (infer roles from workspace numbers)
- Write version 2.0 on save

**Best Practices**:
- Include metadata for debugging (app_name, source)
- Timestamp last update for staleness detection
- Validate schema on load, fail gracefully on parse errors
- Log diffs when state changes (old → new)

---

## 7. Sway IPC Command Strategy for Workspace Assignments

### Decision: Use `workspace N output <output>` Sway IPC Commands

**Rationale**:
- Sway supports runtime workspace-to-output assignment via IPC
- Assignments persist until Sway restart or manual override
- No need to reload entire Sway config

**Command Format**:
```python
async def assign_workspace_to_output(workspace_num: int, output_name: str):
    """Assign workspace to specific output via Sway IPC."""
    await sway.command(f'workspace {workspace_num} output {output_name}')
```

**Batch Assignment for Monitor Changes**:
```python
async def reassign_all_workspaces(assignments: Dict[int, str]):
    """Batch reassign workspaces on monitor connect/disconnect."""
    commands = [f'workspace {ws} output {output}' for ws, output in assignments.items()]
    # Sway IPC supports batch commands
    await sway.command('; '.join(commands))
```

**Alternatives Considered**:
- **Static Sway config reload**: Rejected due to disruption (all windows flicker)
- **Per-window moves**: Rejected as inefficient; workspace assignment is cleaner

**Best Practices**:
- Execute assignments in workspace number order (1, 2, 3, ...)
- Log each assignment at DEBUG level
- Verify assignment via GET_WORKSPACES query after applying
- Handle race conditions: debounce rapid output events (500ms)

---

## 8. Testing Strategy for Monitor Role Resolution

### Decision: Multi-Layer Test Pyramid

**Unit Tests (pytest)**:
- Test monitor role resolution logic in isolation
- Mock Sway IPC responses
- Validate fallback chain logic
- Test role inference from workspace numbers

**Integration Tests (pytest-asyncio)**:
- Test interaction with Feature 049 workspace assignment manager
- Verify state file read/write
- Test hot-reload mechanism with file watcher
- Validate Sway IPC command execution

**End-to-End Tests (sway-test framework)**:
- Declarative JSON test definitions
- Launch apps, verify workspace-to-output assignments via Sway IPC
- Disconnect monitors, verify automatic fallback
- Test floating window size and positioning

**Example sway-test JSON**:
```json
{
  "name": "VS Code assigned to primary monitor (workspace 2)",
  "actions": [
    {
      "type": "launch_app_sync",
      "params": {"app_name": "code"}
    }
  ],
  "expectedState": {
    "focusedWorkspace": 2,
    "workspaces": [
      {
        "num": 2,
        "output": "HEADLESS-1",
        "windows": [{"app_id": "Code"}]
      }
    ]
  }
}
```

**Best Practices**:
- Run tests on both hetzner-sway (3 monitors) and M1 (1 monitor)
- Use sway-test partial mode for focused assertions
- Mock monitor connect/disconnect events for automated testing
- Verify state via Sway IPC GET_TREE (authoritative source)

---

## Summary of Key Technologies

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Configuration Language | Nix expressions | Declarative, type-safe, hot-reloadable |
| Daemon Language | Python 3.11+ | Matches existing i3pm daemon, async support |
| IPC Library | i3ipc.aio | Async Sway IPC, event subscriptions |
| Data Validation | Pydantic | Type-safe models, automatic validation |
| State Storage | JSON files | Simple, version-controlled, human-readable |
| Testing (Unit) | pytest-asyncio | Python standard, async support |
| Testing (E2E) | sway-test | Declarative window manager tests |
| Hot-Reload | Feature 047 pattern | Proven <100ms latency, Git version control |
| Window Rules | Sway for_window | Native support for floating, sizing, positioning |

---

## Open Questions & Future Enhancements

**Resolved in this research**:
- ✅ How to resolve monitor roles to physical outputs
- ✅ How to integrate with Feature 047 hot-reload
- ✅ What floating window size presets to support
- ✅ How project filtering applies to floating windows
- ✅ State file format extensions
- ✅ Sway IPC command strategy
- ✅ Testing approach

**Future enhancements** (out of scope for initial implementation):
- Custom pixel-perfect floating window dimensions
- Per-monitor DPI scaling for floating windows
- Workspace-specific floating rules (WS 7 always floats)
- Multi-output spanning windows
- Monitor role priority lists (prefer [HDMI-A-1, DP-1] for primary)

---

**Status**: All research questions resolved. Ready for Phase 1 (Design & Contracts).

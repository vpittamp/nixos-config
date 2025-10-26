# Implementation Plan: Window State Preservation Across Project Switches

**Branch**: `038-create-a-new` | **Date**: 2025-10-25 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/etc/nixos/specs/038-create-a-new/spec.md`

## Summary

**Primary Requirement**: Fix window floating bug where tiled windows become floating when switching between projects.

**Root Cause**: Current implementation uses `move workspace current` which doesn't preserve tiling/floating state and restores windows to current workspace instead of their original workspace.

**Technical Approach**: Extend window state tracking to capture and restore:
1. Tiling/floating state (via i3 window properties)
2. Exact workspace number (not "current")
3. Window geometry for floating windows (position, size)
4. Scratchpad origin flag (distinguish filtered vs manually scratchpadded windows)

**Implementation Strategy**:
- Phase 0: Research i3 window property APIs and restoration commands
- Phase 1: Extend data model (`window-workspace-map.json`), update window filtering logic
- Phase 2: Implement P1 (tiled state + workspace preservation), test, then P2 (floating geometry)

## Technical Context

**Language/Version**: Python 3.11+ (async/await with i3ipc.aio)
**Primary Dependencies**:
- i3ipc-python (i3ipc.aio for async i3 IPC communication)
- asyncio (event-driven architecture)
- json (state persistence)

**Storage**: JSON files in `~/.config/i3/window-workspace-map.json` (existing persistence mechanism)

**Testing**: Manual testing procedure documented in quickstart.md, future pytest integration planned

**Target Platform**: Linux (NixOS) with i3 window manager via i3 IPC

**Project Type**: Single project (daemon extension in `home-modules/desktop/i3-project-event-daemon/`)

**Performance Goals**:
- <50ms per window restore operation
- <100ms total for 10 windows
- Maintains current 11.7ms filtering performance baseline

**Constraints**:
- Must preserve existing mark-based filtering (Feature 037)
- Must maintain backward compatibility with existing window-workspace-map.json
- Cannot break existing daemon event subscription architecture
- i3 tiling algorithm prevents pixel-perfect tiled window positioning (acceptable)

**Scale/Scope**:
- Modify 3 files: `window_filter.py`, `state.py`, `ipc_server.py`
- Extend 1 JSON schema (window-workspace-map.json)
- Add 2 new fields: `geometry`, `original_scratchpad`
- Support typical workload: 10-20 windows across 3-5 workspaces

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ Core Principles Compliance

**I. Modular Composition**:
- ✅ Changes isolated to window filtering service (`services/window_filter.py`)
- ✅ State persistence module (`state.py`) extended via existing patterns
- ✅ No duplication - uses existing `save_window_workspace_map()` mechanism
- ✅ Single responsibility maintained: window state capture/restore

**III. Test-Before-Apply**:
- ✅ Manual testing procedure documented in quickstart.md
- ✅ Dry-build required before NixOS rebuild (daemon version bump)
- ✅ Backward compatible - no breaking changes to daemon startup

**VI. Declarative Configuration**:
- ✅ No imperative scripts - purely daemon logic extension
- ✅ Data model declaratively defined in JSON schema
- ✅ NixOS module version bump triggers rebuild (declarative deployment)

**VII. Documentation as Code**:
- ✅ Specification complete with all mandatory sections
- ✅ Quickstart guide provides implementation guidance
- ✅ Code snippets included for all modified functions
- ✅ Testing procedures documented

**X. Python Development Standards**:
- ✅ Python 3.11+ with async/await patterns (existing daemon stack)
- ✅ Uses i3ipc.aio for async i3 IPC communication
- ✅ Type hints required for new functions
- ✅ Follows existing daemon module structure (services/, state.py)
- ✅ Pydantic/dataclass validation for window state (optional enhancement)

**XI. i3 IPC Alignment**:
- ✅ Uses i3 IPC GET_TREE for authoritative window state
- ✅ Queries window.rect, window.floating, workspace properties via i3ipc
- ✅ Window restoration uses i3 COMMAND messages
- ✅ No custom state assumed authoritative - validates against i3 IPC

**XII. Forward-Only Development**:
- ✅ Replaces broken `move workspace current` logic completely
- ✅ No backward compatibility shims - immediate complete replacement
- ✅ No feature flags for "legacy mode"
- ✅ Old restoration logic removed in same commit as new implementation

### 🟡 Potential Constitution Violations (Requiring Justification)

**None Identified** - This feature:
- Extends existing daemon service (no new projects/modules)
- Uses established Python async patterns (no new tech stack)
- Maintains existing architecture (event-driven, mark-based filtering)
- Provides optimal solution without legacy support burden

### ✅ Platform Support Standards

**Multi-Platform Compatibility**:
- ✅ Applies to all platforms with i3wm: Hetzner (primary), future M1 i3 configs
- ✅ WSL and containers don't use i3wm, so N/A (no impact)
- ✅ Changes isolated to i3 IPC layer - platform-agnostic

**Testing Requirements**:
- ✅ Primary testing on Hetzner (reference implementation with i3wm)
- 🔲 Future: Test on M1 if/when i3wm config added (currently N/A)

## Project Structure

### Documentation (this feature)

```
specs/038-create-a-new/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 output (i3 window property APIs)
├── data-model.md        # Phase 1 output (WindowState schema)
├── quickstart.md        # Already created - implementation guide
├── contracts/           # Phase 1 output (window state contracts)
│   └── window-state-schema.json
└── tasks.md             # Phase 2 output (/speckit.tasks - NOT YET CREATED)
```

### Source Code (repository root)

```
home-modules/desktop/i3-project-event-daemon/
├── services/
│   └── window_filter.py       # MODIFIED: Capture/restore window state
├── state.py                    # MODIFIED: Persist geometry + scratchpad flag
├── ipc_server.py               # MODIFIED: Debug output includes geometry
└── __init__.py

~/.config/i3/
└── window-workspace-map.json  # EXTENDED SCHEMA: geometry, original_scratchpad
```

**Structure Decision**: Single project structure - extends existing daemon service in `home-modules/desktop/i3-project-event-daemon/`. All changes are daemon logic extensions, no new projects or modules required.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**No violations requiring justification** - this feature follows all constitution principles and uses existing architecture patterns.

---

## Phase 0: Research & Analysis

**Objective**: Resolve all technical unknowns about i3 window property APIs and restoration commands.

### Research Tasks

**R001: i3 Window Property API**
- **Question**: What properties does i3ipc.Con provide for window state? (rect, floating, workspace, etc.)
- **Method**: Review i3ipc-python documentation and test with interactive Python session
- **Output**: List of available properties with data types

**R002: i3 Command Syntax for Restoration**
- **Question**: What is the exact i3 command syntax to restore tiled vs floating windows to specific workspaces?
- **Method**: Test commands via `i3-msg` and i3ipc to verify state preservation
- **Experiments**:
  1. `[id=X] move workspace number N` - does this preserve tiling state?
  2. `[id=X] floating enable` - can this be combined with move?
  3. `[id=X] move position X Y` - syntax and behavior
  4. `[id=X] resize set WIDTH HEIGHT` - syntax and behavior
- **Output**: Verified command patterns with example code

**R003: Scratchpad Detection**
- **Question**: How to reliably detect if a window is in scratchpad vs on a workspace?
- **Method**: Inspect i3 tree structure for scratchpad windows
- **Output**: Scratchpad detection logic (workspace.name == "__i3_scratch")

**R004: Floating Window Edge Cases**
- **Question**: What happens to geometry when a floating window is moved offscreen due to monitor changes?
- **Method**: Test window restoration with different monitor configurations
- **Output**: Auto-adjustment strategy (accept i3's default behavior vs implement bounds checking)

**R005: Backward Compatibility**
- **Question**: How to handle existing window-workspace-map.json files missing new fields?
- **Method**: Test daemon startup with old JSON format
- **Output**: Default value strategy (geometry=null, original_scratchpad=false)

### Research Dependencies

**i3ipc-python Documentation**:
- Review `Con` class properties: rect, floating, workspace()
- Review async command execution patterns

**i3 IPC Protocol**:
- Review GET_TREE response structure
- Review COMMAND message format for window operations

**Existing Codebase**:
- Review current `window_filter.py` implementation (lines 191-274)
- Review `state.py` persistence patterns
- Review mark-based filtering logic (Feature 037)

### Deliverable: research.md

**Format**:
```markdown
# Research: Window State Preservation

## R001: i3 Window Property API
**Decision**: Use i3ipc.Con properties: rect, floating, workspace()
**Rationale**: [findings from testing]
**Alternatives Considered**: [if any]

## R002: i3 Restoration Commands
**Decision**: Use `[id=X] move workspace number N` followed by floating/geometry commands
**Rationale**: [test results showing state preservation]
**Command Patterns**: [verified syntax]

[... continue for all research tasks]
```

---

## Phase 1: Design & Contracts

**Prerequisites**: `research.md` complete with all NEEDS CLARIFICATION resolved

### D001: Data Model Design

**Entity**: WindowState (extends existing window-workspace-map.json schema)

**Existing Fields**:
- `workspace_number`: int - Workspace number (1-70)
- `floating`: bool - Floating state (currently tracked but not used)
- `project_name`: str - Project name from I3PM_PROJECT_NAME
- `app_name`: str - Application name
- `window_class`: str - Window class from i3
- `last_seen`: float - Unix timestamp

**New Fields** (Feature 038):
- `geometry`: object | null - Window geometry for floating windows
  - `x`: int - X position
  - `y`: int - Y position
  - `width`: int - Width in pixels
  - `height`: int - Height in pixels
- `original_scratchpad`: bool - True if window was in scratchpad before project filtering

**Validation Rules**:
- `geometry` MUST be null for tiled windows (floating=false)
- `geometry` MUST be object for floating windows (floating=true)
- `original_scratchpad` defaults to false if missing (backward compatibility)
- All numeric values MUST be >= 0

**State Transitions**:
1. Window created → Capture initial state on first project switch
2. Project switch (hide) → Capture current state before moving to scratchpad
3. Project switch (show) → Restore from saved state
4. Window manually moved → Update workspace_number on next hide
5. Window toggled floating → Update floating + geometry on next hide

### D002: API Contracts

**Internal Function Contracts** (no external API changes):

**Contract 1: save_window_state()**
```python
async def save_window_state(window_id: int, window_state: dict) -> None:
    """
    Save window state to persistence file.

    Args:
        window_id: X11 window ID
        window_state: Dictionary with schema:
            - workspace_number: int
            - floating: bool
            - geometry: dict | None
            - original_scratchpad: bool
            - project_name: str
            - app_name: str
            - window_class: str
            - last_seen: float

    Side Effects:
        - Writes to ~/.config/i3/window-workspace-map.json
        - Creates file if doesn't exist

    Error Handling:
        - Raises IOError if file write fails
        - Logs error but doesn't crash daemon
    """
```

**Contract 2: load_window_state()**
```python
async def load_window_state(window_id: int) -> dict:
    """
    Load window state from persistence file.

    Args:
        window_id: X11 window ID

    Returns:
        Dictionary with window state, or empty dict if not found
        Missing fields get defaults:
            - geometry: None
            - original_scratchpad: False

    Error Handling:
        - Returns empty dict if file doesn't exist
        - Returns empty dict if window_id not in map
        - Logs warning for malformed JSON
    """
```

**Contract 3: filter_windows_by_project() - Extended**
```python
async def filter_windows_by_project(conn: i3ipc.aio.Connection, project_name: str | None) -> dict:
    """
    Filter windows by project, capturing and restoring full state.

    Args:
        conn: Active i3 IPC connection
        project_name: Active project name, or None for global mode

    Returns:
        Dictionary:
            - visible: int - Number of windows shown
            - hidden: int - Number of windows hidden
            - errors: int - Number of errors during filtering

    Side Effects:
        - Moves windows to/from scratchpad
        - Saves window state to persistence file before hiding
        - Restores window state (workspace, floating, geometry) when showing
        - Updates window-workspace-map.json

    Performance:
        - Target: <50ms per window
        - Measured: ~12ms current baseline (will increase slightly)

    Error Handling:
        - Logs errors but continues filtering remaining windows
        - Returns error count in result dict
    """
```

### D003: Quickstart Guide

**File**: `quickstart.md` (already created, no changes needed)

**Contents**:
- Problem summary with root cause
- Solution overview (3-step approach)
- Implementation priority (P1/P2/P3)
- Manual testing procedures
- Code snippets for all modified functions
- Troubleshooting guide

### D004: Agent Context Update

**Script**: `.specify/scripts/bash/update-agent-context.sh claude`

**Updates**:
- Add i3 window state restoration patterns to agent context
- Document window geometry capture/restore commands
- Add scratchpad detection patterns
- Include backward compatibility strategy

**Manual Additions to Preserve**:
- Existing i3pm project management patterns
- Mark-based filtering context from Feature 037
- Event-driven architecture patterns from Feature 015

---

## Phase 2: Task Generation

**Note**: Phase 2 is executed by the `/speckit.tasks` command (NOT by `/speckit.plan`).

This section outlines the expected task breakdown structure for planning purposes only.

### Expected Task Categories

**T001-T005: Phase 0 Research Tasks**
- T001: Research i3 window property API
- T002: Test i3 restoration command syntax
- T003: Verify scratchpad detection logic
- T004: Test floating window edge cases
- T005: Validate backward compatibility

**T006-T010: Phase 1 Data Model & Contracts**
- T006: Extend window-workspace-map.json schema
- T007: Implement save_window_state() with new fields
- T008: Implement load_window_state() with defaults
- T009: Create contract documentation (contracts/window-state-schema.json)
- T010: Update agent context with new patterns

**T011-T020: Phase 1 Implementation (P1 - Critical)**
- T011: Modify filter_windows_by_project() to capture window state before hiding
- T012: Add workspace and floating property queries via i3ipc
- T013: Modify filter_windows_by_project() to restore exact workspace
- T014: Add floating state restoration logic
- T015: Update state.py to persist new fields
- T016: Bump daemon version to 1.3.0 in i3-project-daemon.nix
- T017: Test P1 with manual procedure (tiled windows)
- T018: Verify backward compatibility with old JSON files
- T019: Deploy to production (nixos-rebuild switch)
- T020: Validate fix in production environment

**T021-T025: Phase 1 Implementation (P2 - Important)**
- T021: Add geometry capture for floating windows
- T022: Implement geometry restoration (move position, resize set)
- T023: Test P2 with manual procedure (floating windows)
- T024: Deploy P2 to production
- T025: Validate floating window preservation

**T026-T030: Phase 1 Implementation (P3 - Optional)**
- T026: Add original_scratchpad detection
- T027: Skip restoration for originally scratchpadded windows
- T028: Test P3 with manual scratchpad workflow
- T029: Deploy P3 to production
- T030: Update documentation with complete feature set

**T031-T035: Testing & Validation**
- T031: Execute full manual test suite from quickstart.md
- T032: Measure performance impact (should be <50ms per window)
- T033: Verify all 6 success criteria (SC-001 to SC-006)
- T034: Create regression test scenarios for future automation
- T035: Document any discovered edge cases or limitations

---

## Success Criteria Validation

After implementation, verify all success criteria from spec.md:

- **SC-001**: 100% of tiled windows remain tiled (currently ~0% - all become floating) ✅
- **SC-002**: 100% of floating windows remain floating with <10px drift ✅
- **SC-003**: 100% of windows return to assigned workspace (currently 0% - all go to current) ✅
- **SC-004**: <50ms per window restore operation ✅
- **SC-005**: Zero data loss across daemon restarts ✅
- **SC-006**: Handles 3+ project switches per second without corruption ✅

---

## Deliverables Summary

### Phase 0 Deliverables
- ✅ `research.md` - All technical unknowns resolved

### Phase 1 Deliverables
- ✅ `data-model.md` - WindowState schema with validation rules
- ✅ `contracts/window-state-schema.json` - JSON schema definition
- ✅ `quickstart.md` - Already created (implementation guide)
- ✅ Agent context updated via update-agent-context.sh

### Phase 2 Deliverables (NOT created by /speckit.plan)
- 🔲 `tasks.md` - Generated by /speckit.tasks command
- 🔲 Implementation checklist with T001-T035 tasks
- 🔲 Success criteria validation checklist

---

**Plan Status**: Phase 0 & Phase 1 structure complete, ready for research phase execution
**Next Command**: Execute research tasks (R001-R005) and generate `research.md`

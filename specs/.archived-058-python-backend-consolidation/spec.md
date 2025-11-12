# Feature Specification: Python Backend Consolidation

**Feature Branch**: `058-python-backend-consolidation`
**Created**: 2025-11-03
**Status**: Draft
**Input**: User description: "Consolidate TypeScript backend operations into Python daemon to eliminate code duplication, improve performance, and establish clear architectural separation between CLI (TypeScript UI) and backend (Python daemon)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Eliminate Duplicate Environment Reading (Priority: P1)

The system currently reads process environment variables (`/proc/<pid>/environ`) in two places: the TypeScript layout engine service and the Python daemon's window_environment module (Feature 057). This duplication creates maintenance burden, potential inconsistencies, and violates the single source of truth principle.

**Why this priority**: This is the highest-impact duplication with immediate negative consequences:
- Code maintenance burden (two implementations to maintain)
- Potential behavior inconsistencies between TypeScript and Python
- Foundation for all other consolidation work
- Blocks effective use of Feature 057's environment-based matching

**Independent Test**: Launch multiple applications with I3PM_* environment variables. Verify that both layout operations and window identification queries use the same Python implementation (no TypeScript /proc reads). Monitor performance - should show consistent sub-millisecond /proc read times across all operations.

**Acceptance Scenarios**:

1. **Given** the TypeScript CLI needs window environment information, **When** a user runs layout capture or window inspection commands, **Then** the CLI queries the Python daemon via JSON-RPC (no direct /proc filesystem access in TypeScript)
2. **Given** duplicate /proc reading code exists in `layout-engine.ts` (lines 101-121), **When** the consolidation is complete, **Then** this TypeScript code is removed and all environment reading goes through Python's `window_environment.py`
3. **Given** the Python daemon's `window_environment.py` module reads `/proc/<pid>/environ` in 0.4ms average, **When** the TypeScript CLI needs the same data, **Then** it receives the data from the daemon with <10ms total latency (including IPC overhead)
4. **Given** window environment data is needed for layout operations, **When** layouts are captured or restored, **Then** the daemon uses its existing `get_window_environment()` function (Feature 057) without any TypeScript code accessing `/proc` directly
5. **Given** both TypeScript and Python previously read environment variables, **When** a developer updates environment parsing logic, **Then** they only need to update one location (`window_environment.py` in the Python daemon)

---

### User Story 2 - Consolidate Layout Operations in Daemon (Priority: P2)

Layout capture and restore operations (saving window positions and restoring them) are currently implemented in TypeScript (`layout-engine.ts`). These operations require direct system access (reading window state, querying i3/Sway IPC, file I/O) that should be handled by the Python daemon.

**Why this priority**: Layout operations are backend functionality that belongs in the daemon:
- Requires system-level access (i3 IPC, filesystem, /proc)
- Benefits from direct i3ipc library access (vs shelling out to i3-msg)
- Natural fit with existing daemon capabilities (window tracking, environment reading)
- TypeScript should only handle CLI parsing and display formatting

**Independent Test**: Create a project with 5 open windows. Save the layout via CLI command (`i3pm layout save project-name`). Verify the daemon performs the capture operation (logs show Python execution, no TypeScript file I/O). Close all windows and restore the layout. Verify all 5 windows return to their saved positions with deterministic APP_ID matching.

**Acceptance Scenarios**:

1. **Given** a user wants to save their current window layout, **When** they run `i3pm layout save <project>`, **Then** the TypeScript CLI sends a JSON-RPC request to the daemon, and the daemon performs all window state queries and file I/O operations
2. **Given** the daemon has captured window layout data, **When** saving the layout to disk, **Then** windows are identified by their `I3PM_APP_ID` and `I3PM_APP_NAME` environment variables (using Feature 057's existing infrastructure)
3. **Given** a saved layout exists for a project, **When** a user runs `i3pm layout restore <project>`, **Then** the daemon reads the layout file, matches windows by APP_ID, and positions them without any TypeScript file system or i3 IPC access
4. **Given** layout operations previously shelled out to `i3-msg` and `xprop`, **When** operations are moved to the daemon, **Then** the daemon uses direct `i3ipc.aio` Python library calls (10-20x faster than shell commands)
5. **Given** a layout file contains 10 window positions, **When** restoring the layout, **Then** the daemon reports which windows were successfully restored vs missing (CLI displays this information formatted as a table)

---

### User Story 3 - Unify Project State Management (Priority: P3)

Project management (create, list, update, delete projects; track active project) is currently split between TypeScript (`project-manager.ts`) and Python daemon. Both services read and write the same JSON files, creating potential race conditions and duplicate state management logic.

**Why this priority**: Project state should have a single source of truth:
- Prevents race conditions when both TypeScript and Python access same files
- Daemon already needs project context for window filtering (Feature 037, 057)
- Simplifies state management (one authoritative source)
- TypeScript CLI becomes a pure display layer

**Independent Test**: Create, list, update, and delete projects entirely via CLI commands. Verify all operations are handled by the daemon (check daemon logs). Verify both CLI and daemon always see consistent project state. Test concurrent operations (multiple CLI commands) to ensure no file corruption or race conditions.

**Acceptance Scenarios**:

1. **Given** a user wants to create a new project, **When** they run `i3pm project create <name> --dir <path>`, **Then** the TypeScript CLI sends a JSON-RPC request to the daemon, and the daemon performs all validation, file I/O, and state updates
2. **Given** the daemon maintains the authoritative project list, **When** a CLI command queries projects, **Then** the CLI requests the list from the daemon (no direct JSON file reading in TypeScript)
3. **Given** a user switches active projects, **When** they run `i3pm project switch <name>`, **Then** the daemon updates the active project state AND triggers window filtering automatically (leveraging existing `window_filter.py` from Feature 057)
4. **Given** both TypeScript and Python previously read `~/.config/i3/projects/*.json` files, **When** consolidation is complete, **Then** only the daemon accesses these files (TypeScript project-manager.ts is deleted)
5. **Given** project operations require directory validation, **When** creating or updating a project, **Then** the daemon performs all filesystem checks and returns validation errors to the CLI for display

---

### User Story 4 - Establish Clear Architectural Boundaries (Priority: P4)

After consolidating backend operations, the codebase should have clear architectural separation: TypeScript handles CLI user interface (argument parsing, table rendering, output formatting) while Python handles all backend operations (system access, state management, business logic).

**Why this priority**: Clear architecture improves maintainability long-term:
- Easier onboarding for new developers (clear boundaries)
- Simpler testing (UI tests vs backend tests)
- Better performance (native Python-i3 communication, no unnecessary shell commands)
- Foundation for future features (know where new code belongs)

**Independent Test**: Review all TypeScript services. Verify no backend operations remain (no file I/O, no shell commands to i3-msg/xprop, no /proc access). All TypeScript code should fall into these categories: CLI parsing, daemon client communication, display formatting (tables/trees), or UI components.

**Acceptance Scenarios**:

1. **Given** the TypeScript codebase, **When** the refactoring is complete, **Then** services like `layout-engine.ts` and `project-manager.ts` are deleted (approximately 1000 lines removed)
2. **Given** TypeScript CLI commands, **When** they need backend operations, **Then** all commands use `DaemonClient` to send JSON-RPC requests (no direct system access)
3. **Given** the Python daemon exposes operations via JSON-RPC, **When** new features are added, **Then** developers know to implement backend logic in Python and UI logic in TypeScript
4. **Given** TypeScript previously contained ~1000 lines of backend logic, **When** consolidation is complete, **Then** this is replaced by ~500 lines of Python daemon code (better suited for backend operations)
5. **Given** operations that previously shelled out to system commands, **When** moved to Python daemon, **Then** performance improves 10-20x (direct i3ipc library vs subprocess overhead)

---

### Edge Cases

- What happens when the daemon is not running and a CLI command requires backend operations? (CLI should display clear error: "Daemon not running. Start with: systemctl --user start i3-project-event-listener")
- How does system handle concurrent CLI commands accessing the same project or layout file? (Daemon serializes operations, preventing corruption)
- What happens when a layout file references windows by APP_ID but those apps are no longer running? (Daemon reports missing windows to CLI, which displays them in a "not restored" list)
- How does the system handle TypeScript code removal without breaking existing user workflows? (All CLI commands continue to work identically - implementation change is transparent to users)
- What happens if Feature 057 environment reading fails for a window during layout operations? (Daemon falls back to window class for that specific window, logs warning, continues with other windows)
- How does the system maintain backward compatibility with existing layout files that might use window class instead of APP_ID? (Daemon detects old format, attempts best-effort migration, warns user if migration is needed)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Python daemon MUST provide JSON-RPC methods for all layout operations (capture, restore, save, load, list)
- **FR-002**: The Python daemon MUST provide JSON-RPC methods for all project operations (create, read, update, delete, list, get_active, set_active)
- **FR-003**: Layout capture MUST identify windows using I3PM_APP_ID and I3PM_APP_NAME from environment variables (leveraging Feature 057's `window_environment.py`)
- **FR-004**: Layout restore MUST match saved windows to current windows by APP_ID with deterministic matching (no class-based ambiguity)
- **FR-005**: The TypeScript CLI MUST use DaemonClient for all backend operations (no direct file I/O, no shell commands to i3-msg/xprop, no /proc access)
- **FR-006**: The daemon MUST use direct `i3ipc.aio` library calls for window tree queries (not shell commands to i3-msg)
- **FR-007**: Project state files MUST be accessed exclusively by the daemon (single source of truth, preventing race conditions)
- **FR-008**: The daemon MUST serialize concurrent operations on the same project or layout to prevent file corruption
- **FR-009**: The CLI MUST display clear error messages when the daemon is unreachable
- **FR-010**: All layout files MUST be saved in JSON format with schema version for future migration support
- **FR-011**: The daemon MUST automatically trigger window filtering when active project changes (using existing `window_filter.py`)
- **FR-012**: The TypeScript services `layout-engine.ts` and `project-manager.ts` MUST be removed after their functionality is moved to Python
- **FR-013**: The daemon MUST log all layout and project operations for debugging and audit purposes
- **FR-014**: CLI commands MUST maintain identical syntax and behavior (refactoring is implementation-only, user-facing interface unchanged)
- **FR-015**: The daemon MUST provide detailed error responses when operations fail (validation errors, missing files, permission errors, etc.)

### Key Entities

- **Layout Snapshot**: Represents the captured state of all windows at a point in time, identified by project name, containing window positions, dimensions, floating state, and APP_ID/APP_NAME for each window
- **Window Snapshot**: Individual window state within a layout, including workspace number, output name, geometry (x, y, width, height), floating status, focus state, and environment-based identifiers (APP_ID, APP_NAME)
- **Project**: Represents a development project or workspace context, containing name, directory path, display name, icon, timestamps (created/updated), and associated layout files
- **Active Project State**: Singleton representing which project is currently active, persisted to disk, used to determine window visibility filtering

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Layout operations complete in under 100ms for workspaces with up to 50 windows (10-20x faster than shell-based approach)
- **SC-002**: Zero code duplication between TypeScript and Python for environment variable reading (currently duplicated in `layout-engine.ts` lines 101-121)
- **SC-003**: TypeScript codebase reduced by approximately 1000 lines through deletion of `layout-engine.ts` and `project-manager.ts`
- **SC-004**: Python daemon code increases by approximately 500 lines (net reduction of 500 lines total)
- **SC-005**: All layout restore operations achieve 100% window matching when APP_IDs are available (deterministic matching, no ambiguity)
- **SC-006**: CLI commands maintain identical user-facing behavior (same arguments, same output format, same error messages)
- **SC-007**: Zero race conditions in project state management (verified through concurrent operation testing)
- **SC-008**: Daemon handles at least 100 concurrent CLI requests without performance degradation
- **SC-009**: Error messages clearly guide users when daemon is not running or operations fail (user satisfaction metric)
- **SC-010**: All existing layout files continue to work after migration (backward compatibility)

## Scope *(mandatory)*

### In Scope

- Moving layout capture/restore operations from `layout-engine.ts` to Python daemon
- Moving project CRUD operations from `project-manager.ts` to Python daemon
- Adding JSON-RPC methods to daemon IPC server for layout and project operations
- Updating TypeScript CLI commands to use DaemonClient exclusively
- Removing duplicate /proc environment reading from TypeScript
- Removing TypeScript services after functionality migration
- Documentation updates for architecture changes
- Testing all operations work via daemon

### Out of Scope

- Changes to CLI command syntax or user-facing behavior (implementation-only refactor)
- New features beyond consolidation (no new layout or project capabilities)
- Migration of UI/display logic from TypeScript (TypeScript retains table rendering, TUI interfaces)
- Changes to registry service unless it contains backend operations requiring consolidation
- Performance optimization beyond natural improvements from consolidation
- Database or alternative storage mechanisms (continue using JSON files)

## Dependencies *(mandatory)*

### Prerequisites

- **Feature 057** (Environment Variable-Based Window Matching): Consolidation depends on `window_environment.py`, `window_filter.py`, and environment-based identification being complete and functional
- **Python daemon IPC server**: Must support JSON-RPC 2.0 method registration
- **TypeScript DaemonClient**: Must support async/await communication with daemon
- **i3ipc.aio library**: Python async i3 IPC library must be available

### Related Features

- **Feature 037**: Window filtering and project switching (daemon already has window filtering logic that will be used)
- **Feature 041**: Launch context tracking (layout operations will leverage launch notifications)
- **Feature 035**: Registry-centric architecture (project manager will integrate with existing registry)

## Assumptions *(mandatory)*

1. **Daemon availability**: Users run the i3-project-event-daemon as a systemd service (standard setup)
2. **Python version**: Python 3.11+ is available (already required by Feature 057)
3. **File format**: JSON is acceptable for layout and project storage (no migration to database)
4. **Performance target**: <100ms for layout operations on 50-window workspaces is achievable with direct i3ipc
5. **Migration strategy**: Can delete TypeScript services after Python equivalents are tested and working
6. **Backward compatibility**: Layout files can be migrated on-the-fly when old format is detected
7. **Error handling**: JSON-RPC error responses are sufficient for CLI error display
8. **Concurrency model**: Daemon's event loop can handle serialized concurrent operations
9. **Testing approach**: Integration tests can validate daemon operations via JSON-RPC

## Risks *(mandatory)*

### Technical Risks

- **Risk**: Layout restore may fail if APP_IDs are not available (old layout files or apps without environment variables)
  - **Mitigation**: Implement fallback to window class matching with warning logged, detect old layout format and offer migration

- **Risk**: Performance regression if JSON-RPC overhead is high
  - **Mitigation**: Benchmark JSON-RPC latency early, ensure <10ms overhead, consider connection pooling if needed

- **Risk**: Breaking changes if TypeScript code removal affects other modules
  - **Mitigation**: Review all imports of `layout-engine.ts` and `project-manager.ts` before deletion, run full test suite after removal

- **Risk**: Daemon crashes could block all CLI operations
  - **Mitigation**: Daemon already has watchdog monitoring, ensure CLI displays helpful error when daemon unreachable

### Process Risks

- **Risk**: Large refactor may introduce subtle behavioral changes
  - **Mitigation**: Implement feature flag for new code paths, enable gradually, maintain side-by-side operation during transition

- **Risk**: Testing may miss edge cases in layout/project operations
  - **Mitigation**: Write comprehensive integration tests, test with real user workflows, review all acceptance scenarios

## Open Questions

None - all architectural decisions are informed by the analysis in `/etc/nixos/specs/057-env-window-matching/ARCHITECTURE_REFACTORING.md`

## Revision History

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2025-11-03 | 1.0 | Initial specification | Claude Code |

---

**Next Steps**:
1. Run `/speckit.clarify` to identify any specification gaps
2. Run `/speckit.plan` to create implementation plan with task breakdown
3. Review architecture refactoring document for detailed technical approach

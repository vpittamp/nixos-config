# Implementation Tasks: Event-Based i3 Project Synchronization

**Feature**: 015-create-a-new
**Branch**: 015-create-a-new
**Created**: 2025-10-20
**Status**: Ready for Implementation

## Summary

Replace polling-based i3 project management with event-driven architecture using i3 IPC subscriptions. Implement long-running daemon with in-memory state, mark-based window tracking, and JSON-RPC IPC for CLI tools.

**Technology Stack**:
- Language: Python 3.11+ with asyncio
- IPC Library: i3ipc-python (only external dependency)
- Daemon Management: systemd user service
- State Storage: In-memory (persistent config in JSON files)

**User Stories** (from spec.md):
1. **US1 (P1)**: Real-time Project State Updates - instant status bar reflection (<200ms)
2. **US2 (P2)**: Automatic Window Tracking - event-based marking (<200ms)
3. **US4 (P2)**: Application Workspace Distinction - PWAs and terminal apps as separate applications
4. **US3 (P3)**: Workspace State Monitoring - multi-monitor awareness

---

## Phase 1: Setup & Infrastructure

### T001 - Setup NixOS Module Structure [P]
**Story**: Foundation
**File**: `home-modules/desktop/i3-project-daemon.nix`

Create the NixOS home-manager module structure for the event listener daemon.

**Tasks**:
1. Create `home-modules/desktop/i3-project-daemon.nix` with module skeleton
2. Define module options:
   - `services.i3ProjectDaemon.enable` (bool)
   - `services.i3ProjectDaemon.logLevel` (enum: DEBUG|INFO|WARNING|ERROR, default "INFO")
   - `services.i3ProjectDaemon.autoStart` (bool, default true)
3. Add conditional logic: Only enable if `config.xsession.windowManager.i3.enable = true`
4. Add assertions to validate i3 is enabled
5. Add systemd tmpfiles rules for directories: `%t/i3-project-daemon`, `%h/.config/i3/projects`, `%h/.config/i3/app-identification`
6. Document module options in comments

**Dependencies**: None
**Test**: `nix eval .#nixosConfigurations.hetzner.config.home-manager.users.vpittamp.services.i3ProjectDaemon`

---

### T002 - Create Python Project Structure [P]
**Story**: Foundation
**Directory**: `home-modules/desktop/i3-project-event-daemon/`

Set up Python project structure for the daemon.

**Tasks**:
1. Create directory `home-modules/desktop/i3-project-event-daemon/`
2. Create `__init__.py` (empty or version export)
3. Create `py.typed` marker file for type checking
4. Create `setup.py` or `pyproject.toml` for packaging (minimal, NixOS-managed)
5. Create `.python-version` file (3.11)

**Dependencies**: None
**Test**: Directory structure exists, Python can import package

---

### T003 - Define Python Data Models (dataclasses) [P]
**Story**: Foundation
**File**: `home-modules/desktop/i3-project-event-daemon/models.py`

Define TypeScript-like interfaces using Python dataclasses for all entities from data-model.md.

**Tasks**:
1. Create `models.py`
2. Define `DaemonState` dataclass with connection state, runtime stats, project state
3. Define `WindowInfo` dataclass with window identity, properties, project association
4. Define `ProjectConfig` dataclass with project metadata
5. Define `ActiveProjectState` dataclass
6. Define `ApplicationClassification` dataclass
7. Define `EventQueueEntry` dataclass
8. Define `WorkspaceInfo` dataclass
9. Add type hints using `typing` module (Optional, List, Dict, Set)
10. Add `__post_init__` validation where needed

**Dependencies**: None
**Test**: Import models, instantiate dataclasses, validate type hints with mypy

---

### T004 - Implement Configuration Loader
**Story**: Foundation
**File**: `home-modules/desktop/i3-project-event-daemon/config.py`

Load project configurations and application classification from JSON files.

**Tasks**:
1. Create `config.py`
2. Implement `load_project_configs(config_dir: Path) -> Dict[str, ProjectConfig]`
   - Scan `~/.config/i3/projects/*.json`
   - Parse JSON into `ProjectConfig` dataclass
   - Validate project names, directories
   - Handle missing/invalid files gracefully
3. Implement `load_app_classification(config_file: Path) -> ApplicationClassification`
   - Load `~/.config/i3/app-classes.json`
   - Parse into `ApplicationClassification` dataclass
   - Validate no overlap between scoped/global sets
4. Implement `save_active_project(state: ActiveProjectState, config_file: Path)`
   - Atomic write using temp file + rename pattern
5. Implement `load_active_project(config_file: Path) -> Optional[ActiveProjectState]`
6. Add error logging for invalid configs

**Dependencies**: T003 (models.py)
**Test**: Create test JSON files, verify parsing, test atomic writes

---

## Phase 2: Foundational Components

### T005 - Implement State Manager
**Story**: Foundation (blocks all user stories)
**File**: `home-modules/desktop/i3-project-event-daemon/state.py`

Manage in-memory daemon state with thread-safe operations.

**Tasks**:
1. Create `state.py`
2. Implement `StateManager` class:
   - `__init__`: Initialize `DaemonState` with empty maps
   - `add_window(window_info: WindowInfo)`: Add to window_map
   - `remove_window(window_id: int)`: Remove from window_map
   - `update_window(window_id: int, **kwargs)`: Update window properties
   - `get_window(window_id: int) -> Optional[WindowInfo]`: Query window
   - `get_windows_by_project(project: str) -> List[WindowInfo]`: Filter windows
   - `set_active_project(project: Optional[str])`: Update active project
   - `get_active_project() -> Optional[str]`: Query active project
   - `add_workspace(workspace_info: WorkspaceInfo)`: Add to workspace_map
   - `remove_workspace(name: str)`: Remove from workspace_map
   - `rebuild_from_marks(tree: i3ipc.Con)`: Scan tree for project marks
3. Add thread locking for concurrent access (asyncio.Lock)
4. Add event count/error count incrementers

**Dependencies**: T003 (models.py)
**Test**: Unit tests for CRUD operations, test mark rebuilding with mock tree

---

### T006 - Implement i3 IPC Connection Manager
**Story**: Foundation (blocks all user stories)
**File**: `home-modules/desktop/i3-project-event-daemon/connection.py`

Manage i3 IPC connection with resilient reconnection and i3 restart handling.

**Tasks**:
1. Create `connection.py`
2. Implement `ResilientI3Connection` class:
   - `async connect_with_retry(max_attempts=10)`: Connect with exponential backoff (100ms to 5s)
   - `async rebuild_state()`: Rebuild window_map from i3 marks via GET_TREE
   - `async handle_shutdown_event(event)`: Distinguish i3 restart vs exit
   - Set `auto_reconnect=True` on i3ipc.aio.Connection
3. Exponential backoff logic: 100ms, 200ms, 400ms, 800ms, ... up to 5s max
4. On reconnect: automatically rebuild state from marks + reload active project
5. On i3 restart event: log and wait for auto-reconnect
6. On i3 exit event: set shutdown flag and quit main loop
7. Use systemd.journal.write() for structured logging with priorities

**Dependencies**: T003 (models.py), T005 (state.py)
**Test**: Mock i3 socket, test connection/reconnection, verify state rebuild, test i3 restart simulation

---

## Phase 3: User Story 1 (P1) - Real-time Project State Updates

**Goal**: Instant project switch reflection in status bar and window visibility (<200ms).

**Independent Test Criteria**:
- Switch projects 5 times rapidly (within 2 seconds)
- Status bar always shows correct project name
- All project-scoped windows hide/show correctly
- No orphaned windows visible from old project
- Measured latency <200ms from tick event to window visibility change

---

### T007 - [US1] Implement Tick Event Handler
**Story**: US1
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py`

Handle `tick` events for project switch notifications.

**Tasks**:
1. Create `handlers.py`
2. Implement `on_tick(conn: Connection, event: TickEvent, state: StateManager, config_loader: ConfigLoader)`
   - Parse payload (format: `project:PROJECT_NAME`)
   - If `project:none`: Clear active project
   - If `project:reload`: Reload project configs
   - Else: Switch to specified project
3. Implement `_switch_project(project_name: str, state: StateManager, conn: Connection)`
   - Validate project exists
   - Get windows for old project → hide (move to scratchpad)
   - Get windows for new project → show (move to workspace)
   - Update `state.active_project`
   - Save to `active-project.json`
4. Add error handling for invalid project names
5. Log project switch events

**Dependencies**: T005 (state.py), T006 (connection.py)
**Test**: Send tick event via `i3-msg -t send_tick "project:nixos"`, verify switch

---

### T008 - [US1] Implement Window Visibility Control
**Story**: US1
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py` (add functions)

Control window show/hide operations via i3 commands.

**Tasks**:
1. Implement `hide_window(conn: Connection, window_id: int)`
   - Send i3 command: `[id={window_id}] move scratchpad`
   - Log action
2. Implement `show_window(conn: Connection, window_id: int, workspace: str)`
   - Send i3 command: `[id={window_id}] move container to workspace {workspace}`
   - Optionally focus window
3. Implement `hide_project_windows(conn: Connection, windows: List[WindowInfo])`
   - Batch hide windows (iterate with error handling per window)
4. Implement `show_project_windows(conn: Connection, windows: List[WindowInfo])`
   - Batch show windows
5. Add performance logging (measure time for batch operations)

**Dependencies**: T005 (state.py), T006 (connection.py)
**Test**: Create windows, call functions, verify windows move to scratchpad/workspace

---

### T009 - [US1] Implement JSON-RPC IPC Server with Socket Activation
**Story**: US1
**File**: `home-modules/desktop/i3-project-event-daemon/ipc_server.py`

Expose daemon state via UNIX socket for CLI queries, inheriting socket from systemd.

**Tasks**:
1. Create `ipc_server.py`
2. Implement `IPCServer` class:
   - `__init__(state_manager: StateManager)`
   - `@classmethod async from_systemd_socket()`: Inherit socket FD from systemd (LISTEN_FDS env var)
   - `async start(socket: Optional[socket.socket])`: Use provided socket or create new
   - `async handle_client(reader, writer)`: Process JSON-RPC requests
   - `async stop()`: Close connections, no need to remove socket (systemd manages it)
3. Implement JSON-RPC request handlers:
   - `get_status() -> dict`: Return daemon runtime status
   - `get_active_project() -> dict`: Return active project info
   - `get_projects() -> dict`: List all projects with window counts
   - `get_windows(**filters) -> dict`: Query windows
   - `switch_project(project_name: str) -> dict`: Trigger project switch
   - `get_events(limit, event_type) -> dict`: Return recent events for diagnostics
   - `reload_config() -> dict`: Reload project configs from disk
4. Implement error responses (JSON-RPC error codes)
5. Socket permissions set by systemd (0600 owner-only)

**Dependencies**: T005 (state.py)
**Test**: Send JSON-RPC requests via `nc -U`, verify responses, test socket survives daemon restart

---

### T010 - [US1] Create CLI Tool: i3-project-switch [P]
**Story**: US1
**File**: `scripts/i3-project-switch`

CLI command to switch projects via daemon IPC.

**Tasks**:
1. Create `scripts/i3-project-switch` (bash script)
2. Parse arguments: `<project_name>` or `--clear`
3. Connect to daemon socket at `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
4. Send JSON-RPC request: `{"method": "switch_project", "params": {"project_name": "..."}}`
5. Parse response, display human-readable output
6. Handle errors (daemon not running, project not found)
7. Set appropriate exit codes (0=success, 1=error, 2=daemon not running)
8. Add shell completion support (bash/fish)

**Dependencies**: T009 (ipc_server.py)
**Test**: Run command, verify project switch occurs, test error cases

---

### T011 - [US1] Create CLI Tool: i3-project-current [P]
**Story**: US1
**File**: `scripts/i3-project-current`

CLI command to query current project.

**Tasks**:
1. Create `scripts/i3-project-current` (bash script)
2. Parse options: `--format=text|json|icon`
3. Connect to daemon socket
4. Send JSON-RPC request: `{"method": "get_active_project"}`
5. Format output based on `--format` flag
6. Handle global mode (no active project)

**Dependencies**: T009 (ipc_server.py)
**Test**: Run command, verify output formats, test with no active project

---

### T012 - [US1] Update i3blocks Status Bar Script
**Story**: US1
**File**: `home-modules/desktop/i3blocks/scripts/project.sh`

Replace signal-based updates with daemon queries.

**Tasks**:
1. Edit `home-modules/desktop/i3blocks/scripts/project.sh`
2. Remove signal handling logic
3. Add daemon IPC query: Call `i3-project-current --format=icon`
4. Display project icon or empty if global mode
5. Add click handler: `Win+P` to open project switcher
6. Add error handling (daemon not running)

**Dependencies**: T011 (i3-project-current)
**Test**: Start i3blocks, verify project indicator updates on switch, test clicks

---

### T013 - [US1] Integration Test: Rapid Project Switching
**Story**: US1
**Test File**: `tests/integration/test_project_switching.py`

End-to-end test for User Story 1 acceptance criteria.

**Tasks**:
1. Create `tests/integration/test_project_switching.py`
2. Test setup: Start daemon, create 2 projects, open windows in each
3. Test Case 1: Switch projects 5 times in 2 seconds
   - Verify status bar shows correct project after each switch
   - Verify all windows hide/show correctly
4. Test Case 2: Measure latency
   - Send tick event, measure time until window visibility changes
   - Assert latency <200ms
5. Test Case 3: i3 restart recovery
   - Trigger i3 restart, verify daemon reconnects
   - Verify project state restored correctly

**Dependencies**: T007-T012
**Test**: Run with pytest, all assertions pass

---

## Phase 4: User Story 2 (P2) - Automatic Window Tracking

**Goal**: New windows automatically marked with active project within 200ms.

**Independent Test Criteria**:
- Launch VS Code in project context
- Window marked with `project:nixos` within 200ms
- Open 5 terminals simultaneously, all marked correctly
- No unmarked windows remain after launch

---

### T014 - [US2] Implement window::new Event Handler
**Story**: US2
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py` (add function)

Auto-mark new windows when they appear.

**Tasks**:
1. Implement `on_window_new(conn: Connection, event: WindowEvent, state: StateManager, app_class: ApplicationClassification)`
   - Extract window properties: `window_id`, `window_class`, `window_instance`, `window_title`
   - Check if active project exists
   - Check if `window_class` is in `app_class.scoped_classes`
   - If both true: Apply mark `project:{active_project}`
   - Add window to `state.window_map`
2. Handle race conditions: Mark application may happen before properties available
3. Log window creation events with timing

**Dependencies**: T005 (state.py), T006 (connection.py)
**Test**: Launch application, verify mark applied within 200ms

---

### T015 - [US2] Implement window::mark Event Handler
**Story**: US2
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py` (add function)

Track mark changes (auto or manual).

**Tasks**:
1. Implement `on_window_mark(conn: Connection, event: WindowEvent, state: StateManager)`
   - Extract window marks from event
   - Filter marks starting with `project:`
   - If project mark found: Update `state.window_map[window_id].project`
   - If project mark removed: Remove from `state.window_map`
2. Validate project name matches existing config
3. Log mark changes

**Dependencies**: T005 (state.py), T006 (connection.py)
**Test**: Manually add/remove marks, verify state updates

---

### T016 - [US2] Implement window::close Event Handler [P]
**Story**: US2
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py` (add function)

Remove closed windows from tracking.

**Tasks**:
1. Implement `on_window_close(conn: Connection, event: WindowEvent, state: StateManager)`
   - Extract window_id from event
   - Remove from `state.window_map` if exists
2. Log window close events

**Dependencies**: T005 (state.py)
**Test**: Close window, verify removed from state

---

### T017 - [US2] Implement window::focus Event Handler [P]
**Story**: US2
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py` (add function)

Track focus changes for diagnostics.

**Tasks**:
1. Implement `on_window_focus(conn: Connection, event: WindowEvent, state: StateManager)`
   - Update `state.window_map[window_id].last_focus = datetime.now()`
2. Optionally notify IPC subscribers of focus change

**Dependencies**: T005 (state.py)
**Test**: Focus windows, verify last_focus timestamp updates

---

### T018 - [US2] Integration Test: Auto Window Marking
**Story**: US2
**Test File**: `tests/integration/test_window_tracking.py`

End-to-end test for User Story 2 acceptance criteria.

**Tasks**:
1. Create `tests/integration/test_window_tracking.py`
2. Test Case 1: Single window launch
   - Activate project, launch VS Code
   - Verify mark applied within 200ms
3. Test Case 2: Multiple windows simultaneously
   - Launch 5 terminals at once
   - Verify all marked correctly
4. Test Case 3: Workspace move
   - Move window to different workspace
   - Verify project association maintained

**Dependencies**: T014-T017
**Test**: Run with pytest, all assertions pass

---

## Phase 5: User Story 4 (P2) - Application Workspace Distinction

**Goal**: Terminal apps and PWAs treated as distinct applications with separate workspaces.

**Independent Test Criteria**:
- Launch lazygit via rofi, verify assigned to lazygit workspace (not ghostty workspace)
- Launch ArgoCD PWA, verify assigned to ArgoCD workspace (not firefox workspace)
- Launch multiple PWAs, each in own workspace

---

### T019 - [US4] Implement Application Identifier
**Story**: US4
**File**: `home-modules/desktop/i3-project-event-daemon/app_identifier.py`

Identify applications using hierarchical window property matching.

**Tasks**:
1. Create `app_identifier.py`
2. Implement `identify_application(window: i3ipc.Con, rules: Optional[List[IdentificationRule]]) -> str`
   - Priority 1: Check `window.window_instance` against rules
   - Priority 2: Check `window.window_class` against rules
   - Priority 3: Check `window.window_title` against regex patterns in rules
   - Priority 4: Check process name via `/proc/{pid}/comm`
   - Fallback: Return `window.window_class` or "unknown"
3. Implement `load_identification_rules(config_file: Path) -> List[IdentificationRule]`
   - Load from `~/.config/i3/app-identification/rules.json`
   - Parse into dataclass structure
4. Handle edge cases: None values, placeholder windows

**Dependencies**: T003 (models.py - add IdentificationRule dataclass)
**Test**: Test with various window types, verify correct identification

---

### T020 - [US4] Integrate App Identifier into Window Handlers
**Story**: US4
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py` (modify)

Use application identifier when marking windows.

**Tasks**:
1. Modify `on_window_new` to call `identify_application()`
2. Store app identifier in `WindowInfo.app_identifier` field (add to dataclass)
3. Use app identifier for workspace assignment logic (if integrated with i3wsr)
4. Log application identification results

**Dependencies**: T014 (on_window_new), T019 (app_identifier.py)
**Test**: Launch lazygit and regular terminal, verify different identifiers

---

### T021 - [US4] Create Default App Identification Rules
**Story**: US4
**File**: `home-modules/desktop/i3-project-daemon.nix` (generate config file)

Provide default identification rules for common applications.

**Tasks**:
1. Define default rules in NixOS module
2. Generate `~/.config/i3/app-identification/rules.json` with defaults:
   - lazygit: `{wm_instance: "lazygit", wm_class: "ghostty", identifier: "lazygit"}`
   - yazi: `{wm_instance: "yazi", wm_class: "ghostty", identifier: "yazi"}`
   - ArgoCD PWA: `{wm_instance: "argocd", wm_class: "firefox", identifier: "argocd"}`
   - Backstage PWA: `{wm_instance: "backstage", wm_class: "firefox", identifier: "backstage"}`
3. Document rule format in comments

**Dependencies**: T019 (app_identifier.py)
**Test**: Launch apps, verify rules match correctly

---

### T022 - [US4] Integration Test: Application Distinction
**Story**: US4
**Test File**: `tests/integration/test_app_distinction.py`

End-to-end test for User Story 4 acceptance criteria.

**Tasks**:
1. Create `tests/integration/test_app_distinction.py`
2. Test Case 1: lazygit vs terminal
   - Launch lazygit via desktop file
   - Launch regular ghostty terminal
   - Verify identified as separate applications
3. Test Case 2: Multiple PWAs
   - Launch ArgoCD, Backstage, YouTube PWAs
   - Verify each identified separately (not as "firefox")
4. Test Case 3: Workspace assignment
   - Verify lazygit assigned to dedicated workspace
   - Verify ArgoCD assigned to dedicated workspace

**Dependencies**: T019-T021
**Test**: Run with pytest, all assertions pass

---

## Phase 6: User Story 3 (P3) - Workspace State Monitoring

**Goal**: Automatic workspace reassignment on monitor changes.

**Independent Test Criteria**:
- Connect/disconnect external monitor
- Workspaces reassign automatically within 1 second
- No manual `Win+Shift+M` trigger needed

---

### T023 - [US3] Implement workspace::init Event Handler [P]
**Story**: US3
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py` (add function)

Track new workspace creation.

**Tasks**:
1. Implement `on_workspace_init(conn: Connection, event: WorkspaceEvent, state: StateManager)`
   - Extract workspace info from event
   - Add to `state.workspace_map`
   - Apply project-scoped visibility rules if project active
2. Log workspace creation

**Dependencies**: T005 (state.py)
**Test**: Create workspace, verify added to state

---

### T024 - [US3] Implement workspace::empty Event Handler [P]
**Story**: US3
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py` (add function)

Track workspace destruction.

**Tasks**:
1. Implement `on_workspace_empty(conn: Connection, event: WorkspaceEvent, state: StateManager)`
   - Remove from `state.workspace_map`
2. Log workspace destruction

**Dependencies**: T005 (state.py)
**Test**: Close all windows on workspace, verify removed from state

---

### T025 - [US3] Implement workspace::move Event Handler [P]
**Story**: US3
**File**: `home-modules/desktop/i3-project-event-daemon/handlers.py` (add function)

Track workspace moves between monitors.

**Tasks**:
1. Implement `on_workspace_move(conn: Connection, event: WorkspaceEvent, state: StateManager)`
   - Update `state.workspace_map[workspace].output`
   - Optionally trigger workspace reassignment logic
2. Log workspace moves with old/new output

**Dependencies**: T005 (state.py)
**Test**: Move workspace to different monitor, verify state updates

---

### T026 - [US3] Integration Test: Multi-Monitor Support
**Story**: US3
**Test File**: `tests/integration/test_workspace_monitoring.py`

End-to-end test for User Story 3 acceptance criteria.

**Tasks**:
1. Create `tests/integration/test_workspace_monitoring.py`
2. Test Case 1: Workspace creation
   - Create new workspace via i3 command
   - Verify daemon tracks it
3. Test Case 2: Workspace destruction
   - Close all windows on workspace
   - Verify daemon removes it
4. Test Case 3: Monitor changes (simulated)
   - Mock monitor connect/disconnect events
   - Verify workspace assignments update

**Dependencies**: T023-T025
**Test**: Run with pytest, all assertions pass (mocked monitor events)

---

## Phase 7: Daemon Lifecycle & CLI Tools

### T027 - Implement Main Daemon Entry Point
**Story**: Foundation
**File**: `home-modules/desktop/i3-project-event-daemon/daemon.py`

Main event loop with systemd integration (sd_notify, watchdog, journald).

**Tasks**:
1. Create `daemon.py`
2. Implement `DaemonHealthMonitor` class:
   - `notify_ready()`: Send `systemd.daemon.notify('READY=1')` after successful i3 connection
   - `notify_watchdog()`: Send `systemd.daemon.notify('WATCHDOG=1')` ping
   - `notify_stopping()`: Send `systemd.daemon.notify('STOPPING=1')` on shutdown
   - `async watchdog_loop()`: Background task sending pings every 15s (half of WatchdogSec=30)
   - `_get_watchdog_interval()`: Read watchdog interval from systemd environment
3. Implement `main()` async function:
   - Load project configs (T004)
   - Initialize state manager (T005)
   - Connect to i3 with retry (T006)
   - Start IPC server from systemd socket (T009)
   - Register all event handlers (T007, T014-T017, T023-T025)
   - Signal READY=1 to systemd
   - Start watchdog loop as background task
   - Run i3 event loop: `await conn.main()`
4. Implement graceful shutdown:
   - Handle SIGTERM/SIGINT signals
   - Signal STOPPING=1 to systemd
   - Close IPC socket, close i3 connection
5. Use systemd.journal.write() for all logging with priority levels (DEBUG, INFO, WARNING, ERROR)
6. Add error recovery with journald error logging

**Dependencies**: T004-T006, T007, T009, T014-T017, T023-T025
**Test**: Start daemon, verify READY=1 sent, watchdog pings every 15s, graceful shutdown sends STOPPING=1

---

### T028 - Create Systemd User Service with Socket Activation
**Story**: Foundation
**File**: `home-modules/desktop/i3-project-daemon.nix` (add systemd service + socket)

Configure production-grade systemd user service with socket activation, watchdog, and security hardening.

**Tasks**:
1. Define **systemd socket unit** `i3-project-daemon.socket`:
   - `Socket.ListenStream = "%t/i3-project-daemon/ipc.sock"`
   - `Socket.SocketMode = "0600"` (owner-only)
   - `Socket.DirectoryMode = "0700"`
   - `Socket.Accept = false` (single daemon handles all connections)
   - `Install.WantedBy = [ "sockets.target" ]`
2. Define **systemd service unit** `i3-project-daemon.service`:
   - `Unit.After = [ "graphical-session.target" "i3-project-daemon.socket" ]`
   - `Unit.Requires = [ "i3-project-daemon.socket" ]`
   - `Unit.PartOf = [ "graphical-session.target" ]`
   - `Unit.ConditionEnvironment = "DESKTOP_SESSION=i3"` (only run on i3)
   - `Service.Type = "notify"` (wait for READY=1)
   - `Service.NotifyAccess = "main"`
   - `Service.Sockets = "i3-project-daemon.socket"` (inherit socket FD)
   - `Service.Restart = "always"` (restart even on clean exit)
   - `Service.RestartSec = 3`
   - `Service.StartLimitBurst = 10` within `StartLimitIntervalSec = 60`
   - `Service.WatchdogSec = 30` (expect ping every 30s)
3. Configure **resource limits**:
   - `MemoryMax = "100M"`, `MemoryHigh = "80M"` (soft limit)
   - `CPUQuota = "50%"` (max half a core)
   - `TasksMax = 20`
4. Configure **security hardening**:
   - `PrivateTmp = true` (isolated /tmp)
   - `NoNewPrivileges = true` (no privilege escalation)
   - `ProtectSystem = "strict"` (read-only /usr, /boot, /etc)
   - `ProtectHome = "read-only"`
   - `ReadWritePaths = [ "%t/i3-project-daemon" "%h/.config/i3/projects" "%h/.config/i3/app-identification" ]`
5. Configure **environment**:
   - `PYTHONUNBUFFERED=1`, `PYTHONDONTWRITEBYTECODE=1`
6. Configure **process management**:
   - `KillMode = "mixed"` (SIGTERM to main, SIGKILL to children)
   - `KillSignal = "SIGTERM"`
   - `TimeoutStopSec = 10`
7. Integrate **i3 keybindings** in `xsession.windowManager.i3.config.keybindings`:
   - `"${mod}+p"` = project switcher (rofi)
   - `"${mod}+Shift+p"` = clear project (global mode)
8. Integrate **i3blocks config** with project indicator block
9. Enable when `services.i3ProjectDaemon.enable = true` AND i3 enabled

**Dependencies**: T027 (daemon.py with sd_notify support)
**Test**: Rebuild NixOS, verify socket created before service, verify READY=1 received, verify watchdog pings, check `systemctl --user status i3-project-daemon`

---

### T029 - Create CLI Tool: i3-project-list [P]
**Story**: Foundation
**File**: `scripts/i3-project-list`

List all projects with window counts.

**Tasks**:
1. Create `scripts/i3-project-list` (bash script)
2. Parse options: `--format=text|json|simple`
3. Connect to daemon socket
4. Send JSON-RPC request: `{"method": "get_projects"}`
5. Format output (table, JSON, or simple names)
6. Add shell completion support

**Dependencies**: T009 (ipc_server.py)
**Test**: Run command, verify output formats match contract

---

### T030 - Create CLI Tool: i3-project-create
**Story**: Foundation
**File**: `scripts/i3-project-create`

Create new project configuration.

**Tasks**:
1. Create `scripts/i3-project-create` (bash script)
2. Parse options: `--name`, `--dir`, `--display-name`, `--icon`
3. Validate arguments (name format, directory exists)
4. Check project doesn't already exist
5. Generate JSON file: `~/.config/i3/projects/{name}.json`
6. Optionally trigger daemon reload

**Dependencies**: None (writes files directly)
**Test**: Create project, verify JSON file created, verify daemon loads it

---

### T031 - Create CLI Tool: i3-project-daemon-status [P]
**Story**: Foundation
**File**: `scripts/i3-project-daemon-status`

Show daemon status and diagnostics.

**Tasks**:
1. Create `scripts/i3-project-daemon-status` (bash script)
2. Parse options: `--format=text|json`
3. Connect to daemon socket
4. Send JSON-RPC request: `{"method": "get_status"}`
5. Format output (human-readable or JSON)
6. Show connection status, uptime, event stats, active project

**Dependencies**: T009 (ipc_server.py)
**Test**: Run command, verify shows correct daemon state

---

### T032 - Create CLI Tool: i3-project-daemon-events [P]
**Story**: Foundation
**File**: `scripts/i3-project-daemon-events`

Show recent daemon events for debugging.

**Tasks**:
1. Create `scripts/i3-project-daemon-events` (bash script)
2. Parse options: `--limit=N`, `--type=<type>`
3. Connect to daemon socket
4. Send JSON-RPC request: `{"method": "get_events", "params": {...}}`
5. Format output (event log table)

**Dependencies**: T009 (ipc_server.py)
**Test**: Run command, verify shows recent events

---

### T033 - Package Python Daemon for NixOS
**Story**: Foundation
**File**: `home-modules/desktop/i3-project-daemon.nix` (add package)

Package Python daemon with dependencies for NixOS, including systemd-python.

**Tasks**:
1. Create package definition in NixOS module:
   ```nix
   let
     pythonWithDeps = pkgs.python311.withPackages (ps: [
       ps.i3ipc        # i3 IPC library (only external dependency for i3 integration)
       ps.systemd      # systemd-python for sd_notify/watchdog/journald
     ]);
     daemon = pkgs.writeShellScriptBin "i3-project-event-daemon" ''
       exec ${pythonWithDeps}/bin/python3 ${./i3-project-event-daemon/daemon.py} "$@"
     '';
   in { ... }
   ```
2. Copy daemon Python files to Nix store (models.py, config.py, state.py, connection.py, handlers.py, app_identifier.py, ipc_server.py, daemon.py)
3. Verify only 2 external dependencies: i3ipc-python, systemd-python
4. Add daemon to systemd ExecStart path when enabled
5. Add CLI tools (i3-project-switch, etc.) to `home.packages`
6. Add shell aliases (pswitch, pcurrent, plist) when enabled
7. Add monitoring commands (pdaemon-status, pdaemon-logs, pdaemon-memory)

**Dependencies**: T027 (daemon.py), T028 (systemd service)
**Test**: Build package, run daemon, verify no import errors, verify systemd integration works

---

### T034 - Create Shell Aliases
**Story**: Foundation
**File**: `home-modules/desktop/i3-project-daemon.nix` (add aliases)

Add bash aliases for convenience.

**Tasks**:
1. Define aliases in NixOS module:
   - `pswitch = "i3-project-switch"`
   - `pcurrent = "i3-project-current"`
   - `plist = "i3-project-list"`
2. Add to `programs.bash.shellAliases` when daemon enabled

**Dependencies**: T010, T011, T029
**Test**: Source bashrc, verify aliases work

---

## Phase 8: Testing & Validation

### T035 - Create Unit Test Suite
**Story**: Foundation
**Directory**: `tests/unit/`

Unit tests for all Python modules.

**Tasks**:
1. Create `tests/unit/test_models.py`: Test dataclass validation
2. Create `tests/unit/test_config.py`: Test config loading/saving
3. Create `tests/unit/test_state.py`: Test state manager CRUD operations
4. Create `tests/unit/test_app_identifier.py`: Test application identification
5. Create `tests/unit/test_handlers.py`: Test event handlers with mocks
6. Use pytest with mocking for i3ipc objects

**Dependencies**: T003-T006, T019
**Test**: Run `pytest tests/unit/`, all tests pass

---

### T036 - Create Integration Test Harness
**Story**: Foundation
**Directory**: `tests/integration/`

Test infrastructure for end-to-end tests.

**Tasks**:
1. Create `tests/integration/conftest.py` (pytest fixtures):
   - `daemon_fixture`: Start/stop daemon for tests
   - `i3_fixture`: Mock i3 connection or use Xvfb
   - `project_fixture`: Create test project configs
2. Create `tests/integration/utils.py` (helper functions):
   - `wait_for_daemon_ready(timeout=5)`: Poll until daemon responsive
   - `send_i3_event(event_type, payload)`: Trigger test events
   - `verify_window_mark(window_id, expected_mark)`: Check marks
3. Add pytest-asyncio for async test support

**Dependencies**: T027 (daemon.py)
**Test**: Run integration tests, fixtures work correctly

---

### T037 - Performance Benchmarking
**Story**: Foundation
**File**: `tests/benchmark/test_performance.py`

Verify performance targets (FR-027 to FR-030).

**Tasks**:
1. Create `tests/benchmark/test_performance.py`
2. Benchmark memory usage: Assert <15MB (target: <5MB, tolerance: 10MB)
3. Benchmark event processing latency: Assert 95% <100ms
4. Benchmark project switch latency: Assert <200ms
5. Stress test: 50 events/second for 10 seconds, assert no drops
6. Use `pytest-benchmark` plugin

**Dependencies**: T027 (daemon.py), all event handlers
**Test**: Run benchmarks, all targets met

---

### T038 - Migration Script for Existing Users
**Story**: Foundation
**File**: `scripts/migrate-to-event-based.sh`

Help users migrate from polling-based system.

**Tasks**:
1. Create `scripts/migrate-to-event-based.sh` (bash script)
2. Backup existing configs: Copy `~/.config/i3/projects/` to `.../projects.backup/`
3. Extract scoped_applications from project JSONs
4. Generate `~/.config/i3/app-classes.json` with extracted apps
5. Mark all existing windows with current active project
6. Display migration summary
7. Provide rollback instructions

**Dependencies**: T004 (config.py understands old format)
**Test**: Run on test environment with old configs, verify successful migration

---

## Phase 9: Documentation & Polish

### T039 - Update CLAUDE.md with Project Workflow
**Story**: Documentation
**File**: `/etc/nixos/CLAUDE.md`

Document the event-based project management workflow.

**Tasks**:
1. Add section "Event-Based Project Management" to CLAUDE.md
2. Document keybindings, CLI commands, aliases
3. Explain daemon status checking and troubleshooting
4. Update "Recent Updates" section with Feature 015 summary
5. Document app identification configuration

**Dependencies**: All CLI tools complete
**Test**: Review documentation for accuracy and completeness

---

### T040 - Generate Completion Scripts
**Story**: Polish
**Files**: `scripts/completions/*`

Shell completion for all CLI tools.

**Tasks**:
1. Create `scripts/completions/bash/i3-project-completion.sh` (bash completion)
2. Create `scripts/completions/fish/i3-project-*.fish` (fish completion)
3. Include in NixOS module to install completions automatically
4. Completions dynamically query daemon for project names

**Dependencies**: All CLI tools complete
**Test**: Source completions, test tab completion

---

### T041 - Create Troubleshooting Guide
**Story**: Documentation
**File**: `docs/I3_PROJECT_EVENTS.md`

Comprehensive troubleshooting documentation.

**Tasks**:
1. Create `docs/I3_PROJECT_EVENTS.md`
2. Document common issues:
   - Daemon not starting
   - Windows not marking
   - Project switch delays
   - IPC socket errors
3. Add diagnostic commands for each issue
4. Include journalctl log examples
5. Add FAQ section

**Dependencies**: T027-T032
**Test**: Review with user perspective, ensure covers common scenarios

---

## Phase 10: Final Integration & Testing

### T042 - End-to-End System Test
**Story**: Final Validation
**Test File**: `tests/e2e/test_full_system.py`

Comprehensive test covering all user stories.

**Tasks**:
1. Create `tests/e2e/test_full_system.py`
2. Test full user workflow:
   - Start daemon
   - Create 3 projects
   - Switch between projects rapidly (US1)
   - Launch windows in each project (US2)
   - Verify app identification for PWAs/terminal apps (US4)
   - Simulate monitor changes (US3)
   - Verify all windows tracked correctly
   - Stop daemon gracefully
3. Run on actual i3 instance (not mocked)

**Dependencies**: All phases complete
**Test**: Run full system test, all assertions pass

---

### T043 - Apply Configuration to Hetzner Test System
**Story**: Final Validation
**System**: Hetzner Cloud Server

Deploy to test environment.

**Tasks**:
1. Update `configurations/hetzner.nix` to import daemon module
2. Run `sudo nixos-rebuild dry-build --flake .#hetzner`
3. Fix any evaluation errors
4. Run `sudo nixos-rebuild switch --flake .#hetzner`
5. Verify daemon starts successfully
6. Test project switching workflow
7. Test CLI tools
8. Monitor daemon for 24 hours, check for crashes/memory leaks

**Dependencies**: All code complete, T033 (packaged for NixOS)
**Test**: Successful deployment, daemon runs stably

---

### T044 - User Acceptance Testing
**Story**: Final Validation
**Manual Testing**

Real-world usage testing.

**Tasks**:
1. Perform all user story acceptance scenarios from spec.md:
   - US1: Rapid project switching (5 times in 2 seconds)
   - US2: Auto window marking (5 terminals simultaneously)
   - US4: App distinction (lazygit, ArgoCD, Backstage)
   - US3: Monitor connect/disconnect
2. Test edge cases from spec.md
3. Measure actual latencies (project switch, window marking)
4. Verify all success criteria met (SC-001 to SC-016)
5. Document any issues found

**Dependencies**: T043 (deployed to test system)
**Test**: All acceptance criteria pass

---

## Summary Statistics

**Total Tasks**: 44
**Phases**: 10

**Tasks by User Story**:
- Foundation (Setup): 10 tasks (T001-T006, T027-T028, T033-T034)
- US1 (P1 - Real-time Updates): 7 tasks (T007-T013)
- US2 (P2 - Auto Tracking): 5 tasks (T014-T018)
- US4 (P2 - App Distinction): 4 tasks (T019-T022)
- US3 (P3 - Workspace Monitoring): 4 tasks (T023-T026)
- CLI Tools & Infrastructure: 6 tasks (T029-T032, T038, T040)
- Testing & Validation: 7 tasks (T035-T037, T042-T044)
- Documentation: 2 tasks (T039, T041)

**Parallel Opportunities**:
- Phase 1 (Setup): All 3 tasks can run in parallel (T001, T002, T003)
- Phase 2 (Foundation): T003, T004 parallel; then T005, T006 parallel
- Phase 3 (US1): T010, T011, T012 parallel after T009
- Phase 4 (US2): T016, T017 parallel
- Phase 6 (US3): T023, T024, T025 all parallel
- Phase 7 (CLI): T029, T031, T032 parallel

**Critical Path**:
T001 → T003 → T005 → T006 → T007 → T009 → T027 → T028 → T043 → T044

**Estimated Time**:
- Phase 1-2 (Foundation): 2-3 days
- Phase 3-6 (User Stories): 3-4 days
- Phase 7 (CLI & Daemon): 2-3 days
- Phase 8-9 (Testing & Docs): 2-3 days
- Phase 10 (Integration): 1-2 days

**Total Estimated Time**: 10-15 days

---

## Implementation Strategy

### MVP Scope (Minimum Viable Product)

For initial deployment, implement in this order:

1. **Foundation** (T001-T006, T027-T028): Core daemon with basic event handling
2. **US1 - Project Switching** (T007-T013): Most critical user story (P1)
3. **US2 - Auto Marking** (T014-T018): Second priority (P2)
4. **CLI Tools** (T010-T011, T029-T032): User-facing commands
5. **Deploy to Test** (T043-T044): Validate in real environment

**MVP Delivers**: Real-time project switching with auto window marking. Defers US3 (workspace monitoring) and US4 (app distinction) to post-MVP.

### Incremental Delivery

After MVP, add features incrementally:

1. **Increment 1**: US4 (App Distinction) - T019-T022
2. **Increment 2**: US3 (Workspace Monitoring) - T023-T026
3. **Increment 3**: Polish & Documentation - T039-T041

### Testing Strategy

- **Unit tests** (T035): Run after each module complete
- **Integration tests** (T036, T013, T018, T022, T026): Run after each user story phase
- **Performance tests** (T037): Run before deployment
- **System test** (T042): Run after all code complete
- **UAT** (T044): Run on test system for 24+ hours

---

## Dependencies Diagram

```
Foundation Layer:
T001 (Module) ─┬─> T028 (Systemd) ─> T033 (Package) ─> T043 (Deploy)
T002 (Structure)┘
T003 (Models) ─┬─> T004 (Config) ─┬─> T005 (State) ─┬─> T006 (Connection) ─> T027 (Daemon)
               │                   │                  │
               └─> T019 (AppID) ───┘                  │
                                                      ▼
                                      ┌───────────────┴────────────────┐
                                      │                                │
                                      ▼                                ▼
                          US1: T007-T009 ─> T010-T012      US2: T014-T017 ─> T018
                                      │                                │
                                      └─> T013 (Test)                 └─> US4: T019-T022
                                                                              │
                                                                              └─> US3: T023-T026
                                                                                      │
                                                                                      └─> T042 (E2E) ─> T044 (UAT)
```

---

## Checkpoints

### Checkpoint 1: Foundation Complete
**After**: T001-T006, T027-T028
**Verify**: Daemon starts, connects to i3, processes events (logged)

### Checkpoint 2: US1 Complete (MVP)
**After**: T007-T013
**Verify**: Project switching works end-to-end, <200ms latency

### Checkpoint 3: US2 Complete
**After**: T014-T018
**Verify**: Windows auto-mark within 200ms

### Checkpoint 4: All User Stories Complete
**After**: T007-T026
**Verify**: All 4 user stories pass acceptance criteria

### Checkpoint 5: Production Ready
**After**: T001-T044
**Verify**: Deployed to test system, 24h stable, all tests pass

---

## Next Steps

1. **Start with T001**: Create NixOS module structure
2. **Proceed sequentially through Foundation** (T001-T006)
3. **Implement US1 (P1)** as first user story (T007-T013)
4. **Deploy MVP** (Foundation + US1) to test environment
5. **Iterate** on remaining user stories (US2, US4, US3)
6. **Polish & Document** (T035-T041)
7. **Final Validation** (T042-T044)

**Ready to begin implementation!**

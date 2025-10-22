# Feature Specification: TypeScript/Deno CLI Rewrite

**Feature Branch**: `026-i-want-to`
**Created**: 2025-10-22
**Status**: Draft
**Input**: User description: "i want to rewrite the cli in typescript using deno library, using as much of their standard library as possible. create a new spec for this implementation"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real-time Window Monitoring (Priority: P1)

As a window manager user, I want to launch the CLI tool and see my current window state displayed in a terminal UI that updates automatically when windows open, close, or change focus, so I can monitor my workspace layout in real-time.

**Why this priority**: This is the core value proposition of the tool - providing real-time visibility into window state. Without this, the tool has no purpose.

**Independent Test**: Can be fully tested by running `i3pm windows --live` and observing that the display shows current windows and updates when switching between applications, without requiring any other features.

**Acceptance Scenarios**:

1. **Given** the daemon is running, **When** user runs `i3pm windows --live`, **Then** terminal UI displays current window tree with all open windows
2. **Given** the live TUI is running, **When** user opens a new window, **Then** the display updates within 100ms to show the new window
3. **Given** the live TUI is running, **When** user closes a window, **Then** the display updates within 100ms to remove the closed window
4. **Given** the live TUI is running, **When** user switches window focus, **Then** the focused window indicator updates within 100ms

---

### User Story 2 - Static Window Queries (Priority: P2)

As a script author, I want to query current window state from the command line and receive structured output (tree, table, or JSON formats), so I can integrate window information into scripts and automation workflows.

**Why this priority**: Enables scriptability and automation, which is a common use case for CLI tools. Less critical than the live TUI but important for power users.

**Independent Test**: Can be tested by running `i3pm windows --json` and verifying the output is valid JSON containing current window state, without requiring the live TUI.

**Acceptance Scenarios**:

1. **Given** windows are open, **When** user runs `i3pm windows --tree`, **Then** terminal displays hierarchical tree view of windows
2. **Given** windows are open, **When** user runs `i3pm windows --table`, **Then** terminal displays sortable table of windows
3. **Given** windows are open, **When** user runs `i3pm windows --json`, **Then** terminal outputs valid JSON structure
4. **Given** user pipes JSON output, **When** user runs `i3pm windows --json | jq '.total_windows'`, **Then** command completes successfully with window count

---

### User Story 3 - Project Management Commands (Priority: P3)

As a developer working on multiple projects, I want to use CLI commands to switch between project contexts and manage project configurations, so I can organize my workspace by project without manually arranging windows.

**Why this priority**: Adds productivity features but the tool is still useful without it. Users can monitor windows without project management.

**Independent Test**: Can be tested by running `i3pm project switch nixos` and verifying workspace windows are filtered/shown based on project context, independent of real-time monitoring.

**Acceptance Scenarios**:

1. **Given** projects are configured, **When** user runs `i3pm project list`, **Then** terminal displays all available projects
2. **Given** projects exist, **When** user runs `i3pm project switch <name>`, **Then** windows associated with that project become visible
3. **Given** user is in a project, **When** user runs `i3pm project current`, **Then** terminal displays the active project name
4. **Given** user wants to create a project, **When** user runs `i3pm project create --name=foo --dir=/path`, **Then** new project is created and saved

---

### Edge Cases

- What happens when the daemon is not running and user attempts to run CLI commands?
- What happens when the Unix socket connection is interrupted mid-stream during live monitoring?
- How does the CLI handle terminal resize events during live TUI display?
- What happens when JSON-RPC responses from daemon are malformed or incomplete?
- How does the tool behave when no windows are open (empty state)?
- What happens when very long window titles cause display overflow in tree/table views?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: CLI MUST connect to existing Python daemon via Unix socket using JSON-RPC 2.0 protocol
- **FR-002**: CLI MUST provide `windows` subcommand with `--live`, `--tree`, `--table`, and `--json` output modes
- **FR-003**: CLI MUST subscribe to daemon event stream for real-time updates in live mode
- **FR-004**: CLI MUST render terminal UI with keyboard navigation (Tab, H, Q keys at minimum)
- **FR-005**: CLI MUST display version information via `--version` flag
- **FR-006**: CLI MUST support graceful shutdown on Ctrl+C (single press) and double Ctrl+C (within 1 second)
- **FR-007**: CLI MUST format window data in tree, table, and JSON structures matching current Python implementation output
- **FR-008**: CLI MUST handle connection errors with user-friendly error messages (daemon not running, socket not found, etc.)
- **FR-009**: CLI MUST support filtering hidden windows via `h` keyboard shortcut in live mode
- **FR-010**: CLI MUST provide `project` subcommand for listing, switching, and querying project state
- **FR-011**: CLI MUST maintain feature parity with existing Python CLI for core window visualization commands
- **FR-012**: CLI MUST use Deno standard library for all operations where standard library modules exist (HTTP, JSON, file I/O, etc.)

### Key Entities

- **Window State**: Represents a single window with properties: ID, class, instance, title, workspace, output, marks, focused state, hidden state, floating state, geometry
- **Workspace**: Represents an i3 workspace containing windows, with properties: number, name, focused state, visible state
- **Output**: Represents a monitor/display with properties: name, active state, geometry, list of workspaces
- **Project**: Represents a project context with properties: name, display name, icon, directory path, associated windows
- **Event Notification**: Real-time updates from daemon with properties: event type, change type, window ID, timestamp

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete the same workflows (window monitoring, project switching) in under the same time as the Python implementation
- **SC-002**: CLI binary size is under 15MB (compiled Deno executable)
- **SC-003**: CLI starts and displays first frame of live TUI within 500ms on standard hardware
- **SC-004**: Real-time window updates appear in TUI within 100ms of window events
- **SC-005**: CLI memory usage remains under 50MB during extended live monitoring sessions (>1 hour)
- **SC-006**: All existing Python CLI commands have equivalent TypeScript/Deno implementations with identical output formats
- **SC-007**: Users report terminal UI responsiveness is equal to or better than Python Textual implementation
- **SC-008**: Zero Python runtime dependencies required for end users (single compiled Deno executable)

## Scope *(mandatory)*

### In Scope

- Complete rewrite of existing Python CLI (`i3_project_manager/cli/`) in TypeScript
- Deno runtime and standard library usage for all operations
- JSON-RPC client implementation for daemon communication
- Terminal UI rendering for live window monitoring mode
- Static output formatters (tree, table, JSON)
- Project management commands (`list`, `switch`, `current`, `create`)
- Keyboard event handling and user input
- Error handling and user-friendly error messages
- Signal handling (Ctrl+C, SIGTERM)
- Feature parity with existing Python CLI commands

### Out of Scope

- Python daemon rewrite (daemon remains Python, only CLI is TypeScript/Deno)
- Changes to JSON-RPC protocol or daemon IPC interface
- New features not present in Python CLI
- Browser-based UI or web interface
- Configuration file format changes
- Window rule management commands (remain in Python for now)
- Test framework or monitoring tools (separate Python tools)

## Assumptions *(mandatory)*

1. **Daemon Compatibility**: Existing Python daemon will continue to run unchanged and maintain the current JSON-RPC 2.0 protocol over Unix socket
2. **Terminal Capabilities**: Users have modern terminal emulators supporting ANSI escape codes and UTF-8
3. **Deno Version**: Deno 1.40+ is available (for latest standard library features)
4. **Unix Socket Access**: CLI runs on same system as daemon with read/write access to Unix socket at `~/.config/i3/daemon.sock`
5. **Performance Target**: TypeScript/Deno performance will be comparable or better than Python/Textual for UI rendering
6. **Standard Library Coverage**: Deno standard library provides sufficient modules for JSON-RPC, terminal UI, and file I/O operations
7. **Compilation Model**: Users will receive a single compiled Deno executable, not raw TypeScript source requiring Deno runtime installation

## Dependencies *(mandatory)*

### External Dependencies

- **Deno Runtime**: Required for development and compilation (version 1.40+)
- **Deno Standard Library**: Core dependency for file I/O, JSON parsing, async operations
- **i3-project-event-daemon**: Python daemon must be running for CLI to function
- **Unix Socket**: Daemon's Unix socket at `~/.config/i3/daemon.sock` must exist and be accessible

### Internal Dependencies

- **JSON-RPC Protocol**: CLI depends on daemon's JSON-RPC 2.0 interface contract
- **Event Stream Format**: CLI depends on daemon's event notification message structure
- **Window Data Schema**: CLI depends on daemon's window state JSON schema

### Build-time Dependencies

- **Deno Compiler**: Required to produce standalone executable
- **TypeScript**: Deno includes TypeScript compiler, no separate install needed

## Out of Scope Features *(optional - include if relevant)*

- Daemon rewrite: Python daemon will remain unchanged
- New visualization modes: Only existing modes (tree, table, JSON, live) will be ported
- Configuration UI: No interactive configuration editor
- Plugin system: No extensibility framework
- Network protocol: Communication remains local via Unix socket only
- Multi-daemon support: CLI connects to single local daemon only

## Open Questions *(optional - use sparingly)*

[None - user request is clear: rewrite CLI in TypeScript/Deno using standard library]

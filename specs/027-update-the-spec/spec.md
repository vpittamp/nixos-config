# Feature Specification: Complete i3pm Deno CLI with Extensible Architecture

**Feature Branch**: `027-update-the-spec`
**Created**: 2025-10-22
**Status**: Draft
**Input**: User description: "update the spec to fully transition all major fucntionality of our current i3pm cli/tui to the new deno cli that we should create.  we plan on having other projects connected to the same cli so make sure we organize the cli topics such that we can add additional parent topics.  we want to use typescript types everywhere, and we should compile our final program into a binary and use that binary within our nixos/home-manager configuration"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Project Context Switching (Priority: P1)

As a developer working on multiple projects simultaneously, I want to switch between project contexts using a single command, so I can instantly focus on project-specific windows without manual window management.

**Why this priority**: Project switching is the core workflow that drives all project-scoped operations. Without this, users cannot leverage project-based window organization, making this the foundation for all other features.

**Independent Test**: Can be fully tested by running `i3pm project switch nixos` and verifying that only nixos-scoped windows become visible and the i3bar indicator updates to show "nixos", deliverable value being instant workspace context isolation.

**Acceptance Scenarios**:

1. **Given** user is in global mode with all windows visible, **When** user runs `i3pm project switch nixos`, **Then** only windows marked with nixos project become visible and i3bar shows "nixos"
2. **Given** user is in nixos project, **When** user runs `i3pm project switch stacks`, **Then** nixos windows become hidden, stacks windows become visible, i3bar updates to "stacks"
3. **Given** user is in any project, **When** user runs `i3pm project clear`, **Then** all windows become visible and i3bar shows "Global"
4. **Given** user wants to see current context, **When** user runs `i3pm project current`, **Then** terminal displays active project name or "Global"

---

### User Story 2 - Real-time Window State Visualization (Priority: P2)

As a window manager power user, I want to view current window state in multiple formats (tree, table, live TUI) with real-time updates, so I can understand workspace layout, debug window management issues, and monitor system state.

**Why this priority**: Window state visualization provides transparency into the window manager's state, essential for debugging and understanding workspace organization. While valuable, project switching is more fundamental to daily workflow.

**Independent Test**: Can be tested by running `i3pm windows --live` and verifying real-time display updates when opening/closing windows, delivering immediate visual feedback of window state changes.

**Acceptance Scenarios**:

1. **Given** windows are open, **When** user runs `i3pm windows`, **Then** terminal displays hierarchical tree view (outputs → workspaces → windows)
2. **Given** user needs tabular format, **When** user runs `i3pm windows --table`, **Then** terminal displays sortable table with window properties
3. **Given** user runs `i3pm windows --live`, **When** user opens a new window, **Then** TUI updates within 100ms showing new window
4. **Given** live TUI is running, **When** user presses H key, **Then** hidden windows toggle visibility in the display
5. **Given** user needs machine-readable output, **When** user runs `i3pm windows --json`, **Then** terminal outputs valid JSON with complete window state

---

### User Story 3 - Project Configuration Management (Priority: P3)

As a project maintainer, I want to create, edit, and validate project configurations through CLI commands, so I can define project metadata, directory paths, and window scoping rules declaratively.

**Why this priority**: Configuration management supports the project switching workflow but is less frequently used. Users can work with existing projects without frequently modifying configurations.

**Independent Test**: Can be tested by running `i3pm project create --name test --dir /tmp/test` and verifying new project appears in `i3pm project list`, delivering the ability to add new project contexts.

**Acceptance Scenarios**:

1. **Given** user wants a new project, **When** user runs `i3pm project create --name nixos --dir /etc/nixos --icon ""`, **Then** new project is created and appears in project list
2. **Given** projects exist, **When** user runs `i3pm project list`, **Then** terminal displays all projects with names, directories, and icons
3. **Given** user runs `i3pm project show nixos`, **Then** terminal displays complete project configuration including scoped window classes
4. **Given** user runs `i3pm project validate`, **Then** all project configurations are validated with errors reported
5. **Given** user runs `i3pm project edit nixos`, **When** user modifies configuration, **Then** changes are validated and saved

---

### User Story 4 - Daemon Status and Event Monitoring (Priority: P4)

As a system administrator, I want to view daemon status, recent events, and diagnostic information through CLI commands, so I can troubleshoot issues and monitor system health.

**Why this priority**: Monitoring and diagnostics are essential for troubleshooting but not part of daily workflow. Users only need these commands when problems occur.

**Independent Test**: Can be tested by running `i3pm daemon status` and verifying output shows daemon uptime, connected state, event counts, and active project.

**Acceptance Scenarios**:

1. **Given** daemon is running, **When** user runs `i3pm daemon status`, **Then** terminal displays daemon uptime, connection state, event statistics, and active project
2. **Given** user needs event history, **When** user runs `i3pm daemon events`, **Then** terminal displays recent daemon events with timestamps and event types
3. **Given** user runs `i3pm daemon events --type=window --limit=50`, **Then** only window events are shown (up to 50)
4. **Given** daemon is not running, **When** user runs any daemon command, **Then** terminal shows user-friendly error with systemctl command to start daemon

---

### User Story 5 - Window Classification and Rule Management (Priority: P5)

As a project administrator, I want to manage window classification rules, test rule matching, and debug application classifications, so I can ensure windows are correctly assigned to project scopes.

**Why this priority**: Rule management is advanced configuration rarely modified after initial setup. Most users work with existing rules without frequent changes.

**Independent Test**: Can be tested by running `i3pm rules list` and verifying output shows current window classification rules with scoping information.

**Acceptance Scenarios**:

1. **Given** user runs `i3pm rules list`, **Then** terminal displays all window rules with class patterns and scope assignments
2. **Given** user runs `i3pm rules classify --class Ghostty --instance ghostty`, **Then** terminal shows how window would be classified (scoped or global)
3. **Given** user runs `i3pm rules validate`, **Then** window rules file is validated with errors reported
4. **Given** user runs `i3pm rules test --class Firefox`, **Then** terminal shows which rules match and final classification
5. **Given** user manages application classes, **When** user runs `i3pm app-classes`, **Then** terminal displays scoped and global application class configurations

---

### User Story 6 - Interactive Monitor Dashboard (Priority: P6)

As a system operator, I want to launch an interactive TUI dashboard that displays real-time daemon state, events, and window information in multiple panes, so I can monitor the system holistically during debugging sessions.

**Why this priority**: The monitor dashboard is a specialized debugging tool used infrequently compared to basic CLI commands. Valuable for deep troubleshooting but not daily workflow.

**Independent Test**: Can be tested by running `i3pm monitor` and verifying multi-pane TUI launches showing live daemon status, event stream, and window state.

**Acceptance Scenarios**:

1. **Given** user runs `i3pm monitor`, **Then** interactive TUI launches with multiple panes (status, events, windows)
2. **Given** monitor is running, **When** daemon processes event, **Then** event appears in event pane within 100ms
3. **Given** monitor is running, **When** window state changes, **Then** windows pane updates to reflect new state
4. **Given** user presses Q in monitor, **Then** TUI exits gracefully and terminal is restored

---

### Edge Cases

- What happens when daemon is not running and user attempts project switch or window query?
- How does CLI handle Unix socket connection failure or timeout during long-running operations?
- What happens when terminal is resized during live TUI display (windows, monitor)?
- How does CLI behave when JSON-RPC responses are malformed or missing expected fields?
- What happens when no windows are open (empty state) for window visualization commands?
- How does CLI handle very long window titles causing display overflow in tree/table views?
- What happens when user runs CLI from NixOS configuration before binary is compiled?
- How does CLI handle concurrent project switch requests (rapid switching)?
- What happens when project directory path doesn't exist or is not accessible?
- How does CLI handle keyboard interrupts (Ctrl+C) gracefully across all commands?

## Requirements *(mandatory)*

### Functional Requirements

#### Core CLI Architecture

- **FR-001**: CLI MUST use extensible parent command structure (`i3pm <parent> <subcommand>`) supporting multiple top-level namespaces (project, windows, daemon, rules, monitor, app-classes)
- **FR-002**: CLI MUST be implemented in TypeScript with strict type checking enabled for all modules
- **FR-003**: CLI MUST use Deno standard library `@std/cli/parse-args` for all command-line argument parsing
- **FR-004**: CLI MUST compile to standalone executable binary via `deno compile` with all permissions embedded
- **FR-005**: CLI binary MUST be integrated into NixOS/home-manager configuration as system package
- **FR-006**: CLI MUST provide `--help` flag for every parent command and subcommand showing usage and options
- **FR-007**: CLI MUST provide `--version` flag showing CLI version and build information
- **FR-008**: CLI MUST support `--verbose` and `--debug` flags for detailed logging output
- **FR-009**: CLI MUST handle keyboard interrupts (Ctrl+C) gracefully with proper cleanup and terminal restoration

#### Daemon Communication

- **FR-010**: CLI MUST connect to Python daemon via Unix socket using JSON-RPC 2.0 protocol
- **FR-011**: CLI MUST discover daemon socket path from XDG_RUNTIME_DIR environment variable or default to `/run/user/<uid>/i3-project-daemon/ipc.sock`
- **FR-012**: CLI MUST subscribe to daemon event stream for real-time updates in live mode
- **FR-013**: CLI MUST handle connection errors with user-friendly messages (daemon not running, socket not found, permission denied)
- **FR-014**: CLI MUST implement connection timeout (5 seconds) and retry logic for transient failures
- **FR-015**: CLI MUST validate JSON-RPC responses against expected schema and handle malformed responses gracefully

#### Project Management Commands

- **FR-016**: CLI MUST provide `i3pm project switch <name>` command to activate project context
- **FR-017**: CLI MUST provide `i3pm project clear` command to deactivate project context (global mode)
- **FR-018**: CLI MUST provide `i3pm project current` command to display active project name
- **FR-019**: CLI MUST provide `i3pm project list` command to display all configured projects
- **FR-020**: CLI MUST provide `i3pm project create` command with flags: `--name`, `--dir`, `--icon`, `--display-name`
- **FR-021**: CLI MUST provide `i3pm project show <name>` command to display complete project configuration
- **FR-022**: CLI MUST provide `i3pm project edit <name>` command to modify project configuration
- **FR-023**: CLI MUST provide `i3pm project delete <name>` command to remove project
- **FR-024**: CLI MUST provide `i3pm project validate` command to validate all project configurations

#### Window State Visualization

- **FR-025**: CLI MUST provide `i3pm windows` command with default tree view output
- **FR-026**: CLI MUST support `--tree` flag for hierarchical output (outputs → workspaces → windows)
- **FR-027**: CLI MUST support `--table` flag for tabular output with sortable columns
- **FR-028**: CLI MUST support `--json` flag for machine-readable JSON output
- **FR-029**: CLI MUST support `--live` flag for interactive TUI with real-time updates
- **FR-030**: Live TUI MUST update display within 100ms of window events (new, close, focus, title)
- **FR-031**: Live TUI MUST support keyboard shortcuts: Tab (switch view), H (toggle hidden), Q (quit), Ctrl+C (exit)
- **FR-032**: Live TUI MUST handle terminal resize events and redraw display appropriately
- **FR-033**: CLI MUST format window data with visual indicators: ● (focus), 🔸 (scoped), 🔒 (hidden), ⬜ (floating)
- **FR-034**: CLI MUST display project tags for scoped windows: `[nixos]`, `[stacks]`, `[personal]`

#### Daemon Status and Events

- **FR-035**: CLI MUST provide `i3pm daemon status` command showing uptime, connection state, event counts, active project
- **FR-036**: CLI MUST provide `i3pm daemon events` command showing recent daemon events with timestamps
- **FR-037**: CLI MUST support `--limit` flag to control number of events displayed (default 20)
- **FR-038**: CLI MUST support `--type` flag to filter events by type (window, workspace, output, tick)
- **FR-039**: CLI MUST support `--since-id` flag to show events after specific event ID

#### Window Classification and Rules

- **FR-040**: CLI MUST provide `i3pm rules list` command showing all window classification rules
- **FR-041**: CLI MUST provide `i3pm rules classify` command with `--class` and `--instance` flags for testing classification
- **FR-042**: CLI MUST provide `i3pm rules validate` command to validate window rules configuration
- **FR-043**: CLI MUST provide `i3pm rules test` command with `--class` flag to show rule matching logic
- **FR-044**: CLI MUST provide `i3pm app-classes` command to display scoped and global application classes

#### Interactive Monitor Dashboard

- **FR-045**: CLI MUST provide `i3pm monitor` command launching interactive TUI dashboard
- **FR-046**: Monitor TUI MUST display multiple panes: daemon status, event stream, window state
- **FR-047**: Monitor TUI MUST update all panes in real-time with <250ms refresh rate
- **FR-048**: Monitor TUI MUST support keyboard navigation and graceful exit (Q key)

#### Terminal UI Standards

- **FR-049**: All TUI modes MUST use Deno standard library ANSI utilities from `@std/cli/unstable-ansi` for terminal formatting
- **FR-050**: All TUI modes MUST use `@std/cli/unicode-width` for string width calculations in table formatting
- **FR-051**: All TUI modes MUST restore terminal state on exit (alternate screen buffer, cursor visibility, raw mode)
- **FR-052**: All TUI modes MUST support double Ctrl+C (within 1 second) for immediate exit

#### Type Safety and Data Validation

- **FR-053**: CLI MUST define TypeScript interfaces for all daemon protocol messages (requests, responses, events)
- **FR-054**: CLI MUST define TypeScript types for all entity models (WindowState, Workspace, Output, Project, Event)
- **FR-055**: CLI MUST validate all runtime data against TypeScript types using runtime validation library (Zod recommended)
- **FR-056**: CLI MUST handle type validation failures gracefully with descriptive error messages

#### NixOS Integration

- **FR-057**: CLI binary MUST be packaged as NixOS derivation using Deno build infrastructure
- **FR-058**: CLI package MUST declare all required Deno permissions in compilation flags (--allow-net, --allow-read)
- **FR-059**: CLI package MUST be installed via home-manager in user packages with executable name `i3pm`
- **FR-060**: CLI binary path MUST be available in system PATH for all user sessions

### Key Entities

- **WindowState**: Represents a single window with properties: ID, class, instance, title, workspace, output, marks (including project mark), focused state, hidden state, floating state, fullscreen state, geometry (x, y, width, height)

- **Workspace**: Represents an i3 workspace with properties: number, name, focused state, visible state, output assignment, list of windows

- **Output**: Represents a monitor/display with properties: name, active state, primary state, geometry (x, y, width, height), current workspace, list of all workspaces assigned to output

- **Project**: Represents a project context with properties: name, display name, icon (emoji/Unicode character), directory path, list of scoped window classes, created timestamp, last used timestamp

- **EventNotification**: Real-time update from daemon with properties: event ID, event type (window, workspace, output, tick), change type (new, close, focus, title, move, etc.), affected window/workspace/output data, timestamp

- **DaemonStatus**: Daemon state information with properties: status string (running/stopped), connected state (to i3), uptime seconds, active project name, window count, workspace count, event count, error count

- **WindowRule**: Classification rule with properties: rule ID, window class pattern (regex), window instance pattern (optional), scope assignment (scoped/global), priority, enabled state

- **ApplicationClass**: Application classification with properties: class name, display name, scope (scoped/global), icon, description

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete project switching workflow (switch, verify windows, switch back) in under 5 seconds
- **SC-002**: CLI binary size is under 20MB (compiled Deno executable with all dependencies)
- **SC-003**: CLI starts and displays first command output within 300ms on standard hardware
- **SC-004**: Real-time window updates in live TUI appear within 100ms of actual window events
- **SC-005**: CLI memory usage remains under 50MB during extended live monitoring sessions (>1 hour)
- **SC-006**: All existing Python CLI commands have equivalent Deno implementations with identical output formats
- **SC-007**: Users can execute scripted workflows using `--json` output piped to jq or other tools
- **SC-008**: Zero runtime dependencies required for end users (single compiled Deno executable)
- **SC-009**: CLI handles daemon unavailability gracefully with actionable error messages in 100% of test cases
- **SC-010**: Terminal UI exits cleanly without artifacts in 100% of test cases (proper terminal restoration)

## Scope *(mandatory)*

### In Scope

- Complete TypeScript/Deno implementation of all Python CLI commands and features
- Extensible CLI architecture supporting multiple parent command namespaces
- JSON-RPC 2.0 client for daemon communication over Unix socket
- Real-time event subscription and processing for live TUI modes
- Terminal UI rendering using Deno std library ANSI utilities
- Multiple output formats: tree, table, JSON for window state
- Interactive TUI modes: live window monitoring, monitor dashboard
- Project management: create, list, switch, show, edit, delete, validate
- Window rules: list, classify, validate, test
- Daemon commands: status, events with filtering
- Type-safe data models for all entities with runtime validation
- NixOS packaging and home-manager integration
- Compiled standalone binary distribution
- Keyboard event handling and signal management
- Error handling with user-friendly messages
- Help documentation for all commands

### Out of Scope

- Python daemon rewrite (daemon remains Python-based)
- Changes to daemon JSON-RPC protocol or IPC interface
- New features not present in existing Python CLI
- Browser-based or web UI
- Configuration file format changes
- Automated testing framework (remains Python-based)
- Real-time monitoring tools for daemon debugging (remains Python-based)
- Multi-daemon support or network-based communication
- Plugin system or third-party extensions
- Alternative compilation targets (WASM, native binaries)

## Assumptions *(mandatory)*

1. **Daemon Compatibility**: Existing Python daemon continues to run unchanged with current JSON-RPC 2.0 protocol over Unix socket
2. **Terminal Capabilities**: Users have modern terminal emulators supporting ANSI escape codes, UTF-8, and alternate screen buffer
3. **Deno Version**: Deno 1.40+ is available in NixOS for development and compilation
4. **Unix Socket Access**: CLI runs on same system as daemon with read/write access to Unix socket
5. **NixOS Build System**: NixOS infrastructure supports Deno compilation and packaging via buildDenoApplication or custom derivation
6. **Performance Target**: Deno/TypeScript performance is comparable or better than Python for CLI operations and TUI rendering
7. **Standard Library Coverage**: Deno standard library provides sufficient functionality for JSON-RPC, terminal UI, and file I/O without third-party dependencies
8. **Type System**: TypeScript's type system is sufficient for modeling all daemon protocol messages and entity types
9. **Compilation Model**: Single compiled executable is acceptable deployment model for NixOS users (no requirement for source distribution)
10. **Python CLI Deprecation**: After Deno CLI is validated, Python CLI will be deprecated and removed to eliminate maintenance burden

## Dependencies *(mandatory)*

### External Dependencies

- **Deno Runtime**: Required for development and compilation (version 1.40+)
- **Deno Standard Library**: Core dependency for CLI parsing (`@std/cli/parse-args`), ANSI formatting (`@std/cli/unstable-ansi`), Unicode width (`@std/cli/unicode-width`), file I/O (`@std/fs`, `@std/path`), JSON utilities (`@std/json`)
- **i3-project-event-daemon**: Python daemon must be running for all CLI operations
- **Unix Socket**: Daemon's Unix socket at `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock` must exist and be accessible
- **NixOS Build Infrastructure**: Required for packaging and compilation

### Internal Dependencies

- **JSON-RPC Protocol**: CLI depends on daemon's JSON-RPC 2.0 interface contract (methods: get_status, get_events, get_windows, get_window_tree, subscribe_events, etc.)
- **Event Stream Format**: CLI depends on daemon's event notification message structure (event_notification method with params)
- **Window Data Schema**: CLI depends on daemon's window state JSON schema (WindowState properties)
- **Project Configuration Schema**: CLI depends on project JSON configuration format (name, directory, icon, scoped_classes)

### Build-time Dependencies

- **Deno Compiler**: Required to produce standalone executable (`deno compile`)
- **TypeScript Compiler**: Built into Deno, no separate installation needed
- **NixOS Packaging Tools**: For creating derivation and integrating into home-manager

### Runtime Dependencies

- **None**: Compiled binary is self-contained with no external runtime dependencies

## Out of Scope Features *(optional - include if relevant)*

- **Daemon Rewrite**: Python daemon will remain unchanged - only CLI is being rewritten
- **New Visualization Modes**: Only existing modes (tree, table, JSON, live, monitor) will be ported
- **Configuration UI**: No interactive configuration editor or setup wizard
- **Plugin System**: No extensibility framework or third-party plugin support
- **Network Protocol**: Communication remains local Unix socket only, no TCP/HTTP support
- **Multi-daemon Support**: CLI connects to single local daemon only
- **Alternative Runtimes**: No support for Node.js, Bun, or other JavaScript runtimes
- **Cross-compilation**: Binary compilation targets only the system where NixOS rebuild runs
- **Backward Compatibility Mode**: No support for old Python CLI command aliases or deprecated features

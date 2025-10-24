# Feature Specification: Declarative Workspace-to-Monitor Mapping Configuration

**Feature Branch**: `033-declarative-workspace-to`
**Created**: 2025-10-23
**Status**: Draft
**Input**: User description: "Declarative workspace-to-monitor mapping configuration with dynamic multi-monitor support for 1-3 displays"

## Problem Statement

The current workspace-to-monitor assignment system uses hardcoded distribution rules embedded in Python code (`workspace_manager.py`) and bash scripts (`detect-monitors.sh`). While this works, it has several limitations:

**Current Issues**:
- Workspace-to-monitor preferences are not explicitly documented or configurable
- Distribution rules (1-2 on primary, 3-5 on secondary, etc.) are embedded in code
- Dual implementation (Python and bash) creates maintenance burden and inconsistency
- No way to specify which workspaces belong on which monitor role without editing code
- Difficult to adjust workspace assignments for specific use cases (e.g., workspace 18 should always be on secondary)
- No visibility into current monitor configuration and workspace assignments
- Manual reassignment requires running shell scripts directly

The system already has the foundation (Python workspace manager, monitor detection, i3ipc integration), but lacks a declarative configuration layer to make it user-friendly and maintainable.

## Design Principle: Forward-Only Development

**This feature will REPLACE the existing implementation, not extend it.**

Following the principle of "don't worry about backward compatibility - create the best solution":

- **REMOVE**: `detect-monitors.sh` bash script - replaced by daemon-based event-driven system
- **REPLACE**: Hardcoded distribution logic in `workspace_manager.py` - replaced by configuration-driven logic
- **MODERNIZE**: Event-driven architecture only (no startup scripts)
- **SIMPLIFY**: Single source of truth (JSON config) instead of code + scripts

**Migration Strategy**:
- Users will need to create a configuration file or accept new defaults
- No compatibility mode for old bash script
- Existing hardcoded rules become the default config template
- One-time migration: extract current behavior → JSON config → delete old scripts

This approach ensures the cleanest, most maintainable solution without technical debt from legacy compatibility layers.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Declarative Workspace Distribution Configuration (Priority: P1)

As a system administrator, I need to define workspace-to-monitor distribution rules in a JSON configuration file, so that I can explicitly document and customize which workspaces appear on which monitor role (primary/secondary/tertiary) without editing Python code.

**Why this priority**: This is the foundation that enables all other functionality. A declarative config file makes the current implicit behavior explicit and allows for customization. This provides immediate value by documenting the system's behavior and enabling simple adjustments.

**Independent Test**: Create a JSON config file that assigns workspaces 1-2 to primary, 3-10 to secondary, verify the daemon reads this config and applies assignments correctly when monitors are connected.

**Acceptance Scenarios**:

1. **Given** I have a 2-monitor setup, **When** I define workspace distribution in JSON config (workspaces 1-2 on primary, 3-10 on secondary), **Then** the system reads this configuration and assigns workspaces to the correct monitors on startup
2. **Given** I have a configuration file with workspace preferences, **When** I change the config to reassign workspace 5 from secondary to primary, **Then** after reloading the configuration (without restarting i3), workspace 5 moves to the primary monitor
3. **Given** I have custom workspace assignments for specific workspaces (e.g., workspace 18 always on secondary), **When** the system applies the configuration, **Then** those specific assignments override the default distribution rules
4. **Given** I have no configuration file, **When** the system initializes, **Then** it uses built-in default distribution rules (1-2 primary, 3-9 secondary for 2 monitors)

---

### User Story 2 - Multi-Monitor Adaptation (Priority: P1)

As a laptop user who docks and undocks from external monitors, I need the system to automatically adjust workspace distribution based on the number of active monitors (1, 2, or 3), so that workspaces are always accessible regardless of my current monitor configuration.

**Why this priority**: This is critical for usability in laptop scenarios. Users frequently change monitor configurations, and the system must adapt without manual intervention. This builds on the existing auto-detection but makes it configurable.

**Independent Test**: Start with 1 monitor (all workspaces on primary), connect a second monitor (workspaces redistribute according to config), verify all workspaces are accessible and on correct outputs.

**Acceptance Scenarios**:

1. **Given** I have 1 monitor configured, **When** the system starts or monitors change, **Then** all workspaces (1-10) are assigned to the primary output
2. **Given** I connect a second monitor, **When** the system detects the new output, **Then** workspaces automatically redistribute (1-2 on primary, 3-10 on secondary by default)
3. **Given** I disconnect a secondary monitor, **When** only the primary remains active, **Then** all workspaces move to the primary monitor so they remain accessible
4. **Given** I have 3 monitors configured, **When** the system applies workspace distribution, **Then** workspaces are distributed across all three (1-2 primary, 3-5 secondary, 6-10 tertiary by default)

---

### User Story 3 - Comprehensive CLI/TUI Interface (Priority: P1)

As a system administrator, I need a complete CLI and TUI interface to view monitor configuration, manage workspace assignments, edit configuration, and troubleshoot issues, so that I can fully control the workspace-to-monitor system without leaving the terminal.

**Why this priority**: This is the primary user interface for the feature. Without comprehensive CLI/TUI commands, users cannot effectively use or troubleshoot the system. This is P1 because it's the main interaction point - the config file is secondary.

**Independent Test**: Run various CLI commands to view status, move workspaces, edit config, validate changes, and view live monitor dashboard. Verify all operations complete successfully with clear, actionable output.

**Acceptance Scenarios**:

#### Status and Information Display

1. **Given** I want to see current system state, **When** I run `i3pm monitors status`, **Then** I see a formatted table showing all outputs (name, active, primary, role, resolution, current workspaces)
2. **Given** I want detailed workspace info, **When** I run `i3pm monitors workspaces`, **Then** I see which workspaces are on which monitor, with window counts and visibility status
3. **Given** I want to see the config, **When** I run `i3pm monitors config show`, **Then** I see the current configuration with syntax highlighting and comments explaining each section
4. **Given** I want live monitoring, **When** I run `i3pm monitors watch`, **Then** I enter an interactive TUI that updates in real-time as monitors connect/disconnect and workspaces move

#### Configuration Management

5. **Given** I want to edit the config, **When** I run `i3pm monitors config edit`, **Then** my default editor opens with the config file and validates on save
6. **Given** I want to generate a default config, **When** I run `i3pm monitors config init`, **Then** a default configuration file is created with comments explaining all options
7. **Given** I want to validate my config, **When** I run `i3pm monitors config validate`, **Then** I see validation results with specific errors or confirmation that config is valid
8. **Given** I made config changes, **When** I run `i3pm monitors config reload`, **Then** the daemon reloads the config without restart and I see a summary of what changed

#### Workspace Operations

9. **Given** I want to move a workspace, **When** I run `i3pm monitors move 5 --to secondary`, **Then** workspace 5 immediately moves to the secondary monitor
10. **Given** I want to reorganize all workspaces, **When** I run `i3pm monitors reassign`, **Then** all workspaces redistribute according to current config and monitor setup
11. **Given** I want to preview reassignment, **When** I run `i3pm monitors reassign --dry-run`, **Then** I see what would change without applying changes
12. **Given** I disconnected a monitor, **When** I run `i3pm monitors restore`, **Then** workspaces return to their last known good state for the current monitor configuration

#### Interactive TUI

13. **Given** I want an interactive interface, **When** I run `i3pm monitors tui`, **Then** I enter a full-screen TUI with:
    - Live monitor status (top panel)
    - Workspace-to-monitor mapping (middle panel)
    - Keybindings to move workspaces, reload config, view logs (bottom panel)
14. **Given** I'm in the TUI, **When** I press 'm' on a workspace, **Then** I get a menu to move that workspace to any available monitor
15. **Given** I'm in the TUI, **When** I press 'e', **Then** the config editor opens, and on save the TUI updates with new assignments
16. **Given** I'm in the TUI, **When** monitors connect/disconnect, **Then** the display updates in real-time showing the new configuration

#### Troubleshooting and Diagnostics

17. **Given** I have workspace visibility issues, **When** I run `i3pm monitors diagnose`, **Then** I see a diagnostic report showing:
    - Active vs inactive outputs
    - Workspaces on inactive outputs (if any)
    - Windows that might be "lost" on hidden workspaces
    - Suggested fixes
18. **Given** I want to see recent changes, **When** I run `i3pm monitors history`, **Then** I see a log of recent monitor events and workspace reassignments
19. **Given** something isn't working, **When** I run `i3pm monitors debug`, **Then** I see verbose debug output including config load status, monitor detection, and workspace assignment commands sent to i3

---

### User Story 4 - Intelligent Workspace State Preservation (Priority: P2)

As a laptop user who frequently docks and undocks, I need the system to remember which workspaces had windows when I disconnect monitors, and intelligently restore those workspaces to the correct monitor roles when I reconnect, so that my workspace organization is preserved across monitor configuration changes.

**Why this priority**: This is critical for maintaining workflow continuity when docking/undocking. Without this, disconnecting a monitor causes all windows to collapse onto the remaining display, and users must manually reorganize when reconnecting. This is high priority (P2) because it dramatically improves the laptop docking experience.

**Independent Test**: With 2 monitors, open windows on workspaces 1-8 (some on primary, some on secondary). Disconnect the secondary monitor (all workspaces collapse to primary). Reconnect the secondary monitor. Verify that workspaces automatically return to their original monitor roles, preserving the workspace organization.

**Acceptance Scenarios**:

1. **Given** I have windows on workspaces 3-5 on the secondary monitor, **When** I disconnect the secondary monitor, **Then** those workspaces move to the primary monitor (so windows remain accessible) and the system records their original monitor assignment
2. **Given** I previously disconnected a monitor that had workspaces 3-5, **When** I reconnect a monitor that becomes the secondary, **Then** workspaces 3-5 automatically return to the secondary monitor within 3 seconds
3. **Given** I have a custom workspace preference (workspace 18 always on secondary), **When** I reconnect monitors after a disconnect, **Then** workspace 18 returns to the secondary monitor even if it was temporarily on primary
4. **Given** I disconnect and reconnect monitors multiple times, **When** the monitor topology stabilizes, **Then** all workspaces return to their configured monitor roles based on the current configuration
5. **Given** I have windows on workspace 7 when I disconnect, **When** I reconnect with a different number of monitors (e.g., went from 2 to 3 monitors), **Then** workspace 7 moves to the appropriate monitor role according to the current distribution rules (e.g., tertiary instead of secondary)

---

### Edge Cases

- **Monitor disconnected mid-session**: System detects inactive output, moves affected workspaces to remaining active monitors according to configuration, prevents "lost" workspaces
- **All monitors disconnect except one**: System falls back to single-monitor distribution, all workspaces move to the remaining output
- **Primary monitor not specified in xrandr**: System uses first active output as primary, logs a warning, continues with workspace assignment
- **Configuration file has conflicting assignments**: System reports error during validation, uses last-defined assignment or falls back to defaults, logs warning
- **Workspace assigned to non-existent monitor role**: If config assigns workspace to "tertiary" but only 2 monitors exist, system assigns to secondary instead with warning
- **Configuration file missing or corrupt**: System uses built-in default distribution rules, logs warning, continues operation
- **Rapid monitor connect/disconnect cycles**: System debounces monitor change events (wait 2 seconds for stabilization) before redistributing workspaces
- **User manually moves workspace then config reloads**: Config reload overrides manual assignments (manual moves are temporary unless saved to config)
- **Workspace numbers beyond defined range**: System supports unlimited workspace numbers (10-70+), applies default role assignment based on number ranges if not explicitly configured

## Requirements *(mandatory)*

### Functional Requirements

#### Configuration File Management

- **FR-001**: System MUST read workspace-to-monitor mapping configuration from a JSON file at `~/.config/i3/workspace-monitor-mapping.json`
- **FR-002**: Configuration file MUST define default distribution rules for 1-monitor, 2-monitor, and 3-monitor scenarios
- **FR-003**: Configuration file MUST support workspace preferences that override default distribution (e.g., workspace 18 always on secondary)
- **FR-004**: System MUST use built-in default distribution rules if configuration file is missing or invalid
- **FR-005**: System MUST validate configuration file syntax (valid JSON) before loading
- **FR-006**: System MUST validate workspace numbers are positive integers
- **FR-007**: Configuration file MUST support output preferences (preferred output names with fallback strategy)

#### Monitor Detection and Role Assignment

- **FR-008**: System MUST query i3 IPC GET_OUTPUTS to detect active monitors on startup and when monitors change
- **FR-009**: System MUST assign roles (primary, secondary, tertiary) to active monitors based on xrandr primary flag and output order
- **FR-010**: System MUST handle 1-monitor, 2-monitor, and 3+ monitor configurations with different distribution rules
- **FR-011**: System MUST use "primary" keyword for the xrandr-designated primary output
- **FR-012**: System MUST provide fallback role assignment if primary monitor is not explicitly set

#### Workspace Distribution

- **FR-013**: System MUST assign workspaces to monitors by sending i3 IPC commands (`workspace <num> output <output>`)
- **FR-014**: Default distribution for 1 monitor MUST assign all workspaces to primary
- **FR-015**: Default distribution for 2 monitors MUST assign workspaces 1-2 to primary, 3-10 to secondary (configurable)
- **FR-016**: Default distribution for 3 monitors MUST assign workspaces 1-2 to primary, 3-5 to secondary, 6-10 to tertiary (configurable)
- **FR-017**: System MUST support workspace numbers beyond 10 (up to 70+) with configurable assignments
- **FR-018**: System MUST apply workspace preferences from config that override default distribution rules

#### Runtime Workspace Movement

- **FR-019**: System MUST support moving individual workspaces to specific outputs via CLI command
- **FR-020**: System MUST support moving workspaces using relative directions (left, right, up, down)
- **FR-021**: System MUST support moving workspaces to outputs by name (e.g., "DP-1", "HDMI-2")
- **FR-022**: System MUST support moving workspaces to outputs by role (primary, secondary, tertiary)

#### Status and Monitoring

- **FR-023**: System MUST provide CLI command to display current monitor configuration (names, active status, primary flag, roles)
- **FR-024**: System MUST provide CLI command to display current workspace-to-output assignments
- **FR-025**: System MUST show which workspaces are visible vs hidden on current monitor setup
- **FR-026**: System MUST report inactive outputs and affected workspaces

#### Configuration Validation

- **FR-027**: System MUST validate configuration file syntax and report specific errors (line numbers, invalid fields)
- **FR-028**: System MUST support dry-run mode that shows what would change without applying changes
- **FR-029**: System MUST detect conflicting workspace assignments and report errors during validation
- **FR-030**: System MUST warn if workspace is assigned to a monitor role that doesn't exist in current setup

#### Event-Driven Updates

- **FR-031**: System MUST subscribe to i3 IPC output events to detect monitor connect/disconnect
- **FR-032**: System MUST automatically redistribute workspaces when monitors are added or removed
- **FR-033**: System MUST debounce monitor change events (2-second delay) to avoid rapid reassignments during unstable periods
- **FR-034**: System MUST reload configuration file without restarting daemon when configuration changes are detected

#### CLI/TUI Interface (Deno CLI Integration)

- **FR-035**: CLI MUST provide `i3pm monitors status` command showing all outputs with name, active status, primary flag, role, resolution, and current workspaces in a formatted table
- **FR-036**: CLI MUST provide `i3pm monitors workspaces` command showing workspace-to-output mapping with window counts and visibility
- **FR-037**: CLI MUST provide `i3pm monitors config show` command displaying current config with syntax highlighting
- **FR-038**: CLI MUST provide `i3pm monitors config edit` command opening default editor with validation on save
- **FR-039**: CLI MUST provide `i3pm monitors config init` command generating default config with explanatory comments
- **FR-040**: CLI MUST provide `i3pm monitors config validate` command checking syntax and logical errors
- **FR-041**: CLI MUST provide `i3pm monitors config reload` command reloading daemon config and showing change summary
- **FR-042**: CLI MUST provide `i3pm monitors move <workspace> --to <role|output>` command for moving workspaces
- **FR-043**: CLI MUST provide `i3pm monitors reassign` command redistributing all workspaces according to config
- **FR-044**: CLI MUST provide `i3pm monitors reassign --dry-run` command previewing changes without applying
- **FR-045**: CLI MUST provide `i3pm monitors restore` command restoring workspaces to last known good state
- **FR-046**: CLI MUST provide `i3pm monitors watch` command entering live-updating TUI dashboard
- **FR-047**: CLI MUST provide `i3pm monitors tui` command entering full interactive TUI with workspace management
- **FR-048**: CLI MUST provide `i3pm monitors diagnose` command generating diagnostic report for troubleshooting
- **FR-049**: CLI MUST provide `i3pm monitors history` command showing recent monitor events and workspace changes
- **FR-050**: CLI MUST provide `i3pm monitors debug` command showing verbose debug output
- **FR-051**: TUI MUST update in real-time when monitors connect/disconnect (event subscription)
- **FR-052**: TUI MUST provide keybindings for common operations (m=move, e=edit, r=reload, q=quit)
- **FR-053**: TUI MUST show live window counts per workspace
- **FR-054**: TUI MUST highlight workspaces on inactive outputs (visibility warning)
- **FR-055**: All CLI commands MUST provide `--json` flag for scripting/automation
- **FR-056**: All CLI commands MUST provide `--help` with examples and usage information
- **FR-057**: CLI MUST integrate with existing `i3pm` command structure (subcommand: `monitors`)

#### Migration and Cleanup (Forward-Only Development)

- **FR-058**: System MUST generate a default configuration file from current hardcoded rules on first run if no config exists
- **FR-059**: Implementation MUST delete `detect-monitors.sh` script and remove it from i3 config startup
- **FR-060**: Implementation MUST refactor `workspace_manager.py` to load distribution rules from config instead of hardcoded values
- **FR-061**: System MUST NOT provide any compatibility mode or fallback to bash script - config-driven approach is the only supported method
- **FR-062**: Documentation MUST clearly state that users need to use the new config file format - no migration path for custom bash scripts

### Key Entities

- **WorkspaceMonitorConfig**: The declarative configuration defining workspace distribution rules, workspace preferences, and output preferences. Contains distribution rules for 1/2/3 monitor scenarios, specific workspace-to-role assignments, and preferred output names with fallback strategies.

- **MonitorConfig**: Represents a physical output/display with its name (from i3 IPC), active status, primary flag, assigned role (primary/secondary/tertiary), and rectangle (position and size). Created from i3 IPC GET_OUTPUTS data.

- **WorkspaceAssignment**: Represents the mapping of a specific workspace number to an output name or role. Can be default (from distribution rule) or explicit (from workspace preference). Includes the workspace number, target output name or role, and assignment source (default vs explicit).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can create a workspace configuration file and have it applied correctly within 5 seconds of daemon startup
- **SC-002**: System automatically redistributes workspaces within 3 seconds of monitor connect/disconnect events
- **SC-003**: 100% of workspaces remain accessible (on active outputs) when monitors are added or removed
- **SC-004**: Configuration validation reports all errors in under 1 second with specific error messages
- **SC-005**: CLI status commands display current monitor and workspace configuration in under 500 milliseconds
- **SC-006**: Manual workspace movement via CLI takes effect immediately (under 200 milliseconds)
- **SC-007**: System maintains workspace distribution preferences across i3 restarts without configuration loss
- **SC-008**: Users can understand and modify workspace distribution by editing JSON config file without reading code
- **SC-009**: TUI updates display within 100 milliseconds of monitor connect/disconnect events
- **SC-010**: Users can complete common tasks (view status, move workspace, reload config) using CLI commands in under 5 seconds
- **SC-011**: Interactive TUI provides all essential operations without requiring memorization of commands
- **SC-012**: Diagnostic commands identify and suggest fixes for 90% of common misconfiguration issues

## Assumptions

- **i3 window manager version**: Assumes i3 v4.16+ with support for multiple output assignment (`workspace <num> output <out1> <out2>...`)
- **i3ipc-python library**: Already available and supports async GET_OUTPUTS and GET_WORKSPACES queries
- **Existing workspace_manager.py**: Can be extended with configuration loading logic without breaking existing functionality
- **xrandr primary output**: Assumes users set primary output via `xrandr --output <name> --primary` for consistent role assignment
- **Monitor naming**: Assumes output names from i3 IPC (DP-1, HDMI-2, rdp0, etc.) are stable and consistent across sessions
- **JSON configuration format**: Assumes users are comfortable editing JSON or configuration will be managed via CLI tools in the future
- **Workspace numbering**: Assumes users primarily use numbered workspaces (1-70) rather than named workspaces
- **Default distributions are reasonable**: Assumes current hardcoded rules (1-2 primary, 3-9 secondary) are acceptable defaults for most users
- **Monitor roles are sufficient**: Assumes primary/secondary/tertiary roles cover most use cases (no need for custom role names)

## Dependencies

- **i3 IPC protocol**: Feature relies on GET_OUTPUTS, GET_WORKSPACES, and output event subscriptions
- **Python daemon**: Feature requires the i3 project event daemon to be running for automatic reassignment
- **i3pm CLI**: Feature adds new subcommands to existing Deno CLI for user interaction

## Components to Remove/Replace

Following forward-only development principles, this feature **removes** these legacy components:

- **`detect-monitors.sh`**: Bash startup script - DELETED (replaced by daemon event-driven system)
- **Hardcoded distribution logic in `workspace_manager.py`**: Lines 186-221 - REPLACED with config-driven logic
- **`assign_workspaces_to_monitors()` function**: REFACTORED to load from config instead of hardcoded rules
- **i3 config startup exec**: `exec --no-startup-id ~/.config/i3/scripts/detect-monitors.sh` - REMOVED

**Justification**:
- Bash script adds complexity and runs only once at startup (misses runtime monitor changes)
- Hardcoded rules cannot be customized without editing Python code
- Dual implementation (bash + Python) creates inconsistency
- Event-driven daemon approach is superior in all cases (detects runtime changes, no startup delay, single source of truth)

## Out of Scope

The following are explicitly **not** included in this feature:

### Not Implementing (Future Features)
- **Layout restoration**: Saving and restoring window positions and layouts (this is a separate concern, potentially using i3-resurrect or existing layout module)
- **Named workspaces**: Configuration focuses on numbered workspaces; named workspace support is not prioritized
- **Per-project workspace assignments**: Project-specific workspace preferences are handled by existing project system, not this feature
- **Automatic layout save on monitor change**: System redistributes workspaces but doesn't save/restore window layouts
- **GUI configuration editor**: Configuration is JSON file-based; future GUI tool could be added separately
- **Historical workspace assignments**: No tracking of previous assignments or undo functionality
- **Cross-machine configuration sync**: No cloud sync or sharing of workspace configurations across different machines

### Explicitly NOT Maintaining (Removed)
- **Backward compatibility with detect-monitors.sh**: Script will be deleted, no migration or dual-mode support
- **Hardcoded distribution fallback**: No fallback to old hardcoded logic if config is missing - generate default config instead
- **Bash script integration**: No support for custom bash scripts or shell-based workspace assignment
- **Dual implementation paths**: Only one way to do workspace assignment (config-driven daemon), not multiple alternatives

## Open Questions

No critical open questions remain. All design decisions have reasonable defaults based on existing implementation and i3 best practices.

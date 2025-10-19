# Implementation Plan: Project-Scoped Application Workspace Management

**Branch**: `011-project-scoped-application` | **Date**: 2025-10-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/etc/nixos/specs/011-project-scoped-application/spec.md`

## Summary

This feature implements project-scoped application workspace management for i3 window manager, enabling developers to switch between project contexts (NixOS, Stacks, Personal) and have relevant applications (VS Code, Ghostty terminals, lazygit, yazi) automatically shown/hidden based on the active project. Global applications (Firefox, YouTube PWA) remain accessible across all projects. The system uses i3 IPC for dynamic window management, workspace assignment, and monitor-aware workspace distribution.

**Core Technical Approach**:
- Bash scripts for project management logic and application launchers
- i3 IPC (Inter-Process Communication) API for querying window state and executing window/workspace commands
- State file (~/.config/i3/current-project) for tracking active project context
- Polybar integration for visual project indicator and interactive project switching
- Declarative project definitions in ~/.config/i3/projects.json
- Dynamic monitor detection and adaptive workspace assignment using i3 IPC GET_OUTPUTS

## Technical Context

**Language/Version**: Bash 5.x (system scripting), i3-msg CLI (i3 IPC client), jq 1.6+ (JSON processing)

**Primary Dependencies**:
- i3wm 4.20+ (window manager with IPC support)
- i3-msg (command-line IPC client, bundled with i3)
- jq (JSON query processor for parsing i3 IPC responses and project definitions)
- xrandr (monitor detection fallback)
- sesh (tmux session manager for terminal project context)
- polybar (status bar for project indicator module)
- fzf (interactive project switcher UI)
- Standard Unix tools: grep, sed, awk, find, basename

**Storage**:
- Project definitions: ~/.config/i3/projects.json (declarative JSON configuration)
- Active project state: ~/.config/i3/current-project (JSON file tracking current project context)
- i3 configuration: ~/.config/i3/config (keybindings and module includes)
- Polybar configuration: ~/.config/polybar/config.ini (project indicator module)

**Testing**:
- Shell script unit tests using bats-core framework
- Integration tests validating i3 IPC command execution and window state transitions
- Manual acceptance testing for each user story scenario
- Monitor configuration testing (1, 2, 3 monitor setups)

**Target Platform**: NixOS Linux with i3 window manager on x86_64 (Hetzner cloud) and ARM64 (M1 Mac)

**Project Type**: Single project (i3 window manager integration via bash scripting)

**Performance Goals**:
- Project switching completes in <2 seconds including window show/hide animations
- Application launching responds within 500ms of keybinding press
- i3 IPC queries return in <100ms for window/workspace state
- Polybar project indicator updates within 1 second of state change

**Constraints**:
- Must work within i3 window manager constraints (no custom compositor)
- Must preserve existing keybindings and workflow patterns
- Must support multi-monitor configurations dynamically
- Must handle applications that don't expose clean window properties
- Must maintain compatibility with existing sesh terminal sessions

**Scale/Scope**:
- Support 3-5 project definitions per user
- Handle 10-20 open application windows per project
- Support 1-3 monitor configurations
- Manage 9 workspaces (1-9) with dynamic content

## i3 IPC Integration

The i3 IPC protocol is the primary mechanism for querying window state, controlling window visibility, managing workspaces, and detecting monitor configuration. This section documents the specific i3 IPC message types and event subscriptions required for this feature.

### i3 IPC Message Types Used

#### 1. RUN_COMMAND (Type 0)
**Purpose**: Execute i3 commands for window/workspace manipulation

**Critical Commands**:
```bash
# Hide project-scoped windows (move to scratchpad or high workspace)
i3-msg "[class=\"Code\"] mark project_${PROJECT_ID}, move scratchpad"

# Show project-scoped windows (move to designated workspace)
i3-msg "[mark=\"project_${PROJECT_ID}\"] scratchpad show, move to workspace 2"

# Move window to specific workspace
i3-msg "[id=${WINDOW_ID}] move to workspace ${WORKSPACE_NUM}"

# Assign workspace to monitor output
i3-msg "workspace ${WORKSPACE_NUM} output ${OUTPUT_NAME}"
```

**Response Format**: Array of results with `success` boolean and optional `error` string
```json
[{ "success": true }]
```

#### 2. GET_WORKSPACES (Type 1)
**Purpose**: Query current workspace state for monitor assignment and visibility

**Usage**:
```bash
i3-msg -t get_workspaces | jq '.[] | {num, name, visible, focused, output}'
```

**Response Fields Used**:
- `num`: Workspace number (1-9)
- `name`: Workspace display name (may be dynamically set by i3wsr)
- `visible`: Boolean indicating if workspace is currently displayed on a monitor
- `focused`: Boolean indicating if workspace has input focus
- `output`: Monitor name where workspace is displayed (e.g., "eDP-1", "HDMI-1")

**Example Response**:
```json
[
  {
    "num": 1,
    "name": "1",
    "visible": true,
    "focused": true,
    "output": "eDP-1"
  }
]
```

#### 3. GET_OUTPUTS (Type 3)
**Purpose**: Detect connected monitors for adaptive workspace distribution

**Usage**:
```bash
i3-msg -t get_outputs | jq '.[] | select(.active == true) | {name, primary}'
```

**Response Fields Used**:
- `name`: Output identifier (e.g., "eDP-1", "HDMI-1", "DP-1")
- `active`: Boolean indicating if output has valid mode (connected and enabled)
- `primary`: Boolean indicating primary monitor designation
- `current_workspace`: Current workspace visible on this output (or null)
- `rect`: Output dimensions {x, y, width, height}

**Example Response**:
```json
[
  {
    "name": "eDP-1",
    "active": true,
    "primary": true,
    "current_workspace": "1",
    "rect": { "x": 0, "y": 0, "width": 1920, "height": 1080 }
  }
]
```

#### 4. GET_TREE (Type 4)
**Purpose**: Query window tree for identifying project-associated windows

**Usage**:
```bash
# Get all windows with their properties
i3-msg -t get_tree | jq '.. | objects | select(.window != null) | {id, name, window, window_properties, marks}'
```

**Response Fields Used**:
- `id`: Internal container ID (for addressing windows)
- `window`: X11 window ID (integer)
- `name`: Window title (_NET_WM_NAME property)
- `window_properties`: Object containing:
  - `class`: WM_CLASS window class
  - `instance`: WM_CLASS instance name
  - `title`: Window title
- `marks`: Array of i3 marks assigned to this container
- `focused`: Boolean indicating if this window has focus

**Window Property Matching Strategy**:
```bash
# VS Code instances: Match by class and extract project from title
jq '.window_properties.class == "Code" and (.name | contains("/etc/nixos"))'

# Ghostty terminals: Match by class and check for sesh session in title
jq '.window_properties.class == "Ghostty" and (.name | contains("sesh-nixos"))'

# Lazygit: Match by class and repository path in title
jq '.window_properties.class == "lazygit"'

# Yazi: Match by class and working directory in title
jq '.window_properties.class == "yazi"'
```

#### 5. GET_MARKS (Type 5)
**Purpose**: Query assigned marks for project-window association tracking

**Usage**:
```bash
i3-msg -t get_marks | jq '.[] | select(startswith("project_"))'
```

**Mark Naming Convention**:
- Format: `project_${PROJECT_ID}_${APP_TYPE}`
- Examples: `project_nixos_vscode`, `project_stacks_terminal`, `project_personal_lazygit`

### i3 IPC Event Subscriptions

#### window event (Type 3)
**Purpose**: React to window lifecycle changes for automatic project association

**Subscription**:
```bash
i3-msg -t subscribe '["window"]'
```

**Change Types Used**:
- `new`: Window becomes managed by i3 → automatically assign to active project
- `close`: Window closes → clean up marks and state tracking
- `focus`: Window receives focus → potential trigger for project context switch
- `title`: Window title changes → re-evaluate project association (for terminals with dynamic titles)

**Event Response**:
```json
{
  "change": "new",
  "container": {
    "id": 35569536,
    "window": 12345678,
    "window_properties": {
      "class": "Code",
      "instance": "code",
      "title": "/etc/nixos - Visual Studio Code"
    }
  }
}
```

**Automation Strategy**:
- When `change == "new"` and window matches project-scoped application class → assign mark based on active project
- When `change == "title"` and window is project-scoped → re-parse title to verify project association still valid
- When `change == "close"` → cleanup project association tracking

#### workspace event (Type 0)
**Purpose**: Track workspace changes for monitor-aware workspace distribution

**Subscription**:
```bash
i3-msg -t subscribe '["workspace"]'
```

**Change Types Used**:
- `init`: Workspace created → assign to appropriate monitor based on priority
- `focus`: Workspace gains focus → potential trigger for restoring project windows

**Event Response**:
```json
{
  "change": "focus",
  "current": {
    "num": 2,
    "name": "2: Code",
    "output": "eDP-1"
  },
  "old": {
    "num": 1,
    "name": "1: Terminal",
    "output": "eDP-1"
  }
}
```

#### output event (Type 1)
**Purpose**: Detect monitor hotplug events for dynamic workspace reassignment

**Subscription**:
```bash
i3-msg -t subscribe '["output"]'
```

**Change Types**:
- `unspecified`: Monitor configuration changed (connection/disconnection detected)

**Response Action**:
- Query GET_OUTPUTS to get updated monitor list
- Reassign workspaces to available monitors based on priority configuration
- Execute RUN_COMMAND to move workspaces: `workspace X output <monitor>`

### i3 IPC Implementation Patterns

#### Pattern 1: Query-Modify-Verify
For reliable state changes, use three-step pattern:
```bash
# 1. Query current state
WINDOWS=$(i3-msg -t get_tree | jq '.. | objects | select(.window != null)')

# 2. Modify state
for window_id in $WINDOW_IDS; do
  i3-msg "[id=${window_id}] move scratchpad"
done

# 3. Verify state changed
VERIFY=$(i3-msg -t get_tree | jq '.. | objects | select(.scratchpad_state != "none") | .id')
```

#### Pattern 2: Mark-Based Window Management
Use marks for persistent project-window association:
```bash
# Assign mark when launching or detecting project window
i3-msg "[class=\"Code\" title=\".*${PROJECT_DIR}.*\"] mark project_${PROJECT_ID}_vscode"

# Show all windows for project
i3-msg "[con_mark=\"^project_${PROJECT_ID}_.*\"] scratchpad show"

# Hide all windows for project
i3-msg "[con_mark=\"^project_${PROJECT_ID}_.*\"] move scratchpad"
```

#### Pattern 3: Monitor-Aware Workspace Assignment
Detect monitors and assign workspaces by priority:
```bash
# Get active outputs
OUTPUTS=$(i3-msg -t get_outputs | jq -r '.[] | select(.active) | .name')
OUTPUT_COUNT=$(echo "$OUTPUTS" | wc -l)

# Assign high-priority workspaces to primary monitor
PRIMARY=$(i3-msg -t get_outputs | jq -r '.[] | select(.primary) | .name')
i3-msg "workspace 1 output ${PRIMARY}"
i3-msg "workspace 2 output ${PRIMARY}"

# Distribute remaining workspaces across secondary monitors
# (Implementation in scripts/assign-workspace-monitor.sh)
```

#### Pattern 4: Event-Driven Automation
Subscribe to events and react to window lifecycle:
```bash
# Background daemon listening to window events
i3-msg -t subscribe -m '["window"]' | while read -r event; do
  CHANGE=$(echo "$event" | jq -r '.change')
  CLASS=$(echo "$event" | jq -r '.container.window_properties.class')

  if [[ "$CHANGE" == "new" ]] && [[ "$CLASS" == "Code" ]]; then
    # Automatically assign to active project
    ACTIVE_PROJECT=$(cat ~/.config/i3/current-project | jq -r '.id')
    WINDOW_ID=$(echo "$event" | jq -r '.container.id')
    i3-msg "[id=${WINDOW_ID}] mark project_${ACTIVE_PROJECT}_vscode, move to workspace 2"
  fi
done
```

### i3 IPC Error Handling

#### Common Error Scenarios
1. **Invalid window ID**: Window closed before command executed
   - Retry logic: Query current windows before each command
   - Graceful degradation: Skip missing windows, continue batch operations

2. **Workspace assignment conflicts**: Workspace already on different monitor
   - Strategy: Force reassignment with explicit output parameter
   - Command: `workspace X output <monitor>` (overrides current assignment)

3. **Mark conflicts**: Mark already assigned to different window
   - Prevention: Use unique mark format with window ID suffix
   - Cleanup: Remove stale marks on window close events

4. **IPC socket connection failures**: i3 restarting or socket unavailable
   - Retry: Exponential backoff (100ms, 500ms, 1s)
   - Fallback: Exit gracefully, rely on state file for next invocation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ Principle I: Modular Composition
**Status**: PASS
- Scripts organized in `/etc/nixos/scripts/` directory (project-scoped utilities)
- i3 configuration modularized in `home-modules/desktop/i3-projects.nix`
- Polybar module for project indicator in `home-modules/desktop/polybar.nix`
- Reusable functions extracted into shared libraries (e.g., i3-ipc-helpers.sh)

### ✅ Principle II: Reference Implementation Flexibility
**Status**: PASS
- Feature developed against Hetzner i3 configuration (current reference)
- i3 window manager already established as standard in constitution
- Testing on both Hetzner (x86_64) and M1 (ARM64) validates cross-platform compatibility

### ✅ Principle III: Test-Before-Apply
**Status**: PASS
- All configuration changes tested via `nixos-rebuild dry-build --flake .#hetzner`
- Integration tests validate i3 IPC commands before deployment
- Manual acceptance testing per user story before committing

### ✅ Principle IV: Override Priority Discipline
**Status**: PASS
- i3 keybindings use normal assignment (user may override in local config)
- Project-scoped launcher scripts use `lib.mkDefault` for configurable paths
- No `lib.mkForce` required (additive feature, no overrides needed)

### ✅ Principle V: Platform Flexibility Through Conditional Features
**Status**: PASS
- Scripts detect i3 availability: `command -v i3-msg >/dev/null 2>&1 || exit 0`
- Conditional package installation: `lib.optionals hasI3 [ fzf jq sesh ]`
- Graceful degradation: Feature disabled on non-i3 systems (WSL, containers)

### ✅ Principle VI: Declarative Configuration Over Imperative
**Status**: PASS with justification
- Project definitions declaratively configured in ~/.config/i3/projects.json (generated via home-manager)
- i3 keybindings declaratively configured via `environment.etc."i3/config".text`
- Scripts are execution logic, not configuration (allowed per constitution)
- State file (~/.config/i3/current-project) is runtime state, not configuration drift

**Justification for runtime state file**:
- Current project selection is user interaction state, not system configuration
- Persisting across i3 restarts is expected behavior (like tmux session state)
- Alternative (no persistence) rejected: users lose project context on every i3 restart

### ✅ Principle VII: Documentation as Code
**Status**: PASS
- Feature specification in `/etc/nixos/specs/011-project-scoped-application/spec.md`
- Implementation plan (this document) in `/etc/nixos/specs/011-project-scoped-application/plan.md`
- Script headers document purpose, dependencies, and usage
- Update `CLAUDE.md` with project management workflow section

### ✅ Principle VIII: Remote Desktop & Multi-Session Standards
**Status**: PASS
- i3 window manager supports multi-session isolation (separate instances per xrdp session)
- Project context isolated per user session (state file in ~/.config)
- No shared state between concurrent sessions
- Works with existing xrdp + X11 + clipcat architecture

### ✅ Principle IX: Tiling Window Manager & Productivity Standards
**Status**: PASS (core feature alignment)
- Directly implements keyboard-driven workflow improvements
- Extends i3 workspace management with project-aware context switching
- Integrates with existing rofi launcher (fzf-based project switcher)
- Maintains compatibility with i3wsr dynamic workspace naming
- Enhances developer productivity through automated window management

### Overall Constitution Compliance
✅ **APPROVED** - All principles satisfied. Feature aligns with i3wm productivity standards and modular architecture. No violations requiring justification.

## Project Structure

### Documentation (this feature)

```
specs/011-project-scoped-application/
├── spec.md              # Feature specification (user stories, requirements)
├── plan.md              # This file (implementation plan with i3 IPC integration)
├── research.md          # Phase 0 output (i3 IPC best practices, window management patterns)
├── data-model.md        # Phase 1 output (project schema, state file format)
├── quickstart.md        # Phase 1 output (setup guide, keybinding reference)
├── contracts/           # Phase 1 output (project.json schema, IPC command contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
# Single project structure (bash scripting integration with i3)
scripts/
├── project-switch.sh              # Interactive project switcher (fzf UI)
├── project-set.sh                 # Set active project (called by switcher)
├── project-clear.sh               # Clear active project (return to global mode)
├── project-show-windows.sh        # Show windows for active project
├── project-hide-windows.sh        # Hide windows for inactive projects
├── launch-vscode-project.sh       # Launch VS Code in project context
├── launch-ghostty-project.sh      # Launch Ghostty with sesh session
├── launch-lazygit-project.sh      # Launch lazygit in project repository
├── launch-yazi-project.sh         # Launch yazi in project directory
├── assign-workspace-monitor.sh    # Adaptive monitor assignment
├── detect-monitors.sh             # Monitor detection and priority assignment
├── i3-ipc-helpers.sh              # Shared i3 IPC query/command functions
└── project-window-daemon.sh       # Background daemon for automatic window association

home-modules/desktop/
├── i3-projects.nix                # Project management keybindings and module config
├── i3.nix                         # Enhanced with project-aware workspace management
└── polybar.nix                    # Project indicator module

configurations/
└── base.nix                       # Project definitions in environment.etc

tests/
├── integration/
│   ├── test_project_switching.bats    # Project activation/deactivation tests
│   ├── test_window_management.bats    # Window show/hide via i3 IPC
│   ├── test_launcher_scripts.bats     # Application launching in project context
│   └── test_monitor_assignment.bats   # Multi-monitor workspace distribution
└── unit/
    ├── test_i3_ipc_helpers.bats       # i3 IPC query/command wrapper tests
    ├── test_project_state.bats        # State file parsing and validation
    └── test_window_matching.bats      # Window property matching logic
```

**Structure Decision**: Single project structure selected because this is an i3 window manager integration implemented via bash scripting and NixOS home-manager configuration. No frontend/backend separation needed. Scripts directory contains executable logic, home-modules contain declarative configuration, tests validate integration behavior.

## Phase 0: Outline & Research

### Research Tasks

Based on the Technical Context and i3 IPC integration requirements, the following research tasks must be completed:

1. **i3 IPC Window Management Patterns**
   - Research best practices for moving windows between workspaces and scratchpad
   - Investigate mark-based window management vs. window ID tracking
   - Evaluate window property matching strategies (class, title regex, custom properties)
   - Document reliable patterns for showing/hiding windows without visual artifacts

2. **i3 IPC Event Handling and Automation**
   - Research event subscription patterns for window lifecycle tracking
   - Investigate background daemon patterns for automatic window association
   - Evaluate event processing performance and reliability
   - Document error handling for IPC socket connection failures and race conditions

3. **Multi-Monitor Workspace Assignment**
   - Research i3 workspace-to-output assignment mechanisms
   - Investigate monitor hotplug detection and dynamic reassignment
   - Evaluate priority-based workspace distribution algorithms
   - Document xrandr vs. i3 IPC GET_OUTPUTS for monitor detection

4. **Terminal Session Management with sesh**
   - Research sesh integration patterns for project-scoped tmux sessions
   - Investigate window title propagation from sesh to Ghostty
   - Evaluate session creation vs. connection behavior
   - Document reliable patterns for identifying terminal project association

5. **State Persistence and Race Conditions**
   - Research file-based state management patterns (locking, atomic writes)
   - Investigate race conditions when multiple scripts access current-project state
   - Evaluate alternatives: state in i3 config variables, temporary files, shared memory
   - Document best practices for avoiding state corruption

### Research Output

Research findings will be documented in `/etc/nixos/specs/011-project-scoped-application/research.md` with the following structure:

- **Decision**: Chosen approach (e.g., "Use mark-based window management")
- **Rationale**: Why chosen (e.g., "Marks persist across i3 restarts, window IDs do not")
- **Alternatives Considered**: What else was evaluated (e.g., "Window ID tracking, custom properties")
- **Implementation Notes**: Practical guidance for implementation phase

## Phase 1: Design & Contracts

*Prerequisites: research.md complete*

### Entity Extraction

From the feature spec and i3 IPC integration, the following entities will be documented in `data-model.md`:

1. **Project Definition** (declarative configuration)
   - Fields: id, name, directory, icon, scopedApplications[], workspaceAssignments{}
   - Validation: Unique ID, valid directory path, valid icon name
   - Source: ~/.config/i3/projects.json (generated via home-manager)

2. **Active Project State** (runtime state)
   - Fields: projectId, projectName, projectDirectory, activatedAt (timestamp)
   - Validation: Must reference valid project ID
   - Source: ~/.config/i3/current-project (JSON file)

3. **Window-Project Association** (derived from i3 IPC)
   - Fields: windowId, containerId, projectId, appType, wmClass, title, marks[]
   - Validation: Valid window ID, project ID must exist
   - Derivation: Query i3 GET_TREE, parse window_properties and marks

4. **Workspace Configuration** (declarative + runtime)
   - Fields: number (1-9), priority (1-10), preferredMonitor (primary/secondary/tertiary/any)
   - Validation: Number in range 1-9, priority unique
   - Source: Project definition + dynamic monitor assignment

5. **Monitor Configuration** (runtime, detected)
   - Fields: name, isPrimary, isActive, currentWorkspace, dimensions
   - Validation: Active monitors must have valid output names
   - Source: i3 IPC GET_OUTPUTS

### API Contracts

From the functional requirements, the following "contracts" (bash script interfaces) will be documented in `/etc/nixos/specs/011-project-scoped-application/contracts/`:

1. **project-switch.sh**
   - Input: None (interactive fzf selector)
   - Output: Exit code 0 on success, 1 on cancellation
   - Side effects: Updates ~/.config/i3/current-project, shows/hides windows

2. **project-set.sh**
   - Input: Project ID (string)
   - Output: Exit code 0 on success, 1 on invalid project ID
   - Side effects: Updates current-project, calls show/hide scripts

3. **launch-{app}-project.sh**
   - Input: None (reads current-project state)
   - Output: Exit code 0 on success, 1 if no active project
   - Side effects: Launches application with project context, assigns i3 mark

4. **i3-ipc-helpers.sh library functions**
   - `i3_get_windows_by_mark`: Query windows with specific mark pattern
   - `i3_get_windows_by_class`: Query windows with WM_CLASS match
   - `i3_assign_mark`: Assign mark to window by ID
   - `i3_move_to_workspace`: Move window to workspace by number
   - `i3_get_active_outputs`: Query connected monitors

Contract documentation will include:
- Function signature and parameters
- Expected i3 IPC message types used
- Return value conventions (exit codes, stdout format)
- Error handling behavior
- Usage examples

### Quickstart Guide

The `quickstart.md` document will provide:
1. Installation verification (check i3-msg, jq, sesh, fzf availability)
2. Project definition creation (example projects.json)
3. Keybinding reference (Mod+p, Mod+c, Mod+Return, etc.)
4. Polybar integration setup
5. Troubleshooting common issues (IPC connection failures, window matching problems)

### Agent Context Update

After Phase 1 design completion, run:
```bash
.specify/scripts/bash/update-agent-context.sh claude
```

This will update `~/.config/claude/context/project-context.md` with:
- i3 IPC integration patterns
- Bash scripting conventions used in this project
- Testing framework (bats-core)
- State management patterns (JSON files, file locking)

## Complexity Tracking

*No constitutional violations detected. This section intentionally left empty per template guidance.*

---

**Next Steps**:
1. Execute Phase 0 research tasks (document findings in research.md)
2. Execute Phase 1 design tasks (data-model.md, contracts/, quickstart.md)
3. Run `/speckit.tasks` command to generate tasks.md with implementation tasks
4. Begin Phase 2 implementation following tasks.md

**Note**: This plan stops after Phase 1 per speckit workflow. Phase 2 (implementation) will be generated by `/speckit.tasks` command.

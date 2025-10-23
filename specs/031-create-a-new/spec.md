# Feature Specification: Automated Window Rules Discovery and Validation

**Feature Branch**: `031-create-a-new`
**Created**: 2025-10-23
**Status**: Draft
**Input**: Create a robust, accurate, and automated process for window rules and mapping applications to workspaces in a 1:1 fashion

## Problem Statement

The current workspace mapping system relies on inference-based patterns that were created through guesswork rather than actual validation against running applications. Testing revealed that windows are appearing on incorrect workspaces (e.g., VSCode on WS2 instead of WS31, Ghostty on WS1 instead of WS33), indicating that the 65 configured patterns in window-rules.json are untested and potentially incorrect.

**Current Issues**:
- Patterns were inferred without launching applications to verify actual WM_CLASS properties
- No automated way to discover correct patterns from running applications
- Manual xprop/i3-msg workflow is tedious and error-prone for 70+ applications
- No validation mechanism to test patterns against real windows
- Migration path needed to fix broken configurations with verified patterns

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Pattern Discovery (Priority: P1)

As a system administrator, I need to automatically discover the correct window matching patterns for all installed applications by launching them and capturing their actual properties, so that workspace assignments work reliably without manual investigation.

**Why this priority**: This is the foundation that enables all other functionality. Without accurate pattern discovery, workspace mapping cannot work correctly. This provides immediate value by replacing guesswork with verified data.

**Independent Test**: Launch a single application (e.g., pavucontrol), automatically capture its WM_CLASS/title properties, generate a pattern rule, and verify the pattern matches the window correctly. Success means the generated pattern can reliably identify that application.

**Acceptance Scenarios**:

1. **Given** I have an application installed (e.g., pavucontrol), **When** I run the discovery tool with the application name, **Then** the tool launches the application (either via direct command or by simulating rofi launcher with xdotool Meta+D and application search), waits for the window to appear, captures its WM_CLASS (class and instance) and title, and outputs a valid pattern that matches that window
2. **Given** I have a terminal-based application (e.g., lazygit), **When** I run discovery for this application, **Then** the tool detects that it's launched via a terminal, captures the title pattern correctly, and generates a title-based rule (e.g., `title:lazygit`)
3. **Given** I have a PWA application with a FFPWA ID, **When** I run discovery, **Then** the tool captures the full FFPWA-* pattern and generates a class-based rule with the unique ID
4. **Given** I have 70 applications to discover, **When** I provide a bulk application list, **Then** the tool processes all applications sequentially, launching each one, waiting for window appearance, capturing properties, and generating a comprehensive pattern database

---

### User Story 2 - Pattern Validation and Testing (Priority: P2)

As a system administrator, I need to validate that configured patterns correctly match their intended windows by testing against both currently open windows and newly launched windows, so that I can identify and fix broken patterns before they cause workspace assignment failures.

**Why this priority**: Validation ensures the patterns we discover or configure actually work. This prevents the issue we encountered where 65 rules were configured but untested, leading to windows on wrong workspaces. This builds upon P1 discovery to ensure reliability.

**Independent Test**: Given a window-rules.json configuration with 5 test patterns, launch each corresponding application and verify that the pattern matches the window correctly and the window appears on the assigned workspace. Success means all 5 windows are correctly identified and placed.

**Acceptance Scenarios**:

1. **Given** I have configured patterns in window-rules.json, **When** I run the validation tool against currently open windows, **Then** the tool reports which windows match their assigned patterns correctly and which windows are on wrong workspaces or unmatched
2. **Given** I have a specific pattern to test (e.g., `Code` for VSCode), **When** I run validation in launch-and-test mode, **Then** the tool launches VSCode, waits for the window, checks if the pattern matches, verifies the workspace assignment, and reports success or failure
3. **Given** I have 65 configured patterns, **When** I run comprehensive validation, **Then** the tool generates a detailed report showing: patterns that work correctly, patterns that don't match any windows, patterns that match wrong windows, and windows that have no matching patterns
4. **Given** a pattern validation fails, **When** I view the failure report, **Then** I see the expected vs actual window properties (WM_CLASS, title), expected vs actual workspace, and a suggested fix

---

### User Story 3 - Bulk Migration and Configuration Update (Priority: P3)

As a system administrator, I need to migrate my existing broken configuration to verified patterns in bulk, updating window-rules.json and app-classes.json with discovered patterns, so that I can fix all 65+ workspace assignments efficiently without manual editing.

**Why this priority**: Migration makes the discovered patterns actionable. After discovery (P1) and validation (P2), we need to efficiently update configuration files. This enables fixing the current broken state with minimal manual work.

**Independent Test**: Start with a test window-rules.json containing 5 known-broken patterns, run discovery for those 5 applications, generate new verified patterns, execute the migration, and verify the configuration file is updated with correct patterns. Success means the 5 patterns are replaced and windows now appear on correct workspaces.

**Acceptance Scenarios**:

1. **Given** I have discovered patterns for 20 applications, **When** I run the migration tool, **Then** it updates window-rules.json by replacing old patterns with verified patterns, preserves workspace assignments, maintains pattern priorities, and creates a backup of the original file
2. **Given** I have new applications to add (not in current config), **When** I run migration with discovered patterns, **Then** the tool inserts new rules into window-rules.json with appropriate workspace assignments, updates app-classes.json with scoped/global classifications, and maintains file structure
3. **Given** I have duplicate patterns in my configuration, **When** I run migration, **Then** the tool detects duplicates, reports conflicts, and prompts for resolution (e.g., which pattern to keep, or if intentional for different contexts)
4. **Given** a migration is performed, **When** the daemon is running, **Then** the tool automatically reloads the daemon configuration or provides clear instructions to restart the daemon, ensuring new patterns take effect immediately

---

### User Story 4 - Interactive Pattern Learning and Refinement (Priority: P4)

As a system administrator, I want an interactive mode where I can launch applications one at a time, see their captured properties in real-time, classify them as scoped/global, assign workspaces, and immediately test the assignment, so that I can learn and refine patterns with instant feedback.

**Why this priority**: Interactive mode provides a learning experience and fine-tuning capability. While automated bulk discovery (P1-P3) handles most cases, this allows for edge cases and user preference adjustments. This is valuable but not critical for fixing the immediate broken configuration.

**Independent Test**: Launch interactive mode, select an application from a list, watch it launch and capture properties, manually review and adjust the pattern if needed, assign a workspace, test the assignment by closing and relaunching, and save the verified pattern. Success means one application is correctly configured with user oversight.

**Acceptance Scenarios**:

1. **Given** I start interactive pattern learning mode, **When** I select an application from the list, **Then** the tool launches it, displays captured properties (WM_CLASS class/instance, title, window type), shows a suggested pattern, and waits for my confirmation or adjustment
2. **Given** I see captured properties for an application, **When** I classify it as scoped or global, **Then** the tool updates the classification, explains the difference (project-specific vs always-visible), and shows which other applications have similar classifications
3. **Given** I have confirmed a pattern, **When** I assign a workspace number, **Then** the tool validates the assignment (warns if workspace is already taken), updates the configuration, and immediately applies the rule by reloading the daemon
4. **Given** I want to test my new pattern, **When** I trigger a test launch, **Then** the tool closes the current window, relaunches the application, and reports whether it appeared on the correct workspace with real-time feedback

---

### User Story 5 - Deno CLI Integration for Unified System Management (Priority: P2)

As a system administrator, I need all window rules discovery, validation, and configuration functionality integrated into the central Deno CLI (i3pm), so that I have a single, unified terminal interface to manage the entire i3 project system including window rules, daemon status, logs, and system diagnostics.

**Why this priority**: The Deno CLI is already the central user-facing interface for i3 project management (e.g., `i3pm daemon status`, `i3pm windows`, `i3pm project switch`). Integrating window rules functionality into this CLI provides a cohesive user experience and follows Constitution Principle XIII (Deno CLI Development Standards) for new command-line tools. This is high priority (P2) because it establishes the proper architecture before implementation.

**Independent Test**: Run `i3pm rules discover --app pavucontrol` from the Deno CLI, which internally delegates to the Python discovery service, captures the result, and displays it in a formatted TUI. Success means the Deno CLI acts as the presentation layer while Python handles i3 IPC integration.

**Acceptance Scenarios**:

1. **Given** I want to discover a window pattern, **When** I run `i3pm rules discover --app vscode`, **Then** the Deno CLI invokes the Python discovery service, waits for the result, and displays captured window properties and generated pattern in a Rich-formatted table
2. **Given** I want to validate my configuration, **When** I run `i3pm rules validate`, **Then** the Deno CLI calls the Python validation service, retrieves validation results, and displays a comprehensive report with color-coded pass/fail indicators and suggested fixes
3. **Given** I want to view system state, **When** I run `i3pm status`, **Then** the CLI shows unified status including daemon health, active project, window rules loaded, recent events, and any configuration issues in a single TUI dashboard
4. **Given** I want to review logs, **When** I run `i3pm logs --source=rules --tail=50`, **Then** the CLI retrieves and displays discovery/validation/migration logs with syntax highlighting and filtering options
5. **Given** I want to configure window rules interactively, **When** I run `i3pm rules interactive`, **Then** the Deno CLI launches an interactive TUI that guides me through application discovery, pattern configuration, and testing with real-time updates

**Integration Architecture**:
- **Deno CLI**: User-facing command-line interface using `@std/cli/parse-args` for argument parsing, terminal UI for presentation
- **Python Services**: Backend services for i3 IPC integration (discovery.py, validation.py, migration.py) - handles complex async i3 communication
- **IPC Communication**: Deno CLI communicates with Python services via JSON-RPC over Unix sockets or stdout/stdin pipes
- **Unified Commands**: All functionality accessible through `i3pm` commands: `i3pm rules discover`, `i3pm rules validate`, `i3pm rules migrate`, `i3pm daemon events`, `i3pm windows`, etc.

---

### Edge Cases

- **Application takes long time to launch**: System waits with configurable timeout (default 10s), shows progress indicator, allows manual override to extend wait time
- **Application spawns multiple windows**: Tool detects multi-window scenario, captures properties for each window, and asks user which window to use for pattern generation
- **Application WM_CLASS changes between launches**: Tool detects pattern mismatch, warns user, stores multiple observed patterns, and suggests using title-based pattern instead if WM_CLASS is unstable
- **Terminal applications with same terminal WM_CLASS**: Tool detects terminal emulator (ghostty, alacritty), uses title-based patterns instead of class-based, captures the command name from title
- **PWA applications with auto-generated IDs**: Tool recognizes FFPWA-* pattern format, extracts full ID string, warns that pattern is instance-specific
- **Application doesn't appear in i3 tree**: Tool detects missing window after timeout, reports potential issues (wrong WM_CLASS filter, application crashed, runs in background without window), suggests manual investigation
- **Workspace already assigned to different application**: Tool detects conflict, reports both applications, suggests available workspace numbers, allows user to override or skip
- **Pattern matches multiple different applications**: Tool detects ambiguous pattern during validation, lists all matching windows, reports false positives, suggests making pattern more specific (add instance or title criteria)
- **Rofi launcher simulation fails or times out**: System detects rofi not responding (menu doesn't appear), falls back to direct command execution, logs the failure, and continues with discovery
- **Application name in rofi differs from command name**: Tool allows specifying both rofi search term and underlying command separately, handles cases where display name differs from executable name (e.g., "Volume Control" in rofi launches "pavucontrol" command)
- **Parameterized commands need different parameters for discovery vs project use**: Tool supports defining base discovery command (e.g., `code`) separate from parameterized project command (e.g., `code $PROJECT_DIR`), discovers pattern from base command, validates that same pattern matches parameterized launches
- **Desktop file doesn't exist yet for new application**: Tool generates suggested desktop file content for NixOS declarative configuration, shows where to add it in /etc/nixos structure, includes custom Exec command with parameters

## Requirements *(mandatory)*

### Functional Requirements

#### Discovery

- **FR-001**: System MUST be able to launch an application using either direct command execution or by simulating the rofi launcher workflow (Meta+D keybinding via xdotool, then typing application name), and wait for its window to appear in the i3 window tree
- **FR-002**: System MUST capture window properties from i3 tree: WM_CLASS (class and instance), WM_NAME (title), window ID, workspace, window type
- **FR-003**: System MUST detect whether an application is terminal-based by checking if the WM_CLASS matches known terminal emulators (ghostty, alacritty, xterm, etc.)
- **FR-004**: System MUST generate class-based patterns for GUI applications (e.g., `Pavucontrol`) using exact WM_CLASS match
- **FR-005**: System MUST generate title-based patterns for terminal applications (e.g., `title:lazygit`) by extracting the command name from window title
- **FR-006**: System MUST handle PWA applications by capturing full FFPWA-* ID patterns
- **FR-007**: System MUST support bulk discovery by processing a list of applications sequentially with configurable delays between launches
- **FR-008**: System MUST allow configurable timeout for window appearance (default 10 seconds)
- **FR-009**: System MUST clean up launched applications after discovery (close windows) unless user specifies to keep them open

#### Pattern Matching Logic

- **FR-010**: System MUST support multiple pattern types: exact class match, title substring match, title regex match, PWA ID match
- **FR-011**: System MUST evaluate patterns using a precedence order: exact class match (highest), PWA ID match, title regex match, title substring match (lowest)
- **FR-012**: System MUST research and decide between two window rule application approaches: (1) native i3 config-based rules (for_window directives) versus (2) current event-driven Python daemon implementation, evaluating trade-offs in dynamism, project context awareness, and maintainability
- **FR-013**: System MUST consider using multi-criteria scoring for pattern matching (evaluating whether i3king's scoring system from 2021 is still relevant or if i3's built-in matching has improved)
- **FR-014**: System MUST support both case-sensitive and case-insensitive matching with configuration option
- **FR-015**: System MUST handle special regex characters in patterns (escape them for exact matching, or allow regex mode)

#### Validation

- **FR-016**: System MUST validate patterns against currently open windows without launching new windows
- **FR-017**: System MUST validate patterns by launching applications in test mode and checking workspace placement
- **FR-018**: System MUST report validation results showing: pattern matched correctly, pattern didn't match (false negative), pattern matched wrong window (false positive), window on wrong workspace
- **FR-019**: System MUST compare expected workspace (from window-rules.json) against actual workspace (from i3 tree)
- **FR-020**: System MUST detect patterns that match multiple windows and report ambiguity issues
- **FR-021**: System MUST identify windows that have no matching pattern (unclassified windows)
- **FR-022**: System MUST generate comprehensive validation reports with statistics: total patterns, passed, failed, accuracy percentage

#### Configuration Management

- **FR-023**: System MUST read existing window-rules.json and app-classes.json configurations
- **FR-024**: System MUST update window-rules.json by replacing patterns while preserving workspace assignments, scope, priority, and descriptions
- **FR-025**: System MUST update app-classes.json by adding new applications to scoped_classes or global_classes lists
- **FR-026**: System MUST create timestamped backups of configuration files before any modifications
- **FR-027**: System MUST maintain JSON structure and formatting when updating configuration files
- **FR-028**: System MUST validate JSON syntax after updates and rollback to backup if corruption detected
- **FR-029**: System MUST detect and report duplicate patterns or workspace conflicts
- **FR-030A**: System MUST maintain an application command registry that defines the launch command for each application, including any parameters (e.g., project directory paths, command-line flags)
- **FR-030B**: System MUST support parameterized commands that can include project-specific values (e.g., `code $PROJECT_DIR` or `ghostty -e lazygit --work-tree=$PROJECT_DIR`)
- **FR-030C**: System MUST provide a way to map application command definitions to desktop file customizations for NixOS declarative configuration

#### Daemon Integration

- **FR-031**: System MUST provide commands to reload daemon configuration after updates (e.g., systemctl restart, or IPC reload signal)
- **FR-032**: System MUST verify daemon is running before attempting configuration reload
- **FR-033**: System MUST provide option to test patterns without reloading daemon (dry-run mode)

#### Interactive Mode

- **FR-034**: System MUST provide interactive TUI mode with application selection, property display, pattern editing, workspace assignment, and testing capabilities
- **FR-035**: System MUST display captured window properties in human-readable format with explanations
- **FR-036**: System MUST allow users to manually adjust generated patterns before saving
- **FR-037**: System MUST provide immediate testing by relaunching applications to verify workspace placement
- **FR-038**: System MUST explain classification differences (scoped vs global) with examples
- **FR-039**: System MUST show which workspaces are already assigned to prevent conflicts

#### Deno CLI Integration

- **FR-040**: System MUST provide Deno-based CLI (`i3pm`) as the primary user-facing interface for all window rules operations
- **FR-041**: Deno CLI MUST use `@std/cli/parse-args` for command-line argument parsing following standard patterns (flags, options, subcommands)
- **FR-042**: Deno CLI MUST communicate with Python backend services via JSON-RPC over Unix sockets or stdin/stdout pipes
- **FR-043**: CLI MUST provide unified command structure: `i3pm rules discover`, `i3pm rules validate`, `i3pm rules migrate`, `i3pm rules interactive`
- **FR-044**: CLI MUST provide system status dashboard command (`i3pm status`) showing daemon health, active project, loaded rules count, recent events
- **FR-045**: CLI MUST provide log viewing command (`i3pm logs`) with source filtering (daemon/rules/windows), tail mode, and syntax highlighting
- **FR-046**: CLI MUST display discovery results in formatted tables with window properties, generated patterns, and confidence scores
- **FR-047**: CLI MUST display validation results with color-coded pass/fail indicators, expected vs actual workspace comparisons, and suggested fixes
- **FR-048**: CLI MUST handle Python service errors gracefully with user-friendly messages (e.g., "daemon not running", "i3 IPC connection failed")
- **FR-049**: CLI MUST provide progress indicators for long-running operations (bulk discovery, comprehensive validation)
- **FR-050**: CLI MUST support JSON output mode (`--json` flag) for all commands to enable scripting and automation

### Key Entities

- **Window**: Represents an application window with properties (ID, WM_CLASS class/instance, title, workspace, type, output)
- **Pattern**: A matching rule with type (class/title/PWA), pattern string, scope (scoped/global), priority, and description
- **WindowRule**: Associates a pattern with a workspace assignment for automatic placement
- **ApplicationDefinition**: Describes an application with launch command (including optional parameters like project directory), rofi display name (if different from command), expected pattern type, classification (scoped/global), preferred workspace, and desktop file path (for NixOS declarative customization)
- **DiscoveryResult**: Contains captured window properties, generated pattern, confidence score, launch command used, and any warnings or issues detected
- **ValidationResult**: Reports pattern match status (success/false-positive/false-negative), expected vs actual workspace, and any discrepancies
- **ConfigurationBackup**: Timestamped snapshot of window-rules.json and app-classes.json before modifications

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can discover correct patterns for a single application in under 15 seconds (launch + capture + generate pattern)
- **SC-002**: Users can discover patterns for all 70 applications in under 20 minutes (bulk discovery mode with average 15s per app including cleanup)
- **SC-003**: Pattern accuracy reaches 95%+ when validated against real windows (fewer than 5% false positives/negatives across all 65+ patterns)
- **SC-004**: Validation reports identify 100% of windows on incorrect workspaces compared to configuration
- **SC-005**: Configuration migration completes for 65+ patterns in under 2 minutes with automatic backup creation
- **SC-006**: Interactive pattern learning allows users to configure and test one application in under 60 seconds
- **SC-007**: System reduces manual xprop/i3-msg investigation time by 90% compared to current manual workflow
- **SC-008**: Zero configuration file corruption incidents (all updates maintain valid JSON with automatic rollback on error)
- **SC-009**: Pattern changes take effect within 5 seconds after daemon reload
- **SC-010**: 100% of terminal-based applications are correctly identified and assigned title-based patterns (no false GUI pattern assignments)
- **SC-011**: Deno CLI starts and displays help output in under 100ms (fast startup for interactive use)
- **SC-012**: All i3pm system management commands accessible through unified CLI interface (no need to remember multiple tool names)
- **SC-013**: CLI error messages provide actionable guidance with 90% of users able to resolve issues without documentation
- **SC-014**: System status dashboard (`i3pm status`) loads and displays in under 500ms with current state of all components

## Assumptions

- i3 window manager's IPC interface provides sufficient window property information (WM_CLASS, title, type) for reliable pattern matching
- Modern i3 versions (4.20+) may have improved built-in window matching, potentially reducing need for complex scoring logic from older tools like i3king
- Applications have stable WM_CLASS properties that don't change between launches (or changes are detectable and reportable)
- Terminal applications consistently include the command name in their window title
- PWA applications maintain their FFPWA-* ID pattern consistently
- The i3-project-event-daemon's window::new event handler is the appropriate integration point for applying discovered patterns
- Configuration files (window-rules.json, app-classes.json) follow the established schema from Phase 11 work
- systemd user service is the daemon management mechanism (systemctl --user restart)
- Users have necessary permissions to launch all applications and modify configuration files
- rofi application launcher is configured with Meta+D keybinding and xdotool is available for simulating keyboard input to automate application launching in a realistic workflow
- Application names used in rofi menu are either identical to command names or can be mapped via configuration
- Desktop files in /etc/nixos can be declaratively customized to use custom launch commands with parameters (e.g., project directory)
- Each application will have a defined command (potentially parameterized) that serves as the canonical launch method for both discovery and runtime use
- Command parameters can include project-specific values that are substituted at runtime (e.g., $PROJECT_DIR variable)
- Deno CLI can efficiently communicate with Python backend services via JSON-RPC or process spawning with minimal latency (<50ms per call)
- i3pm CLI will be the central unified interface for all i3 project management operations (replacing standalone Python CLIs)

## Key Architectural Research Questions

This feature requires researching and deciding on two fundamental architectural approaches before implementation:

### 1. Window Rule Application Mechanism (FR-012)

**Question**: Should window rules be applied via native i3 config (`for_window` directives) or via the current event-driven Python daemon?

**Current Implementation**:
- Event-driven Python daemon subscribes to `window::new` events
- Dynamically evaluates patterns and applies workspace assignments
- Supports project context awareness (scoped vs global applications)
- Allows runtime pattern updates without i3 restart

**Native i3 Alternative**:
- Uses `for_window [class="Pattern"] move container to workspace number N` in i3 config
- Evaluated by i3 core on window creation
- Less dynamic, requires i3 reload for pattern changes
- No built-in project context awareness

**Trade-offs to Evaluate**:
- **Dynamism**: Can patterns be updated at runtime without restarting i3?
- **Project Context**: Can rules differentiate between project-scoped and global applications?
- **Performance**: Which approach has lower latency for window placement?
- **Maintainability**: Which is easier to debug and maintain?
- **Parameterized Commands**: Can native i3 rules handle project-specific parameters ($PROJECT_DIR)?
- **Complexity**: Is the Python daemon overhead justified by added capabilities?

**Decision Criteria**:
- If project context awareness is essential → Event-driven daemon required
- If parameterized commands need dynamic workspace routing → Event-driven daemon required
- If simple static workspace mapping is sufficient → Native i3 rules may be simpler
- If configuration reload flexibility is critical → Evaluate both approaches

This decision affects FR-001 (discovery approach), FR-023-029 (configuration management), and FR-031-033 (daemon integration).

### 2. Pattern Matching Complexity (FR-013)

**Question**: Is i3king's multi-criteria scoring system (window_role=1pt, class=2pt, instance=3pt, title=10pt) still necessary with modern i3 versions (4.20+)?

**Trade-offs to Evaluate**:
- Has i3's built-in pattern matching improved sufficiently?
- Do we need weighted scoring for disambiguation?
- Is simple precedence order (FR-011) adequate?

## Out of Scope

- Automatic classification of applications as scoped vs global (requires user decision based on workflow needs)
- Pattern learning from historical daemon logs (focus is on active discovery by launching applications)
- Integration with external application databases or package managers for automatic application discovery
- Support for non-i3 window managers
- Automatic workspace number assignment (users specify preferred workspaces, tool warns on conflicts)
- Window rule conditions beyond pattern matching (e.g., rules based on window size, position, parent process)
- Multi-monitor workspace distribution logic (separate concern from pattern matching)

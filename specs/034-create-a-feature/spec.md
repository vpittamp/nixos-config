# Feature Specification: Unified Application Launcher with Project Context

**Feature Branch**: `034-create-a-feature`
**Created**: 2025-10-24
**Status**: Draft
**Input**: Create a feature that unifies my application launching. The solution should use the registry as a way to register commands, and parameterize certain values. It should integrate with projects and app classes. We want to launch using our custom fzfmenu tool or rofi (we need to research and then decide). The objective is to launch applications in a way that is integrated within our project based workflow, uses native i3, seamlessly integrates with my deno CLI, etc. We should also consider how our registry will correspond to our desktop files? Perhaps we can define in our registry and then auto-generate the desktop files using home-manager? Or we can manage outside of home-manager if we need to. Also, we need to determine if, based on the way we launch, we need to change our window rules. Finally, we should think about project scoped applications, and how we show/hide them based on the active project.

## Problem Statement

The current application launching system is fragmented and inconsistent. Applications are launched through multiple mechanisms (rofi, fzf, hard-coded bash scripts, i3 keybindings), each requiring separate configuration. There's no unified way to launch applications with project context awareness, leading to:

- **Manual repetition**: Each project-aware application needs a custom launch script (launch-code.sh, launch-ghostty.sh, etc.)
- **Configuration sprawl**: Application commands are scattered across i3 config, bash scripts, and desktop files
- **No parameterization**: Cannot easily substitute project directory, session names, or other context variables
- **Inconsistent UX**: Different launch methods (rofi vs fzf vs keybindings) behave differently
- **Desktop file duplication**: Must maintain both registry concepts and separate .desktop files for NixOS/home-manager

Users need a single, declarative application registry that defines launch commands with variable templates, automatically generates desktop files, integrates with the project system, and provides a consistent launch experience across all methods.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Launch Project-Aware Application from Launcher (Priority: P1)

As a developer, I need to launch applications (like VS Code or terminal) that automatically open in my active project's directory, so that I don't have to manually navigate to the project location every time I open an application.

**Why this priority**: This is the core value proposition - eliminating manual navigation and context switching. Provides immediate productivity improvement and is the foundation for all other launcher features.

**Independent Test**: Activate the "nixos" project, open the application launcher (rofi/fzf), select "VS Code", and verify that VS Code opens directly to `/etc/nixos` without additional navigation steps.

**Acceptance Scenarios**:

1. **Given** I have the "nixos" project active with directory `/etc/nixos`, **When** I launch the application launcher and select "VS Code", **Then** VS Code opens with `/etc/nixos` as the workspace directory
2. **Given** I have the "stacks" project active with directory `~/projects/stacks`, **When** I launch "Ghostty Terminal", **Then** Ghostty opens with a sesh session named "stacks" in the `~/projects/stacks` directory
3. **Given** I have no active project (global mode), **When** I launch "VS Code", **Then** VS Code opens without any directory specified, using its default behavior
4. **Given** I have the "nixos" project active, **When** I launch a global application like Firefox, **Then** Firefox opens normally without any project context (no directory parameters)

---

### User Story 2 - Declarative Application Registry with Variable Substitution (Priority: P1)

As a system administrator, I need to define all applications in a single registry file with parameterized launch commands, so that I can manage application launch behavior declaratively without writing custom scripts for each application.

**Why this priority**: This is the technical foundation that enables P1. Without the registry and variable system, project-aware launching cannot work consistently. This allows scaling from 4 hard-coded scripts to unlimited applications.

**Independent Test**: Add a new application (e.g., "yazi file manager") to the registry with `"parameters": "$PROJECT_DIR"`, rebuild the system, and verify the application appears in the launcher and opens in the active project directory without writing any custom code.

**Acceptance Scenarios**:

1. **Given** I define an application in the registry with `{"name": "vscode", "command": "code", "parameters": "$PROJECT_DIR"}`, **When** the system is rebuilt, **Then** launching VS Code substitutes the active project's directory for `$PROJECT_DIR` in the command
2. **Given** I define `{"name": "lazygit", "command": "ghostty -e lazygit", "parameters": "--work-tree=$PROJECT_DIR"}`, **When** I launch lazygit from the "nixos" project, **Then** the command executed is `ghostty -e lazygit --work-tree=/etc/nixos`
3. **Given** I define multiple variable types: `$PROJECT_DIR`, `$PROJECT_NAME`, `$SESSION_NAME`, **When** I launch an application, **Then** each variable is replaced with the corresponding value from the active project context
4. **Given** I update the registry to change VS Code's parameters, **When** I rebuild the system, **Then** the next launch uses the updated parameters without requiring manual script editing

---

### User Story 3 - Automatic Desktop File Generation from Registry (Priority: P2)

As a system administrator, I need the system to automatically generate .desktop files from the application registry, so that applications appear in rofi/fzf launchers with correct display names, icons, and launch commands without maintaining duplicate configuration.

**Why this priority**: Eliminates configuration duplication and ensures consistency. Desktop files must match registry definitions. This builds on P1/P2 by making registered applications discoverable through standard Linux desktop integration.

**Independent Test**: Define 3 applications in the registry (one scoped, one global, one terminal-based), rebuild with home-manager, and verify all 3 appear in rofi with correct names and icons, and launch with expected parameters.

**Acceptance Scenarios**:

1. **Given** I define an application in the registry with `"display_name": "VS Code"` and `"icon": "vscode"`, **When** home-manager generates desktop files, **Then** a .desktop file is created at `~/.local/share/applications/vscode.desktop` with `Name=VS Code` and `Icon=vscode`
2. **Given** I define a scoped application with project parameters, **When** the desktop file is generated, **Then** the Exec line contains the registry command with parameter placeholders that the launcher script will resolve at runtime
3. **Given** I remove an application from the registry, **When** I rebuild, **Then** the corresponding desktop file is removed from `~/.local/share/applications/`
4. **Given** I define a PWA application with a specific FFPWA ID, **When** the desktop file is generated, **Then** the Exec command uses the correct firefox-pwa launch syntax and the application appears in the launcher

---

### User Story 4 - Unified Launcher Interface (rofi or fzf) (Priority: P2)

As a user, I need a consistent launcher interface (either rofi or fzf) that shows all registered applications, displays scoped vs global status, and launches applications with appropriate project context, so that I have a predictable and efficient application launching experience.

**Why this priority**: Provides the user-facing interface for P1/P2. Must unify the currently split launcher mechanisms (rofi for GUI apps, fzf for project switching). This completes the end-to-end launch workflow.

**Independent Test**: Open the launcher, see a list of all registered applications with visual indicators for scoped/global status, select a scoped application, and verify it launches with project context while global applications launch without context.

**Acceptance Scenarios**:

1. **Given** I have 20 applications in the registry (10 scoped, 10 global), **When** I open the launcher, **Then** I see all 20 applications listed with clear visual indicators distinguishing scoped from global apps
2. **Given** I have the "nixos" project active, **When** I open the launcher and select a scoped application, **Then** the launcher shows the target project directory in the preview/description before launching
3. **Given** I type "code" in the launcher search, **When** the results filter, **Then** VS Code appears at the top of the results with fuzzy matching on both command name and display name
4. **Given** I select an application from the launcher, **When** it launches, **Then** the launcher closes automatically and the application window appears within 2 seconds

---

### User Story 5 - Integration with i3pm Deno CLI (Priority: P2)

As a power user, I need to manage the application registry through the i3pm CLI with commands like `i3pm apps list`, `i3pm apps launch <name>`, and `i3pm apps edit`, so that I can work entirely from the terminal and integrate application launching into scripts and workflows.

**Why this priority**: Provides programmatic access and terminal-focused workflow. Essential for users who prefer CLI over GUI launchers. Enables automation and scripting of application launches.

**Independent Test**: Run `i3pm apps list` to see all registered applications, run `i3pm apps launch vscode` to launch VS Code with project context, and verify the command works identically to the GUI launcher.

**Acceptance Scenarios**:

1. **Given** I have 15 applications registered, **When** I run `i3pm apps list`, **Then** I see a formatted table showing app name, display name, scope (scoped/global), and preferred workspace for all applications
2. **Given** I have the "stacks" project active, **When** I run `i3pm apps launch vscode`, **Then** VS Code launches with the stacks project directory, equivalent to using the GUI launcher
3. **Given** I want to add a new application, **When** I run `i3pm apps edit`, **Then** the registry JSON file opens in my $EDITOR, and after saving, changes are validated and applied on next rebuild
4. **Given** I run `i3pm apps info vscode`, **When** the command executes, **Then** I see detailed information including the resolved launch command with actual variable values for the current project context

---

### User Story 6 - Window Rules Alignment with Registry (Priority: P3)

As a system administrator, I need the window rules system to automatically align with the application registry, so that windows launched from the registry are correctly classified, assigned to workspaces, and shown/hidden based on project context without manual window-rules.json editing.

**Why this priority**: Ensures launched applications behave correctly with project scoping. Builds on P1-P5 by connecting the launcher to the window management system. Lower priority because window rules can be configured manually initially.

**Independent Test**: Add a new scoped application to the registry with preferred_workspace=5, launch it from a project, and verify it automatically appears on workspace 5 and is hidden when switching to a different project, without editing window-rules.json.

**Acceptance Scenarios**:

1. **Given** I define an application in the registry with `"scope": "scoped"` and `"expected_class": "Code"`, **When** the system generates configuration, **Then** window-rules.json is updated to classify windows with WM_CLASS="Code" as scoped
2. **Given** I define `"preferred_workspace": 2` for VS Code, **When** VS Code is launched and its window appears, **Then** the window is automatically moved to workspace 2 via window rules
3. **Given** I change an application's scope from "global" to "scoped" in the registry, **When** I rebuild, **Then** the window rules are updated and future launches of that application respect the new scoped behavior
4. **Given** I have a scoped application running in the "nixos" project, **When** I switch to the "stacks" project, **Then** the window is hidden (moved to scratchpad) automatically based on its registry-defined scope

---

### Edge Cases

- **Variable not available**: When `$PROJECT_DIR` is used but no project is active, system launches application without the parameter or uses a sensible default (e.g., home directory)
- **Application already running**: When launching an application that's already open, system either focuses the existing window or opens a new instance based on registry configuration (`"multi_instance": true/false`)
- **Desktop file conflicts**: When registry generates a .desktop file that conflicts with a system-provided one, the registry version takes precedence via path ordering (~/.local/share/applications before /usr/share/applications)
- **Launcher tool unavailable**: If rofi or fzf is not installed, system falls back to a basic dmenu-based launcher or shows error message with installation instructions
- **Parameter contains special characters**: When project directory contains spaces or special characters, system properly escapes/quotes parameters in the launch command
- **Registry syntax errors**: When registry JSON is malformed, system shows clear error during rebuild with line numbers and specific validation failure, preventing broken launchers
- **Application not in PATH**: When registry references a command not in PATH, system shows error during launch with suggestion to check package installation or update registry
- **Scoped app launched without project**: When a scoped application is launched in global mode (no active project), system either (a) prompts user to select a project first, or (b) launches in default mode without project context based on registry config
- **Registry update during active session**: When registry is updated and system is rebuilt while applications are running, existing windows continue with old rules but new launches use new rules; daemon detects config change and reloads
- **PWA ID changes**: When a PWA is reinstalled and gets a new FFPWA ID, registry must be updated with new ID; old desktop file becomes orphaned and should be cleaned up
- **Legacy code removal**: When the registry system is implemented, ALL existing launch scripts, keybindings, and launcher mechanisms are removed in the same commit. No gradual migration period, no backwards compatibility mode. The system immediately uses only the registry-based launcher.

## Requirements *(mandatory)*

### Functional Requirements

#### Application Registry

- **FR-001**: System MUST provide a single JSON-based application registry file (`~/.config/i3/application-registry.json`) that defines all launchable applications with properties: name, display_name, command, parameters, scope (scoped/global), expected_class, preferred_workspace, icon, and nix_package
- **FR-002**: System MUST support variable substitution in the `parameters` field with these variables: `$PROJECT_DIR` (active project directory), `$PROJECT_NAME` (active project name), `$SESSION_NAME` (tmux/sesh session name), `$WORKSPACE` (target workspace number)
- **FR-003**: System MUST validate the registry JSON schema on rebuild, showing clear error messages for invalid entries including line numbers, field names, and expected formats
- **FR-004**: System MUST allow applications to specify `"multi_instance": true` to allow multiple windows or `"multi_instance": false` to focus existing windows on relaunch

#### Desktop File Generation

- **FR-005**: System MUST automatically generate .desktop files from the registry using home-manager, placing them in `~/.local/share/applications/` with names matching the registry `name` field
- **FR-006**: Generated desktop files MUST include: Name (from display_name), Exec (from command + parameters with launcher wrapper), Icon (from icon field), Categories (auto-generated from scope), and StartupWMClass (from expected_class)
- **FR-007**: System MUST use a launcher wrapper script in the Exec line that resolves variable substitutions at runtime based on active project context
- **FR-008**: System MUST remove orphaned desktop files when applications are removed from the registry during home-manager rebuild

#### Launcher Interface

- **FR-009**: System MUST provide a unified launcher interface using rofi (GUI-focused, better visual design with icons and colors, native XDG integration) that displays all registered applications
- **FR-010**: Launcher MUST show visual distinction between scoped and global applications (e.g., icon indicators, color coding, or prefixes like "" for scoped)
- **FR-011**: Launcher MUST support fuzzy search matching on both application name and display_name
- **FR-012**: Launcher MUST show project context in preview/description for scoped applications when a project is active (e.g., "Will open in: /etc/nixos")
- **FR-013**: Launcher MUST close automatically after successful application launch, with error display if launch fails

#### Command Execution

- **FR-014**: System MUST execute launch commands by first reading active project context from the daemon (`i3pm project current`), then substituting all variables in the parameters field, then executing the full command
- **FR-015**: System MUST handle missing project context gracefully: for scoped apps in global mode, either skip the parameter or use a fallback value (configurable in registry)
- **FR-016**: System MUST properly escape and quote parameter values containing spaces, special characters, or shell metacharacters
- **FR-017**: System MUST log all application launches (command executed, project context, timestamp) for debugging and monitoring

#### i3pm CLI Integration

- **FR-018**: System MUST provide `i3pm apps list` command showing all registered applications in a formatted table with columns: name, display_name, scope, preferred_workspace
- **FR-019**: System MUST provide `i3pm apps launch <name>` command that launches the specified application with project context, equivalent to GUI launcher behavior
- **FR-020**: System MUST provide `i3pm apps info <name>` command that displays detailed application information including the resolved launch command with actual variable values for current context
- **FR-021**: System MUST provide `i3pm apps edit` command that opens the registry JSON in $EDITOR, validates on save, and provides rebuild instructions
- **FR-022**: System MUST provide `i3pm apps validate` command that checks registry syntax, verifies expected_class patterns match running windows, and reports discrepancies

#### Window Rules Integration

- **FR-023**: System MUST support automatic window-rules.json generation from registry entries, creating rules that map expected_class to scope and preferred_workspace, ensuring zero manual effort and guaranteed consistency between registry and window rules
- **FR-024**: System MUST allow manual window-rules.json entries to override registry-generated rules via priority system (manual rules have higher priority)
- **FR-025**: System MUST notify the daemon to reload window rules when registry changes are applied, ensuring new rules take effect immediately
- **FR-026**: System MUST track which window rules were generated from the registry vs manually created, showing this in `i3pm rules list` output

#### Project Context Awareness

- **FR-027**: Scoped applications launched from the registry MUST be automatically marked with the active project tag (e.g., `project:nixos`) for show/hide behavior
- **FR-028**: When switching projects, scoped applications launched from the registry MUST be hidden (moved to scratchpad) or shown based on project membership
- **FR-029**: Global applications launched from the registry MUST remain visible across all projects regardless of active project state
- **FR-030**: System MUST support session management integration where terminal applications receive both PROJECT_DIR and SESSION_NAME variables for sesh/tmux integration

#### Legacy Code Removal

- **FR-031**: Implementation MUST remove all legacy launch scripts (launch-code.sh, launch-ghostty.sh, and any other custom application launchers in ~/.local/bin/ or ~/scripts/) in the same commit that introduces the registry system
- **FR-032**: Implementation MUST update all i3 keybindings to reference the new unified launcher, removing references to old script paths
- **FR-033**: Implementation MUST NOT include backwards compatibility modes, feature flags, or gradual migration paths - the registry system immediately becomes the sole application launching mechanism
- **FR-034**: Implementation MUST document all removed legacy code in the commit message for reference

### Key Entities

- **Application Registry Entry**: Represents a launchable application with properties: unique name (identifier), human-readable display name, base command (executable), optional parameters (with variable templates), scope classification (scoped/global), expected window class pattern, preferred workspace number (1-9), icon name/path, NixOS package reference, multi-instance flag
- **Variable Context**: Represents the runtime environment for variable substitution with properties: active project name, project directory path, session name, target workspace number, user home directory
- **Desktop File**: Generated artifact representing an XDG desktop entry with properties: file path, exec command (including launcher wrapper), display name, icon, categories, startup WM class
- **Launch Command**: Represents a fully resolved command ready for execution with properties: original template, substituted parameters, resolved full command string, project context snapshot, timestamp

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can add a new application to the registry and have it appear in the launcher within one rebuild cycle (under 2 minutes total time from edit to availability)
- **SC-002**: Launching a project-aware application from the launcher takes under 3 seconds from selection to window appearance with correct project directory
- **SC-003**: All registered applications appear in the launcher with correct display names, icons, and scope indicators without requiring manual desktop file creation
- **SC-004**: All variable substitutions resolve correctly in launches when project context is available
- **SC-005**: Users can manage all application launching through a single registry file, eliminating the need for custom launch scripts (reducing from 4+ custom scripts to 0)
- **SC-006**: Window rules automatically align with registry scope definitions for registered applications without manual window-rules.json editing
- **SC-007**: CLI commands execute in under 500ms and provide equivalent functionality to GUI launcher
- **SC-008**: Configuration drift between registry definitions and actual launcher behavior is eliminated (what's in registry matches what user sees and executes)
- **SC-009**: All legacy launch scripts and old launcher mechanisms are completely removed from the codebase with zero backwards compatibility code remaining (verified by absence of launch-*.sh files and old keybinding patterns)

## Assumptions

- **Integration with existing systems**: This feature integrates with the existing i3pm daemon (Feature 015), window rules system (Feature 024/031), and project management (Features 010-012). It assumes these systems are functional and expose necessary APIs (active project query, window marking, rule reloading).
- **Home-manager for desktop files**: Desktop file generation uses home-manager's declarative approach (requires rebuild for changes to take effect), ensuring full reproducibility and declarative management consistent with NixOS philosophy.
- **Launcher choice**: System will use rofi for the unified launcher interface, leveraging its GUI-focused design, icon/color support, and native XDG desktop integration for a polished user experience with 70+ applications.
- **Variable scope**: Initial variable set is limited to project-related values (`$PROJECT_DIR`, `$PROJECT_NAME`, `$SESSION_NAME`, `$WORKSPACE`). Future expansion could include environment variables (`$HOME`, `$USER`), time-based variables, or custom user-defined variables.
- **No backwards compatibility (Constitution XII)**: This feature follows the Forward-Only Development principle. Existing hard-coded launch scripts (launch-code.sh, launch-ghostty.sh, etc.) will be COMPLETELY REMOVED in the same commit that introduces the registry system. Old i3 keybindings will be replaced entirely with new launcher keybindings. No compatibility layers, feature flags, or dual-mode support will be implemented. The migration is immediate and complete - the optimal solution replaces legacy code with zero preservation of old patterns.
- **Window rules generation**: Automatic window-rules.json generation is enabled by default, with manual rules taking priority via the priority system to handle edge cases and allow overrides when needed.
- **Single registry file**: All applications are defined in one JSON file. For larger deployments, the registry could be split into multiple files (e.g., per-category) and merged during build, but single-file is the initial design for simplicity.
- **Launch wrapper script**: A generic launcher wrapper script handles variable resolution and command execution. This script is referenced in desktop file Exec lines and invoked by CLI commands, providing a single point of launch logic.

## Dependencies

- **Feature 015**: Event-driven i3 project daemon (provides `i3pm project current` API for active project query)
- **Feature 024/031**: Window rules system (provides classification and workspace assignment based on WM_CLASS)
- **Feature 033**: Workspace-to-monitor mapping (ensures applications land on correct workspaces across multi-monitor setups)
- **Existing tools**: rofi or fzf (launcher UI), home-manager (desktop file generation), i3pm Deno CLI (command interface)

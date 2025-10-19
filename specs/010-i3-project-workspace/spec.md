# Feature Specification: i3 Project Workspace Management System

**Feature Branch**: `010-i3-project-workspace`
**Created**: 2025-10-17
**Status**: Complete - Ready for Planning
**Input**: User description: "i3 project workspace management system with isolated environments for multi-monitor development projects"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quick Project Environment Switch (Priority: P1)

As a developer working on multiple projects throughout the day, I need to instantly switch between complete project environments so I can maintain focus and reduce context switching time.

**Why this priority**: This is the core value proposition - the ability to save and restore complete working environments. Without this, the feature provides no benefit over basic workspace switching.

**Independent Test**: Can be fully tested by defining a project with 2-3 applications, activating it, verifying all applications launch in correct positions, then switching to a different project and switching back to verify state persistence.

**Acceptance Scenarios**:

1. **Given** I have defined a project named "website-redesign" with VSCode, Firefox, and a terminal, **When** I execute the project activation command, **Then** all three applications launch in their designated workspace positions
2. **Given** I am currently working in project "api-development", **When** I switch to project "website-redesign", **Then** the system changes focus to the website-redesign workspace without closing api-development applications
3. **Given** I have been working in a project for 30 minutes with multiple windows opened and positioned, **When** I switch away and return to the project, **Then** all windows remain in their original positions and states

---

### User Story 2 - Declarative Project Configuration via NixOS (Priority: P1)

As a user who values reproducibility, I need to define all my project environments in a single configuration file managed by NixOS/home-manager so I can version control my workspace setup and share it across machines.

**Why this priority**: Integration with the existing NixOS configuration is essential for this user's workflow. Without declarative configuration, this becomes just another tool that doesn't fit the existing infrastructure.

**Independent Test**: Can be tested by adding a project definition to the NixOS configuration file, rebuilding the system, and verifying the project is available and functional without any manual setup steps.

**Acceptance Scenarios**:

1. **Given** I define a new project in my home-manager configuration with application names, window positions, and workspace assignments, **When** I rebuild my NixOS configuration, **Then** the project becomes immediately available for activation
2. **Given** I have defined project configurations on my primary workstation, **When** I deploy the same configuration to a secondary machine, **Then** all projects work identically without manual intervention
3. **Given** I modify a project definition in my configuration file, **When** I rebuild the system, **Then** the next activation of that project uses the updated configuration
4. **Given** I define a project with a parameterized working directory path, **When** I activate the project with a specific directory argument, **Then** all applications launch with that directory as their working context

---

### User Story 3 - Multi-Monitor Workspace Management (Priority: P2)

As a developer with three monitors, I need project environments that span all my displays so I can maintain my preferred multi-monitor layout for each project while also being able to work on a single monitor when away from my desk.

**Why this priority**: Multi-monitor support is critical for the target user but the system should still be functional with basic single-workspace project support. This can be added after core functionality works.

**Independent Test**: Can be tested by defining a project with applications distributed across 3 workspaces (representing 3 monitors), verifying they launch on correct outputs, then testing the same project configuration on a single-monitor setup to ensure graceful degradation.

**Acceptance Scenarios**:

1. **Given** I have three monitors connected and a project defined with workspace assignments for each monitor, **When** I activate the project, **Then** applications appear on their designated monitors in correct positions
2. **Given** I have a project configured for 3 monitors, **When** I activate the project with only 1 monitor available, **Then** the system presents all workspaces as switchable workspaces on the single display
3. **Given** I am working with a project on 3 monitors, **When** I disconnect 2 monitors, **Then** I can switch between the previously separate workspaces using keyboard shortcuts
4. **Given** I am working on a single monitor, **When** I reconnect my other monitors, **Then** workspaces redistribute to their designated monitors automatically

---

### User Story 4 - Ad-Hoc Project Creation from Running State (Priority: P2)

As a developer who often discovers useful window arrangements organically, I need to capture my current workspace layout and save it as a project configuration so I can recreate successful workflows without manually defining window positions.

**Why this priority**: This significantly reduces the friction of adopting the system. Users can experiment naturally and capture what works rather than having to plan everything upfront.

**Independent Test**: Can be tested by manually arranging 3-4 applications in specific positions, executing a capture command with a project name, then clearing the workspace and re-activating the captured project to verify the layout matches.

**Acceptance Scenarios**:

1. **Given** I have spent 20 minutes arranging applications in an optimal layout, **When** I execute a save command with a project name, **Then** the system captures window positions, sizes, applications, and workspace assignments
2. **Given** I have captured a workspace layout, **When** I examine the generated configuration file, **Then** I see declarative configuration that can be edited and version controlled
3. **Given** I have captured a project and made manual edits to the generated configuration, **When** I activate the project, **Then** the system uses my edited configuration
4. **Given** I have multiple workspaces with different applications, **When** I execute a capture command specifying workspace scope, **Then** only the specified workspaces are included in the project definition

---

### User Story 5 - Shorthand Project Activation (Priority: P3)

As a power user who switches projects frequently, I need a compact command-line syntax to quickly compose and activate workspace configurations so I can create temporary project variations without editing configuration files.

**Why this priority**: This is a power-user feature that enhances efficiency but isn't required for basic functionality. The system is fully usable with explicit project names and predefined configurations.

**Independent Test**: Can be tested by executing a shorthand command like "prj web:1 term:2 notes:3" and verifying that the system interprets this as placing a web browser on workspace 1, terminal on workspace 2, and notes application on workspace 3.

**Acceptance Scenarios**:

1. **Given** I have defined application aliases (e.g., "vsc" for VSCode, "ff" for Firefox), **When** I execute a command with syntax "vsc:1 ff:2 term:3", **Then** VSCode launches on workspace 1, Firefox on workspace 2, and terminal on workspace 3
2. **Given** I want to temporarily add an application to an existing project, **When** I execute a project activation with additional shorthand parameters, **Then** the system launches the base project plus the additional applications
3. **Given** I frequently use a specific configuration that isn't worth saving permanently, **When** I execute a shorthand command, **Then** the environment is created without generating configuration files

---

### User Story 6 - Git Repository Integration (Priority: P3)

As a developer whose projects are organized as git repositories, I need to automatically associate project environments with repository directories so application contexts (terminal working directories, editor workspaces) are automatically set when I activate a project.

**Why this priority**: This is a significant quality-of-life improvement but projects can function without it by manually navigating to directories after launch. Can be added incrementally.

**Independent Test**: Can be tested by defining a project linked to a git repository path, activating the project, and verifying that terminals open in the repository root and editors open workspace files from that repository.

**Acceptance Scenarios**:

1. **Given** I define a project with a repository path parameter, **When** I activate the project, **Then** all terminal windows open with that directory as their working directory
2. **Given** I define a project with a code editor and repository path, **When** I activate the project, **Then** the editor opens with that repository as its workspace root
3. **Given** I have a project template for "go-api-development", **When** I activate it with a specific repository path argument, **Then** the system parameterizes all application contexts with that path
4. **Given** I have multiple projects referencing different subdirectories of a monorepo, **When** I switch between projects, **Then** application contexts update to the correct subdirectory

---

### Edge Cases

- **What happens when a defined application is not installed?** System should warn during project activation and continue launching other applications, allowing partial environment creation.

- **What happens when workspace assignments conflict with existing windows?** System should either move existing windows to different workspaces or prompt the user to choose between merging or isolating the environments.

- **How does the system handle applications that take significant time to start?** System should launch all applications concurrently and allow the user to begin working as applications become ready, rather than blocking on sequential launches.

- **What happens when monitor configuration changes during a session?** System should detect monitor changes and offer to redistribute workspaces or maintain them as virtual workspaces accessible via keyboard switching.

- **What happens when a project is activated while another project is active?** Default behavior should switch focus to the new project's primary workspace while keeping both projects running. User should be able to configure whether activating a project closes other projects.

- **How does the system handle applications that don't support multiple instances?** System should detect already-running single-instance applications and either focus existing windows or skip that application with a warning.

- **What happens when a saved layout references workspace positions that no longer make sense (e.g., saved on 3 monitors, restored on 2)?** System should gracefully degrade by consolidating workspaces onto available monitors or making excess workspaces accessible via workspace switching.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow users to define named project environments in NixOS/home-manager configuration files
- **FR-002**: System MUST support project definitions that specify applications to launch, window positions, sizes, and workspace assignments
- **FR-003**: System MUST provide a command to activate a project by name, launching all defined applications in their configured positions
- **FR-004**: System MUST allow users to switch between projects without terminating applications from other projects
- **FR-005**: System MUST preserve running application state when switching away from a project workspace
- **FR-006**: System MUST support multi-monitor configurations with workspace assignments for each monitor output
- **FR-007**: System MUST gracefully handle single-monitor scenarios when projects are defined for multiple monitors
- **FR-008**: System MUST allow workspace content from different monitors to be accessible via keyboard shortcuts on a single display
- **FR-009**: System MUST provide a command to capture current workspace layout and generate a declarative project configuration
- **FR-010**: System MUST support parameterized project definitions where working directory can be specified at activation time
- **FR-011**: System MUST associate terminal and editor working directories with project-specific paths when configured
- **FR-012**: System MUST integrate with i3's native workspace and window management without conflicting with existing i3 keybindings
- **FR-013**: System MUST generate configuration that is version-controllable and human-readable
- **FR-014**: System MUST detect when required applications are not installed and provide clear error messages
- **FR-015**: System MUST support application aliases for shorthand command syntax (e.g., "vsc" for VSCode)
- **FR-016**: System MUST allow ad-hoc project composition via command-line syntax without requiring configuration file changes
- **FR-017**: System MUST handle monitor connection/disconnection events and redistribute workspaces appropriately
- **FR-018**: System MUST respect i3's existing workspace management and not interfere with manual workspace operations
- **FR-019**: System MUST provide commands to list available projects and show project status
- **FR-020**: System MUST support both persistent projects (defined in configuration) and temporary projects (ad-hoc creation)
- **FR-021**: System MUST provide a command to close/terminate all applications associated with a specific project (Decision 1)
- **FR-022**: System MUST maintain a list of known single-instance applications and treat them as "shared" across projects (Decision 2)
- **FR-023**: System MUST allow users to override default instance behavior (shared/unique) on a per-application basis in project configuration (Decision 2)
- **FR-024**: System MUST notify users when a shared application is moved from one project to another (Decision 2)
- **FR-025**: Layout capture command MUST scan all workspaces and capture any workspace containing windows (Decision 3)
- **FR-026**: Layout capture command MUST skip empty workspaces and report which workspaces were captured (Decision 3)
- **FR-027**: System MUST support a `--workspace <number>` flag for capturing only a specific workspace (Decision 3)

### Non-Functional Requirements

- **NFR-001**: Project activation SHOULD complete within 10 seconds for projects with up to 10 applications
- **NFR-002**: Configuration file syntax SHOULD be intuitive enough for users to create projects without referencing documentation after seeing one example
- **NFR-003**: System SHOULD integrate with existing i3wsr workspace renaming to show project names in the i3 bar
- **NFR-004**: Generated configuration files SHOULD follow NixOS conventions and best practices
- **NFR-005**: System SHOULD minimize dependencies on external tools beyond what's already in the NixOS configuration

### Key Entities

- **Project**: A named collection of workspace configurations representing a cohesive development environment (e.g., "api-backend", "docs-site", "ml-research")
  - Attributes: name, display name, description, workspace configurations, default directory path
  - Relationships: contains one or more workspace configurations

- **Workspace Configuration**: Defines the applications and layout for a single i3 workspace
  - Attributes: workspace number/name, monitor output, application assignments, layout structure
  - Relationships: belongs to a project, contains one or more application assignments

- **Application Assignment**: Specifies an application to launch with its positioning and context
  - Attributes: application executable, window class, position (split direction, size), working directory, startup parameters
  - Relationships: belongs to a workspace configuration

- **Application Alias**: A short name that maps to a full application definition
  - Attributes: alias (e.g., "vsc"), full application name, default launch parameters
  - Relationships: used in shorthand syntax, references an application definition

- **Layout Snapshot**: A captured state of current workspace arrangement
  - Attributes: timestamp, workspace state, window positions, application instances
  - Relationships: can be converted to a project configuration

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can activate any defined project and see all applications launch within 10 seconds
- **SC-002**: Users can define a new project in their configuration file and activate it after a system rebuild without any manual setup
- **SC-003**: Users can switch between 5 different projects throughout a workday without losing application state or window arrangements
- **SC-004**: Users working with 3 monitors can activate projects that span all displays with applications appearing on correct monitors
- **SC-005**: Users working on a single monitor can access all content from multi-monitor project configurations via workspace switching
- **SC-006**: Users can capture their current workspace arrangement and reactivate it with 100% fidelity in window positions and application types
- **SC-007**: Users can activate a project with a parameterized directory path and have all terminals and editors open in that directory context
- **SC-008**: System configuration remains under 500 lines of NixOS code for core functionality (excluding project definitions)
- **SC-009**: Users can create an ad-hoc 3-application workspace using shorthand syntax in a single command under 50 characters
- **SC-010**: Project switching reduces context switching time by at least 60% compared to manually launching and arranging applications

### User Experience Goals

- **UX-001**: Users feel confident version controlling their entire workspace setup alongside their dotfiles
- **UX-002**: Users can experiment with workspace arrangements without fear of losing working configurations
- **UX-003**: New users can create their first project within 15 minutes of reading documentation
- **UX-004**: Power users can compose temporary workspaces without leaving the terminal
- **UX-005**: Users working across multiple machines experience consistent project environments

## Assumptions *(mandatory)*

1. **i3 Window Manager**: The system assumes i3wm is already configured and functional (via existing modules/desktop/i3wm.nix)
2. **Application Installation**: All applications referenced in project definitions must be installed via NixOS configuration; the system will not auto-install missing applications
3. **Home-Manager Integration**: Project definitions will be managed through home-manager as part of the existing NixOS configuration structure
4. **Workspace Numbering**: i3's default workspace numbering (1-10) will be used; projects can span multiple workspaces but won't create new workspace paradigms
5. **Window Class Detection**: Applications must have consistent WM_CLASS values for reliable window matching (most modern applications do)
6. **JSON Layout Storage**: Project layouts will leverage i3's native JSON layout saving format where applicable
7. **Single User**: The system is designed for single-user workstations; multi-user concurrent project activation is not considered
8. **X11 Environment**: The system targets X11-based i3 sessions (current configuration uses X11, not Wayland)
9. **Terminal Emulator**: Alacritty is the default terminal; projects using terminal applications will launch Alacritty unless specified otherwise
10. **Monitor Identification**: Monitor outputs will be identified using xrandr output names (e.g., DP-1, HDMI-2)
11. **Application Launch Commands**: Applications can be launched via standard shell commands available in the user's PATH
12. **Filesystem Access**: Projects referencing directory paths assume standard Linux filesystem access permissions
13. **State Persistence**: The system does NOT preserve application internal state (e.g., unsaved editor buffers) - only window positioning and which applications are running
14. **i3 IPC Access**: The system will use i3's IPC (Inter-Process Communication) interface for workspace and window management
15. **Resource Availability**: The system assumes sufficient system resources to run multiple projects concurrently (CPU, RAM, display memory)

## Out of Scope *(mandatory)*

- **Application State Persistence**: Saving and restoring internal application state (e.g., Firefox tabs, editor buffers, terminal scrollback)
- **Cross-Machine Window Sharing**: Remote desktop or window streaming between different machines
- **Automatic Application Installation**: Installing applications that are referenced in project definitions but not present in the system
- **GUI Configuration Interface**: A graphical tool for creating and editing project definitions (CLI and config file editing only)
- **Application-Specific Integrations**: Deep integration with specific applications (e.g., automatically restoring VSCode workspace state beyond opening the directory)
- **Dynamic Application Discovery**: Automatically detecting and suggesting applications for projects based on directory contents
- **Resource Monitoring**: Tracking CPU, memory, or network usage per project
- **Project Templates Marketplace**: Sharing or downloading project configurations from a community repository
- **Time Tracking**: Logging time spent in each project or automatic time tracking integration
- **Window Content Capture**: Taking screenshots or recording video of workspace arrangements
- **Wayland Support**: System targets X11-based i3; Wayland compatibility is not included
- **Cloud Synchronization**: Automatically syncing project states across machines beyond version control
- **AI-Powered Layout Suggestions**: Machine learning-based recommendations for workspace arrangements
- **Per-Application Configuration**: Automatically configuring application settings (e.g., editor themes, browser profiles) per project
- **Dependency Management**: Managing or installing project dependencies (npm packages, Python libraries, etc.)

## Technical Constraints *(optional)*

- **i3 Version**: Must be compatible with i3 v4.8 or later (current NixOS stable provides i3 4.24)
- **NixOS Module System**: All configuration must integrate with NixOS module system and home-manager
- **Existing Keybindings**: Must not override existing i3 keybindings defined in modules/desktop/i3wm.nix without explicit user configuration
- **i3wsr Compatibility**: Should work alongside the existing i3wsr workspace renaming system
- **Shell Script vs Compiled**: Implementation should prefer shell scripts or Python over compiled languages for easier NixOS integration
- **Configuration File Format**: Project definitions should use Nix attribute sets for native NixOS integration
- **Launch Dependencies**: Cannot assume specific window creation order; must handle asynchronous application startup
- **Window Matching**: Limited by applications' WM_CLASS consistency; cannot reliably match windows without proper class names

## Design Decisions *(resolved)*

### Decision 1: Default Project Activation Behavior - OPTION A

**Decision**: Keep all projects running, focus switches to new project workspace

**Rationale**: When a user activates a new project while another project is already active, the system will:
- Keep all applications from the previous project running in their workspaces
- Switch focus to the new project's primary workspace
- Allow users to manually close projects when they want to free resources

**Implications**:
- Maximizes application state preservation - users never lose work when switching projects
- Consumes more system resources if many projects are activated throughout the day
- Users must manually close project applications when they want to free memory/CPU
- Aligns with i3's philosophy of giving users explicit control over their environment

**Implementation Notes**:
- System will need a separate command (e.g., `i3-project close <name>`) to terminate all applications associated with a project
- Project activation command should be fast and non-destructive
- Users can leverage i3's existing workspace switching to navigate between active projects

---

### Decision 2: Application Instance Handling - OPTION B

**Decision**: Detect single-instance applications and configure them as "shared" across projects by default

**Rationale**: When a user has Firefox open in "project-A" and activates "project-B" which also includes Firefox, the system will:
- Detect that Firefox is already running and is a single-instance application
- Move the existing Firefox window to the appropriate workspace in project-B
- Mark applications like Firefox, Spotify, Slack as "shared" by default

**Implications**:
- More intelligent behavior that matches user expectations for applications like web browsers and media players
- Requires maintaining a curated list of known single-instance applications
- Some applications may not be correctly identified and may need user configuration overrides
- Provides better user experience than having multiple failed launch attempts or orphaned windows

**Implementation Notes**:
- System should include a default list of common single-instance applications (Firefox, Chrome, Spotify, Slack, Discord)
- Users can override default behavior in their project configuration with per-application `instance: "unique"` or `instance: "shared"` flags
- When moving a shared application, system should notify user (e.g., "Firefox moved from project-A to project-B")
- For applications that support profiles (Firefox, Chrome), future enhancement could use `instance: "clone"` with profile parameters

---

### Decision 3: Layout Capture Scope - OPTION B

**Decision**: Capture all non-empty workspaces by default

**Rationale**: When a user executes a layout capture command, the system will:
- Scan all workspaces across all monitors
- Capture any workspace that contains windows (skip empty workspaces)
- Generate a project configuration representing the complete multi-workspace layout

**Implications**:
- Captures everything automatically, which is convenient for multi-monitor setups
- May include unrelated workspaces that the user didn't intend to associate with the project
- Users can manually edit the generated configuration to remove unwanted workspaces
- Provides the most comprehensive default while still being editable

**Implementation Notes**:
- After capture, system should display which workspaces were included (e.g., "Captured workspaces: 1, 3, 5, 7")
- Generated configuration file should clearly comment each workspace section for easy editing
- Users can add a flag `--workspace <number>` to capture only a specific workspace if needed
- System should warn if capturing workspaces with system/background applications (e.g., system monitors)

## Dependencies *(optional)*

### Required Dependencies

- **i3wm** (v4.8+): Core window manager - already installed via modules/desktop/i3wm.nix
- **i3ipc**: i3 IPC library for programmatic control - likely needs to be added
- **xdotool**: X11 automation for window manipulation - may already be in system packages
- **xprop**: X11 property viewer for window class detection - typically in xorg.xprop
- **jq**: JSON processing for layout files - likely already installed

### Optional Dependencies (for enhanced functionality)

- **i3-save-tree**: Built into i3, used for layout capture
- **rofi** or **dmenu**: Already installed, could be used for interactive project selection
- **psutil** (Python): Process utilities if using Python implementation
- **xrandr**: Monitor configuration - already available in X11 systems

### Ecosystem Integration

- **i3wsr**: Existing workspace renaming system - should display project names in workspace labels
- **clipcat**: Existing clipboard manager - should continue to function across project switches
- **alacritty**: Default terminal emulator - will be primary terminal for project environments

## Privacy & Security Considerations *(optional)*

- **Command History**: Project activation commands and directory paths will appear in shell history; users working with sensitive directory names should be aware
- **Configuration Exposure**: Project definitions in NixOS config files may reveal directory structures and workflow patterns if config is shared publicly; users should review before committing to public repositories
- **Application Credentials**: System does not manage application authentication; users must handle credentials separately (e.g., browser profiles, editor tokens)
- **Process Visibility**: Launched application processes are visible to system administrators and process monitoring tools
- **No Data Encryption**: Project configurations and workspace states are stored in plaintext; no sensitive data should be embedded in project definitions

## Accessibility Considerations *(optional)*

- **Keyboard-Driven**: System is fully operable via keyboard commands, following i3's keyboard-centric philosophy
- **Screen Reader Compatibility**: Relies on i3's existing accessibility support; workspace announcements should include project names
- **Visual Indicators**: Project status visible in i3 bar via i3wsr integration; no additional visual-only signals
- **Command Verbosity**: Command output should be readable by screen readers with clear status messages
- **No Mouse Required**: All functionality accessible without mouse/pointing device

## Internationalization Considerations *(optional)*

- **Project Names**: Support UTF-8 project names for international characters
- **Directory Paths**: Must handle non-ASCII characters in repository and directory paths
- **Application Names**: Application class names and launch commands typically ASCII; no special i18n handling needed
- **Documentation**: Command help text and error messages should be clear and translatable if needed in future
- **Locale Independence**: System behavior should not depend on system locale settings

## Future Enhancements *(optional)*

1. **Project Templates**: Pre-built project configurations for common development stacks (Python+Django, Node+React, Go+Postgres, etc.)
2. **Automatic Directory Detection**: When activating a project from within a git repository, automatically parameterize the project with the current repo path
3. **Project Groups**: Organize related projects into groups with commands to list and activate projects within a group
4. **Resource Quotas**: Optional resource limits per project (max applications, memory usage warnings)
5. **Integration with tmux**: Support for launching tmux sessions as part of project environments with pre-configured windows
6. **Activity Tracking**: Optional logging of project activation/switch times for personal productivity analysis
7. **Project Hooks**: Run custom scripts on project activation/deactivation (e.g., start database, mount network drives)
8. **Cloud Workspace Sync**: Export/import project states to/from remote storage for cross-machine synchronization
9. **Layout Templates**: Define reusable layout patterns (e.g., "triple-column", "main-and-sidebar") that can be applied to different application sets
10. **Wayland Support**: Port to Sway (i3-compatible Wayland compositor) when ready to migrate from X11
11. **Dynamic Monitor Adaptation**: Automatically adjust layouts when monitor configuration changes during a session
12. **Project Search**: Fuzzy search across project names and descriptions for quick activation
13. **Recently Used Projects**: Quick-switch to recently activated projects via keybinding
14. **Project Overlays**: Temporarily add applications to active project without modifying project definition

## References *(optional)*

- **i3 Official Documentation**: https://i3wm.org/docs/layout-saving.html - Layout saving feature documentation
- **i3 User Guide**: https://i3wm.org/docs/userguide.html - Complete i3 configuration reference
- **i3-layout-manager**: https://github.com/klaxalk/i3-layout-manager - Community tool for layout management with rofi integration
- **i3-resurrect**: https://github.com/JonnyHaystack/i3-resurrect - Python-based workspace saving/restoring tool
- **i3 IPC Reference**: https://i3wm.org/docs/ipc.html - Inter-process communication protocol for i3 control
- **NixOS Manual - home-manager**: https://nix-community.github.io/home-manager/ - User environment management
- **Current i3 Configuration**: /etc/nixos/modules/desktop/i3wm.nix - Existing i3wm module
- **i3wsr Integration**: /etc/nixos/home-modules/desktop/i3wsr.nix - Workspace renaming module

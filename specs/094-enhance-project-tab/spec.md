# Feature Specification: Enhanced Projects & Applications CRUD Interface

**Feature Branch**: `094-enhance-project-tab`
**Created**: 2025-11-24
**Status**: Draft
**Input**: User description: "i want enhance the functionality of the projects tab and the applications tab in our eww monitoring widget in the following ways.

projects: add crud operations.  provide the ability to edit, add, and delete.  provide a great user experience to do that.  perhaps using a form inline to edit and add.  we also want the equivalent functionality for worktrees.  we may need to provide a sequnence of items or an organization structure that allows for the parent/child relationship of projects/worktrees.  think through the semantic relationships of our "projects" and git worktrees and use that logic to create the correct logic.  use the functionality from tab 1 that provides the window json detail upon however in the projects tab to show the configuration detail of the project/worktree.


applications: add crud operations.  provide the ability to edit, add, and delete.  provide a great user experience to do that.  perhaps add a form inline to edit and add. use the functionality from tab 1 that provides the window json detail upon however in the apps tab to show the configuration detail of the app.  in all aspects, we need to think through the differences betwee firefox pwa apps, and regular apps, and terminal apps.  pwa's in particular have different characterstics, and structure.  review @ and @ and related files to understand how we configure apps to be deployed into our system.


for both tabs, use styling/visual characteristics from tab 1 and 5 to maintain consistency and to make the tabs look stunning."

## Clarifications

### Session 2025-11-24

- Q: Should worktrees have their own create/edit/delete operations separate from main projects, or are they created only through Git operations external to the UI? → A: Worktrees support full CRUD (create via form with branch selection, edit working dir/display name, delete with Git cleanup). Use `i3pm worktree create` as template; form should provide the parameters to that command.
- Q: What happens if a user edits project JSON or Nix registry files externally while the monitoring panel has local changes pending? → A: Detect conflicts on save attempt, show diff view with options to: Keep UI changes (overwrite file), Keep file changes (reload form), or Merge manually (advanced). Last-write-wins without detection risks data loss.
- Q: What should happen when CLI commands (`i3pm project create`, `i3pm worktree create`, Git commands) fail with non-zero exit codes or errors? → A: Parse CLI stderr/exit codes, categorize errors (validation/permission/git/timeout), show user-friendly error messages with actionable recovery steps, preserve form data for retry. Log full CLI output for debugging.
- Q: Should the UI provide a button to trigger `sudo nixos-rebuild switch` directly after application registry changes, or only display instructions for manual execution? → A: Show notification with "Copy Command" button that copies `sudo nixos-rebuild switch --flake .#<target>` to clipboard. Include instructions: "Run in terminal to apply changes." Avoid direct sudo execution from UI for security.
- Q: Where does the ULID come from when creating a new PWA through the monitoring panel UI? → A: Auto-generate ULID programmatically using `/etc/nixos/scripts/generate-ulid.sh` (same as `/add-pwa` command), add to `app-registry-data.nix`, then user triggers `nixos-rebuild switch` which automatically installs the PWA via firefoxpwa during home-manager activation with the generated ULID.

## User Scenarios & Testing

### User Story 1 - View Project Configuration Details (Priority: P1)

Users need to inspect detailed configuration of their i3pm projects (local and remote) to understand settings like working directory, icon, display name, scope type, and for remote projects: SSH host, user, and remote path.

**Why this priority**: Foundation for all CRUD operations - users must first be able to view project details before editing them. This builds on the existing Tab 1 hover detail functionality and extends it to the Projects tab.

**Independent Test**: Can be fully tested by opening the monitoring panel Projects tab, hovering over a project entry, and verifying that a detailed JSON view appears with syntax-highlighted configuration matching the project's JSON file.

**Acceptance Scenarios**:

1. **Given** user has 5 projects configured (3 local, 2 remote), **When** user opens Projects tab in monitoring panel, **Then** all projects are listed with display name, icon, and working directory
2. **Given** Projects tab is visible, **When** user hovers over a project entry, **Then** colorized JSON configuration appears showing all project fields (name, icon, display_name, working_dir, scope, remote config if applicable)
3. **Given** user hovers over a remote project, **When** viewing JSON detail, **Then** remote configuration section is visible with host, user, remote_dir, and port fields

---

### User Story 2 - Edit Existing Project Configuration (Priority: P2)

Users need to modify project settings like display name, icon, working directory, and remote SSH parameters without manually editing JSON files, enabling quick fixes and adjustments during workflow.

**Why this priority**: Highest-value CRUD operation - editing is more common than creating or deleting. Builds on P1 viewing functionality.

**Independent Test**: Can be tested by clicking an "Edit" button on a project, modifying the display name and icon in an inline form, saving changes, and verifying the project list updates immediately and the JSON file on disk reflects the changes.

**Acceptance Scenarios**:

1. **Given** Projects tab is visible, **When** user clicks "Edit" icon next to a project, **Then** project entry expands to show inline edit form with current values pre-filled
2. **Given** inline edit form is showing, **When** user modifies display name from "My Project" to "Updated Project" and clicks "Save", **Then** project list updates immediately showing new name, JSON file is updated, and form collapses back to list view
3. **Given** user is editing a remote project, **When** user updates SSH host from "old-host" to "new-host.tailnet" and saves, **Then** remote configuration is validated and updated in project JSON file
4. **Given** inline edit form is showing, **When** user clicks "Cancel", **Then** form collapses without saving changes and original values remain

---

### User Story 3 - Create New Project (Priority: P3)

Users need to create new i3pm projects directly from the monitoring panel, specifying name, display name, icon, working directory, and optionally remote SSH parameters, without using CLI commands.

**Why this priority**: Less frequent than editing but essential for complete CRUD workflow. Can be developed after edit functionality is stable.

**Independent Test**: Can be tested by clicking "New Project" button, filling out form with project details, saving, and verifying the new project appears in the list and a JSON file is created at `~/.config/i3/projects/<name>.json`.

**Acceptance Scenarios**:

1. **Given** Projects tab is visible, **When** user clicks "New Project" button at top of list, **Then** inline create form appears with empty fields for name, display_name, icon, working_dir
2. **Given** create form is showing, **When** user fills in name="my-new-project", display_name="My New Project", icon="📦", working_dir="~/projects/new", and clicks "Save", **Then** new project is created in `~/.config/i3/projects/`, appears in project list immediately
3. **Given** create form is showing with "Remote Project" toggle enabled, **When** user fills in remote fields (host, user, remote_dir) and saves, **Then** project is created with remote configuration and marked as remote in the list
4. **Given** create form is showing, **When** user enters invalid name (contains spaces or special chars), **Then** validation error appears inline and save is prevented

---

### User Story 4 - Delete Project (Priority: P4)

Users need to remove obsolete or incorrectly configured projects from the system, with confirmation to prevent accidental deletion.

**Why this priority**: Least critical CRUD operation - used infrequently and lower risk of loss since projects can be recreated. Should be implemented after create/edit are stable.

**Independent Test**: Can be tested by clicking "Delete" icon on a project, confirming in a dialog, and verifying the project disappears from the list and its JSON file is removed from disk.

**Acceptance Scenarios**:

1. **Given** Projects tab is visible, **When** user clicks "Delete" icon next to a project, **Then** confirmation dialog appears asking "Delete project 'Project Name'? This cannot be undone."
2. **Given** delete confirmation is showing, **When** user clicks "Confirm Delete", **Then** project is removed from list immediately, JSON file is deleted from `~/.config/i3/projects/`, and success message appears briefly
3. **Given** delete confirmation is showing, **When** user clicks "Cancel", **Then** dialog closes and project remains in list unchanged

---

### User Story 5 - Manage Git Worktree Hierarchy (Priority: P2)

Users need to understand parent-child relationships between main projects and their Git worktrees, with visual indication of hierarchy (indentation, tree lines) and ability to create, edit, and delete worktrees directly from the UI using forms that invoke `i3pm worktree` CLI commands with appropriate parameters.

**Why this priority**: Essential for worktree management - users need full CRUD control over worktrees just like projects, but worktrees are more complex due to Git branch dependencies. Parallel to P1-P4 for projects.

**Independent Test**: Can be tested by creating a new worktree via "New Worktree" button under a parent project, specifying branch name and working directory, editing a worktree's display name, and deleting a worktree with Git cleanup confirmation.

**Acceptance Scenarios**:

1. **Given** user has main project "nixos" with 3 worktrees, **When** user opens Projects tab, **Then** main project appears as root entry, worktrees appear indented with "├─" tree lines, showing parent-child relationship
2. **Given** worktree hierarchy is displayed, **When** user hovers over a worktree entry, **Then** JSON detail shows worktree-specific fields (branch_name, worktree_path, parent_project)
3. **Given** user has multiple unrelated projects with worktrees, **When** viewing Projects tab, **Then** each main project and its worktrees form a separate tree group, visually separated
4. **Given** user clicks "New Worktree" button under a main project, **When** create form appears, **Then** form shows fields: branch_name (required, Git branch to checkout), worktree_path (required, absolute path for new worktree), display_name (optional, defaults to branch name), icon (optional)
5. **Given** user fills worktree create form with branch="feature-095", path="~/projects/nixos-feature-095", **When** user clicks "Save", **Then** system invokes `i3pm worktree create` with provided parameters, worktree appears in hierarchy immediately, Git worktree is created
6. **Given** user clicks "Edit" on a worktree entry, **When** edit form appears, **Then** branch_name and worktree_path are read-only (cannot change after creation), but display_name and icon are editable
7. **Given** user clicks "Delete" on a worktree entry, **When** confirmation appears, **Then** dialog warns "Delete worktree 'Worktree Name'? This will remove the Git worktree and project configuration." with "Confirm Delete" and "Cancel" buttons
8. **Given** user confirms worktree deletion, **When** deletion completes, **Then** system invokes Git worktree cleanup, removes worktree project JSON, updates hierarchy view immediately

---

### User Story 6 - View Application Registry Configuration (Priority: P1)

Users need to inspect detailed configuration of applications including command, parameters, scope (scoped/global), workspace assignment, monitor role preference, floating settings, and for PWAs: ULID, URL, manifest data.

**Why this priority**: Foundation for application CRUD operations - must view details before editing. Critical for understanding differences between regular apps, terminal apps, and PWAs.

**Independent Test**: Can be tested by opening Applications tab, hovering over an app entry, and verifying JSON detail shows all relevant fields with special PWA section for PWA apps.

**Acceptance Scenarios**:

1. **Given** Applications tab is visible, **When** user opens tab, **Then** all applications are listed grouped by type: Regular Apps, Terminal Apps, PWAs, each with app name, display name, command, and icon
2. **Given** Applications tab is showing, **When** user hovers over a regular app (e.g., "firefox"), **Then** JSON detail shows command, scope, workspace, monitor role, icon, nix_package
3. **Given** user hovers over a PWA app (e.g., "youtube-pwa"), **When** viewing JSON detail, **Then** PWA-specific fields are shown: ULID, start_url, scope URL, expected_class, and app_scope
4. **Given** user hovers over terminal app (e.g., "terminal"), **When** viewing JSON detail, **Then** terminal flag is true, parameters show sesh/tmux commands, and scope is marked as "scoped"

---

### User Story 7 - Edit Application Configuration (Priority: P2)

Users need to modify application settings like display name, preferred workspace, monitor role, floating size, and parameters through inline forms that understand app type constraints (regular vs terminal vs PWA).

**Why this priority**: High-value operation for adjusting workspace assignments and display preferences. Must handle three distinct app types differently.

**Independent Test**: Can be tested by editing a regular app's workspace from 3 to 5, editing a PWA's display name, and editing a terminal app's parameters, verifying changes save and system updates accordingly.

**Acceptance Scenarios**:

1. **Given** Applications tab is visible, **When** user clicks "Edit" on a regular app, **Then** inline form shows with fields: display_name, preferred_workspace (1-50 dropdown), preferred_monitor_role (primary/secondary/tertiary), floating toggle, floating_size (if floating enabled)
2. **Given** user is editing a PWA app, **When** inline form appears, **Then** PWA-specific fields are editable: display_name, preferred_workspace (50+ only), icon path, start_url, but ULID is read-only (cannot change)
3. **Given** user is editing a terminal app, **When** form shows, **Then** parameters field allows modifying command arguments (e.g., changing "-e btop" to "-e htop"), scope is editable (scoped/global)
4. **Given** user modifies workspace from 3 to 7 and saves, **When** changes are committed, **Then** app registry JSON is updated, and next app launch uses new workspace

---

### User Story 8 - Create New Application Entry (Priority: P3)

Users need to add new applications to the registry, choosing between regular app, terminal app, or PWA type, with type-specific form fields and validation.

**Why this priority**: Less frequent than editing but essential for extensibility. Complex due to three distinct app types requiring different forms.

**Independent Test**: Can be tested by creating a new regular app ("slack"), creating a new terminal app ("lazydocker"), and creating a new PWA ("notion-pwa"), verifying each saves correctly with appropriate type-specific fields.

**Acceptance Scenarios**:

1. **Given** Applications tab is visible, **When** user clicks "New Application" button, **Then** app type selector appears: "Regular App", "Terminal App", "PWA"
2. **Given** user selects "Regular App", **When** create form appears, **Then** fields shown: name (required, lowercase-hyphen), display_name, command (required), parameters, scope (scoped/global), workspace (1-50), monitor_role, icon, nix_package
3. **Given** user selects "PWA", **When** create form appears, **Then** PWA-specific fields shown: name (must end in "-pwa"), start_url (required, valid URL), scope url, icon (absolute path), workspace (50+ only), app_scope (scoped/global), description, categories, keywords. ULID field is NOT shown (auto-generated on save)
4. **Given** user fills out PWA form and clicks "Save", **When** validation passes, **Then** system invokes `/etc/nixos/scripts/generate-ulid.sh` to create ULID, adds entry to app-registry-data.nix with generated ULID, shows rebuild notification
5. **Given** user fills out new regular/terminal app form and clicks "Save", **When** validation passes, **Then** app registry data file is updated (Nix rebuild required message shown), new app appears in Applications tab list

---

### User Story 9 - Delete Application Entry (Priority: P4)

Users need to remove applications from the registry with confirmation and special warnings for PWAs (must be uninstalled separately via firefoxpwa CLI).

**Why this priority**: Least critical - deletion is infrequent and has system-wide impact requiring Nix rebuild. Should be implemented last.

**Independent Test**: Can be tested by deleting a regular app, attempting to delete a PWA (seeing warning about firefoxpwa), and confirming deletion removes entry from Nix file.

**Acceptance Scenarios**:

1. **Given** Applications tab is visible, **When** user clicks "Delete" icon on a regular app, **Then** confirmation dialog appears: "Delete application 'App Name'? This requires NixOS rebuild."
2. **Given** user attempts to delete a PWA app, **When** delete confirmation appears, **Then** special warning is shown: "Note: PWA must also be uninstalled via 'pwa-uninstall <ULID>' separately"
3. **Given** delete confirmation is accepted, **When** deletion completes, **Then** app is removed from Applications tab list, entry is removed from app-registry-data.nix file, and message shown: "Rebuild required: sudo nixos-rebuild switch"

---

### Edge Cases

#### Projects Tab

- **Empty project list**: When no projects exist, show "No projects configured" message with "Create Project" button prominently displayed
- **Duplicate project names**: When creating/editing, validate that project name is unique (case-sensitive) and show error if conflict exists
- **Invalid working directory**: When creating/editing, validate that working_dir path exists and show error if path is inaccessible
- **Remote SSH validation**: When configuring remote project, validate SSH host is reachable (optional check) and port is in range 1-65535
- **Editing while project is active**: If user edits the currently active project, show warning that changes take effect after next project switch
- **Worktree without parent**: If worktree JSON references non-existent parent project, show warning icon and mark as "orphaned"
- **Icon picker integration**: When editing icon field, support both emoji picker and file path input with validation
- **Worktree branch validation**: When creating worktree, validate branch exists in parent project's Git repository; show error with list of available branches if branch not found
- **Worktree path conflict**: When creating worktree, validate path doesn't already exist; suggest alternative path with timestamp suffix if conflict detected
- **Deleting worktree with active windows**: When deleting worktree, check if worktree project has open windows; show warning listing affected windows before deletion
- **Git worktree cleanup failure**: If Git worktree removal fails (locked files, permissions), preserve project JSON and show error with manual cleanup instructions
- **Creating worktree from remote project**: Remote projects cannot have worktrees (Git operations unsupported over SSH in this context); disable "New Worktree" button for remote projects
- **CLI command timeout**: If `i3pm` or Git command exceeds timeout (30 seconds default), show error "Command timed out. Check that Git repository is accessible and try again."
- **Git repository not initialized**: If user tries to create worktree in project without Git repository, show error "Not a Git repository. Initialize with: git init"
- **Permission denied on CLI execution**: If `i3pm` command fails with permission error, show error "Permission denied. Check file permissions for ~/.config/i3/projects/"
- **Invalid CLI arguments**: If form validation passes but CLI rejects arguments (edge case), parse stderr for specific error (e.g., "invalid branch name format") and display to user
- **i3pm command not found**: If `i3pm` CLI not in PATH, show error "i3pm command not found. Ensure i3pm is installed and in PATH."

#### Applications Tab

- **Empty applications list**: Should never occur (registry always has base apps), but handle gracefully if registry is missing/corrupted
- **Workspace validation**: Enforce 1-50 for regular/terminal apps, 50+ for PWAs, show error on violation
- **ULID validation**: For PWAs, validate ULID is exactly 26 characters matching pattern `[0-9A-HJKMNP-TV-Z]{26}`
- **Command validation**: Validate command field does not contain shell metacharacters (;|&`) to prevent injection
- **Nix rebuild requirement**: After any create/edit/delete operation, show persistent notification with text "NixOS rebuild required to apply changes" and "Copy Command" button that copies `sudo nixos-rebuild switch --flake .#<target>` to clipboard; include instructions "Run in terminal to apply changes. Estimated time: 2-5 minutes."
- **Multiple pending application changes**: If user makes multiple application edits in sequence, only show single rebuild notification (don't spam notifications); update notification count: "3 application changes require rebuild"
- **Copy command failure**: If clipboard copy fails (rare), show fallback text field with selectable command text for manual copy
- **Unknown system target**: If system target cannot be auto-detected (not wsl/hetzner-sway/m1), show rebuild command without --flake flag: `sudo nixos-rebuild switch`
- **PWA uninstall coordination**: When deleting PWA, check if PWA is currently installed via `firefoxpwa list` and show specific uninstall command
- **Multi-instance apps**: For apps with `multi_instance: true`, clarify in form that multiple windows can exist simultaneously
- **Expected class validation**: For PWAs, validate expected_class matches format `FFPWA-<ULID>`
- **ULID generation failure**: If `/etc/nixos/scripts/generate-ulid.sh` fails or returns invalid ULID, show error "ULID generation failed. Check that generate-ulid.sh script is executable." and preserve form data for retry
- **Duplicate ULID collision**: If generated ULID already exists in app-registry-data.nix (extremely rare, ~1 in 2^80 chance), regenerate new ULID automatically and retry save (max 3 attempts)
- **ULID script not found**: If generate-ulid.sh script doesn't exist at expected path, show error with path and instructions to verify NixOS scripts directory
- **Invalid ULID format from script**: If generated ULID contains forbidden characters (I, L, O, U) or wrong length, show error with validation details and retry generation

#### General UI/UX

- **Form validation feedback**: Show inline validation errors immediately as user types (debounced 300ms)
- **Unsaved changes warning**: If user starts editing and clicks away without saving, show confirmation dialog
- **Concurrent edits**: Prevent editing multiple items simultaneously - auto-collapse previous edit form when opening new one
- **JSON syntax highlighting**: Maintain Catppuccin Mocha color scheme from Tab 1 for consistency
- **Scroll position**: When list updates after create/edit/delete, maintain scroll position or scroll to modified item
- **Keyboard navigation**: Support Tab/Shift+Tab to navigate form fields, Enter to save, Escape to cancel
- **Error state recovery**: If save operation fails (e.g., file permissions), preserve form data and allow retry without re-entering
- **External file modification conflict**: If project JSON or app registry Nix file is modified externally while form is open, detect conflict on save attempt by comparing file modification timestamps; show conflict resolution dialog with diff view and three options: Keep UI Changes (overwrite), Keep File Changes (reload form), Merge Manually (advanced)
- **Conflict during batch operations**: If multiple forms are edited and conflict detected on one save, handle conflicts sequentially; preserve pending changes for remaining forms
- **Merge manually option**: "Merge Manually" option closes conflict dialog, preserves form state, and allows user to manually edit file externally then retry save or reload form

## Requirements

### Functional Requirements

#### Projects Tab (FR-P-001 through FR-P-015)

- **FR-P-001**: System MUST display all i3pm projects from `~/.config/i3/projects/*.json` in a scrollable list view
- **FR-P-002**: System MUST show project hierarchy with main projects and worktrees visually differentiated (indentation + tree lines)
- **FR-P-003**: System MUST support hovering over project entry to display colorized JSON configuration detail tooltip
- **FR-P-004**: System MUST provide "Edit" button on each project entry that expands inline edit form
- **FR-P-005**: System MUST provide "New Project" button at top of Projects tab that expands inline create form
- **FR-P-006**: System MUST provide "Delete" button on each project entry with confirmation dialog
- **FR-P-007**: System MUST validate project name format (lowercase, hyphens only, no spaces) during create/edit
- **FR-P-008**: System MUST validate working directory exists and is accessible during create/edit
- **FR-P-009**: System MUST support editing local project fields: name, display_name, icon, working_dir, scope
- **FR-P-010**: System MUST support editing remote project fields: host, user, remote_dir, port (in addition to FR-P-009 fields)
- **FR-P-011**: System MUST save project changes to JSON file at `~/.config/i3/projects/<name>.json` immediately on save
- **FR-P-012**: System MUST update project list view immediately after create/edit/delete operations without page reload
- **FR-P-013**: System MUST invoke `i3pm project create` CLI command for new projects with provided parameters
- **FR-P-014**: System MUST show worktree-specific fields in JSON detail: branch_name, worktree_path, parent_project
- **FR-P-015**: System MUST prevent deleting a main project that has active worktrees (show error message)
- **FR-P-016**: System MUST provide "New Worktree" button under each main project entry that expands inline create form
- **FR-P-017**: System MUST validate worktree branch name exists in Git repository before creation
- **FR-P-018**: System MUST validate worktree path does not already exist before creation
- **FR-P-019**: System MUST invoke `i3pm worktree create` CLI command with parameters: parent project, branch name, worktree path, display name, icon
- **FR-P-020**: System MUST support editing worktree fields: display_name, icon (branch_name and worktree_path are read-only after creation)
- **FR-P-021**: System MUST provide "Delete" button on each worktree entry with confirmation dialog warning about Git worktree removal
- **FR-P-022**: System MUST invoke Git worktree cleanup and remove worktree project JSON file on deletion
- **FR-P-023**: System MUST update worktree hierarchy view immediately after worktree create/edit/delete operations
- **FR-P-024**: System MUST detect file modification conflicts by comparing file modification timestamps before saving project changes
- **FR-P-025**: System MUST display conflict resolution dialog when external file modification detected, showing: current file content, pending UI changes, and three action buttons (Keep UI Changes/Keep File Changes/Merge Manually)
- **FR-P-026**: System MUST reload form with file content when user selects "Keep File Changes" option in conflict dialog
- **FR-P-027**: System MUST overwrite file with UI changes when user selects "Keep UI Changes" option in conflict dialog
- **FR-P-028**: System MUST capture and parse CLI command exit codes and stderr output when invoking `i3pm project create`, `i3pm worktree create`, or Git commands
- **FR-P-029**: System MUST categorize CLI errors into types: validation errors (invalid input), permission errors (file/directory access), Git errors (repository/branch issues), timeout errors (command exceeded threshold)
- **FR-P-030**: System MUST display user-friendly error messages with actionable recovery steps based on error category (e.g., "Branch 'feature-096' not found. Available branches: main, develop, feature-095")
- **FR-P-031**: System MUST preserve form data when CLI command fails, allowing user to correct input and retry without re-entering all fields
- **FR-P-032**: System MUST log full CLI command invocation, exit code, stdout, and stderr to backend log file for debugging purposes

#### Applications Tab (FR-A-001 through FR-A-020)

- **FR-A-001**: System MUST display all applications from `app-registry-data.nix` grouped by type: Regular Apps, Terminal Apps, PWAs
- **FR-A-002**: System MUST support hovering over application entry to display colorized JSON configuration detail tooltip
- **FR-A-003**: System MUST provide "Edit" button on each application entry that expands inline edit form
- **FR-A-004**: System MUST provide "New Application" button at top of Applications tab with app type selector
- **FR-A-005**: System MUST provide "Delete" button on each application entry with confirmation dialog
- **FR-A-006**: System MUST validate application name format (lowercase, hyphens or dots, no spaces) during create/edit
- **FR-A-007**: System MUST enforce workspace range validation: 1-50 for regular/terminal apps, 50+ for PWAs
- **FR-A-008**: System MUST validate PWA ULID is exactly 26 characters matching pattern `[0-9A-HJKMNP-TV-Z]{26}`
- **FR-A-009**: System MUST validate command field does not contain shell metacharacters (;|&`)
- **FR-A-010**: System MUST differentiate between regular app fields (command, parameters, scope, workspace, monitor_role) and PWA fields (ULID, start_url, scope url, expected_class)
- **FR-A-011**: System MUST differentiate terminal app fields (terminal flag, parameters with sesh/tmux syntax, scope=scoped)
- **FR-A-012**: System MUST save application changes to `app-registry-data.nix` file via Nix expression editing
- **FR-A-013**: System MUST show "NixOS rebuild required" notification after any create/edit/delete operation
- **FR-A-014**: System MUST display PWA-specific warning when deleting PWA: "Must also run: pwa-uninstall <ULID>"
- **FR-A-015**: System MUST validate start_url field for PWAs is a valid HTTP/HTTPS URL
- **FR-A-016**: System MUST validate icon field is either emoji (1-2 characters) or absolute file path
- **FR-A-017**: System MUST mark ULID and expected_class as read-only when editing existing PWA
- **FR-A-018**: System MUST support dropdown selection for monitor_role (primary/secondary/tertiary)
- **FR-A-019**: System MUST support dropdown selection for scope (scoped/global)
- **FR-A-020**: System MUST support toggle for floating and conditional dropdown for floating_size (scratchpad/small/medium/large)
- **FR-A-021**: System MUST detect file modification conflicts by comparing file modification timestamps before saving application registry changes
- **FR-A-022**: System MUST display conflict resolution dialog when external Nix file modification detected, showing: current file content, pending UI changes, and three action buttons (Keep UI Changes/Keep File Changes/Merge Manually)
- **FR-A-023**: System MUST reload form with file content when user selects "Keep File Changes" option in conflict dialog
- **FR-A-024**: System MUST overwrite file with UI changes when user selects "Keep UI Changes" option in conflict dialog
- **FR-A-025**: System MUST display persistent notification after application create/edit/delete operations with text: "NixOS rebuild required to apply changes"
- **FR-A-026**: System MUST provide "Copy Command" button in rebuild notification that copies `sudo nixos-rebuild switch --flake .#<target>` to system clipboard (target auto-detected from system: wsl/hetzner-sway/m1)
- **FR-A-027**: System MUST include instructions in rebuild notification: "Run in terminal to apply changes. Estimated time: 2-5 minutes."
- **FR-A-028**: System MUST dismiss rebuild notification when user clicks "Copy Command" button or manually dismisses notification
- **FR-A-029**: System MUST auto-generate ULID for new PWAs by invoking `/etc/nixos/scripts/generate-ulid.sh` during save operation
- **FR-A-030**: System MUST validate generated ULID is exactly 26 characters from Crockford Base32 alphabet (0-9, A-H, J-K, M-N, P-T, V-Z, excluding I, L, O, U)
- **FR-A-031**: System MUST validate generated ULID first character is 0-7 (48-bit timestamp constraint)
- **FR-A-032**: System MUST check generated ULID for uniqueness against existing PWAs in app-registry-data.nix before saving
- **FR-A-033**: System MUST NOT display ULID field in PWA create form (field is auto-generated, not user-editable)
- **FR-A-034**: System MUST display generated ULID in success notification after PWA creation: "PWA created with ULID: {ULID}"

#### UI/UX Common Requirements (FR-U-001 through FR-U-010)

- **FR-U-001**: System MUST use Catppuccin Mocha color scheme matching Tab 1 and Tab 5 for consistency
- **FR-U-002**: System MUST display inline validation errors with 300ms debounce as user types
- **FR-U-003**: System MUST auto-collapse previous edit form when user opens new edit form (prevent concurrent edits)
- **FR-U-004**: System MUST show confirmation dialog if user clicks away from edit form with unsaved changes
- **FR-U-005**: System MUST support keyboard navigation: Tab/Shift+Tab (fields), Enter (save), Escape (cancel)
- **FR-U-006**: System MUST preserve scroll position after list updates or scroll to modified item
- **FR-U-007**: System MUST display JSON configuration detail with syntax highlighting (Catppuccin colors): keys (blue), strings (green), numbers (peach), booleans (yellow), null (gray)
- **FR-U-008**: System MUST show loading spinner during save operations and disable form inputs to prevent double-submit
- **FR-U-009**: System MUST display success notification (3s auto-dismiss) after successful create/edit/delete
- **FR-U-010**: System MUST display error notification (persist until dismissed) if save operation fails with retry option

### Key Entities

#### Project (i3pm project)

Represents an i3pm project with working directory, display preferences, and optional remote SSH configuration. Stored as JSON at `~/.config/i3/projects/<name>.json`.

**Core Attributes**:
- `name`: Unique identifier (lowercase-hyphen format)
- `display_name`: Human-readable name shown in UI
- `icon`: Emoji or file path for visual identification
- `working_dir`: Absolute path to project directory
- `scope`: "scoped" or "global" (determines window hiding behavior)

**Remote Attributes** (optional):
- `remote.enabled`: Boolean flag
- `remote.host`: SSH hostname or Tailscale FQDN
- `remote.user`: SSH username
- `remote.remote_dir`: Absolute path on remote host
- `remote.port`: SSH port (default 22)

**Relationships**:
- Has many worktrees (child relationship)
- Belongs to zero or one parent project (worktrees only)

#### Worktree (Git worktree)

A Git worktree linked to a main project, representing a separate branch checkout in a different directory.

**Additional Attributes** (extends Project):
- `worktree_path`: Absolute path to worktree directory
- `branch_name`: Git branch name for this worktree
- `parent_project`: Name of main project this worktree belongs to

#### Application (app registry entry)

Represents a launchable application with workspace assignment, monitor preferences, and launch parameters. Defined in `app-registry-data.nix`.

**Common Attributes**:
- `name`: Unique identifier (lowercase-hyphen format)
- `display_name`: Human-readable name
- `command`: Executable command (e.g., "firefox", "ghostty")
- `parameters`: Command-line arguments array
- `scope`: "scoped" or "global"
- `preferred_workspace`: Workspace number (1-50 for regular, 50+ for PWAs)
- `preferred_monitor_role`: "primary" | "secondary" | "tertiary" | null
- `icon`: Icon name, emoji, or file path
- `nix_package`: Nix package identifier (e.g., "pkgs.firefox")
- `multi_instance`: Boolean (allow multiple windows)
- `floating`: Boolean (launch as floating window)
- `floating_size`: "scratchpad" | "small" | "medium" | "large" (if floating)

**Terminal App Attributes** (additional):
- `terminal`: true (flag)
- `parameters`: Includes sesh/tmux/bash syntax (e.g., ["-e", "sesh", "connect", "$PROJECT_DIR"])

**PWA App Attributes** (additional):
- `name`: Must end with "-pwa"
- `ulid`: 26-character ULID (immutable after creation)
- `start_url`: PWA launch URL (e.g., "https://www.youtube.com")
- `scope`: URL scope for PWA (usually same as start_url with trailing slash)
- `expected_class`: Sway window class (format: "FFPWA-<ULID>")
- `app_scope`: "scoped" or "global" (distinct from regular scope)
- `description`: PWA description text
- Workspace: Must be 50 or higher

#### Application Type Enum

- **Regular**: Standard GUI application (command + parameters)
- **Terminal**: Terminal-based application (wrapped in ghostty/terminal)
- **PWA**: Progressive Web App via firefoxpwa (browser-based, ULID-identified)

## Success Criteria

### Measurable Outcomes

#### Projects Tab

- **SC-P-001**: Users can view all project configuration details by hovering over project entries without navigating away from monitoring panel
- **SC-P-002**: Users can edit an existing project's display name and icon in under 15 seconds (open edit form, modify, save)
- **SC-P-003**: Users can create a new local project in under 30 seconds by filling inline form with 4 required fields
- **SC-P-004**: Users can create a new remote project in under 45 seconds by filling inline form with 8 required fields (4 base + 4 remote)
- **SC-P-005**: Form validation errors appear within 300ms of user input, preventing invalid submissions
- **SC-P-006**: Project list updates within 500ms after create/edit/delete operations without requiring page reload
- **SC-P-007**: Main projects with worktrees display parent-child hierarchy correctly with visual indentation and tree connector lines
- **SC-P-008**: 95% of project edits succeed on first save attempt without backend errors
- **SC-P-009**: Users can create a new worktree in under 40 seconds by filling inline form with branch name and worktree path (form appears under parent project)
- **SC-P-010**: Worktree branch validation completes within 1 second, querying parent project's Git repository for available branches
- **SC-P-011**: Users can edit a worktree's display name in under 10 seconds (branch_name and worktree_path are read-only)
- **SC-P-012**: Worktree deletion with Git cleanup completes within 3 seconds for typical worktree (no locked files or permission issues)
- **SC-P-013**: CLI error messages are actionable - 90% of errors include specific recovery steps (e.g., "Branch not found" shows list of available branches)
- **SC-P-014**: CLI command failures preserve form data - users can correct errors and retry without re-entering all fields in 100% of cases
- **SC-P-015**: CLI error categorization accuracy is 95% or higher (correctly identifies validation/permission/git/timeout errors from exit codes and stderr)

#### Applications Tab

- **SC-A-001**: Users can view all application registry configuration by hovering over app entries, with type-specific fields highlighted (regular vs terminal vs PWA)
- **SC-A-002**: Users can edit an existing application's workspace assignment in under 10 seconds
- **SC-A-003**: Users can create a new regular application in under 45 seconds with 8 required fields
- **SC-A-004**: Users can create a new PWA application in under 60 seconds with 10 required fields including ULID and URLs
- **SC-A-005**: Form validation prevents 100% of invalid submissions (workspace range violations, ULID format errors, URL malformation)
- **SC-A-006**: Application list correctly groups apps by type (Regular, Terminal, PWA) with correct count badges
- **SC-A-007**: PWA deletion shows special warning about firefoxpwa uninstall requirement in 100% of cases
- **SC-A-008**: After application CRUD operation, system displays clear "NixOS rebuild required" notification with "Copy Command" button that copies rebuild command to clipboard within 100ms
- **SC-A-009**: Rebuild notification correctly auto-detects system target (wsl/hetzner-sway/m1) in 100% of supported systems
- **SC-A-010**: Multiple application edits trigger single rebuild notification with accurate change count, not multiple duplicate notifications
- **SC-A-011**: ULID generation for PWAs completes within 500ms using generate-ulid.sh script
- **SC-A-012**: Generated ULIDs are unique with 99.99%+ success rate on first attempt (collision rate < 0.01%)
- **SC-A-013**: ULID validation accuracy is 100% - rejects all invalid formats (wrong length, forbidden characters, invalid first character)
- **SC-A-014**: Users creating PWAs do not see ULID field in form - field is auto-generated transparently with ULID shown in success notification

#### General UI/UX

- **SC-U-001**: JSON syntax highlighting in hover tooltips matches Catppuccin Mocha theme with consistent colors for keys, strings, numbers, booleans
- **SC-U-002**: Inline edit forms auto-collapse when user opens different edit form, preventing confusion from multiple open forms
- **SC-U-003**: Keyboard navigation works for 100% of form interactions (Tab/Shift+Tab, Enter, Escape)
- **SC-U-004**: Users can cancel edit operations without losing data if they change mind before clicking save
- **SC-U-005**: Scroll position is maintained when list updates after CRUD operations, or automatically scrolls to modified item for visibility
- **SC-U-006**: Loading states appear for operations taking longer than 200ms, with spinner and disabled inputs to prevent double-submission
- **SC-U-007**: Error messages are specific and actionable (e.g., "Working directory '/invalid/path' does not exist" not "Save failed")
- **SC-U-008**: Success notifications auto-dismiss after 3 seconds, error notifications persist until user dismisses, maintaining non-disruptive UX
- **SC-U-009**: Conflict detection completes within 100ms on save attempt (file timestamp comparison), conflict dialog appears immediately if conflict detected
- **SC-U-010**: Conflict resolution dialog shows side-by-side diff view with current file content (left) and pending UI changes (right) for easy comparison

## Assumptions

1. **File System Access**: Monitoring panel backend has read/write access to `~/.config/i3/projects/` directory and read access to Nix configuration files
2. **CLI Availability**: `i3pm` CLI commands are available in PATH for project creation and worktree management
3. **Nix Rebuild Workflow**: Users understand that application registry changes require `sudo nixos-rebuild switch` to take effect; UI provides "Copy Command" button to copy rebuild command to clipboard with auto-detected system target (wsl/hetzner-sway/m1); users must execute command in terminal with sudo access
4. **Git Worktree Knowledge**: Users creating worktrees understand Git worktree concept and have valid branch names for worktree creation; UI form provides parameters to `i3pm worktree create` CLI command
5. **PWA ULID Management**: System auto-generates ULIDs programmatically using `/etc/nixos/scripts/generate-ulid.sh` during PWA creation; users do not manually enter or manage ULIDs; ULID field is read-only when editing existing PWAs; nixos-rebuild automatically installs PWA via firefoxpwa during home-manager activation with generated ULID
6. **Remote SSH Setup**: Users configuring remote projects have already set up SSH key authentication and can connect to remote hosts
7. **Icon Resources**: Users have access to emoji input or know absolute paths to icon files in their system
8. **Workspace Numbering**: Users understand workspace allocation rules: 1-50 for regular apps, 50+ for PWAs (documented in CLAUDE.md)
9. **Single User Context**: All operations occur within single user's home directory (`~/.config/i3/`, `~/.local/share/`), not system-wide
10. **Monitoring Panel Open**: Users must have monitoring panel open (visible or hidden) for CRUD operations - operations do not work if panel service is not running
11. **Backend Validation**: Nix expressions in `app-registry-data.nix` and `pwa-sites.nix` are syntactically valid before user edits - validation errors from Nix compiler are reported to user if introduced
12. **Conflict Detection**: System detects concurrent external edits by comparing file modification timestamps before save; conflict resolution dialog allows users to choose Keep UI Changes (overwrite), Keep File Changes (reload), or Merge Manually (advanced)

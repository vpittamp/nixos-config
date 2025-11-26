# Feature Specification: Bolster Project & Worktree CRUD Operations in Monitoring Widget

**Feature Branch**: `096-bolster-project-and`
**Created**: 2025-11-26
**Status**: Draft
**Input**: User description: "Enhance the eww monitoring widget Projects tab to ensure CRUD operations for projects and worktrees work correctly with proper visual feedback. Review existing Feature 094 implementation, fix any issues preventing action submission, and improve user experience."

## Context

Feature 094 implemented comprehensive CRUD infrastructure for the Projects tab in the eww monitoring panel, including:
- Python `ProjectCRUDHandler` with handlers for create/edit/delete projects and worktrees
- Shell scripts for Eww form interactions (`project-edit-open`, `project-edit-save`, `worktree-create`, etc.)
- Inline forms with validation feedback
- Conflict detection for concurrent edits
- CLI executor for git operations

However, the user reports that **CRUD actions cannot be submitted**. This feature focuses on:
1. Debugging and fixing the end-to-end CRUD flow
2. Ensuring form submissions reach the Python handlers correctly
3. Adding robust visual feedback for all operation states
4. Verifying functionality through direct testing

## User Scenarios & Testing

### User Story 1 - Create New Project via Monitoring Panel (Priority: P1)

Users need to create new i3pm projects directly from the monitoring panel by clicking "New Project", filling a form with project details, and having the project immediately appear in the list without requiring CLI commands.

**Why this priority**: Project creation is the foundation of the project management workflow. Without working create functionality, users must fall back to CLI commands, defeating the purpose of the UI.

**Independent Test**: Can be tested by clicking "New Project" button in Projects tab, entering name/directory/icon, clicking "Save", and verifying (1) the form submits, (2) success feedback appears, (3) new project appears in list, and (4) JSON file exists at `~/.config/i3/projects/<name>.json`.

**Acceptance Scenarios**:

1. **Given** the Projects tab is visible and no form is open, **When** user clicks "New Project" button, **Then** inline create form expands with empty fields for name, display name, icon, working directory, and scope
2. **Given** the create form is visible, **When** user fills all required fields (name, working_dir) and clicks "Save", **Then** the form submits to Python handler, success notification appears within 500ms, form collapses, and new project appears in the project list
3. **Given** the create form has an invalid name (spaces, special chars), **When** user tries to save, **Then** validation error appears inline below the name field within 300ms, save is prevented
4. **Given** the create form is visible, **When** user clicks "Cancel", **Then** form collapses without creating project, no error messages shown

---

### User Story 2 - Edit Existing Project Configuration (Priority: P1)

Users need to modify project display name, icon, and scope without manually editing JSON files. Changes should take effect immediately.

**Why this priority**: Editing is the most common operation after viewing. Users frequently need to rename projects or change icons for better organization.

**Independent Test**: Can be tested by clicking edit button (✏) on any project, changing display name, clicking "Save", and verifying (1) the save button triggers form submission, (2) success feedback appears, (3) project list updates with new name, and (4) JSON file on disk reflects changes.

**Acceptance Scenarios**:

1. **Given** a project entry is visible in the list, **When** user clicks the edit button (✏), **Then** inline edit form expands with current values pre-filled in all fields
2. **Given** the edit form is showing, **When** user modifies display name and clicks "Save", **Then** Python handler receives update request, project list updates immediately showing new name, success notification appears
3. **Given** the edit form has validation errors, **When** user tries to save, **Then** specific error messages appear inline below affected fields, save is blocked until errors are fixed
4. **Given** the edit form is showing, **When** user clicks "Cancel", **Then** form collapses without saving, original values remain in project list

---

### User Story 3 - Create Git Worktree from Parent Project (Priority: P2)

Users need to create new Git worktrees for feature branches directly from the monitoring panel, with the worktree appearing in the correct hierarchy under its parent project.

**Why this priority**: Worktree creation is more complex than project creation but essential for multi-branch workflows. It depends on project CRUD working correctly.

**Independent Test**: Can be tested by clicking "New Worktree" button under a main project, entering branch name and path, clicking "Save", and verifying (1) Git worktree is created, (2) project JSON is created, and (3) worktree appears indented under parent in the list.

**Acceptance Scenarios**:

1. **Given** a main project (not worktree, not remote) is visible, **When** viewing Projects tab, **Then** "New Worktree" button is visible for that project
2. **Given** "New Worktree" form is visible, **When** user enters branch name and worktree path and clicks "Save", **Then** system (a) validates branch name, (b) creates Git worktree via CLI, (c) creates project JSON, (d) shows success notification, (e) refreshes list with worktree under parent
3. **Given** worktree creation fails (branch not found, path exists), **When** Git command fails, **Then** user-friendly error message appears with specific recovery steps (e.g., "Branch 'feature-xyz' not found. Available branches: main, develop")
4. **Given** a remote project is visible, **When** viewing that project, **Then** "New Worktree" button is NOT visible (worktrees not supported for remote projects)

---

### User Story 4 - Delete Project with Confirmation (Priority: P2)

Users need to remove obsolete projects with a confirmation step to prevent accidental deletion.

**Why this priority**: Deletion is less common but important for cleanup. Requires confirmation to prevent data loss.

**Independent Test**: Can be tested by clicking delete button (🗑) on a project, confirming in dialog, and verifying (1) confirmation dialog appears, (2) after confirm, project disappears from list, and (3) JSON file is removed from disk.

**Acceptance Scenarios**:

1. **Given** a project is visible in the list, **When** user clicks delete button (🗑), **Then** confirmation dialog appears showing project name and warning
2. **Given** confirmation dialog is showing, **When** user clicks "Confirm Delete", **Then** project JSON file is deleted, project removed from list, success notification shown
3. **Given** confirmation dialog is showing, **When** user clicks "Cancel", **Then** dialog closes, project remains in list unchanged
4. **Given** project has active worktrees, **When** user tries to delete, **Then** warning shows worktree count and asks for force confirmation

---

### User Story 5 - Edit Worktree Display Settings (Priority: P3)

Users need to change worktree display name and icon while respecting that branch name and path are immutable after creation.

**Why this priority**: Lower frequency operation. Branch and path changes would require Git operations outside this scope.

**Independent Test**: Can be tested by clicking edit on a worktree, changing display name, and verifying branch name/path fields are read-only while display name saves successfully.

**Acceptance Scenarios**:

1. **Given** a worktree is visible in the list, **When** user clicks edit button, **Then** edit form shows with branch_name and worktree_path displayed as read-only labels, display_name and icon as editable inputs
2. **Given** worktree edit form is showing, **When** user changes display name and saves, **Then** only display_name and icon are updated in JSON, branch information unchanged

---

### User Story 6 - Delete Worktree with Git Cleanup (Priority: P3)

Users need to delete worktrees with proper Git worktree cleanup and project JSON removal.

**Why this priority**: Cleanup operation. Less frequent than creation/editing.

**Independent Test**: Can be tested by deleting a worktree and verifying both Git worktree directory and project JSON are removed.

**Acceptance Scenarios**:

1. **Given** a worktree is visible in the list, **When** user clicks delete and confirms, **Then** system (a) removes Git worktree from parent repo, (b) deletes worktree project JSON, (c) updates hierarchy view
2. **Given** Git worktree removal fails (locked files), **When** deletion proceeds, **Then** warning shown that Git cleanup failed but config was deleted, manual cleanup instructions provided

---

### User Story 7 - Visual Feedback During Operations (Priority: P1)

Users need clear visual feedback during all CRUD operations: loading states, success confirmations, and error messages with actionable recovery steps.

**Why this priority**: Critical for UX. Without feedback, users don't know if their actions succeeded.

**Independent Test**: Can be tested by performing any CRUD operation and observing (1) loading spinner appears during save, (2) success toast appears on completion, (3) error messages are specific and actionable.

**Acceptance Scenarios**:

1. **Given** any form save is initiated, **When** save is in progress, **Then** save button shows loading spinner, inputs are disabled, preventing double-submit
2. **Given** a CRUD operation succeeds, **When** operation completes, **Then** success notification appears with green color, auto-dismisses after 3 seconds
3. **Given** a CRUD operation fails, **When** error occurs, **Then** error notification appears with red color, shows specific error message, persists until dismissed by user
4. **Given** validation errors exist, **When** user focuses on input, **Then** inline error message visible below that specific field with Catppuccin red color

---

### Edge Cases

- **Shell script execution failure**: If Eww onclicks fail to execute shell scripts, show fallback error in panel
- **Python handler import errors**: If PYTHONPATH is incorrect, log detailed error and show "Backend unavailable" message
- **Form state desync**: If Eww variables don't update after save, force refresh via defpoll
- **Concurrent edits**: If two sessions edit same project, conflict detection triggers on save attempt
- **Empty project list**: Show "No projects configured. Click 'New Project' to create one." with prominent button
- **Worktree orphaned from parent**: If parent project deleted, show warning icon on orphaned worktrees
- **Git repository not initialized**: Show error "Not a Git repository" when creating worktree in non-Git directory
- **i3pm CLI not available**: If project-crud-handler can't find i3pm, show "CLI not found" error
- **Network timeouts (remote projects)**: For remote project creation, handle SSH connection failures gracefully
- **Disk full**: Handle file write failures with specific "Disk full" message

## Requirements

### Functional Requirements

#### Core CRUD Operations

- **FR-001**: System MUST execute shell scripts when Eww button onclick events trigger (project-create-save, project-edit-save, worktree-create, etc.)
- **FR-002**: System MUST pass form values from Eww variables to Python CRUD handlers via shell script arguments or eww get commands
- **FR-003**: System MUST refresh project list (projects_data variable) after any successful CRUD operation
- **FR-004**: System MUST display validation errors inline below affected form fields within 300ms of input change
- **FR-005**: System MUST show loading spinner on save buttons during async operations (save_in_progress state)
- **FR-006**: System MUST auto-dismiss success notifications after 3 seconds
- **FR-007**: System MUST persist error notifications until user explicitly dismisses them

#### Project Operations

- **FR-008**: System MUST create project JSON file at `~/.config/i3/projects/<name>.json` on successful create
- **FR-009**: System MUST validate project name format: lowercase letters, numbers, and hyphens only
- **FR-010**: System MUST validate working directory exists and is accessible before creating project
- **FR-011**: System MUST check for duplicate project names before creation

#### Worktree Operations

- **FR-012**: System MUST only show "New Worktree" button for main projects (not worktrees, not remote projects)
- **FR-013**: System MUST execute `git worktree add` command with correct arguments via CLIExecutor
- **FR-014**: System MUST validate branch exists in parent Git repository before worktree creation
- **FR-015**: System MUST display branch_name and worktree_path as read-only in worktree edit form
- **FR-016**: System MUST execute `git worktree remove` when deleting worktree

#### Visual Feedback

- **FR-017**: System MUST display save button with loading spinner during save operations
- **FR-018**: System MUST display success notification with green styling (Catppuccin Mocha green: #a6e3a1)
- **FR-019**: System MUST display error notification with red styling (Catppuccin Mocha red: #f38ba8)
- **FR-020**: System MUST display validation error text below input fields in red italic text

### Key Entities

- **Project**: i3pm project configuration stored as JSON. Attributes: name, display_name, icon, working_dir, scope, remote config (optional)
- **Worktree**: Git worktree with i3pm project association. Attributes: extends Project with branch_name, worktree_path, parent_project
- **FormState**: Eww variables tracking form input values, validation state, editing mode
- **NotificationState**: Toast notification content, type (success/error), auto-dismiss timer

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can create a new project in under 30 seconds (open form → fill fields → save → see in list)
- **SC-002**: Save button onclick events trigger shell scripts in 100% of attempts (no silent failures)
- **SC-003**: Project list refreshes within 500ms after any CRUD operation
- **SC-004**: Validation errors appear within 300ms of user input
- **SC-005**: Success notifications appear within 200ms of operation completion
- **SC-006**: 95% of CRUD operations succeed on first attempt without backend errors
- **SC-007**: Users can identify the cause of any error from the error message alone (no generic "failed" messages)
- **SC-008**: Worktree hierarchy displays correctly with parent-child indentation in 100% of cases
- **SC-009**: All form inputs respond to keyboard navigation (Tab/Shift+Tab, Enter to save, Escape to cancel)

## Assumptions

1. **Feature 094 Infrastructure**: The existing Python handlers, shell scripts, and Eww widgets from Feature 094 are structurally correct; this feature fixes execution/binding issues
2. **Eww Configuration**: The eww-monitoring-panel config directory is at `~/.config/eww-monitoring-panel`
3. **PYTHONPATH**: The shell scripts set PYTHONPATH correctly to include the tools directory
4. **i3pm Daemon**: The i3pm daemon is running and accessible for project state
5. **Git Availability**: Git is installed and repositories are properly initialized for worktree operations
6. **File Permissions**: User has read/write access to `~/.config/i3/projects/` directory
7. **Catppuccin Theme**: Visual styling follows Catppuccin Mocha palette established in Feature 057

# Feature Specification: Enhanced Walker/Elephant Launcher Functionality

**Feature Branch**: `050-enhance-the-walker`
**Created**: 2025-10-29
**Status**: Draft
**Input**: User description: "enhance the walker/elephant functionality via configuration. add the providers/tools that are currently not enabled, including: custom commands, todo list, window switcher, bookmarks, walker commands, web search via google, clipboard history. here is documentation. scrape these sites into a text file that can be used for reference: https://walkerlauncher.com/docs/providers, https://walkerlauncher.com/docs/configuration"

## User Scenarios & Testing

### User Story 1 - Quick Task Management from Launcher (Priority: P1)

Users need to capture and manage tasks without leaving their current workflow. The todo list provider allows users to quickly add, view, and complete tasks directly from the launcher without opening a separate application.

**Why this priority**: Task management is a core productivity feature. Being able to quickly capture a thought or mark a task complete without context switching provides immediate value and addresses a common pain point.

**Independent Test**: Can be fully tested by typing `!` prefix in Walker, adding a task, viewing the task list, and marking tasks as complete. Delivers standalone value for personal task management.

**Acceptance Scenarios**:

1. **Given** Walker is open, **When** user types `!buy groceries`, **Then** a new task "buy groceries" is created and visible in the task list
2. **Given** user has active tasks, **When** user types `!` prefix, **Then** all active tasks are displayed with their creation timestamps
3. **Given** a task is displayed, **When** user selects it and marks as complete, **Then** the task is marked as done and removed from active list
4. **Given** user has tasks with different statuses, **When** user filters by status, **Then** only tasks matching that status are shown

---

### User Story 2 - Window Navigation and Focus (Priority: P1)

Users working with multiple windows need to quickly switch between them without using Alt+Tab repeatedly. The window switcher provider allows users to type partial window titles to instantly focus the desired window.

**Why this priority**: Window management is critical for productivity in multi-window workflows. This feature directly improves the core launcher functionality by making it a comprehensive navigation tool.

**Independent Test**: Can be fully tested by opening multiple windows, using Walker to search for window titles, and verifying focus switches correctly. Delivers immediate value for window navigation.

**Acceptance Scenarios**:

1. **Given** multiple windows are open, **When** user types a partial window title in Walker, **Then** matching windows are displayed with their application icons
2. **Given** a window is displayed in results, **When** user selects it, **Then** that window receives focus and moves to the foreground
3. **Given** windows on different workspaces, **When** user selects a window from another workspace, **Then** Walker switches to that workspace and focuses the window
4. **Given** minimized windows, **When** user searches for them, **Then** they appear in results and can be restored by selection

---

### User Story 3 - Saved Web Bookmarks Access (Priority: P2)

Users need quick access to frequently visited websites without opening a browser and navigating through bookmark folders. The bookmarks provider allows users to search and open saved URLs directly from the launcher.

**Why this priority**: While useful, this is less critical than task management and window switching. Many users have bookmark toolbar or can use web search as an alternative. This is a convenience feature rather than core productivity enhancement.

**Independent Test**: Can be fully tested by configuring bookmarks in Walker config, searching for bookmark names, and verifying they open in the default browser. Delivers value for users who maintain curated bookmark lists.

**Acceptance Scenarios**:

1. **Given** bookmarks are configured, **When** user types a bookmark name or tag, **Then** matching bookmarks are displayed with their URLs
2. **Given** a bookmark is selected, **When** user presses Enter, **Then** the URL opens in the default web browser
3. **Given** bookmarks with descriptions, **When** user searches by description keywords, **Then** matching bookmarks are found
4. **Given** bookmarks organized by category, **When** user filters by category, **Then** only bookmarks in that category are shown

---

### User Story 4 - Custom Command Shortcuts (Priority: P2)

Users perform repetitive command sequences that don't warrant separate scripts but are tedious to type repeatedly. Custom commands allow users to define one-off shortcuts for common operations without needing shell aliases or scripts.

**Why this priority**: Provides workflow optimization for power users but isn't essential for core launcher functionality. Users can achieve similar results with shell aliases or existing runner provider.

**Independent Test**: Can be fully tested by defining custom commands in config, invoking them from Walker, and verifying they execute correctly. Delivers value for users with specific workflow patterns.

**Acceptance Scenarios**:

1. **Given** custom commands are configured, **When** user types the command name, **Then** the command appears in search results with its description
2. **Given** a custom command is selected, **When** user presses Enter, **Then** the command executes and output is displayed if configured
3. **Given** custom commands with parameters, **When** user provides arguments after the delimiter, **Then** arguments are passed to the command correctly
4. **Given** custom commands with different after-execution behaviors, **When** command completes, **Then** Walker behaves according to configuration (close, reload, etc.)

---

### User Story 5 - Enhanced Web Search Integration (Priority: P3)

Users need to search various web resources (Google, GitHub, Wikipedia, etc.) without manually opening browsers and typing in search boxes. Enhanced web search configuration provides quick access to multiple search engines with appropriate prefixes.

**Why this priority**: Basic web search already exists with current `@` prefix. This enhancement adds more search engines and better defaults. It's valuable but not essential since users can already search the web.

**Independent Test**: Can be fully tested by configuring additional search engines, using `@` prefix with search queries, and verifying correct URLs open. Delivers incremental value for users who search diverse sources.

**Acceptance Scenarios**:

1. **Given** multiple search engines are configured, **When** user types `@github typescript error`, **Then** GitHub search opens with the query
2. **Given** default search engine is set, **When** user types `@` without specifying engine, **Then** query uses the default search engine
3. **Given** search engine with custom URL template, **When** user queries that engine, **Then** query parameters are properly encoded in the URL
4. **Given** user queries with special characters, **When** search executes, **Then** characters are properly escaped in the URL

---

### Edge Cases

- What happens when todo list file is corrupted or missing?
- How does window switcher handle windows with identical titles?
- What happens when bookmarks configuration contains invalid URLs?
- How does system handle custom commands that require elevated permissions?
- What happens when web search query contains URL-unsafe characters (spaces, &, #)?
- How does system handle clipboard history when clipboard is empty or contains binary data?
- What happens when window switcher is invoked but no windows are open?
- How does todo list handle very long task descriptions (>500 characters)?

## Requirements

### Functional Requirements

- **FR-001**: System MUST enable todo list provider with `!` prefix for task management
- **FR-002**: System MUST enable window switcher provider for navigating open windows
- **FR-003**: System MUST enable bookmarks provider for quick URL access
- **FR-004**: System MUST enable custom commands provider for user-defined shortcuts
- **FR-005**: System MUST configure web search provider with multiple search engines (Google, GitHub, Wikipedia, DuckDuckGo)
- **FR-006**: System MUST configure clipboard history provider with `:` prefix
- **FR-007**: Todo list MUST support creating, viewing, and completing tasks
- **FR-008**: Todo list MUST persist tasks across Walker restarts
- **FR-009**: Window switcher MUST display all open windows with application icons and titles
- **FR-010**: Window switcher MUST switch focus to selected window, including cross-workspace navigation
- **FR-011**: Bookmarks MUST be configurable via Walker configuration file
- **FR-012**: Custom commands MUST support command name, description, and execution command
- **FR-013**: Custom commands MUST support parameter passing via global argument delimiter
- **FR-014**: Web search MUST support default search engine configuration
- **FR-015**: Web search MUST properly encode query parameters in URLs
- **FR-016**: Clipboard history MUST display timestamped clipboard entries
- **FR-017**: Clipboard history MUST support both text and image clipboard content
- **FR-018**: System MUST provide clear documentation of all enabled providers and their prefixes
- **FR-019**: System MUST gracefully handle provider initialization failures without crashing Walker
- **FR-020**: Custom commands MUST support configurable after-execution behavior (close, reload, nothing)

### Key Entities

- **Task**: Represents a todo item with description, status (active/inactive/done), creation timestamp, and optional deadline
- **Bookmark**: Represents a saved URL with name, URL, optional description, and optional category/tags
- **Custom Command**: Represents a user-defined command shortcut with name, description, command string, and after-execution behavior
- **Window**: Represents an open application window with title, application name, workspace location, and window state
- **Search Engine**: Represents a web search provider with name, URL template, and optional custom encoding rules
- **Clipboard Entry**: Represents a historical clipboard item with content (text or image), timestamp, and content type

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can create and manage tasks in under 5 seconds using the todo provider
- **SC-002**: Users can switch to any open window in under 3 seconds using fuzzy search
- **SC-003**: Users can access saved bookmarks without opening a browser (direct launch from Walker)
- **SC-004**: 100% of configured custom commands execute successfully when invoked
- **SC-005**: Web searches open correct search engine URLs with properly encoded queries
- **SC-006**: Clipboard history displays at least last 50 clipboard entries
- **SC-007**: Walker startup time increases by less than 200ms with all providers enabled
- **SC-008**: Users successfully discover and use at least 3 new providers within first week (measured by usage logs)
- **SC-009**: Zero provider-related crashes during normal Walker operation
- **SC-010**: Task completion rate improves by 30% due to reduced friction in task management workflow

## Scope

### In Scope

- Enabling and configuring all specified Walker providers (todo, windows, bookmarks, custom commands, enhanced web search, clipboard history)
- Creating NixOS configuration to enable providers and set prefixes
- Documenting provider usage and configuration in quickstart guide
- Testing each provider independently to verify functionality
- Configuring sensible defaults for each provider (search engines, clipboard history size, etc.)
- Creating example custom commands for common workflows
- Handling provider initialization errors gracefully

### Out of Scope

- Creating custom providers not available in Walker/Elephant upstream
- Modifying Walker/Elephant source code
- Migrating data from other task management or bookmark systems
- Syncing todos/bookmarks across multiple machines
- Creating GUIs for provider configuration (config remains TOML-based)
- Integration with external task management APIs (Todoist, Trello, etc.)
- Custom window management rules (covered by existing i3pm system)
- Fixing the existing Walker stack overflow bug (separate issue requiring upstream fix)

## Assumptions

- Walker/Elephant are already installed and configured in the NixOS system
- Users are comfortable editing TOML configuration files
- Default browser is configured for bookmark and web search functionality
- Window manager (Sway) exposes window list via standard protocols
- Clipboard manager (wl-clipboard) is available for clipboard history
- Walker configuration is managed via NixOS home-manager module
- Users will reference upstream Walker documentation for advanced provider features
- Todo list will use simple flat-file storage (Walker's built-in implementation)
- Bookmarks will be statically configured in config file (no dynamic bookmark sync)

## Dependencies

- Walker launcher application (minimum version 2.7.x)
- Elephant backend service (version 2.9.x)
- Sway window manager (for window switcher provider)
- wl-clipboard (for clipboard history provider)
- NixOS home-manager module for Walker configuration
- Existing Walker configuration infrastructure in `/etc/nixos/home-modules/desktop/walker.nix`
- Default web browser configuration (for bookmarks and web search)

## Open Questions

None - all provider functionality is well-documented in Walker upstream documentation.

## Documentation Requirements

- Update Walker quickstart guide with all enabled providers and their prefixes
- Create examples of custom commands for common workflows (git operations, system commands, project-specific tools)
- Document bookmark configuration format with examples
- Create troubleshooting section for common provider issues
- Add provider reference table showing prefix, purpose, and example usage for each enabled provider

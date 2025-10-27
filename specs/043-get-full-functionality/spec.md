# Feature Specification: Complete Walker/Elephant Launcher Functionality

**Feature Branch**: `043-get-full-functionality`
**Created**: 2025-10-27
**Status**: Draft
**Input**: User description: "get full functionality from walker/elephant service, including clipboard history, file search, web search, etc.  be careful to understand the impact of running as system vs user.  we are using x11.  there seems to be some known issues with passing environt variables correctly."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Application Launch with Environment Context (Priority: P1)

Users launch applications through Walker/Elephant and expect those applications to receive correct environment variables (DISPLAY, XDG_DATA_DIRS, PATH, etc.) so they function properly in the X11 environment with the i3pm project management system.

**Why this priority**: This is the foundation for the entire launcher system. Without proper environment variable propagation, launched applications cannot display (no DISPLAY), cannot find resources (no XDG paths), and cannot integrate with the project management system (no i3pm environment).

**Independent Test**: Can be fully tested by launching any application via Walker (Meta+D) and verifying: (1) application window appears on screen, (2) application can access its desktop file and resources, (3) application inherits the active project context from i3pm.

**Acceptance Scenarios**:

1. **Given** Walker is invoked via Meta+D keybinding, **When** user selects VS Code from the application list, **Then** VS Code launches with DISPLAY set correctly, opens a window on the current workspace, and inherits the active project directory
2. **Given** Elephant service is running, **When** user launches an application through Walker, **Then** the application receives all necessary environment variables from the user session (DISPLAY, XDG_DATA_DIRS, PATH, I3PM_* variables)
3. **Given** multiple applications are launched sequentially, **When** each application starts, **Then** each receives the current environment state at launch time (not stale cached values)

---

### User Story 2 - Clipboard History Management (Priority: P2)

Users access clipboard history by typing the ":" prefix in Walker, browse previously copied text and images, and paste selected items into their current application.

**Why this priority**: After core application launching works, clipboard history is the most frequently used utility feature. Users copy/paste dozens of times per day and need quick access to previous clipboard entries without losing context.

**Independent Test**: Can be fully tested by: (1) copying 3 different text snippets to clipboard, (2) typing ":" in Walker to show clipboard history, (3) selecting the second item from history, (4) verifying that item is pasted into the focused application.

**Acceptance Scenarios**:

1. **Given** user has copied 5 text snippets in the last hour, **When** user types ":" in Walker, **Then** Walker displays all 5 snippets with previews in reverse chronological order
2. **Given** clipboard history is displayed, **When** user selects a previous entry, **Then** that entry becomes the current clipboard content and can be pasted
3. **Given** user has copied an image (screenshot), **When** user types ":" in Walker, **Then** Walker displays the image with a thumbnail preview alongside text entries
4. **Given** clipboard history contains 100 items, **When** user searches within clipboard history, **Then** Walker filters results using fuzzy matching on clipboard content

---

### User Story 3 - File Search and Navigation (Priority: P2)

Users search for files by typing the "/" prefix in Walker, browse file system results with previews, and open files in appropriate applications (Neovim for text files, default handlers for others).

**Why this priority**: File search is a core productivity feature that complements application launching. Users need quick access to recent files and project resources without opening a file manager.

**Independent Test**: Can be fully tested by: (1) typing "/" followed by "nixos" in Walker, (2) verifying results show files matching "nixos" from home directory and project directories, (3) selecting a .nix file, (4) verifying it opens in Ghostty+Neovim.

**Acceptance Scenarios**:

1. **Given** user types "/" in Walker, **When** user enters a search term, **Then** Walker displays matching files from the user's home directory and active project directory
2. **Given** file search results are displayed, **When** user presses Return on a text file, **Then** the file opens in Ghostty terminal with Neovim at the correct line (if fragment provided)
3. **Given** file search results are displayed, **When** user presses Ctrl+Return on any file, **Then** the file opens with its default system application
4. **Given** user searches for a file, **When** matching files exist in multiple directories, **Then** results show full paths to disambiguate duplicates

---

### User Story 4 - Web Search Integration (Priority: P3)

Users search the web by typing the "@" prefix in Walker, select a search engine (Google, DuckDuckGo, GitHub, etc.), and launch their browser with search results.

**Why this priority**: Web search is useful but less critical than local application/file operations. Users can always open a browser manually if this feature doesn't work.

**Independent Test**: Can be fully tested by: (1) typing "@nixos tutorial" in Walker, (2) verifying search engine options appear, (3) selecting Google, (4) verifying Firefox opens with Google search results for "nixos tutorial".

**Acceptance Scenarios**:

1. **Given** user types "@" followed by search terms in Walker, **When** user selects a search engine, **Then** Firefox opens with a new tab showing search results for those terms
2. **Given** multiple search engines are configured, **When** user types "@" prefix, **Then** Walker shows available engines (Google, DuckDuckGo, GitHub, YouTube, Wikipedia)
3. **Given** a default search engine is configured, **When** user types "@" and presses Return immediately, **Then** search uses the default engine without requiring engine selection

---

### User Story 5 - Calculator and Symbol Insertion (Priority: P3)

Users perform quick calculations by typing "=" prefix or insert symbols/emoji by typing "." prefix without switching to external applications.

**Why this priority**: These are convenience features that enhance productivity but are not essential to core workflows. Users can use external calculator apps or character maps if needed.

**Independent Test**: Can be fully tested by: (1) typing "=2+2" in Walker, (2) verifying result "4" appears, (3) selecting result to copy to clipboard, (4) typing ".lambda" to find λ symbol, (5) inserting symbol into focused application.

**Acceptance Scenarios**:

1. **Given** user types "=" followed by a mathematical expression, **When** user presses Return, **Then** Walker evaluates the expression and copies the result to clipboard
2. **Given** user types "." followed by a symbol name, **When** matching symbols appear, **Then** user can select one to insert it at the current cursor position
3. **Given** user types "." without additional input, **When** symbol picker appears, **Then** Walker displays common emoji and special characters for browsing

---

### User Story 6 - Shell Command Execution (Priority: P3)

Users execute shell commands by typing the ">" prefix in Walker, run commands with or without terminal output, and view results without opening a separate terminal.

**Why this priority**: This is a power user feature. Most users will launch terminal applications directly rather than running one-off commands through the launcher.

**Independent Test**: Can be fully tested by: (1) typing ">echo hello" in Walker, (2) pressing Return to execute without terminal, (3) typing ">htop" and pressing Shift+Return to execute in terminal, (4) verifying htop appears in Ghostty terminal.

**Acceptance Scenarios**:

1. **Given** user types ">" followed by a shell command, **When** user presses Return, **Then** command executes in the background without showing terminal output
2. **Given** user types ">" followed by a shell command, **When** user presses Shift+Return, **Then** command executes in a new Ghostty terminal window with visible output
3. **Given** user executes a command via ">", **When** command requires user input or is long-running, **Then** Walker opens a terminal for interactive execution

---

### Edge Cases

- What happens when Elephant service starts before DISPLAY environment variable is available (X11 session not ready)?
- How does the system handle applications launched before i3pm daemon is running (no project context available)?
- What happens when user launches Walker while Elephant service is not running?
- How does clipboard history behave when clipboard contains binary data or very large content (>1MB)?
- What happens when file search returns thousands of results (performance impact)?
- How does web search handle special characters in search queries (URL encoding)?
- What happens when an application launched via Walker crashes immediately after starting?
- How does the system handle conflicting environment variables between systemd user session and i3 session?
- What happens when XDG_DATA_DIRS isolation causes an application to fail finding its resources?
- How does the system recover when Elephant service crashes (auto-restart behavior)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Elephant service MUST run as a systemd user service (not system service) to access user session environment variables
- **FR-002**: Elephant service MUST receive DISPLAY environment variable before accepting application launch requests
- **FR-003**: Elephant service MUST have access to user's PATH, XDG_DATA_DIRS, and XDG_RUNTIME_DIR environment variables
- **FR-004**: Walker invocation MUST force GDK_BACKEND=x11 to ensure X11 window rendering in XRDP/X11 environments
- **FR-005**: Walker invocation MUST set XDG_DATA_DIRS to include i3pm applications directory for registry-based app filtering
- **FR-006**: Applications launched via Walker/Elephant MUST inherit the current active project context (I3PM_PROJECT_NAME and related variables)
- **FR-007**: Clipboard history provider MUST support both text and image clipboard entries
- **FR-008**: Clipboard history MUST display entries in reverse chronological order (most recent first)
- **FR-009**: File search provider MUST search within user's home directory and active project directory
- **FR-010**: File search MUST support opening text files in Ghostty+Neovim via Return key
- **FR-011**: File search MUST support opening any file with default application via Ctrl+Return key
- **FR-012**: Web search provider MUST support multiple search engines (Google, DuckDuckGo, GitHub, YouTube, Wikipedia)
- **FR-013**: Web search MUST use a configurable default search engine when no engine is explicitly selected
- **FR-014**: Calculator provider MUST evaluate mathematical expressions and copy results to clipboard
- **FR-015**: Symbol picker MUST display emoji and special characters with fuzzy search support
- **FR-016**: Runner provider MUST support background execution (Return key) and terminal execution (Shift+Return)
- **FR-017**: Elephant service MUST auto-restart on failure with 1-second delay
- **FR-018**: i3 configuration MUST import DISPLAY into systemd user environment before starting Elephant service
- **FR-019**: Walker window MUST render as floating, centered window with no border in i3
- **FR-020**: Walker window MUST be marked with "_global_ui" i3 mark to prevent project-scoped filtering

### Key Entities

- **Elephant Service**: Background systemd user service that manages application launching and provider backends (clipboard, file search, web search, calculator, symbols, runner)
- **Walker UI**: GTK4-based launcher interface that connects to Elephant service and displays provider results with fuzzy matching
- **Provider**: A Walker/Elephant plugin that supplies searchable items (applications, clipboard history, files, web searches, calculations, symbols, shell commands)
- **Launch Context**: Set of environment variables (DISPLAY, XDG_DATA_DIRS, PATH, I3PM_*) passed from Elephant service to launched applications
- **Clipboard Entry**: A clipboard history item with content type (text/image), timestamp, and preview data
- **File Result**: A file search result with path, filename, modification time, and optional line number fragment
- **Search Engine**: A web search configuration with name and URL template for query parameter substitution

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can launch applications through Walker with 100% success rate (applications receive correct DISPLAY and environment variables)
- **SC-002**: Elephant service starts successfully within 2 seconds of i3 session start and remains running throughout the session
- **SC-003**: Clipboard history displays the 10 most recent clipboard entries within 200ms of typing ":" prefix
- **SC-004**: File search returns results within 500ms for searches in directories containing up to 10,000 files
- **SC-005**: Walker window appears within 100ms of Meta+D keybinding press
- **SC-006**: Applications launched via Walker receive i3pm project context with 100% accuracy (correct I3PM_PROJECT_NAME for current active project)
- **SC-007**: Web search opens browser with correct search query for 100% of searches (no URL encoding errors)
- **SC-008**: Calculator evaluates mathematical expressions with 100% accuracy for standard operators (+, -, *, /, %, ^)
- **SC-009**: File search opens text files in Neovim at the correct line number when fragment is provided (e.g., file.txt#L42)
- **SC-010**: Elephant service auto-recovery occurs within 2 seconds of service crash (systemd restart)

## Assumptions

- Walker version is ≥1.5 which supports X11 file provider safely when launched as a window (not layer shell)
- i3 window manager is configured to import DISPLAY into systemd user environment via `systemctl --user import-environment DISPLAY`
- i3pm daemon is running and responsive for providing active project context
- XDG_DATA_DIRS isolation to i3pm-applications directory is intentional (only show curated registry applications)
- Ghostty terminal is the default terminal for command execution and file opening
- Firefox is the default browser for web search
- Neovim is the default text editor
- xclip is available for clipboard operations
- System clipboard manager (KDE Klipper or equivalent) is not interfering with Walker's clipboard history

## Dependencies

- Walker package (≥1.5 for X11 file provider support)
- Elephant package (from flake input)
- i3 window manager with systemd user session integration
- X11 display server (not Wayland)
- i3pm daemon service running and responsive
- Ghostty terminal emulator
- Neovim text editor
- Firefox browser
- xclip for clipboard operations
- systemd user session for service management

## Out of Scope

- Wayland support (explicitly using X11)
- Running Elephant as system service (must be user service)
- Integrating with clipboard managers other than Walker's built-in clipboard provider
- Custom search engine configuration UI (configured via TOML file only)
- File search in directories outside user's home directory and active project directory
- Clipboard history persistence across reboots (ephemeral only)
- Calculator support for advanced functions (trigonometry, logarithms, etc.)
- Symbol picker support for custom symbol sets
- Shell command history or auto-completion in runner provider
- Notification when Elephant service crashes (systemd handles auto-restart silently)

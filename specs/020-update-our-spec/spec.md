# Feature Specification: App Discovery & Auto-Classification System

**Feature Branch**: `020-update-our-spec`
**Created**: 2025-10-21
**Status**: Draft
**Input**: User description: "update our spec to reflect the above functionality"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pattern-Based Auto-Classification (Priority: P1)

A developer has 20 Progressive Web Apps (PWAs) installed with window classes like `pwa-youtube`, `pwa-spotify`, `pwa-slack`. Instead of manually classifying each PWA as "global" (visible across all projects), they want to create a single pattern rule `pwa-*` → global that automatically classifies any app matching this pattern.

**Why this priority**: Foundation for all other enhancements. Simplest to implement (80% code exists), no external dependencies, delivers immediate value by reducing manual classification work from 20 actions to 1 pattern rule.

**Independent Test**: Can be fully tested by creating a pattern rule `pwa-*` → global, launching 3 PWAs, verifying all are automatically classified as global without manual intervention.

**Acceptance Scenarios**:

1. **Given** user has 5 PWAs installed (pwa-youtube, pwa-spotify, pwa-gmail, pwa-calendar, pwa-drive), **When** user creates pattern rule `pwa-*` → global, **Then** all 5 PWAs are automatically classified as global and remain visible when switching between projects
2. **Given** user has pattern `terminal-*` → scoped and launches terminal-alacritty, **When** user tests pattern with `i3pm app-classes test-pattern 'terminal-alacritty'`, **Then** system shows "✓ Matches pattern 'terminal-*' → scoped (priority: 50)"
3. **Given** user has pattern `*` → global (priority 10) and explicit entry "Code" in scoped_classes list, **When** user launches VS Code, **Then** system classifies VS Code as scoped (explicit list wins over pattern)
4. **Given** user creates overlapping patterns `pwa-*` (priority 50) and `pwa-youtube` (priority 60), **When** user launches pwa-youtube, **Then** system uses higher-priority specific pattern (60)

---

### User Story 2 - Automated Window Class Detection (Priority: P2)

A developer discovers 50 applications without window class information (StartupWMClass missing from .desktop files). Instead of manually inspecting each app, they want to run a single command that automatically detects window classes by launching apps in an isolated virtual display (Xvfb) where the apps don't appear on screen or interfere with their work.

**Why this priority**: Automates tedious manual work. Builds on pattern foundation. Enables wizard to have complete data. Medium complexity with existing scaffold code.

**Independent Test**: Can be fully tested by running `i3pm app-classes detect --isolated firefox` and verifying system launches Firefox in Xvfb, detects WM_CLASS "firefox" within 10 seconds, and cleans up all processes.

**Acceptance Scenarios**:

1. **Given** user has Xvfb installed and app "firefox" without WM_CLASS, **When** user runs `i3pm app-classes detect --isolated firefox`, **Then** system launches Firefox in virtual display, detects WM_CLASS "firefox", displays result, terminates Firefox process, and cleans up Xvfb resources
2. **Given** user has 10 apps without WM_CLASS, **When** user runs `i3pm app-classes detect --isolated --all-missing`, **Then** system detects all 10 apps in parallel (max 3 concurrent), shows progress percentage, completes in under 60 seconds
3. **Given** user does not have Xvfb installed, **When** user runs isolated detection command, **Then** system shows error "xvfb-run not found. Install with: nix-env -iA nixpkgs.xvfb" and falls back to guessing algorithm
4. **Given** detection timeout expires after 10 seconds, **When** slow app hasn't created window yet, **Then** system terminates app gracefully (SIGTERM then SIGKILL), logs timeout error, and continues with next app

---

### User Story 3 - Interactive Classification Wizard (Priority: P2)

A new i3pm user has 50 discovered applications that need classification as either "scoped" (project-specific, like editors and terminals) or "global" (visible across all projects, like browsers). Instead of manually editing JSON files, they want a visual interface where they can review apps with suggested classifications, accept/reject suggestions using keyboard shortcuts, and complete classification in under 5 minutes.

**Why this priority**: Dramatically improves new user experience. Removes need to understand JSON schema. Discovers 90% of features through exploration. Depends on patterns and detection working first.

**Independent Test**: Can be fully tested by running `i3pm app-classes wizard`, navigating 15 apps with arrow keys, pressing 's' for scoped and 'g' for global, pressing 'A' to accept all suggestions, and verifying all classifications saved to config file.

**Acceptance Scenarios**:

1. **Given** user runs `i3pm app-classes wizard` for first time, **When** wizard displays 15 discovered apps in table format, **Then** user sees columns (Name, Exec, WM Class, Suggestion, Status) with syntax highlighting, can navigate with arrow keys, and see suggestions with confidence percentages
2. **Given** wizard shows app "Alacritty" with suggestion "scoped" (confidence 85%), **When** user presses 's' key, **Then** app is immediately classified as scoped with visual confirmation (green checkmark), and system updates internal state without saving to disk yet
3. **Given** user has classified 10 apps and accidentally marked Firefox as scoped, **When** user presses 'u' for undo, **Then** Firefox classification reverts to previous state (unknown), undo stack preserves up to 20 actions, and user can reclassify correctly
4. **Given** wizard shows 10 apps with high-confidence suggestions (>80%), **When** user presses 'A' to accept all suggestions, **Then** all 10 apps classified according to suggestions, changes summary displayed, user confirms save with 's' key, system writes to app-classes.json atomically (temp file + rename), and daemon reloads configuration automatically

---

### User Story 4 - Real-Time Window Inspection (Priority: P3)

A developer notices a window isn't being classified correctly and wants to understand why. They want to press a keybinding (Win+I), click on the problematic window, and immediately see all window properties (WM_CLASS, instance, title, marks, workspace), current classification status, suggested classification with reasoning, and ability to classify directly without opening configuration files.

**Why this priority**: Essential for troubleshooting but not required for basic operation. Most powerful after patterns, detection, and wizard are working. Helps users understand the system's decisions.

**Independent Test**: Can be fully tested by pressing Win+I keybinding, clicking on VS Code window, verifying inspector shows WM_CLASS "Code", classification status "scoped", source "explicit list", and ability to reclassify with 'g' key for global.

**Acceptance Scenarios**:

1. **Given** user has unknown window open and presses Win+I keybinding, **When** cursor changes to crosshair and user clicks the window, **Then** inspector TUI opens immediately showing comprehensive window properties, current classification status with source (explicit/pattern/heuristic/unknown), suggested classification with reasoning (matched categories, keywords), and action keys (s=scoped, g=global, p=create pattern, q=quit)
2. **Given** user focuses VS Code window and presses Win+I, **When** inspector launches without requiring click, **Then** inspector shows VS Code properties, classification "scoped", source "explicit list: Code in scoped_classes", suggests keeping as scoped with reasoning "Category: Development, matched keywords: code, editor"
3. **Given** user inspects Chrome window with WM_CLASS "Google-chrome", **When** user sees 3 other Chrome windows listed in "related apps" section, **Then** user presses 'G' key to classify all as global, system shows confirmation "Apply classification to 4 windows with WM_CLASS 'Google-chrome'?", user confirms with Enter, all 4 windows classified as global, saved atomically, and daemon reloaded
4. **Given** inspector shows window with title that changes frequently (terminal), **When** window title changes from "bash" to "vim file.txt", **Then** inspector auto-refreshes properties display (1-second interval), highlights changed fields in yellow for 2 seconds, preserves classification status, and logs change in history panel

---

### Edge Cases

- **What happens when pattern has invalid regex syntax?** System validates pattern on add/edit, shows clear error message "Invalid regex syntax at position 15: unclosed group '('", prevents saving invalid pattern, suggests correction
- **What happens when Xvfb detection fails for app?** System logs detailed error to `~/.cache/i3pm/detection-failures.log`, falls back to guessing algorithm, shows warning icon in wizard next to app, allows manual WM_CLASS input
- **What happens when two patterns with same priority match same window?** System warns user on pattern add "Pattern conflicts with existing pattern 'terminal-*' (same priority 50)", uses first-match rule (pattern added first wins), logs warning to systemd journal
- **What happens when user creates pattern that matches everything (`*`)?** System allows pattern but warns "Pattern '*' will match all apps. Ensure higher-priority patterns exist for exceptions." Validates that explicit scoped_classes/global_classes lists take precedence
- **What happens when wizard has 1000+ apps to display?** System uses virtual scrolling (only renders visible rows), lazy-loads app details on selection, maintains <50ms responsiveness, shows count "Showing 50 of 1,247 apps (filter active)"
- **What happens when user changes app-classes.json while wizard is open?** System detects file modification via mtime check, shows modal dialog "Configuration changed externally. Reload (discard changes) | Merge | Overwrite?", preserves user's current work in undo stack
- **What happens when isolated detection launches app that won't close?** System sends SIGTERM after 10s timeout, waits 1s for graceful shutdown, sends SIGKILL if still running, cleans up Xvfb lock files and sockets, logs stubborn app to detection log
- **What happens when user inspects window that closes during inspection?** System detects window destruction via i3 IPC window::close event, shows message "Window closed during inspection", displays last-known properties in read-only mode, allows creating classification rule based on last-known WM_CLASS
- **What happens during i3 restart while wizard is saving changes?** System buffers write operation, detects i3 IPC socket disconnect, waits for reconnection (up to 5 seconds), retries daemon reload after reconnection succeeds, shows progress "Waiting for i3 to restart..."
- **What happens when pattern matches but conflicts with explicit classification?** Explicit lists (scoped_classes, global_classes) always win over patterns. Pattern `Code` → global is ignored if "Code" exists in scoped_classes. Inspector shows "Classification: scoped (explicit list overrides pattern 'Code' → global)"

## Requirements *(mandatory)*

### Functional Requirements

**Pattern-Based Classification**:

- **FR-073**: System MUST support glob pattern syntax for window class matching including wildcards (`*`), single-character wildcard (`?`), character classes (`[abc]`), and brace expansion (`{foo,bar}`)
- **FR-074**: System MUST support regex pattern syntax with explicit prefix (`regex:^pwa-.*$`) using Python re module flavor with flags for case-insensitive and multiline matching
- **FR-075**: System MUST store patterns in app-classes.json under class_patterns key with structure containing pattern, classification, priority (0-100), description, and enabled flag
- **FR-076**: System MUST evaluate patterns in precedence order: explicit scoped_classes/global_classes lists (highest priority), then patterns by priority value (highest first), then heuristics (lowest priority)
- **FR-077**: System MUST default to glob syntax when no prefix specified, case-insensitive matching by default with opt-in case-sensitive flag in pattern metadata
- **FR-078**: System MUST cache compiled patterns in memory for performance, achieving sub-1ms matching time per window even with 100+ patterns
- **FR-079**: System MUST validate pattern syntax on add/edit operations, reject invalid patterns with error message showing specific syntax issue and character position
- **FR-080**: System MUST detect conflicting patterns (same priority, overlapping matches) and warn user during add/edit operation
- **FR-081**: System MUST provide CLI commands for pattern management: add-pattern, list-patterns, remove-pattern, edit-pattern, test-pattern with appropriate flags and arguments
- **FR-082**: System MUST reload daemon pattern cache automatically when app-classes.json modified, using file modification time check or inotify watch

**Automated Window Class Detection**:

- **FR-083**: System MUST check for required dependencies (xvfb-run, xdotool, xprop) before attempting isolated detection and show actionable error if missing
- **FR-084**: System MUST launch apps in isolated Xvfb virtual display using xvfb-run with auto-display-allocation to avoid display conflicts
- **FR-085**: System MUST use default framebuffer size 1920x1080x24 with customization option for apps requiring specific display dimensions
- **FR-086**: System MUST wait for window to appear using polling at 100ms intervals, timeout after configurable duration (default 10 seconds), retry up to 3 times on transient failures
- **FR-087**: System MUST extract WM_CLASS property using xprop command, parse second field (class name), handle malformed WM_CLASS gracefully
- **FR-088**: System MUST terminate launched app gracefully: send SIGTERM, wait 1 second, send SIGKILL if still running, verify process exit
- **FR-089**: System MUST clean up all resources on success, timeout, error, and user interruption: kill app process, remove Xvfb lock files, remove temporary sockets
- **FR-090**: System MUST provide CLI command for detection with options for isolated mode, timeout, bulk detection, dry-run, and verbose output
- **FR-091**: System MUST cache detection results with timestamp, invalidate after 30 days or on app version change
- **FR-092**: System MUST fall back to guess algorithm if Xvfb unavailable, detection fails, or user specifies skip-isolated flag
- **FR-093**: System MUST show progress indication during detection displaying current step and status
- **FR-094**: System MUST log all detection attempts (success and failure) with timestamp, app name, detected class, duration, and errors

**Interactive Classification Wizard**:

- **FR-095**: System MUST launch wizard with command supporting filter options, sort options, and auto-accept flag
- **FR-096**: System MUST display apps in table format with columns for Name, Exec Command, WM Class, Suggestion, and Status, sortable by column header
- **FR-097**: System MUST use semantic color scheme: scoped=green, global=blue, unknown=yellow, error=red, with brightness indicating confidence
- **FR-098**: System MUST show status icons for classification state using standard Unicode glyphs
- **FR-099**: System MUST support keyboard navigation: arrow keys, Page Up/Page Down, Home/End, Tab for panel switching, slash for filter search
- **FR-100**: System MUST support selection keys: Space for toggle, Enter for approve and next, Shift+arrows for multi-select range
- **FR-101**: System MUST support action keys: s=scoped, g=global, u=unknown, p=create pattern, d=detect now, i=inspect details
- **FR-102**: System MUST support bulk action keys: A=accept all suggestions, R=reject all, S=accept selected, I=invert selection
- **FR-103**: System MUST show detail panel displaying desktop file fields, classification source, suggestion reasoning, confidence, and related apps
- **FR-104**: System MUST provide undo stack preserving last 20 actions with undo and redo functionality showing action descriptions
- **FR-105**: System MUST validate changes before save: detect duplicates, conflicts, show validation errors with fix suggestions
- **FR-106**: System MUST save changes with confirmation dialog, atomic write, daemon reload, and success notification
- **FR-107**: System MUST provide quit options: save and exit, discard and exit, emergency exit
- **FR-108**: System MUST detect external file modification, show modal dialog with reload/merge/overwrite options, preserve current work
- **FR-109**: System MUST handle large datasets using virtual scrolling, lazy-loading, maintaining sub-50ms responsiveness
- **FR-110**: System MUST handle empty states gracefully with helpful messages and next action suggestions

**Real-Time Window Inspection**:

- **FR-111**: System MUST provide CLI command for inspection with selection mode options, output format options, and live monitoring flag
- **FR-112**: System MUST support window selection modes: click (with crosshair cursor), focused (current window), by-ID (specific window)
- **FR-113**: System MUST display comprehensive window properties including WM_CLASS, title, role, instance, type, PID, i3 metadata, and geometry
- **FR-114**: System MUST display classification status with source showing precedence chain
- **FR-115**: System MUST display suggested classification with detailed reasoning including matched categories and keywords
- **FR-116**: System MUST display related apps section showing other windows with same WM_CLASS
- **FR-117**: System MUST support direct classification actions for current window and all related windows
- **FR-118**: System MUST show confirmation for bulk classification actions
- **FR-119**: System MUST save classification changes immediately with atomic write, backup, daemon reload, and confirmation
- **FR-120**: System MUST provide live monitoring mode subscribing to window events, auto-refreshing display, highlighting changes
- **FR-121**: System MUST highlight selected window with customizable border color and restore on exit
- **FR-122**: System MUST handle edge cases: window closes during inspection, invalid window ID, with appropriate error messages and fallback behavior

**Cross-Enhancement Integration**:

- **FR-123**: System MUST reload daemon configuration when app-classes.json changes via any enhancement
- **FR-124**: System MUST use consistent CLI command hierarchy under i3pm app-classes namespace
- **FR-125**: System MUST support shared CLI options: verbose, json, dry-run across all subcommands
- **FR-126**: System MUST expose JSON-RPC methods for daemon communication: get_classification, reload_app_classes, test_pattern
- **FR-127**: System MUST use consistent terminology: scoped, global, pattern, WM_CLASS throughout interface
- **FR-128**: System MUST use consistent keybindings across TUI modes
- **FR-129**: System MUST use consistent color scheme across CLI/TUI/notifications with specific color values
- **FR-130**: System MUST validate app-classes.json schema on daemon load, rejecting invalid files with detailed error log

**Testing & Validation**:

- **FR-131**: System MUST provide unit tests for pattern matching achieving 80% code coverage minimum
- **FR-132**: System MUST provide integration tests for complete workflows validating end-to-end functionality
- **FR-133**: System MUST provide automated TUI tests for keyboard navigation and user interactions
- **FR-134**: System MUST provide Xvfb detection tests with mocked dependencies requiring no live X server in CI
- **FR-135**: System MUST provide user acceptance tests for each enhancement with defined pass criteria

### Key Entities

- **Pattern Rule**: Represents a classification rule with pattern string, classification type, priority value, description text, enabled state, created timestamp, and last matched timestamp

- **Detection Result**: Represents output of automated detection with app name, detected class, detection method, confidence percentage, timestamp, duration, and error list

- **App Classification**: Extended classification information with source indicator, matched pattern reference, confidence score, and last updated timestamp

- **Wizard State**: Ephemeral session state with app list, classification decisions, undo stack, active filters, sort configuration, and dirty flag

- **Inspector Session**: Ephemeral inspection state with target window reference, property snapshot, classification status, suggestion data, related windows list, and change history

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-021**: Users can create pattern rule and have it automatically classify all matching apps in under 30 seconds
- **SC-022**: Users can run isolated detection for 10 apps and complete in under 60 seconds with 95% success rate
- **SC-023**: New users can complete wizard workflow classifying 50 apps in under 5 minutes on first attempt without documentation
- **SC-024**: Users can inspect any window and understand its classification status in under 10 seconds
- **SC-025**: Pattern matching performance stays under 1ms per window evaluation even with 100+ patterns and 1000+ open windows
- **SC-026**: Wizard TUI responds to all keyboard inputs in under 50ms providing immediate visual feedback
- **SC-027**: Xvfb detection cleanup is 100% reliable with zero zombie processes or lock files after 1000 detection runs
- **SC-028**: 90% of users discover key features through TUI exploration without reading documentation
- **SC-029**: System maintains 100% data integrity with zero classification loss during concurrent operations
- **SC-030**: Users correctly classify 95% of common applications on first attempt using wizard suggestions

### User Satisfaction Metrics

- **SC-031**: Users prefer wizard over manual JSON editing in 95% of cases when measured by voluntary usage
- **SC-032**: 90% of pattern rules work correctly without modification after creation
- **SC-033**: Users successfully troubleshoot 80% of classification issues using inspector without consulting documentation
- **SC-034**: Zero manual window marking required for apps classified via patterns

### UX/Interface Metrics

- **SC-035**: Wizard presents clear, actionable next steps in 100% of UI states
- **SC-036**: Error messages include remediation steps in 100% of failure cases
- **SC-037**: Inspector displays property changes within 100ms of window modification in live mode
- **SC-038**: Pattern test command provides immediate feedback showing match result and explanation
- **SC-039**: CLI commands provide formatted output that renders correctly in 95% of terminals
- **SC-040**: Undo functionality works reliably for 100% of reversible actions up to 20-action stack depth

## Assumptions

1. **Xvfb availability**: Assumes Xvfb is available via NixOS package manager and user can install it when needed. Detection gracefully degrades to guessing if unavailable.
2. **X11 windowing**: Assumes i3 window manager uses X11 (not Wayland) where Xvfb, xdotool, xprop tools function correctly. Wayland support is out of scope.
3. **Desktop file standards**: Assumes desktop files follow freedesktop.org Desktop Entry Specification version 1.5 with consistent fields.
4. **Pattern syntax compatibility**: Assumes Python fnmatch and re modules provide sufficient expressiveness for window class matching.
5. **File system atomicity**: Assumes POSIX file systems support atomic rename operations for safe concurrent configuration updates.
6. **Daemon responsiveness**: Assumes JSON-RPC daemon responds to reload requests within 100ms making immediate classification updates practical.
7. **Terminal capabilities**: Assumes terminal emulator supports ANSI color codes, UTF-8 glyphs, and minimum 80x24 character display for TUI rendering.
8. **Single i3pm instance**: Assumes single user running one wizard/inspector session at a time. Concurrent sessions may conflict without file locking.
9. **WM_CLASS stability**: Assumes application WM_CLASS values remain consistent across launches and versions. Detection caching relies on this stability.
10. **User familiarity with i3wm**: Assumes users understand basic i3 concepts (workspaces, window classes, marks) before using advanced classification features. Wizard provides inline help for terminology.

# Feature Specification: Event-Based i3 Project Synchronization

**Feature Branch**: `015-create-a-new`
**Created**: 2025-10-20
**Status**: Draft
**Input**: User description: "create a new feature that uses an event based subscription model to synchronize our i3 state of workspaces/windows, etc. and our created construct, projects. review i3's documentation around docs/i3-ipc.txt and commands i3_man.txt and determine if there is functionality within our project management approach that would be more reliable and better at synchronizing state by using the subscription based api's, and, if so, replace the logic. make sure to thoroughly test."

**Additional Requirement**: "when using the i3 workspace construct, we want to treat several applications, pwa's and terminal based applications, as though they were distinct applications (with desktop files). for examples, lazygit is a terminal based program that we run within ghostty. i3 typically would treat a ghostty terminal (our default) the same as the application that is launched when we run lazygit (we have a corresponding desktop file and launch via rofi). this is not the behavior we want. we want lazygit to have a dedicated workspace, and treated as if it was a separate application such as vscode. this is also the behavior we want with firefox pwa based applications that we've created. an example of this is argocd or backstage. i3 would try to treat these pwa instances as if the were the same, and perhaps it wouldn't even make a distinction between a firefox instance and argocd/backstage pwa instances. we want clear distinction between these types, and the should each have desktop files and their own defined workspaces."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real-time Project State Updates (Priority: P1)

When a user switches projects, the system instantly reflects the change in all visual indicators and window states without delays, race conditions, or stale information.

**Why this priority**: This is the core reliability improvement. Currently, a 0.1-second sleep and manual signal-based updates create timing issues where the status bar may show incorrect project states, or windows may not hide/show correctly if the signal arrives before file writes complete.

**Independent Test**: Can be fully tested by switching between two projects rapidly (within 1 second) and verifying: (1) status bar always shows correct project, (2) all project-scoped windows hide/show correctly, (3) no orphaned windows remain visible from the old project.

**Acceptance Scenarios**:

1. **Given** user has NixOS project active, **When** user switches to Stacks project, **Then** status bar updates to show "Stacks" within 100ms without manual refresh
2. **Given** user switches projects rapidly 5 times in 2 seconds, **When** switching completes, **Then** status bar always shows the currently active project with no lag or stale state
3. **Given** VS Code windows are open in NixOS project, **When** user switches to Stacks project, **Then** all NixOS windows move to scratchpad before any Stacks windows appear (no visual overlap)
4. **Given** i3 restarts while a project is active, **When** i3 reconnects, **Then** the system automatically re-subscribes to events and status bar shows correct project state

---

### User Story 2 - Automatic Window Tracking (Priority: P2)

When a new project-scoped application window opens, the system automatically detects and associates it with the active project without requiring manual marking or polling.

**Why this priority**: Current implementation polls i3 tree every 0.5 seconds up to 20 times (10-second timeout) to detect new windows. Event-based detection would be instant and eliminate CPU waste from polling loops.

**Independent Test**: Can be tested independently by launching VS Code in a project context and verifying the window is marked with the project within 200ms without any visible polling delay.

**Acceptance Scenarios**:

1. **Given** NixOS project is active, **When** user launches VS Code via Win+C, **Then** the new window is automatically marked with "project:nixos" within 200ms
2. **Given** user opens 5 terminals simultaneously, **When** all windows appear, **Then** all windows are correctly associated with the active project without any unmarked windows
3. **Given** a window is manually moved to a different workspace, **When** the move completes, **Then** the system detects the workspace change event and maintains the project association
4. **Given** user manually marks a global application (Firefox) as project-scoped, **When** the mark is applied, **Then** the system detects this and begins tracking it as project-scoped

---

### User Story 3 - Workspace State Monitoring (Priority: P3)

When workspaces are created, destroyed, renamed, or moved between monitors, the project management system stays synchronized with i3's actual state without requiring manual refresh commands.

**Why this priority**: Supports multi-monitor workflows where workspace assignments can change dynamically. Currently requires manual Win+Shift+M to reassign workspaces. Event-based subscriptions would detect output changes automatically.

**Independent Test**: Can be tested by connecting/disconnecting an external monitor and verifying workspace assignments update automatically without manual intervention.

**Acceptance Scenarios**:

1. **Given** user has 2 monitors with workspaces 1-2 on primary and 3-9 on secondary, **When** user disconnects the secondary monitor, **Then** workspaces 3-9 automatically reassign to primary monitor
2. **Given** user creates a new workspace via i3 command, **When** the workspace is created, **Then** the project system detects it and applies appropriate project-scoped visibility rules
3. **Given** workspace 5 is empty and user closes the last window, **When** i3 destroys the workspace, **Then** the project system removes any stale workspace references
4. **Given** user renames workspace 1 from "1" to "1:code", **When** rename completes, **Then** project system updates its workspace tracking to use the new name

---

### User Story 4 - Application Workspace Distinction (Priority: P2)

When a user launches terminal-based applications (like lazygit in ghostty) or Firefox PWAs (like ArgoCD, Backstage), each application instance is treated as a distinct application with its own workspace assignment, independent from the base application (ghostty terminal or Firefox browser).

**Why this priority**: Essential for workspace-based workflow organization. Without proper distinction, i3wm treats all ghostty terminals identically (by WM_CLASS) and all Firefox PWAs as Firefox instances, preventing dedicated workspace assignments and breaking application-specific workspace routing. This undermines the core value of workspace isolation.

**Independent Test**: Can be tested by launching lazygit (via rofi desktop file) and a regular ghostty terminal simultaneously, then verifying they are recognized as separate applications with distinct workspace assignments, not grouped together as "ghostty".

**Acceptance Scenarios**:

1. **Given** user has a desktop file for lazygit that launches ghostty with lazygit, **When** user launches lazygit via Win+D (rofi), **Then** the window is identified as "lazygit" (not "ghostty") and assigned to the lazygit workspace
2. **Given** user has ArgoCD PWA and Backstage PWA installed, **When** user launches ArgoCD via rofi, **Then** ArgoCD opens in its dedicated workspace, distinct from Firefox and other PWAs
3. **Given** user launches both lazygit and a regular ghostty terminal, **When** both windows are open, **Then** i3 treats them as separate applications with different workspace assignments
4. **Given** user has Firefox browser and ArgoCD PWA both running, **When** user switches workspaces, **Then** Firefox and ArgoCD remain in their respective workspaces, not grouped together
5. **Given** user relaunches a terminal-based app (lazygit) while it's already running, **When** the new window appears, **Then** the system directs it to the same workspace as the existing lazygit instance (not to a generic terminal workspace)
6. **Given** user has multiple PWAs (ArgoCD, Backstage, YouTube), **When** all are launched, **Then** each PWA occupies its own workspace and is treated as a unique application in workspace naming and routing

---

### Edge Cases

- What happens when the i3 IPC socket becomes unavailable (i3 restart or crash)?
  - System should gracefully handle disconnection, attempt reconnection, and re-subscribe to events automatically
  - Status bar should show a visual indicator (e.g., "⚠ Reconnecting...") during disconnection periods

- How does the system handle event subscription failures?
  - Initial subscription failure should retry with exponential backoff (100ms, 200ms, 400ms, max 2s)
  - After 5 failed attempts, log error and fall back to polling mode temporarily
  - Successful reconnection should restore event-based mode

- What happens when multiple windows of the same class open simultaneously?
  - Each "window::new" event should be processed sequentially to avoid race conditions
  - Window-to-project mapping file must use atomic writes (temp file + rename pattern)

- How does the system handle events arriving out of order?
  - Event timestamps should be used to detect and discard stale events
  - State updates should be idempotent (applying the same event twice has no adverse effects)

- What happens when a user manually changes a window's project mark via i3-msg?
  - System should detect the "binding::run" event for mark changes and update internal tracking
  - Manual mark changes should trigger window visibility updates if the mark conflicts with current project

- How does the system handle very rapid project switches (e.g., 10 switches in 1 second)?
  - Event queue should process switches sequentially with debouncing (ignore intermediate switches if final state is known)
  - Only the final target project should trigger full show/hide window operations

- How does the system distinguish terminal-based applications from regular terminals?
  - System should use window title, WM_INSTANCE, or custom window properties to differentiate
  - Desktop files should set distinguishing metadata (e.g., StartupWMClass) that the system can detect
  - If metadata is unavailable, system should use window title pattern matching as fallback

- How does the system distinguish PWA instances from regular Firefox windows?
  - Firefox PWAs typically set WM_INSTANCE to the PWA name (e.g., "argocd", "backstage")
  - System should prioritize WM_INSTANCE over WM_CLASS for Firefox windows
  - If WM_INSTANCE is unavailable, system should use window title matching against known PWA names

- What happens when a terminal-based app is launched directly (not via desktop file)?
  - System should attempt to identify the app by window title or process name
  - If identification succeeds, treat as the specific app (e.g., lazygit)
  - If identification fails, fall back to generic terminal treatment

- How does the system handle PWAs with identical WM_CLASS and WM_INSTANCE?
  - System should use window title as secondary identifier
  - Desktop files should declare expected window properties for validation
  - User should be able to manually mark windows with application-specific identifiers

## Requirements *(mandatory)*

### Functional Requirements

#### Event Subscription & Connection Management

- **FR-001**: System MUST establish an IPC connection to i3 on startup using the socket path from `i3 --get-socketpath` or `$I3SOCK` environment variable
- **FR-002**: System MUST subscribe to the following i3 event types: "window", "workspace", "tick", "shutdown"
- **FR-003**: System MUST automatically reconnect to i3 IPC socket if connection is lost, with exponential backoff retry logic (100ms, 200ms, 400ms, max 2s intervals)
- **FR-004**: System MUST re-subscribe to all required events after successful reconnection
- **FR-005**: System MUST gracefully handle i3 shutdown events by cleaning up resources and terminating the event listener process

#### Window Event Handling

- **FR-006**: System MUST detect "window::new" events and automatically mark new windows with the active project if the window's class matches a project-scoped application
- **FR-007**: System MUST detect "window::close" events and remove window-to-project mappings from in-memory state for closed windows
- **FR-008**: System MUST detect "window::move" events and verify window remains in the correct workspace for its associated project
- **FR-009**: System MUST detect "window::focus" events and notify subscribed clients (status bars, external tools) with the project context of the focused window
- **FR-010**: System MUST process window events within 100ms of receiving the event from i3 IPC

#### Workspace Event Handling

- **FR-011**: System MUST detect "workspace::init" events and apply project-scoped window visibility rules to newly created workspaces
- **FR-012**: System MUST detect "workspace::empty" events and clean up workspace-specific state when workspaces are destroyed
- **FR-013**: System MUST detect "workspace::focus" events and update window visibility based on the focused workspace's project context
- **FR-014**: System MUST detect "workspace::move" events when workspaces change outputs (monitors) and update workspace-to-output assignments

#### Project Switch Synchronization

- **FR-015**: System MUST detect custom "tick" events with payload "project:*" indicating a project switch has occurred
- **FR-016**: System MUST read the active project state file atomically after receiving a project switch tick event
- **FR-017**: System MUST hide all windows belonging to the previous project within 200ms of project switch event
- **FR-018**: System MUST show all windows belonging to the new project within 200ms of project switch event
- **FR-019**: System MUST update status bar display within 100ms of project switch event without requiring manual signals

#### State Management

- **FR-020**: System MUST maintain all runtime state in-memory within the event listener daemon (no file-based synchronization)
- **FR-021**: System MUST persist only project configuration to disk (user-defined project settings)
- **FR-022**: System MUST rebuild window-to-project mappings from i3 marks on daemon startup or reconnection
- **FR-023**: System MUST provide IPC interface for querying current state (active project, window mappings, subscription status)

#### Project Configuration & Interface

- **FR-024**: System MUST provide a streamlined project configuration format optimized for event-based architecture
- **FR-025**: System MUST support direct i3 mark-based window association without requiring intermediate tracking files
- **FR-026**: System MUST expose project state and event stream via a query API for external tools and status bars

#### Performance & Reliability

- **FR-027**: Event listener process MUST consume less than 5MB of memory during idle operation
- **FR-028**: Event processing MUST complete within 100ms for 95% of events (measured from event receipt to action completion)
- **FR-029**: System MUST handle at least 50 events per second without dropping events or degrading performance
- **FR-030**: System MUST log all errors with context (event type, timestamp, project state) to rotating log file with 10MB max size
- **FR-031**: System MUST provide real-time event monitoring interface for debugging and diagnostics

#### Testing & Validation

- **FR-032**: System MUST provide a test mode that simulates i3 events for validation without requiring actual i3 window manager
- **FR-033**: System MUST provide diagnostic commands to verify event subscription status and show last 50 received events
- **FR-034**: System MUST validate that all event handlers are registered before reporting "ready" status

#### Application Workspace Distinction

- **FR-035**: System MUST distinguish terminal-based applications (e.g., lazygit in ghostty) from base terminal windows using window metadata (WM_INSTANCE, WM_CLASS, window title, or custom properties)
- **FR-036**: System MUST distinguish Firefox PWA instances (e.g., ArgoCD, Backstage) from regular Firefox browser windows using WM_INSTANCE as primary identifier
- **FR-037**: System MUST support configurable application identification rules that map window properties to application identifiers
- **FR-038**: System MUST use hierarchical identification strategy: WM_INSTANCE → WM_CLASS → window title → process name → fallback to generic
- **FR-039**: System MUST assign workspace locations based on application identifier (not base application class)
- **FR-040**: System MUST support desktop file metadata declarations (StartupWMClass, custom properties) to assist in application identification
- **FR-041**: System MUST allow manual window marking with application identifiers when automatic detection fails
- **FR-042**: System MUST treat each unique application identifier as a distinct application for workspace naming (via i3wsr) and workspace routing
- **FR-043**: System MUST prevent grouping of terminal-based apps with generic terminals in workspace labels (e.g., "lazygit" workspace, not "ghostty" workspace)
- **FR-044**: System MUST prevent grouping of PWAs with Firefox browser in workspace labels (e.g., "argocd" workspace, not "firefox" workspace)

### Key Entities

- **Event Listener Daemon**: Long-running background process that maintains IPC connection to i3 and processes events in real-time
  - Attributes: PID, socket path, subscription status, last heartbeat timestamp, event queue depth
  - Lifecycle: Started on i3 startup, stopped on i3 shutdown, auto-restarts on crash

- **Window-Project Mapping**: In-memory registry of which windows belong to which projects
  - Attributes: window ID (X11 ID), container ID (i3 internal), project name, WM class, registration timestamp
  - Persistence: None - rebuilt from i3 marks on daemon start
  - Source of truth: i3 window marks (format: "project:projectname")

- **Event Queue**: In-memory buffer for events awaiting processing
  - Attributes: event type, event payload, timestamp, processing status
  - Capacity: 1000 events (oldest dropped if full to prevent memory exhaustion)

- **Subscription State**: Tracks which i3 events are currently subscribed
  - Attributes: event type array, subscription timestamp, connection status
  - Used for: Reconnection logic (must re-subscribe on reconnect)

- **Application Identifier**: Unique identifier for applications that may share the same WM_CLASS
  - Attributes: identifier name (e.g., "lazygit", "argocd"), matching rules (WM_INSTANCE patterns, window title regex, process name), workspace assignment, desktop file path
  - Source of truth: User configuration files defining identification rules
  - Examples: lazygit (ghostty with "lazygit" in title), argocd (firefox with WM_INSTANCE="argocd")

- **Application Identification Rules**: Configuration mapping window properties to application identifiers
  - Attributes: rule priority, property type (WM_INSTANCE, WM_CLASS, title, process), pattern (string or regex), target application identifier
  - Hierarchy: WM_INSTANCE (highest priority) → WM_CLASS → window title → process name (lowest priority)
  - Storage: JSON/TOML configuration files in `~/.config/i3/app-identification/`

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Project switches complete with status bar fully updated within 200ms (measured from Win+P keystroke to visible status bar change)
- **SC-002**: New window detection and marking occurs within 200ms of window creation (eliminates current 0.5-10 second polling delay)
- **SC-003**: Zero observable race conditions during rapid project switching (tested with 10 project switches within 5 seconds)
- **SC-004**: System successfully reconnects to i3 IPC within 500ms after simulated i3 restart
- **SC-005**: Event listener daemon runs continuously for 7+ days without memory leaks (memory usage remains under 10MB)
- **SC-006**: 100% of window events are processed (verified by comparing event count from i3 logs vs. processed event count in system logs)
- **SC-007**: Status bar never shows incorrect project state for more than 100ms during normal operation
- **SC-008**: System handles monitor connect/disconnect events and reassigns workspaces automatically within 1 second
- **SC-009**: Terminal-based applications launched via desktop files are correctly identified and assigned to dedicated workspaces 100% of the time (tested with lazygit, yazi)
- **SC-010**: Firefox PWA instances are correctly distinguished from Firefox browser windows and from each other 100% of the time (tested with ArgoCD, Backstage, YouTube PWAs)
- **SC-011**: Workspace labels correctly reflect application identifiers (e.g., "1:lazygit", "2:argocd") not base application classes (e.g., "1:ghostty", "2:firefox")

### Qualitative Outcomes

- **SC-012**: Users perceive project switching as instantaneous with no visible delay between action and visual feedback
- **SC-013**: System behavior is predictable and deterministic (same actions always produce same results)
- **SC-014**: Error messages clearly explain what went wrong and suggest corrective actions (e.g., "i3 connection lost - attempting reconnection...")
- **SC-015**: Users can easily distinguish between similar applications in workspace labels (lazygit vs terminal, ArgoCD vs Firefox)
- **SC-016**: Application identification works consistently regardless of launch method (rofi, command line, i3 exec)

## Implementation Constraints

### Technical Constraints

- **TC-001**: Solution must use i3 IPC protocol as documented in `/etc/nixos/docs/i3-ipc.txt` (no protocol modifications)
- **TC-002**: Solution must be implemented in Bash or Python (to match existing tooling and avoid introducing new language dependencies)
- **TC-003**: Solution must work with i3 version 4.20+ (current stable version as of 2024)
- **TC-004**: Event listener daemon must be managed as a systemd user service for proper lifecycle management

### Architecture Constraints

- **TC-005**: System architecture should prioritize event-driven design over file-based state synchronization
- **TC-006**: Status bar integration should use native event subscriptions rather than polling or signal-based updates
- **TC-007**: Window management should leverage i3 marks as the primary tracking mechanism

### Deployment Constraints

- **TC-008**: Must be deployable via home-manager NixOS module (declarative configuration)
- **TC-009**: Must not require root privileges to run (runs as user's systemd service)
- **TC-010**: System should start automatically with i3 session and handle crashes gracefully

## Assumptions

1. **i3 IPC is stable**: Assumes i3's IPC protocol is stable and reliable for long-running connections (industry-standard assumption for i3 tooling)
2. **Event ordering**: Assumes i3 delivers events in the order they occur (documented i3 behavior)
3. **Single i3 instance**: Assumes only one i3 window manager instance is running per user (standard i3 deployment)
4. **Network reliability**: Assumes UNIX domain sockets provide reliable, in-order delivery (kernel guarantee)
5. **Event completeness**: Assumes i3 emits events for all relevant state changes (documented i3 behavior)
6. **Clean slate**: Assumes this is a greenfield implementation that can redesign project management architecture from scratch without preserving legacy behaviors
7. **Window properties available**: Assumes applications set window properties (WM_CLASS, WM_INSTANCE, title) at window creation time (X11/Wayland standard)
8. **Desktop file metadata**: Assumes desktop files for terminal-based apps and PWAs declare appropriate metadata (StartupWMClass or equivalent) for identification
9. **Unique identifiers**: Assumes application identifiers can be uniquely determined through combination of window properties (no two different apps with identical WM_CLASS, WM_INSTANCE, and title patterns)
10. **i3wsr integration**: Assumes i3wsr (workspace renamer) can be configured to use application identifiers from the daemon for workspace naming

## Out of Scope

1. **Multi-user support**: This feature manages projects for a single user session only
2. **Remote i3 instances**: Only supports local i3 IPC connections via UNIX sockets (not TCP)
3. **Event replay**: Does not provide functionality to replay historical events from logs
4. **Custom event types**: Does not add new event types beyond what i3 provides
5. **Window content inspection**: Only tracks window metadata (class, title, workspace), not window contents
6. **Backward compatibility**: Does not preserve compatibility with existing project management scripts or configuration formats
7. **Migration tooling**: Does not provide automated migration from current implementation (users must manually reconfigure projects)

## Dependencies

- **i3 window manager** v4.20 or higher with IPC support enabled (default)
- **systemd** for managing event listener daemon lifecycle
- **Modern scripting language** with native JSON support and async I/O capabilities (Python 3.8+, or other suitable language)
- **No file-based state synchronization**: State maintained entirely in-memory within event listener daemon

## Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| i3 IPC connection fails intermittently | High - Status bar shows wrong state | Medium | Implement auto-reconnect with exponential backoff; rebuild state from i3 marks on reconnection |
| Event processing too slow for rapid window creation | Medium - Some windows not marked | Low | Queue events and process in batches; prioritize window::new events |
| Memory leak in long-running daemon | High - System becomes unresponsive | Medium | Implement memory monitoring; auto-restart daemon if memory exceeds 50MB |
| Breaking changes in i3 IPC protocol | High - System stops working | Very Low | Document supported i3 versions; add protocol version detection on startup |
| State loss on daemon crash | Medium - Window marks remain but in-memory state lost | Low | Rebuild complete state from i3 marks and window tree on daemon restart |
| User disables systemd service | Low - Events not processed | Low | Detect missing daemon and provide clear instructions to re-enable |
| Migration complexity from existing system | High - Users must reconfigure projects | High | Provide clear migration guide and example configurations for common setups |
| Application identification fails (missing window properties) | Medium - Apps grouped incorrectly | Medium | Implement fallback hierarchy (WM_INSTANCE → title → process); allow manual override via window marks |
| Desktop files lack proper StartupWMClass metadata | Medium - Terminal apps not distinguished | Medium | Provide desktop file templates with correct metadata; document best practices for custom desktop files |
| PWAs with identical WM_INSTANCE | Low - PWAs grouped together | Low | Use window title as secondary identifier; document PWA installation requirements |
| Window properties change after window creation | Low - Misidentification after launch | Very Low | Re-evaluate window properties on window title change events; allow re-identification triggers |

## References

- i3 IPC Documentation: `/etc/nixos/docs/i3-ipc.txt`
- i3 Man Page: `/etc/nixos/i3_man.txt`
- Current Implementation: `/etc/nixos/home-modules/desktop/i3-project-manager.nix`
- Window Hook Script: `/etc/nixos/scripts/project-switch-hook.sh`
- i3blocks Integration: `/etc/nixos/home-modules/desktop/i3blocks/scripts/project.sh`

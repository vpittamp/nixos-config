# Feature Specification: Multi-Session Remote Desktop & Web Application Launcher

**Feature Branch**: `007-add-a-few`
**Created**: 2025-10-16
**Status**: Draft
**Input**: User description: "add a few other requirements that are important. fix the ability to connect to sessions from multiple devices. currently when i connect via microsoft remote desktop from one device, and then connect from naother device, it disconnects the first instance. although some of our base configurations are very important, we may consider starting from a known working configuration via online research if it's not easy enough to reuse our current "hetzner" based configuration that we started with. third, we want a solution for pwa items that we've previously used via firefoxpwa. we don't need to use this feature or pwa's neccessarily (although if it works well in our environment, then perhaps we should), but we need a solution to define urls that can act as "applications" in their own windows, searchable via our search feature (rolfi for instance) and other pwa related features (being able to integrate with 1password extension has been helpful, but may not be a strict requirement). Additional: alacritty should be the default terminal emulator. currently our terminal customizations, including tmux, sesh, bash, etc. that are configured via home-manager are working very well, so should keep this customization intact as much as possible, unless there is more native functionality that can replace. Clipboard history: create very robust clipboard history functionality using i3-native approaches; synchronize copied items from all applications (Firefox, VS Code, terminal, tmux, etc) and enable pasting into all these applications. Target environment: i3wm with declarative configuration pattern similar to activity-aware-apps-native.nix."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Concurrent Remote Desktop Access (Priority: P1)

A user needs to access their remote development workstation from multiple physical locations throughout the day - for example, starting work on their laptop, continuing from their desktop, and occasionally checking in from a tablet. Currently, each new connection terminates the previous session, forcing the user to close and reopen applications, losing window arrangements and workflow context.

**Why this priority**: This is the most critical issue as it directly blocks the user's ability to maintain productivity across multiple devices. Without this, the user experiences constant workflow interruption and context loss.

**Independent Test**: Can be fully tested by connecting via Microsoft Remote Desktop from two different devices sequentially and verifying both sessions remain active and independently usable.

**Acceptance Scenarios**:

1. **Given** a user is connected to the remote desktop from Device A, **When** they connect from Device B using Microsoft Remote Desktop, **Then** both sessions remain active and the user can interact with either session independently
2. **Given** a user has multiple active sessions from different devices, **When** they disconnect from one device, **Then** the other sessions remain unaffected and maintain their state
3. **Given** a user is connected from Device A with several applications open, **When** they connect from Device B, **Then** Device A's session preserves all open applications, window positions, and application state

---

### User Story 2 - Web Application Launcher System (Priority: P2)

A user wants to organize frequently-used web applications (like Gmail, Notion, Linear, etc.) as standalone desktop applications that can be launched quickly via keyboard shortcuts or application launcher (rofi). These should behave like native applications with their own windows, taskbar entries, and appear in the application search interface.

**Why this priority**: This significantly improves workflow efficiency by treating web applications as first-class desktop citizens, but the system remains usable without it. This is a productivity enhancement rather than a blocking issue.

**Independent Test**: Can be fully tested by defining a list of web URLs, verifying they appear in rofi search, launching them into separate windows, and confirming they behave as independent applications.

**Acceptance Scenarios**:

1. **Given** a user has defined a list of web applications with URLs, **When** they search for an application name in rofi, **Then** the web application appears as a searchable entry alongside native applications
2. **Given** a user launches a web application, **When** the application opens, **Then** it appears in its own browser window with its own taskbar entry and window management controls
3. **Given** multiple web applications are open, **When** the user switches between them using Alt+Tab or taskbar, **Then** each application is treated as a separate window in the window manager
4. **Given** a web application supports browser extensions, **When** the user interacts with the application, **Then** browser extensions (like 1Password) function normally within that application window

---

### User Story 3 - Declarative Web Application Configuration (Priority: P3)

A user wants to define their web applications declaratively in their NixOS configuration so that application definitions are version-controlled, reproducible, and automatically configured when rebuilding the system. Changes to the application list should not require manual setup steps.

**Why this priority**: This provides the full benefits of NixOS declarative configuration but can be implemented after the basic launcher functionality works. Users can initially configure applications manually if needed.

**Independent Test**: Can be fully tested by adding a new web application to the NixOS configuration, rebuilding the system, and verifying the application appears in rofi without manual intervention.

**Acceptance Scenarios**:

1. **Given** a user adds a new web application definition to their NixOS configuration, **When** they rebuild the system, **Then** the new application automatically appears in rofi search results
2. **Given** a user modifies a web application's properties (name, URL, icon), **When** they rebuild the system, **Then** the changes are reflected in the application launcher without manual cleanup of old configurations
3. **Given** a user removes a web application from their configuration, **When** they rebuild the system, **Then** the application no longer appears in search results and any associated desktop files are cleaned up

---

### Edge Cases

- What happens when a user exhausts available remote desktop session slots? System will automatically clean up sessions idle for >24 hours. If all slots full with active sessions, oldest session should be identified for user-initiated cleanup.
- How does the system handle network interruptions in remote desktop sessions? System will automatically attempt reconnection using exponential backoff strategy to prevent connection storms while providing seamless recovery.
- What happens if a web application URL becomes unavailable or returns an error? System will display a user-visible error message with a retry option, allowing immediate recovery without returning to the launcher.
- How does the system handle web applications that redirect to different URLs or require authentication flows?
- What happens when two web application definitions have the same name but different URLs?
- How are browser profiles managed when multiple web applications need different authentication states for the same domain?
- What happens when a user tries to launch a web application but no suitable browser is installed?
- How does 1Password authentication state persist across remote desktop session reconnections?
- What happens if the 1Password desktop application is not running when a web application needs the browser extension?
- How do web applications handle 1Password biometric authentication when connected via remote desktop?
- What happens to existing tmux sessions when switching terminal emulator to Alacritty?
- How does the system handle terminal configuration conflicts between Alacritty native features and existing home-manager tmux/sesh configurations?
- What happens if Alacritty is not available or fails to launch?
- What happens when clipboard history reaches its storage limit? System will automatically remove oldest entries (FIFO queue) to make room for new clipboard operations.
- How does clipboard history handle large copied content (images, large text blocks)?
- What happens when clipboard content contains sensitive information (passwords, keys)? System will use pattern-based filtering to avoid storing common sensitive patterns (e.g., "password:", API key formats) and provide manual clear functionality for user-initiated history cleanup.
- How does clipboard history synchronize between different remote desktop sessions?

## Requirements *(mandatory)*

### Functional Requirements

#### Multi-Session Remote Desktop

- **FR-001**: System MUST allow multiple simultaneous remote desktop connections from different devices without terminating existing sessions
- **FR-002**: System MUST provide each remote desktop session with an independent desktop environment, including separate window managers, taskbars, and application states
- **FR-003**: System MUST persist session state when a user disconnects, allowing them to reconnect to the same session later. Sessions MUST be automatically cleaned up after 24 hours of idle disconnection to prevent resource exhaustion
- **FR-004**: System MUST maintain session isolation so that actions in one session do not affect other concurrent sessions
- **FR-005**: System MUST support connection via Microsoft Remote Desktop client (RDP protocol)
- **FR-006**: System MUST support a hybrid session model where one user can have one primary session plus additional concurrent sessions as needed from different devices
- **FR-006a**: System MUST support a maximum of 3-5 concurrent remote desktop sessions per user to balance multi-device flexibility with resource management
- **FR-006b**: System MUST support user authentication via password, with optional SSH key-based authentication for advanced workflows
- **FR-006c**: System MUST implement automatic reconnection for network-interrupted sessions using exponential backoff strategy to prevent connection storms while providing seamless recovery

#### Web Application Launcher

- **FR-007**: System MUST provide a mechanism to define web applications by URL, name, and optional icon
- **FR-008**: System MUST launch web applications in separate browser windows (not tabs)
- **FR-009**: System MUST make web applications searchable via the system's application launcher (rofi)
- **FR-010**: System MUST display web applications with unique window manager entries (separate taskbar icons, Alt+Tab entries)
- **FR-011**: System MUST support browser extensions within web application windows (at least 1Password extension compatibility)
- **FR-012**: Web applications SHOULD maintain separate browser contexts to allow different authentication states for the same domain
- **FR-013**: System MUST support user-configurable lifecycle per web application where some applications can persist as running processes while others launch fresh each time
- **FR-013a**: System MUST display user-visible error messages when web application URLs are unavailable or return errors, providing a retry option for immediate recovery

#### Configuration Management

- **FR-014**: System MUST allow web applications to be defined declaratively in NixOS configuration files
- **FR-015**: System MUST apply web application configuration changes automatically during system rebuild without requiring manual cleanup or setup
- **FR-016**: System MUST remove web application launcher entries when they are removed from the configuration
- **FR-017**: System SHOULD leverage existing NixOS Hetzner configuration as the base where practical, but MAY adopt alternative well-documented configurations if significant compatibility issues arise
- **FR-018**: Configuration approach SHOULD follow the declarative scripting pattern used in existing activity-aware application modules (as demonstrated in home-modules/desktop/activity-aware-apps-native.nix), preferring declarative launcher scripts over imperative configuration where the desktop environment provides better native alternatives

#### 1Password Integration

- **FR-019**: System MUST maintain full compatibility with existing 1Password desktop application
- **FR-020**: System MUST maintain full compatibility with existing 1Password CLI (op) integration
- **FR-021**: System MUST preserve the integration between 1Password desktop and CLI that allows CLI operations to authenticate via the desktop application
- **FR-022**: Web applications MUST support 1Password browser extension functionality without requiring additional configuration beyond what currently exists
- **FR-023**: Remote desktop sessions MUST have access to 1Password functionality without requiring re-authentication in each session

#### Terminal Emulator

- **FR-024**: System MUST use Alacritty as the default terminal emulator
- **FR-025**: System MUST preserve all existing terminal customizations configured via home-manager, including tmux, sesh, bash configurations, and shell prompt customizations
- **FR-026**: Terminal emulator MUST integrate seamlessly with existing terminal workflow tools (tmux for session management, sesh for session switching)
- **FR-027**: System SHOULD leverage native terminal emulator features only when they provide superior functionality to existing home-manager configured tools, without disrupting current workflows

#### Clipboard History

- **FR-028**: System MUST provide robust clipboard history functionality that captures all copy operations from all applications
- **FR-029**: Clipboard history MUST synchronize copied items from Firefox, desktop applications, VS Code, Alacritty terminal, and tmux sessions
- **FR-030**: System MUST allow users to paste from clipboard history into all supported applications (Firefox, desktop applications, VS Code, Alacritty, tmux)
- **FR-031**: Clipboard history MUST be accessible via keyboard shortcut for quick selection and pasting
- **FR-032**: System SHOULD leverage i3wm-compatible native clipboard management solutions where available
- **FR-033**: Clipboard history MUST persist across application restarts but MAY be cleared on system reboot
- **FR-034**: System MUST support both X11 PRIMARY selection (middle-click paste) and CLIPBOARD selection (Ctrl+C/V) mechanisms
- **FR-034a**: Clipboard history MUST use FIFO (First-In-First-Out) queue strategy, automatically removing oldest entries when storage limit is reached
- **FR-034b**: Clipboard history MUST implement pattern-based filtering to prevent storing common sensitive content patterns (e.g., "password:", "api_key:", common key formats)
- **FR-034c**: System MUST provide manual clear functionality allowing users to immediately purge clipboard history when needed

### Key Entities

- **Remote Desktop Session**: Represents an active connection from a specific device to the remote workstation, maintaining independent state including open applications, window positions, and desktop environment settings
- **Web Application Definition**: Represents a configured web application with properties including name, URL, display icon, and optional browser profile or context information
- **Browser Context**: Represents an isolated browser environment for a web application, maintaining separate cookies, localStorage, and authentication state
- **Terminal Configuration**: Represents the declarative terminal environment setup including emulator settings, shell configuration (bash), multiplexer configuration (tmux), session manager (sesh), and prompt customizations
- **Clipboard Entry**: Represents a single copied item in clipboard history, including content, timestamp, source application, and selection type (PRIMARY vs CLIPBOARD)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can maintain at least 3 concurrent remote desktop sessions from different devices without any session being disconnected
- **SC-002**: Users can reconnect to a previously disconnected session and find all applications and windows in the same state they left them
- **SC-003**: Users can find and launch any configured web application via rofi search in under 5 seconds
- **SC-004**: Web applications launch in under 3 seconds from selection in the application launcher
- **SC-005**: Users can define a new web application in the configuration and have it available after system rebuild without additional manual steps
- **SC-006**: 1Password browser extension functions correctly in at least 95% of web application windows
- **SC-007**: Users can switch between multiple open web application windows using standard window management features (Alt+Tab, i3wm workspace navigation) with the same efficiency as native applications
- **SC-008**: 1Password CLI authentication via desktop application continues to work without any additional configuration or authentication steps
- **SC-009**: Users can access 1Password browser extension in web applications without re-authenticating after remote desktop reconnection
- **SC-010**: All existing 1Password workflows (password fill, SSH key access, secret retrieval) function identically before and after implementing this feature
- **SC-011**: Terminal launches using Alacritty by default when users invoke terminal via keyboard shortcuts, application launcher, or i3wm configuration
- **SC-012**: All existing terminal customizations (tmux sessions, sesh switching, bash prompt, shell aliases) function identically in Alacritty as they did in previous terminal emulator
- **SC-013**: Users can access all previously configured tmux sessions without reconfiguration or data loss
- **SC-014**: Users can copy text from any supported application and retrieve it from clipboard history within 2 seconds via keyboard shortcut
- **SC-015**: Clipboard history captures at least 95% of copy operations from Firefox, VS Code, Alacritty, and tmux
- **SC-016**: Users can paste from clipboard history into all supported applications with the same reliability as direct clipboard paste
- **SC-017**: Clipboard history maintains at minimum the last 50 clipboard entries across application restarts

## Clarifications

### Session 2025-10-16

- Q: When a user disconnects from a remote desktop session, how long should the session persist before being automatically cleaned up? → A: After idle timeout (e.g., 24 hours of disconnection)
- Q: What is the maximum number of concurrent remote desktop sessions that should be supported per user? → A: 3-5 sessions (typical multi-device usage)
- Q: How should users authenticate when establishing a new remote desktop session? → A: Password with optional SSH key support
- Q: When a web application URL becomes unavailable or returns an error, what should the system do? → A: Show error message to user with retry option
- Q: Should the i3wm configuration target X11 or Wayland as the display server? → A: X11 (mature, better RDP/xrdp compatibility)
- Q: When clipboard history reaches its storage limit, how should the system handle new entries? → A: Remove oldest entries automatically (FIFO queue)
- Q: How should the system handle network interruptions during active remote desktop sessions? → A: Automatic reconnection with exponential backoff
- Q: How should clipboard history handle content that may contain sensitive information (passwords, API keys)? → A: Filter based on patterns, provide manual clear option

## Assumptions

- The target system is a NixOS-based remote workstation (likely similar to the Hetzner configuration)
- The primary remote desktop protocol is RDP (Microsoft Remote Desktop)
- The desktop environment will be i3wm (tiling window manager) running on X11, not KDE Plasma 6 or Wayland
- The application launcher is rofi or a compatible alternative
- Users are comfortable with declarative NixOS configuration and system rebuilds
- Browser-based solution is acceptable for web applications (native PWA implementation not strictly required)
- Session persistence implies at least temporary storage of session state, not necessarily indefinite persistence
- Multiple sessions will be from the same user account (not multi-user scenarios)
- The declarative scripting pattern from activity-aware-apps-native.nix (wrapper scripts, desktop entry overrides) is a proven approach that can be adapted to i3wm context
- i3wm may provide better native mechanisms for some features (workspace management, window rules) than KDE Plasma activities
- Existing 1Password integration is already working and should not be disrupted
- 1Password desktop-CLI integration uses standard 1Password mechanisms (SSH agent, op CLI authentication)
- Current terminal customizations (tmux, sesh, bash, prompt) are configured via home-manager and working well
- Alacritty is compatible with all existing terminal tools and configurations
- Terminal emulator change is primarily a preference for Alacritty's performance and feature set, not a functional requirement
- Users expect terminal behavior and workflows to remain unchanged when switching to Alacritty
- X11 clipboard system is preferred over Wayland for clipboard management due to mature tooling and RDP compatibility
- Clipboard history will use text-based storage (images and binary content are out of scope unless easily supported by chosen solution)
- Users are familiar with keyboard-driven clipboard managers from previous desktop environments
- Clipboard history does not need to sync across multiple machines, only across RDP sessions to the same machine

## Design Considerations

### Architectural Reference

The implementation should draw inspiration from the existing `home-modules/desktop/activity-aware-apps-native.nix` module, which demonstrates:

1. **Declarative Launcher Scripts**: Creating wrapper scripts using `pkgs.writeScriptBin` that add context-aware behavior to applications
2. **Desktop Entry Overrides**: Overriding `.desktop` files in `~/.local/share/applications/` to redirect application launches through custom wrapper scripts
3. **Mapping Files**: Using JSON configuration files to define declarative application behaviors
4. **Shell Script Helpers**: Reusable bash functions for common operations (like `getActivityDirectory`)

### i3wm Native Capabilities

The implementation should research and leverage i3wm's native features where they provide better solutions than scripting:

1. **Workspace Management**: i3wm's workspace system may provide better session isolation than scripting
2. **Window Rules**: i3wm's `for_window` directives may handle application-to-workspace assignment more elegantly
3. **Startup Scripts**: i3wm's exec directives for session-specific initialization
4. **IPC**: i3wm's IPC interface (`i3-msg`) for dynamic configuration

### 1Password Integration Preservation

The implementation must not interfere with existing 1Password integration mechanisms:

1. **1Password Desktop Application**: GUI authentication and vault access
2. **1Password CLI (`op`)**: Authenticates via desktop application using standard integration
3. **SSH Agent Integration**: `~/.1password/agent.sock` for SSH key access
4. **Browser Extensions**: Native messaging between desktop app and browser

### Terminal Emulator Integration

The implementation should use Alacritty while preserving existing terminal workflows:

1. **Home-Manager Configuration Preservation**: All existing terminal customizations (tmux, sesh, bash, prompt) should continue to work without modification
2. **Alacritty as Default**: Configure i3wm and application launchers to use Alacritty as the default terminal emulator
3. **Compatibility Layer**: Ensure Alacritty configuration is compatible with existing terminal tools and workflows
4. **Native Feature Evaluation**: Only replace existing home-manager tools with Alacritty native features if they provide clear advantages without workflow disruption

### Clipboard History Integration

The implementation should prioritize i3wm-native and X11-compatible clipboard management solutions:

1. **i3wm Compatibility**: Research clipboard managers designed for tiling window managers (e.g., clipmenu, copyq, greenclip)
2. **X11 Selection Mechanisms**: Support both PRIMARY (mouse selection, middle-click paste) and CLIPBOARD (Ctrl+C/V) selections
3. **Application Integration**: Ensure compatibility with Firefox, VS Code, Alacritty terminal, and tmux clipboard mechanisms
4. **Keyboard-Driven**: Prioritize keyboard shortcuts and rofi/dmenu integration for clipboard history access
5. **Persistence**: Use declarative configuration for clipboard history settings (retention count, keyboard shortcuts, exclusion patterns)
6. **Security**: Consider filtering sensitive content patterns (passwords, API keys) or providing manual clear functionality

## Dependencies

- Existing NixOS configuration structure and module system
- Remote desktop service (xrdp or similar) with multi-session capabilities
- i3wm window manager with its configuration system
- Browser with extension support (Firefox or Chromium-based)
- Rofi application launcher
- X11 display server (chosen for mature RDP/xrdp compatibility and i3wm support)
- Existing 1Password desktop application and CLI integration
- Existing activity-aware application module pattern as architectural reference
- Alacritty terminal emulator
- Existing home-manager terminal configurations (tmux, sesh, bash, shell prompt)
- X11 clipboard system (xsel, xclip, or similar tools)
- Clipboard manager compatible with i3wm and X11

## Out of Scope

- Multi-user remote desktop scenarios (multiple different users connecting simultaneously)
- Mobile-specific remote desktop clients beyond standard RDP support
- Native PWA implementation or Service Worker functionality
- Offline functionality for web applications
- Custom browser engine or web rendering modifications
- Performance optimization for low-bandwidth connections
- Session recording or monitoring capabilities
- Advanced session management UI (session switching, session naming, etc.)
- Migration of existing KDE Plasma configuration to i3wm (this feature assumes i3wm is the target environment)
- Changes to existing 1Password configuration or authentication mechanisms
- Graphical configuration tools or GUIs for managing web applications or sessions
- Automatic synchronization of web application definitions across multiple machines
- Modifications to existing terminal customizations (tmux, sesh, bash configurations)
- Migration or conversion of terminal configuration from home-manager to Alacritty-native configuration
- Custom terminal emulator features beyond using Alacritty as default
- Image or binary clipboard content support (unless trivially supported by chosen clipboard manager)
- Cross-machine clipboard synchronization (Syncthing, cloud-based clipboard sync)
- Clipboard encryption or advanced security features beyond basic sensitive content filtering
- Custom clipboard history UI beyond keyboard-driven selection interface

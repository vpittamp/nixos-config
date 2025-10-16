# Feature Specification: Lightweight X11 Desktop Environment for Hetzner Cloud

**Feature Branch**: `005-research-a-more`
**Created**: 2025-10-16
**Status**: Draft
**Input**: User description: "research a more compatible window manager for our setup, and then revise our spec. consider whether x11 options are more compatible than wayland, and then limit our search to x11 based systems"

## User Scenarios & Testing

### User Story 1 - Remote Desktop Access to Lightweight X11 Environment (Priority: P1)

As a developer, I need to access a lightweight desktop environment on my headless Hetzner Cloud server via remote desktop, so that I can run GUI applications and manage multiple workspaces without the overhead of a full desktop environment like KDE Plasma.

**Why this priority**: This is the core MVP functionality. Remote desktop access is the primary use case - without this working reliably, the feature has no value.

**Independent Test**: Can be fully tested by connecting via RDP/VNC from a client machine and verifying that a desktop environment appears with working window management and delivers immediate value for running GUI applications.

**Acceptance Scenarios**:

1. **Given** the Hetzner server is running with the lightweight X11 desktop configured, **When** I connect via remote desktop protocol from my MacBook, **Then** I see a functional desktop environment with a working window manager
2. **Given** I am connected to the remote desktop, **When** I launch a GUI application (browser, terminal, etc.), **Then** the application window appears and is fully interactive
3. **Given** I disconnect from the remote desktop session, **When** I reconnect later, **Then** my session state is preserved with all applications still running

---

### User Story 2 - Multiple Workspace Management (Priority: P2)

As a developer working on multiple projects simultaneously, I need to organize my GUI applications across multiple virtual workspaces, so that I can maintain focused work contexts and quickly switch between different tasks.

**Why this priority**: Enhances productivity significantly but the desktop is usable with just one workspace. This can be implemented and tested independently after basic remote access works.

**Independent Test**: Can be fully tested by switching between workspaces using keyboard shortcuts and verifying that windows are correctly organized across workspaces.

**Acceptance Scenarios**:

1. **Given** I have the desktop environment running, **When** I switch to workspace 2 using a keyboard shortcut, **Then** I see only the windows assigned to workspace 2
2. **Given** I have multiple applications open across different workspaces, **When** I move a window from workspace 1 to workspace 3, **Then** the window disappears from workspace 1 and appears on workspace 3
3. **Given** I am on workspace 2 with several windows, **When** I create a new window, **Then** it appears on the currently active workspace (workspace 2)

---

### User Story 3 - Customizable Window Layouts and Keyboard Shortcuts (Priority: P3)

As a power user, I need to customize keyboard shortcuts and window layouts to match my workflow preferences, so that I can work efficiently without relying on mouse navigation.

**Why this priority**: This is a quality-of-life enhancement that improves efficiency but isn't required for basic functionality. Can be implemented after core features work.

**Independent Test**: Can be fully tested by defining custom keybindings in configuration and verifying they work as expected.

**Acceptance Scenarios**:

1. **Given** I have defined custom keyboard shortcuts in the configuration, **When** I press my custom keybinding for launching a terminal, **Then** a new terminal window opens immediately
2. **Given** I have windows arranged in a tiling layout, **When** I press the keyboard shortcut to toggle floating mode, **Then** the focused window switches to floating mode and can be moved freely
3. **Given** I have configured a custom window layout for workspace 1, **When** I switch to workspace 1, **Then** new windows automatically arrange according to my configured layout

---

### User Story 4 - Session Persistence Across Reboots (Priority: P4)

As a developer who occasionally needs to reboot the server for updates, I need my desktop session to persist across system reboots, so that I don't lose my workspace organization and running applications.

**Why this priority**: Nice to have but not critical for initial deployment. Most users can manually restore their session after reboots.

**Independent Test**: Can be fully tested by rebooting the server and verifying session state restoration.

**Acceptance Scenarios**:

1. **Given** I have multiple workspaces configured with specific applications, **When** the system reboots, **Then** my workspace configuration is preserved (though applications may need manual restart)
2. **Given** I have custom keybindings and window manager settings, **When** the system reboots, **Then** all my customizations are still active

---

### Edge Cases

- What happens when the remote desktop connection is interrupted mid-session (network failure)?
- How does the system handle multiple concurrent remote desktop connections (should they share the same session or have separate sessions)?
- What happens when GPU acceleration is unavailable (QEMU virtual environment with no GPU)?
- How does the system behave when audio applications are running remotely (audio redirection requirements)?
- What happens when the display resolution is changed mid-session?
- How does the system handle X11 applications that require specific extensions or features?

## Requirements

### Functional Requirements

- **FR-001**: System MUST provide remote desktop access via a protocol compatible with standard VNC/RDP clients on macOS, Windows, and Linux
- **FR-002**: System MUST use an X11-based window manager that is proven stable in headless virtual environments (QEMU/KVM)
- **FR-003**: System MUST support at least 4 independent virtual workspaces that can be switched using keyboard shortcuts
- **FR-004**: System MUST integrate with existing 1Password authentication system for remote desktop access
- **FR-005**: System MUST run reliably in software rendering mode without GPU acceleration (QEMU llvmpipe)
- **FR-006**: System MUST support session persistence when remote desktop clients disconnect and reconnect
- **FR-007**: System MUST allow launching GUI applications from the remote desktop environment
- **FR-008**: System MUST provide keyboard shortcuts for common window management operations (close, minimize, maximize, move between workspaces)
- **FR-009**: System MUST use less than 500MB of RAM when idle (significantly lighter than KDE Plasma)
- **FR-010**: System MUST be compatible with existing Hetzner Cloud networking setup (Tailscale, firewall rules)
- **FR-011**: System MUST support audio redirection from remote applications to the client machine
- **FR-012**: System MUST allow declarative configuration via NixOS configuration files (no manual setup required)
- **FR-013**: System MUST preserve window manager configuration across system reboots
- **FR-014**: System MUST handle window focus, stacking order, and window decorations correctly
- **FR-015**: System MUST provide a mechanism to launch applications (application launcher or menu)

### Key Entities

- **Window Manager**: The X11 window manager responsible for window placement, focus, and user interaction. Must be lightweight, stable, and proven in headless environments.
- **Remote Desktop Protocol**: The protocol used for accessing the desktop remotely (VNC, RDP, or compatible alternative). Must support session persistence and audio redirection.
- **Workspace**: A virtual desktop that contains a set of windows. Users can switch between workspaces to organize their work.
- **Desktop Session**: The persistent state of the user's desktop including open applications, workspace configuration, and window manager settings.
- **Display Configuration**: Settings controlling virtual display resolution, color depth, and rendering mode for the headless environment.

## Success Criteria

### Measurable Outcomes

- **SC-001**: User can establish remote desktop connection from MacBook and see a functional desktop environment within 30 seconds
- **SC-002**: Window manager memory usage remains under 500MB during typical usage (5-10 applications running)
- **SC-003**: Remote desktop input latency is under 100ms for local network connections
- **SC-004**: User can switch between workspaces in under 200ms using keyboard shortcuts
- **SC-005**: System remains stable for at least 7 days of continuous operation without crashes or restarts
- **SC-006**: User can successfully disconnect and reconnect to remote desktop session with all applications still running at least 95% of the time
- **SC-007**: Audio from remote applications plays on client machine with acceptable quality (no major stuttering or dropouts)
- **SC-008**: System configuration can be rebuilt and deployed in under 10 minutes using NixOS rebuild
- **SC-009**: Window manager responds to user input (keyboard/mouse) within 50ms
- **SC-010**: At least 90% of common GUI applications (browsers, terminals, editors) work correctly in the environment

## Constraints

- Must use X11 (not Wayland) for better compatibility with headless virtual environments
- Must work in QEMU/KVM virtualization without GPU (software rendering only via llvmpipe)
- Must integrate with existing NixOS modular configuration architecture
- Must not conflict with existing Hetzner Cloud services (SSH, Tailscale, firewall)
- Must use existing 1Password infrastructure for authentication
- Must be compatible with Hetzner Cloud networking (no special network requirements)

## Assumptions

- X11 window managers have better compatibility in headless QEMU environments than Wayland compositors due to mature X11 server implementations (Xvnc, xrdp-xorg)
- Software rendering performance is acceptable for typical development workflows (no gaming or heavy graphics work)
- Users will primarily access the desktop via remote desktop clients, not physically attached displays
- Session persistence means keeping applications running across disconnects, not full state serialization
- Standard window manager features (tiling, floating, focus management) are sufficient - no need for advanced compositor effects
- Audio redirection is important but not critical for the MVP
- Users are comfortable with keyboard-driven workflows and minimal GUI chrome
- The lightweight desktop will replace KDE Plasma but reuse all other Hetzner services (development tools, networking, 1Password)
- Configuration should follow the existing Hetzner reference implementation pattern (modular, declarative, testable)

## Out of Scope

- Wayland-based compositors (explicitly excluded per user requirement)
- Heavy desktop environments like GNOME, KDE Plasma, or XFCE
- GPU-accelerated rendering or gaming capabilities
- Multiple simultaneous users with separate desktop sessions
- Desktop environment customization GUI (configuration via NixOS files only)
- Integration with desktop environment-specific tools (panels, docks, system trays) unless provided by the window manager
- Migration tools for existing KDE Plasma settings
- Mobile or tablet remote desktop clients (focus on desktop clients)

## Dependencies

- NixOS 24.11+ with flakes support
- Hetzner Cloud QEMU/KVM virtualization infrastructure
- Existing 1Password authentication services
- Existing Tailscale VPN and firewall configuration
- X11 server implementation suitable for headless operation (Xvnc or xrdp-xorg)
- Remote desktop protocol server (x11vnc, TigerVNC, or xrdp)

## Risks

- X11 window managers may have varying levels of support for declarative NixOS configuration
- Some X11 window managers may require manual configuration files that are difficult to manage declaratively
- Remote desktop protocol choice may impact performance and audio support
- Software rendering may be too slow for some GUI applications
- Session persistence may be unreliable depending on window manager and protocol combination

# Feature Specification: MangoWC Desktop Environment for Hetzner Cloud

**Feature Branch**: `003-create-a-new`
**Created**: 2025-10-16
**Status**: Approved - Ready for Planning
**Input**: User description: "create a new nixos configuration option that corresponds to my hetzner virtual machine, but instead of using kde plasma as the desktop environment we want to use mangowc. for the first iteration we want a sample desktop configuration that provides workspace support. hetzner vm uses a headless display model and we need to make sure that we can access the hetzner cloud vm via some type of remote desktop mechanism."

## User Scenarios & Testing

### User Story 1 - Remote Desktop Connection to MangoWC (Priority: P1)

A system administrator needs to access their Hetzner cloud development environment remotely using a lightweight Wayland compositor. They connect from their local machine (Windows/Mac/Linux) to the cloud VM and interact with the MangoWC desktop environment as if it were running locally, including workspace navigation, window management, and application launching.

**Why this priority**: This is the core functionality that enables the entire system. Without remote access, the headless MangoWC installation on Hetzner would be unusable. This is the Minimum Viable Product (MVP) - a working remote desktop connection to a MangoWC session.

**Independent Test**: Can be fully tested by establishing a remote connection to the Hetzner VM and verifying that the MangoWC desktop environment loads successfully with basic window manager functionality (open terminal, spawn applications, navigate workspaces).

**Acceptance Scenarios**:

1. **Given** a fresh NixOS installation on Hetzner with MangoWC configuration, **When** user connects via remote desktop protocol from their local machine, **Then** MangoWC desktop environment loads and displays correctly with functional mouse and keyboard input
2. **Given** a connected MangoWC remote session, **When** user opens a terminal (Alt+Enter), **Then** terminal window appears and accepts keyboard input
3. **Given** a connected MangoWC session with running applications, **When** user disconnects, **Then** session persists indefinitely and can be reconnected without data loss
4. **Given** a persisted MangoWC session, **When** user reconnects from different device, **Then** session state is restored exactly as left, including window positions and running applications
5. **Given** an active MangoWC remote session, **When** second user connects with valid credentials, **Then** both connections share the same session view and can control windows simultaneously

---

### User Story 2 - Workspace Navigation and Window Management (Priority: P2)

A developer working in MangoWC needs to organize multiple applications across different workspaces (tags) for different tasks. They switch between workspaces, move windows between them, and use different layouts to organize their workflow efficiently.

**Why this priority**: This enables basic productivity in MangoWC by providing workspace organization. While remote access (P1) makes the system usable, workspace management makes it practical for development work. This builds on P1 by adding the core window management features that distinguish MangoWC.

**Independent Test**: Can be tested by opening multiple applications (terminals, browsers, editors) and verifying that workspace switching (Super+1-9), window movement between tags (Alt+1-9), and layout changes (Super+n) all function correctly.

**Acceptance Scenarios**:

1. **Given** multiple applications running in MangoWC, **When** user presses Ctrl+1-9, **Then** switches to the corresponding workspace/tag with correct window state preserved
2. **Given** a window focused in current workspace, **When** user presses Alt+1-9, **Then** window moves to the target workspace and receives focus
3. **Given** multiple windows in a workspace, **When** user presses Super+n, **Then** cycles through available layouts (tile, scroller, monocle, grid, etc.)
4. **Given** windows arranged in a layout, **When** user presses Alt+arrow keys, **Then** focuses the adjacent window in the specified direction

---

### User Story 3 - Application Launching and Basic Configuration (Priority: P3)

A user needs to launch applications, set wallpapers, and customize basic keybindings in MangoWC. They modify the config.conf file to set their preferred terminal emulator, application launcher, and visual settings.

**Why this priority**: This adds customization and quality-of-life improvements. While P1 provides access and P2 provides workspace management, P3 makes the environment personalized and comfortable for daily use. This can be added incrementally after core functionality works.

**Independent Test**: Can be tested by modifying config.conf, reloading configuration (Super+r), and verifying that new keybindings work, wallpaper changes are applied, and custom application launchers function correctly.

**Acceptance Scenarios**:

1. **Given** MangoWC configuration file at ~/.config/mango/config.conf, **When** user adds custom keybinding and presses Super+r, **Then** new keybinding becomes active without restarting session
2. **Given** autostart.sh configured with wallpaper command, **When** MangoWC session starts, **Then** wallpaper displays correctly
3. **Given** custom application launcher configured (wmenu/rofi), **When** user presses Super+d, **Then** launcher appears and successfully launches selected applications

---

### User Story 4 - Multi-Monitor and Display Management (Priority: P4)

A user needs to configure display settings for their remote session, including resolution, scaling, and multi-monitor setup for scenarios where the remote client supports multiple displays.

**Why this priority**: This enhances the user experience for advanced use cases but is not essential for basic functionality. Most initial users will work with single-display remote sessions. This can be added later as needs arise.

**Independent Test**: Can be tested by adjusting display settings and verifying that MangoWC correctly handles resolution changes, display addition/removal, and scaling adjustments.

**Acceptance Scenarios**:

1. **Given** a running MangoWC session, **When** user changes remote client resolution, **Then** MangoWC adapts to the new resolution without disconnection
2. **Given** multiple displays available in remote session, **When** user presses Alt+Shift+Left/Right, **Then** focus switches between monitors
3. **Given** windows on multiple monitors, **When** user presses Super+Alt+Left/Right, **Then** active window moves to the adjacent monitor

---

### Edge Cases

- What happens when remote desktop protocol connection is lost unexpectedly (network failure)?
  - **Expected**: Session persists on server side, allowing reconnection without data loss. Applications continue running.

- How does system handle concurrent remote connections from multiple clients?
  - **Expected**: Multiple concurrent connections are allowed and share the same session view. All connected clients see identical screen state and can control the session. Useful for multi-device work or collaboration.

- What happens when MangoWC compositor crashes during a remote session?
  - **Expected**: Session terminates, remote client disconnects. System should log crash details for debugging. User can reconnect to start a new session.

- How does system handle hardware acceleration in virtualized headless environment?
  - **Expected**: Software rendering fallback if GPU acceleration unavailable. Performance may be reduced but system remains functional.

- What happens when user attempts to start MangoWC without proper Wayland compositor dependencies?
  - **Expected**: Build-time error with clear message indicating missing dependencies.

## Requirements

### Functional Requirements

- **FR-001**: System MUST provide a NixOS configuration option to enable MangoWC as the desktop environment on Hetzner cloud VM
- **FR-002**: System MUST support remote desktop access to MangoWC sessions via Wayland-compatible remote desktop protocol
- **FR-003**: System MUST configure MangoWC with default keybindings for basic window management (spawn terminal, kill window, focus direction, switch workspaces)
- **FR-004**: System MUST support workspace/tag switching with keybindings (Ctrl+1-9 for viewing tags, Alt+1-9 for moving windows to tags)
- **FR-005**: System MUST provide at least 3 window layouts (tile, scroller, monocle) with ability to switch between them
- **FR-006**: System MUST run MangoWC in headless mode on Hetzner cloud VM without physical display attached
- **FR-007**: System MUST persist MangoWC session state when remote desktop client disconnects
- **FR-008**: System MUST provide configuration file at ~/.config/mango/config.conf with customizable keybindings
- **FR-009**: System MUST include essential companion tools (terminal emulator, application launcher, wallpaper setter)
- **FR-010**: System MUST configure remote desktop authentication using the existing 1Password password management system for automatic password rotation and centralized credential management
- **FR-011**: System MUST automatically start MangoWC session when user connects via remote desktop
- **FR-012**: System MUST support audio redirection from cloud VM to remote client
- **FR-013**: System MUST log MangoWC compositor events for debugging and troubleshooting
- **FR-014**: System MUST provide autostart mechanism for launching applications/services when MangoWC session starts
- **FR-015**: System MUST maintain compatibility with existing Hetzner VM hardware configuration (QEMU guest, virtio drivers)

### Key Entities

- **MangoWC Session**: Represents a running instance of the MangoWC Wayland compositor with its window manager state, including active workspaces, window arrangements, and user configuration

- **Remote Desktop Connection**: Represents the network connection between client machine and Hetzner VM, carrying display, input, and audio data

- **Workspace/Tag**: Represents a virtual desktop in MangoWC where windows can be organized, with 9 configurable workspaces available (numbered 1-9)

- **Window**: Represents an application instance managed by MangoWC, with properties like position, size, workspace assignment, and layout state

- **Configuration Profile**: Represents the MangoWC configuration files (config.conf, autostart.sh) that define keybindings, appearance, and startup behavior

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can establish remote desktop connection to Hetzner MangoWC instance within 30 seconds of connection initiation
- **SC-002**: MangoWC session remains responsive with less than 100ms input latency over remote desktop connection on standard broadband (10+ Mbps)
- **SC-003**: System supports at least 3 concurrent workspace switches per second without lag or visual artifacts
- **SC-004**: Window management operations (focus, move, resize) complete within 200ms of user input
- **SC-005**: Remote desktop session reconnects successfully within 10 seconds after network interruption without data loss
- **SC-006**: Users can successfully launch and interact with at least 10 concurrent applications across multiple workspaces
- **SC-007**: Configuration changes via config.conf take effect within 2 seconds of reload command (Super+r)
- **SC-008**: System builds successfully using nixos-rebuild with no manual intervention required
- **SC-009**: MangoWC compositor memory footprint remains under 200MB with basic applications running
- **SC-010**: Remote desktop audio redirection operates with less than 200ms audio delay

## Assumptions

1. **Remote Desktop Protocol**: We assume waypipe or similar Wayland-native remote desktop solution will be used, as MangoWC is a Wayland compositor and traditional X11-based solutions (XRDP) are not compatible. Alternative could be VNC with wlroots support or using RustDesk which supports Wayland compositors.

2. **Session Management**: Sessions persist indefinitely until explicitly terminated. Remote desktop protocol must support session persistence allowing disconnection and reconnection without data loss, matching current XRDP behavior.

3. **Concurrent Connections**: Multiple concurrent remote desktop connections are supported and share the same session view. All connected clients can view and control the session simultaneously, enabling multi-device work and collaboration.

4. **Default Applications**: We assume using foot (terminal), wmenu/rofi (launcher), and swaybg (wallpaper) as companion applications based on MangoWC tutorial recommendations.

5. **Authentication**: Remote desktop authentication will use the existing 1Password password management system configured on Hetzner, providing automatic password rotation and centralized credential management (op://Employee/kzfqt6yulhj6glup3w22eupegu/credential).

6. **Audio Support**: We assume PulseAudio or PipeWire audio redirection will be configured similar to current Hetzner XRDP audio setup.

7. **Display Resolution**: We assume a default display resolution of 1920x1080 for headless operation, configurable via remote desktop client settings.

8. **GPU Acceleration**: We assume software rendering (llvmpipe) in virtualized environment, as Hetzner cloud VMs typically don't expose GPU hardware.

9. **MangoWC Dependencies**: We assume MangoWC package is available in nixpkgs or will be built from the flake referenced in the project (github:DreamMaoMao/mangowc).

10. **Network Firewall**: We assume firewall configuration will follow existing Hetzner patterns (allowing specific ports for remote desktop protocol).

11. **System Resources**: We assume Hetzner VM has sufficient resources (2+ CPU cores, 4GB+ RAM) to run MangoWC with typical development workloads.

## Out of Scope

- Migration of existing KDE Plasma user data or settings to MangoWC
- Advanced MangoWC features like animations, blur effects, or window shadows (basic configuration only)
- Custom MangoWC theme development or extensive visual customization
- Integration with Hetzner-specific monitoring or management tools
- Automated backup/restore of MangoWC configuration
- Support for non-Linux remote desktop clients (may work but not explicitly tested)
- GPU acceleration or hardware video encoding for remote desktop
- High-DPI/Retina display optimization for remote sessions
- Touchpad gesture support (not applicable to remote desktop use case)

## Dependencies

- MangoWC compositor package (either from nixpkgs or built from source)
- wlroots library (version 0.19.1 as specified in MangoWC requirements)
- scenefx library for window effects
- Wayland-compatible remote desktop protocol server (waypipe, wayvnc, or RustDesk with Wayland support)
- Essential companion tools (foot terminal, wmenu/rofi launcher, swaybg wallpaper)
- Existing Hetzner VM hardware configuration and network setup

## Technical Notes

This specification intentionally avoids implementation details to remain technology-agnostic. The planning phase will determine:

- Specific remote desktop protocol to use (waypipe vs wayvnc vs RustDesk)
- How to package MangoWC for NixOS (flake input vs nixpkgs)
- Configuration file generation strategy (templates vs concatenation)
- Session management approach (systemd user services vs display manager integration)
- Audio redirection implementation (PulseAudio modules vs PipeWire)

These decisions will be made during `/speckit.plan` based on technical feasibility and compatibility with existing Hetzner configuration patterns.

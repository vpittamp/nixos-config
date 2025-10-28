# Feature Specification: Migrate M1 MacBook Pro to Sway with i3pm Integration

**Feature Branch**: `045-migrate-m1-macbook`
**Created**: 2025-10-27
**Status**: Draft
**Input**: User description: "Migrate M1 MacBook Pro from KDE Plasma to Sway tiling window manager with full i3pm daemon integration"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Basic Sway Window Management (Priority: P1)

As a developer using the M1 MacBook Pro, I need a functional tiling window manager with keyboard-driven workflows so I can efficiently manage multiple applications without using a mouse, mirroring the experience on my Hetzner workstation.

**Why this priority**: Core functionality - without working window management, the system is unusable. This establishes the foundation for all other features.

**Independent Test**: Can be fully tested by launching Sway, opening multiple terminal windows with Meta+Return, and verifying tiling behavior, window focus, and workspace switching (Ctrl+1-9) work correctly on native Apple Silicon hardware with Retina display.

**Acceptance Scenarios**:

1. **Given** Sway is configured and system boots, **When** user logs in, **Then** Sway session starts successfully with correct DPI scaling for Retina display
2. **Given** Sway is running, **When** user presses Meta+Return, **Then** new terminal window opens and tiles correctly
3. **Given** multiple windows are open, **When** user presses Meta+Arrow keys, **Then** focus moves between windows correctly
4. **Given** user is on workspace 1, **When** user presses Ctrl+2, **Then** workspace switches to workspace 2
5. **Given** a window is focused, **When** user presses Meta+Shift+Q, **Then** window closes gracefully
6. **Given** Sway is running, **When** user presses Meta+Shift+R, **Then** Sway config reloads without session restart

---

### User Story 2 - i3pm Daemon Integration (Priority: P1)

As a developer who uses project-scoped workflows, I need the i3pm daemon to automatically track and manage windows across multiple projects so I can seamlessly switch between NixOS, Stacks, and Personal projects without manually organizing windows.

**Why this priority**: Core differentiator from standard Sway - this is what makes the system productive. The project management workflow is essential for daily work patterns established on Hetzner.

**Independent Test**: Can be tested by starting the i3pm daemon, creating two projects (nixos and stacks), launching VS Code for each project, switching between projects with Meta+P, and verifying windows hide/show correctly.

**Acceptance Scenarios**:

1. **Given** i3pm daemon is running and connected to Sway, **When** system starts, **Then** daemon logs successful Sway IPC connection and loads project configurations
2. **Given** user switches to project "nixos", **When** user launches VS Code via Meta+C, **Then** VS Code window receives project:nixos mark and opens in project directory
3. **Given** VS Code is open for "nixos" project, **When** user switches to "stacks" project, **Then** nixos VS Code window moves to scratchpad (hidden) automatically
4. **Given** user is in "stacks" project with hidden "nixos" windows, **When** user switches back to "nixos", **Then** all nixos windows restore from scratchpad to original workspaces
5. **Given** daemon is processing events, **When** user creates new window in active project, **Then** window receives correct project mark within 100ms

---

### User Story 3 - Walker Launcher with Native Wayland (Priority: P1)

As a keyboard-focused user, I need the Walker application launcher to work natively on Wayland without X11 compatibility layers so I can quickly launch applications, search files, use calculator, and switch projects with optimal performance and correct display scaling.

**Why this priority**: Primary interaction method for launching applications and switching projects. Must work reliably for basic productivity. Native Wayland support eliminates display issues seen with X11 compatibility mode.

**Independent Test**: Can be tested by pressing Meta+D to launch Walker, typing application names to verify fuzzy search, testing calculator with "=2+2", and confirming project switcher works with ";p " prefix.

**Acceptance Scenarios**:

1. **Given** Walker is configured for Wayland, **When** user presses Meta+D, **Then** Walker window appears centered with correct Retina display scaling
2. **Given** Walker is open, **When** user types "code", **Then** VS Code appears in filtered results within 200ms
3. **Given** Walker is showing VS Code, **When** user presses Return, **Then** VS Code launches via app-launcher-wrapper with current project context
4. **Given** Walker is open, **When** user types "=2+2", **Then** calculator shows result "4" and copies to clipboard on Return
5. **Given** Walker is open, **When** user types ";p " (project prefix), **Then** list of all projects appears with icons and active project indicator
6. **Given** clipboard provider is enabled, **When** user types ":", **Then** clipboard history shows recent text and images (Wayland wl-clipboard support)

---

### User Story 4 - Python Daemon Window Tracking (Priority: P2)

As a developer with multiple instances of the same application, I need the Python daemon to correctly identify and track windows using Sway's native window properties instead of xprop so each VS Code window associates with the correct project.

**Why this priority**: Enables reliable multi-instance application tracking (critical for multiple VS Code windows). Depends on P1 daemon integration but represents enhanced reliability.

**Independent Test**: Can be tested by launching two VS Code instances for different projects within 1 second, then verifying both windows have correct project marks and appear on correct workspaces via `i3pm windows --tree`.

**Acceptance Scenarios**:

1. **Given** daemon uses Sway IPC for window properties, **When** new window appears, **Then** daemon reads app_id, name, and PID directly from Sway tree (no xprop calls)
2. **Given** user launches VS Code for "nixos", **When** window appears, **Then** daemon reads /proc/<pid>/environ for I3PM_PROJECT_NAME
3. **Given** user launches second VS Code for "stacks" within 1 second, **When** both windows exist, **Then** each window has distinct project mark (project:nixos:ID1 and project:stacks:ID2)
4. **Given** daemon startup with pre-existing windows, **When** daemon performs startup scan, **Then** all unmarked windows receive correct project marks based on I3PM environment variables

---

### User Story 5 - Multi-Monitor Workspace Distribution (Priority: P2)

As a user with external monitors, I need workspaces to automatically distribute across monitors based on the same configuration as Hetzner so my workspace layout remains consistent when docking/undocking the MacBook.

**Why this priority**: Enhances productivity for docked workstation use but system is functional without it. Matches established workflow from Hetzner configuration.

**Independent Test**: Can be tested by connecting an external monitor, running `i3pm monitors status`, and verifying workspace 1-2 appear on built-in display while workspace 3+ appear on external monitor per configuration.

**Acceptance Scenarios**:

1. **Given** MacBook built-in display only, **When** system starts, **Then** all workspaces 1-70 assigned to built-in display
2. **Given** external monitor connected, **When** monitor detection occurs, **Then** workspaces 1-2 remain on built-in display and workspaces 3-70 move to external monitor
3. **Given** two external monitors connected, **When** workspace distribution runs, **Then** WS 1-2 on primary, WS 3-5 on secondary, WS 6-70 on tertiary
4. **Given** external monitor disconnected, **When** monitor change detected, **Then** all workspaces consolidate to built-in display after 1 second debounce

---

### User Story 6 - Remote Access via VNC (Priority: P3)

As a remote worker, I need to access my M1 MacBook Pro desktop remotely via VNC when away from the machine so I can continue work without physical access.

**Why this priority**: Nice-to-have for remote scenarios but not essential for daily local use. Lower priority than core window management and project workflow.

**Independent Test**: Can be tested by starting wayvnc service, connecting from another machine with VNC client, and verifying Sway desktop is visible and interactive with keyboard/mouse input working correctly.

**Acceptance Scenarios**:

1. **Given** wayvnc service is configured and enabled, **When** system starts, **Then** VNC server listens on port 5900
2. **Given** VNC server is running, **When** remote client connects with credentials, **Then** Sway desktop displays with correct resolution
3. **Given** VNC session is active, **When** user types in remote client, **Then** keyboard input reaches Sway applications correctly
4. **Given** VNC session is active, **When** user moves mouse in remote client, **Then** cursor moves on Sway desktop and click events work

---

### Edge Cases

- What happens when external display is disconnected while windows are on external workspaces? (Windows should move to built-in display's workspaces)
- How does the system handle Sway crash or restart? (Daemon should reconnect automatically with exponential backoff, state should persist)
- What if user launches application before daemon fully initializes? (Window should be marked during startup scan based on /proc environ)
- How does display scaling behave when moving windows between Retina built-in display (2x) and external monitor (1x)? (Sway handles per-output scaling, applications adapt)
- What happens if app-launcher-wrapper fails to inject I3PM environment variables? (Window won't have project context, will remain unmarked - needs logging)
- How does system handle incompatible window rules from i3? (Sway has identical syntax, should work as-is)

## Requirements *(mandatory)*

### Functional Requirements

#### Sway Window Manager Core

- **FR-001**: System MUST replace KDE Plasma with Sway as the default window manager on M1 configuration
- **FR-002**: System MUST configure Sway with identical keybindings to Hetzner i3 configuration (Meta key bindings, workspace switching, window management)
- **FR-003**: System MUST configure Sway bar (swaybar) with project context display matching i3bar implementation on Hetzner
- **FR-004**: System MUST set Wayland-specific environment variables (MOZ_ENABLE_WAYLAND, NIXOS_OZONE_WL, QT_QPA_PLATFORM=wayland)
- **FR-005**: System MUST configure per-output DPI scaling for Retina built-in display (180 DPI or 2x scaling)
- **FR-006**: System MUST preserve touchpad configuration (natural scrolling, tap-to-click, two-finger right-click) under Sway

#### i3pm Daemon Adaptation

- **FR-007**: Python daemon MUST connect to Sway via i3ipc library (same IPC protocol as i3)
- **FR-008**: Daemon MUST replace all xprop calls with Sway IPC tree queries for window properties (app_id, name, pid)
- **FR-009**: Daemon MUST use Sway's `app_id` property instead of X11 window class for window identification
- **FR-010**: Daemon MUST subscribe to identical i3 IPC events (window, workspace, output, tick, shutdown) via Sway
- **FR-011**: Daemon MUST read window environment variables from /proc/<pid>/environ (OS-level, unchanged from i3)
- **FR-012**: Daemon MUST mark windows with project marks using identical syntax (project:NAME:ID)
- **FR-013**: Daemon MUST persist window-workspace mapping in ~/.config/i3/window-workspace-map.json (unchanged schema)

#### Application Launcher

- **FR-014**: Walker MUST be configured for native Wayland operation (remove GDK_BACKEND=x11 flag)
- **FR-015**: Walker MUST launch applications via app-launcher-wrapper.sh with I3PM environment injection
- **FR-016**: Elephant service MUST enable clipboard provider for Wayland (wl-clipboard support)
- **FR-017**: Walker MUST support all existing providers (applications, calculator, symbols, websearch, runner, files, sesh, projects)

#### Multi-Monitor Support

- **FR-018**: System MUST use identical workspace-to-monitor distribution configuration as Hetzner
- **FR-019**: System MUST support monitor hotplug detection via Sway output events
- **FR-020**: System MUST apply workspace distribution automatically when monitors connect/disconnect with 1-second debounce

#### Remote Access

- **FR-021**: System MUST provide VNC remote access via wayvnc for Wayland screen sharing
- **FR-022**: VNC service MUST support authentication and listen on configurable port (default 5900)

#### Configuration Parity

- **FR-023**: Sway configuration syntax MUST remain 100% compatible with i3 config (keybindings, window rules, workspace names)
- **FR-024**: Home manager modules MUST mirror Hetzner structure (sway.nix parallel to i3.nix architecture)
- **FR-025**: Application registry MUST remain unchanged (same desktop files, same I3PM metadata)

### Key Entities *(include if feature involves data)*

- **Sway Configuration**: Window manager settings including keybindings, window rules, bar configuration, output scaling - stored in ~/.config/sway/config (generated by home-manager)
- **Window State**: Sway window tree data including app_id, name, pid, geometry, floating state - queried via Sway IPC GET_TREE
- **Project Context**: Active project name and directory stored in ~/.config/i3/active-project.json (unchanged from i3)
- **Window Marks**: Project associations stored as Sway window marks (format: project:NAME:WINDOW_ID) - persisted in Sway's internal state
- **Monitor Configuration**: Workspace-to-output distribution stored in ~/.config/i3/workspace-monitor-mapping.json (unchanged from i3)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can log into Sway session on M1 MacBook Pro and perform all basic window management operations (open, close, tile, focus, float) with Retina display scaling applied correctly
- **SC-002**: i3pm daemon connects to Sway IPC within 2 seconds of session start and processes window events with <100ms latency
- **SC-003**: User can switch between projects via Meta+P and windows hide/show correctly within 500ms
- **SC-004**: User can launch applications via Walker (Meta+D) and all 7 providers function correctly (applications, calculator, files, symbols, websearch, runner, sesh, projects)
- **SC-005**: Walker displays with correct Retina display scaling in native Wayland mode without X11 compatibility layer
- **SC-006**: Multi-instance applications (VS Code) receive correct project marks with 100% accuracy for launches >2 seconds apart
- **SC-007**: External monitor connection triggers automatic workspace redistribution within 2 seconds with correct workspace assignments per configuration
- **SC-008**: All Python daemon tests pass without modification to test logic (only window property access methods change)
- **SC-009**: User can connect to M1 desktop via VNC from remote machine and interact with Sway session
- **SC-010**: System builds successfully with `nixos-rebuild dry-build --flake .#m1 --impure` (no evaluation errors)

## Dependencies & Assumptions

### Dependencies

- **Sway package**: Available in nixpkgs with i3 IPC compatibility
- **i3ipc Python library**: Works with both i3 and Sway (same protocol)
- **wayvnc**: Available in nixpkgs for Wayland VNC support
- **Walker/Elephant**: Already support native Wayland operation
- **Asahi Linux firmware**: Required for GPU acceleration on Apple Silicon (already present in M1 config)

### Assumptions

- M1 hardware supports Wayland compositors (validated via Asahi Linux project)
- Sway provides 100% i3 IPC protocol compatibility (documented upstream)
- All current applications (VS Code, Firefox, Alacritty, Ghostty) support Wayland natively
- Display scaling in Wayland is handled per-output (built-in Retina vs external monitors)
- Touch gestures on M1 trackpad work better under Wayland than X11 (native libinput support)

## Out of Scope

- **Performance tuning**: Initial migration focuses on functional parity; performance optimization deferred to future iteration
- **Asahi GPU driver**: Experimental GPU features remain disabled (as in current M1 config)
- **DisplayLink support**: USB graphics adapters remain disabled due to version mismatch issues
- **RDP protocol**: VNC replaces RDP for remote access (RDP requires X11 or complex Wayland bridges)
- **Custom Sway features**: No Sway-specific enhancements beyond i3 feature parity
- **Hetzner configuration changes**: Hetzner remains on i3/X11 unchanged

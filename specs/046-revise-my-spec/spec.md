# Feature Specification: Hetzner Cloud Sway Configuration with Headless Wayland

**Feature Branch**: `046-revise-my-spec`
**Created**: 2025-10-28
**Status**: Draft
**Input**: User description: "In addition to migrating m1 to sway, I also want to create another configuration that will work with my hetzner vm (based on the hetzner configuration) to sway. Research whether I can run wayland with sway on a hetzner cloud vm. This should be a separate configuration from hetzner, leaving hetzner configuration exactly as is."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Headless Sway Session on Hetzner Cloud (Priority: P1)

As a remote developer, I need a functional Sway tiling window manager running on my Hetzner Cloud VM with headless Wayland so I can use keyboard-driven workflows and project-scoped window management remotely via VNC, matching the experience on my M1 MacBook Pro.

**Why this priority**: Core functionality - establishes headless Wayland session that can be accessed remotely. Without this, the entire feature is unusable. Enables unified Sway experience across M1 (native display) and Hetzner (headless/remote).

**Independent Test**: Can be fully tested by SSHing into Hetzner VM, starting Sway with WLR_BACKENDS=headless, connecting via VNC client, and verifying tiling window manager is visible and responsive with keyboard input working correctly.

**Acceptance Scenarios**:

1. **Given** Hetzner Cloud VM with new "hetzner-sway" configuration, **When** user logs in, **Then** Sway session starts successfully in headless mode using WLR_BACKENDS=headless backend
2. **Given** headless Sway is running, **When** wayvnc service starts, **Then** VNC server listens on port 5900 and accepts authenticated connections
3. **Given** VNC connection is established, **When** user presses Meta+Return, **Then** new terminal window opens and tiles correctly in VNC viewer
4. **Given** multiple windows are open, **When** user presses Meta+Arrow keys, **Then** focus moves between windows correctly
5. **Given** Sway is running headless, **When** user presses Ctrl+1-9, **Then** workspace switches occur and are reflected in VNC session
6. **Given** headless Sway session, **When** user resizes VNC client window, **Then** Sway virtual display adapts to new resolution

---

### User Story 2 - i3pm Daemon Integration for Headless Sway (Priority: P1)

As a developer who uses project-scoped workflows, I need the i3pm daemon to work identically on headless Hetzner Sway as it does on native M1 Sway and Hetzner i3, so I can seamlessly switch between projects (NixOS, Stacks, Personal) regardless of which machine I'm working on.

**Why this priority**: Core differentiator - project management workflow must work consistently across all machines. Without this, the headless Sway configuration is just a standard window manager without the productivity benefits.

**Independent Test**: Can be tested by starting i3pm daemon on Hetzner Sway, creating two projects (nixos and stacks), launching VS Code for each project via VNC, switching projects with Meta+P, and verifying windows hide/show correctly in VNC session.

**Acceptance Scenarios**:

1. **Given** i3pm daemon is running on headless Sway, **When** system starts, **Then** daemon connects to Sway IPC socket and loads project configurations
2. **Given** user switches to project "nixos" via VNC, **When** user launches VS Code via Meta+C, **Then** VS Code window receives project:nixos mark and opens in project directory
3. **Given** VS Code is open for "nixos" project, **When** user switches to "stacks" project, **Then** nixos VS Code window moves to scratchpad (hidden) automatically
4. **Given** user is in "stacks" project with hidden "nixos" windows, **When** user switches back to "nixos", **Then** all nixos windows restore from scratchpad to original workspaces
5. **Given** daemon is processing events in headless mode, **When** user creates new window, **Then** window receives correct project mark within 100ms (same latency as native Sway)

---

### User Story 3 - Walker Launcher on Headless Sway (Priority: P1)

As a keyboard-focused remote user, I need the Walker application launcher to work on headless Sway with native Wayland support so I can quickly launch applications, search files, use calculator, and switch projects without X11 compatibility layer overhead.

**Why this priority**: Primary interaction method for launching applications and switching projects remotely. Must work reliably for basic productivity. Native Wayland support eliminates compatibility issues.

**Independent Test**: Can be tested by connecting to Hetzner Sway via VNC, pressing Meta+D to launch Walker, typing application names to verify fuzzy search works remotely, testing calculator with "=2+2", and confirming project switcher works with ";p " prefix.

**Acceptance Scenarios**:

1. **Given** Walker is configured for headless Wayland, **When** user presses Meta+D in VNC session, **Then** Walker window appears centered on virtual display
2. **Given** Walker is open remotely, **When** user types "code", **Then** VS Code appears in filtered results within 200ms
3. **Given** Walker is showing VS Code, **When** user presses Return, **Then** VS Code launches via app-launcher-wrapper with current project context
4. **Given** Walker is open, **When** user types "=2+2", **Then** calculator shows result "4" and copies to clipboard on Return
5. **Given** Walker is open, **When** user types ";p " (project prefix), **Then** list of all projects appears with icons and active project indicator
6. **Given** clipboard provider is enabled, **When** user types ":", **Then** clipboard history shows recent text (Wayland wl-clipboard support)

---

### User Story 4 - Remote Desktop Performance Optimization (Priority: P2)

As a remote developer, I need the headless Sway session to provide acceptable performance over VNC so I can work productively without excessive lag or display artifacts, even when working with multiple windows and switching projects frequently.

**Why this priority**: Enhances usability but system is functional without optimization. Critical for long-term productivity but not required for MVP validation.

**Independent Test**: Can be tested by connecting to Hetzner Sway via VNC over typical internet connection, performing rapid window operations (create, move, switch workspaces, switch projects), and measuring response times and visual quality.

**Acceptance Scenarios**:

1. **Given** VNC connection to headless Sway, **When** user opens new window, **Then** window appears within 500ms
2. **Given** VNC session is active, **When** user switches workspaces, **Then** workspace switch completes within 200ms
3. **Given** user is switching projects, **When** windows hide/show operations occur, **Then** visual artifacts are minimal (no tearing or corruption)
4. **Given** headless Sway is running, **When** system is idle, **Then** VNC server uses less than 50MB RAM and less than 5% CPU
5. **Given** multiple applications are open remotely, **When** user types in terminal, **Then** keyboard input latency is under 100ms

---

### User Story 5 - Configuration Isolation from Existing Hetzner (Priority: P2)

As a system administrator, I need the new hetzner-sway configuration to be completely separate from the existing hetzner i3 configuration so I can test and deploy Sway without affecting the stable i3 setup, and easily switch between them if needed.

**Why this priority**: Risk mitigation - ensures existing production environment remains untouched. Allows gradual migration testing without disrupting current workflows.

**Independent Test**: Can be tested by building both hetzner and hetzner-sway configurations, verifying they produce different system profiles, and confirming hetzner configuration remains unchanged after hetzner-sway is deployed.

**Acceptance Scenarios**:

1. **Given** both hetzner and hetzner-sway configurations exist, **When** building hetzner configuration, **Then** no Sway packages or modules are included
2. **Given** both configurations are built, **When** inspecting configuration imports, **Then** hetzner-sway imports sway.nix while hetzner imports i3wm.nix (no overlap)
3. **Given** hetzner-sway is deployed, **When** switching to hetzner configuration via NixOS generations, **Then** system boots to i3/X11 session as before
4. **Given** hetzner configuration is deployed, **When** inspecting system packages, **Then** no Wayland-specific packages (wayvnc, wl-clipboard) are installed
5. **Given** both configurations in repository, **When** building via flake, **Then** `nixos-rebuild switch --flake .#hetzner` and `.#hetzner-sway` produce distinct system closures

---

### User Story 6 - Multi-Monitor Support via Virtual Displays (Priority: P3)

As a remote developer who uses multiple monitors locally, I need the ability to create multiple virtual displays in headless Sway so I can maintain my multi-monitor workspace distribution workflow when connecting remotely.

**Why this priority**: Nice-to-have for advanced users. System is fully functional with single virtual display. Matches feature parity with M1 multi-monitor support but not essential for remote headless use case.

**Independent Test**: Can be tested by configuring headless Sway with multiple virtual outputs (headless-0, headless-1), running `i3pm monitors status`, and verifying workspace 1-2 on first output while workspace 3+ on second output per configuration.

**Acceptance Scenarios**:

1. **Given** headless Sway with single virtual output, **When** system starts, **Then** all workspaces 1-70 assigned to headless-0
2. **Given** headless Sway configured with two virtual outputs, **When** daemon initializes, **Then** workspaces 1-2 on headless-0, workspaces 3-70 on headless-1
3. **Given** two virtual outputs active, **When** user switches to workspace 3, **Then** VNC client shows content from second virtual output
4. **Given** multi-output configuration, **When** user runs `i3pm monitors status`, **Then** output table shows headless-0 (primary) and headless-1 (secondary) with correct workspace assignments

---

### Edge Cases

- What happens when VNC connection drops while Sway session is active? (Sway should continue running headless, VNC client can reconnect without session restart)
- How does system handle headless backend initialization failure? (Fall back to logging error, system should not boot to Sway session)
- What if wayvnc fails to start but Sway is running? (Sway continues headless but inaccessible remotely, systemd should restart wayvnc)
- How does display scaling behave in headless mode with varying VNC client resolutions? (Virtual display should adapt to configured resolution, VNC client scales independently)
- What happens if user tries to use GPU-accelerated applications in headless mode? (Software rendering fallback via WLR_RENDERER=pixman if GPU not available)
- How does system handle simultaneous M1 Sway (native) and Hetzner Sway (headless) deployments from same flake? (Independent NixOS configurations with no shared state, can be deployed in parallel)

## Requirements *(mandatory)*

### Functional Requirements

#### Headless Wayland Backend

- **FR-001**: System MUST configure Sway to run with headless Wayland backend using WLR_BACKENDS=headless environment variable
- **FR-002**: System MUST set WLR_LIBINPUT_NO_DEVICES=1 to disable physical input device detection in headless mode
- **FR-003**: System MUST create at least one virtual output (headless-0) with configurable resolution (default 1920x1080)
- **FR-004**: System MUST support software rendering via WLR_RENDERER=pixman when GPU acceleration unavailable
- **FR-005**: Headless Sway session MUST start automatically on system boot via systemd user service
- **FR-006**: System MUST use identical Wayland environment variables as M1 Sway (MOZ_ENABLE_WAYLAND, NIXOS_OZONE_WL, QT_QPA_PLATFORM=wayland)

#### Remote Access via VNC

- **FR-007**: System MUST provide VNC remote access via wayvnc for headless Sway session
- **FR-008**: wayvnc service MUST start automatically after Sway session is running
- **FR-009**: VNC server MUST listen on port 5900 with PAM authentication enabled
- **FR-010**: VNC connection MUST support full keyboard and mouse input from remote client
- **FR-011**: VNC session MUST support clipboard sharing between remote client and headless Sway (wl-clipboard integration)
- **FR-012**: System MUST allow VNC server to adapt virtual display resolution based on client capability

#### i3pm Daemon Compatibility

- **FR-013**: Python daemon MUST connect to headless Sway via i3ipc library (same IPC protocol)
- **FR-014**: Daemon MUST use Sway IPC for window properties (app_id, name, pid) without xprop dependency
- **FR-015**: Daemon MUST subscribe to identical i3 IPC events (window, workspace, output, tick, shutdown) via headless Sway
- **FR-016**: Daemon MUST read window environment variables from /proc/<pid>/environ (OS-level, unchanged from native Sway)
- **FR-017**: Daemon MUST mark windows with project marks using identical syntax (project:NAME:ID)
- **FR-018**: Daemon MUST persist window-workspace mapping in ~/.config/i3/window-workspace-map.json (unchanged schema)

#### Application Launcher

- **FR-019**: Walker MUST be configured for native Wayland operation in headless mode (no X11 backend)
- **FR-020**: Walker MUST launch applications via app-launcher-wrapper.sh with I3PM environment injection
- **FR-021**: Elephant service MUST enable clipboard provider for Wayland (wl-clipboard support)
- **FR-022**: Walker MUST support all existing providers (applications, calculator, symbols, websearch, runner, files, sesh, projects)

#### Configuration Isolation

- **FR-023**: hetzner-sway configuration MUST be a separate NixOS configuration in flake.nix (not modifying existing hetzner config)
- **FR-024**: hetzner-sway MUST import sway.nix module instead of i3wm.nix module
- **FR-025**: hetzner configuration MUST remain completely unchanged (imports, packages, services)
- **FR-026**: Both hetzner and hetzner-sway MUST be buildable and deployable simultaneously from same flake
- **FR-027**: hetzner-sway MUST disable X11/RDP services (xrdp, xserver) and use wayvnc instead
- **FR-028**: hetzner-sway MUST use identical application registry, project configurations, and i3pm scripts as hetzner

#### Multi-Monitor Support (Virtual Outputs)

- **FR-029**: System MUST support configuring multiple virtual outputs in headless mode (headless-0, headless-1, etc.)
- **FR-030**: System MUST use identical workspace-to-monitor distribution configuration as hetzner and M1
- **FR-031**: System MUST support monitor hotplug simulation for testing workspace distribution logic

### Key Entities

- **Headless Sway Session**: Wayland compositor running with WLR_BACKENDS=headless, no physical displays, creates virtual outputs with in-memory EGL framebuffers
- **Virtual Output**: Headless display (headless-0, headless-1) with configurable resolution and position, rendered in memory and exposed via VNC
- **wayvnc Configuration**: VNC server settings including port, authentication method, output selection - stored in ~/.config/wayvnc/config
- **hetzner-sway NixOS Configuration**: New flake output parallel to hetzner and M1 configurations, imports sway.nix instead of i3wm.nix
- **Project Context**: Identical to M1/hetzner i3 - active project name and directory stored in ~/.config/i3/active-project.json
- **Window Marks**: Project associations stored as Sway window marks (format: project:NAME:WINDOW_ID) - persisted in Sway's internal state

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can log into headless Sway session on Hetzner Cloud VM and perform basic window management operations (open, close, tile, focus, float) remotely via VNC with working keyboard and mouse input
- **SC-002**: i3pm daemon connects to headless Sway IPC within 2 seconds of session start and processes window events with <100ms latency
- **SC-003**: User can switch between projects via Meta+P and windows hide/show correctly within 500ms in VNC session
- **SC-004**: User can launch applications via Walker (Meta+D) remotely and all 7 providers function correctly (applications, calculator, files, symbols, websearch, runner, sesh, projects)
- **SC-005**: VNC session provides acceptable performance with window creation <500ms, workspace switching <200ms, and keyboard latency <100ms over typical internet connection
- **SC-006**: Multi-instance applications (VS Code) receive correct project marks with 100% accuracy for launches >2 seconds apart in headless environment
- **SC-007**: User can build and deploy both hetzner (i3) and hetzner-sway configurations from same flake without conflicts
- **SC-008**: Existing hetzner configuration remains unchanged and functional after hetzner-sway is added to repository
- **SC-009**: All Python daemon tests pass without modification when running against headless Sway (protocol compatibility verified)
- **SC-010**: System builds successfully with `nixos-rebuild dry-build --flake .#hetzner-sway` (no evaluation errors)

## Dependencies & Assumptions

### Dependencies

- **Sway package**: Available in nixpkgs with headless backend support (WLR_BACKENDS=headless)
- **wayvnc**: Available in nixpkgs for Wayland VNC server
- **i3ipc Python library**: Works with both i3 and Sway (same protocol, version 2.2+)
- **Walker/Elephant**: Already support native Wayland operation (configured in Feature 043)
- **wlroots**: Provides headless backend for Sway (part of Sway package)
- **Hetzner Cloud VM**: Linux VM with KVM virtualization, supports standard Wayland/EGL

### Assumptions

- Hetzner Cloud VMs support software rendering for Wayland compositors (CPU-based EGL via llvmpipe or pixman)
- Headless backend performance is acceptable for remote desktop use over VNC (based on swayvnc project success)
- All current applications (VS Code, Firefox, Alacritty, Ghostty) support Wayland natively and work in headless mode
- VNC protocol performance is acceptable for tiling window manager workflows (lower bandwidth than full desktop environments)
- Hetzner Cloud network latency allows for <200ms VNC response times (typical for European datacenter)
- wlroots headless backend can create arbitrary virtual outputs with configurable resolutions

## Out of Scope

- **M1 Configuration Changes**: Feature 045 handles M1 migration, Feature 046 only adds hetzner-sway
- **Existing Hetzner i3 Configuration**: hetzner configuration remains unchanged and supported
- **RDP Protocol**: VNC replaces RDP for remote access (RDP requires X11 or experimental weston-rdp)
- **GPU Acceleration**: Headless mode uses software rendering (llvmpipe/pixman), GPU passthrough not required
- **Audio Forwarding**: VNC protocol doesn't support audio (out of scope for headless server)
- **File Transfer Protocol**: VNC doesn't include file transfer (use scp/rsync separately)
- **Multi-User Sessions**: Single headless Sway session per user (VNC shares active session, not multi-session like RDP)
- **Hybrid i3/Sway Migration**: No gradual migration path, hetzner-sway is complete Sway replacement when activated

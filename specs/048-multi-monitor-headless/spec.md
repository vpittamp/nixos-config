# Feature Specification: Multi-Monitor Headless Sway/Wayland Setup

**Feature Branch**: `048-multi-monitor-headless`
**Created**: 2025-10-29
**Status**: Draft
**Input**: User description: "Multi-monitor headless Sway/Wayland setup for Hetzner Cloud VM with 3 virtual displays accessible via WayVNC over Tailscale"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Three Virtual Displays for Multi-Workspace Workflows (Priority: P1)

As a remote developer using a Hetzner Cloud VM, I want to access three independent virtual displays (HEADLESS-1, HEADLESS-2, HEADLESS-3) via VNC over Tailscale, so that I can organize my workspaces across multiple monitors on my local machine just like a physical multi-monitor setup.

**Why this priority**: This is the core feature request - enabling a multi-monitor workflow in a headless cloud environment. Without this, users are constrained to a single display, limiting productivity for workflows that benefit from spatial organization (e.g., code on one screen, documentation on another, terminal output on a third).

**Independent Test**: Can be fully tested by connecting three VNC clients (one to each port: 5900, 5901, 5902) over Tailscale and verifying each shows a distinct workspace view with independent window content.

**Acceptance Scenarios**:

1. **Given** a fresh Hetzner Cloud VM with Sway/Wayland configured for headless operation, **When** I connect a VNC client to port 5900 over Tailscale, **Then** I see HEADLESS-1 displaying workspaces 1-3
2. **Given** HEADLESS-1 is connected, **When** I connect a second VNC client to port 5901 over Tailscale, **Then** I see HEADLESS-2 displaying workspaces 4-6
3. **Given** HEADLESS-1 and HEADLESS-2 are connected, **When** I connect a third VNC client to port 5902 over Tailscale, **Then** I see HEADLESS-3 displaying workspaces 7-9
4. **Given** all three displays are connected, **When** I move a window to workspace 5, **Then** the window appears only on HEADLESS-2 (which shows workspaces 4-6)
5. **Given** all three displays are connected, **When** I focus workspace 8 via keyboard shortcut, **Then** HEADLESS-3 shows workspace 8 as active, and HEADLESS-1/2 remain unchanged

---

### User Story 2 - Dynamic Resolution and Layout Control (Priority: P2)

As a user with different VNC client setups (laptop, desktop, tablet), I want to configure the resolution and positioning of each virtual display independently, so that each VNC viewer shows content at the optimal size and clarity for my local screen.

**Why this priority**: Once basic multi-monitor support works (P1), users will need to adjust resolutions for different use cases (e.g., 1920x1080 for main work, 1280x720 for a side panel, 2560x1440 for a high-DPI display). This improves usability but isn't required for basic functionality.

**Independent Test**: Can be tested by changing resolution settings for one virtual output (e.g., HEADLESS-2 to 2560x1440) and verifying the VNC stream reflects the new resolution without affecting other outputs.

**Acceptance Scenarios**:

1. **Given** three virtual displays are configured, **When** I set HEADLESS-1 to 1920x1080, HEADLESS-2 to 2560x1440, and HEADLESS-3 to 1280x720, **Then** each VNC client receives a stream at the specified resolution
2. **Given** displays have different resolutions, **When** I position them horizontally (HEADLESS-1 at 0,0, HEADLESS-2 at 1920,0, HEADLESS-3 at 4480,0), **Then** workspaces respect the logical layout (no overlap or gaps)
3. **Given** a display is configured with 2560x1440 resolution, **When** I connect via VNC, **Then** text remains sharp and readable (no excessive compression or scaling blur)

---

### User Story 3 - Persistent Multi-Display Configuration Across Reboots (Priority: P3)

As a system administrator, I want the three-display configuration to persist across VM reboots and Sway restarts, so that I don't have to manually reconfigure outputs every time the system starts.

**Why this priority**: While important for production use, persistence can be added after the core functionality works. Users can manually reconfigure temporarily during testing phases.

**Independent Test**: Can be tested by configuring three displays, rebooting the VM, and verifying all three VNC endpoints are accessible with correct workspace assignments.

**Acceptance Scenarios**:

1. **Given** a configured three-display setup, **When** I reboot the VM, **Then** all three VNC servers start automatically on ports 5900-5902
2. **Given** workspaces 1-3 were assigned to HEADLESS-1 before reboot, **When** the system restarts, **Then** workspaces 1-3 remain assigned to HEADLESS-1
3. **Given** custom resolutions were set for each display, **When** Sway restarts, **Then** each display retains its configured resolution and position

---

### User Story 4 - Integration with Existing i3pm Workspace Management (Priority: P2)

As a user of the i3pm project management system, I want workspace assignments to automatically distribute across all three displays based on monitor count detection, so that projects use the full multi-monitor layout without manual configuration.

**Why this priority**: Critical for users who rely on i3pm for workspace organization. Without this, the multi-monitor setup won't integrate with existing workflows.

**Independent Test**: Can be tested by switching projects and verifying workspaces distribute across three displays (e.g., WS 1-2 on HEADLESS-1, WS 3-5 on HEADLESS-2, WS 6-9 on HEADLESS-3) automatically.

**Acceptance Scenarios**:

1. **Given** three headless displays are active, **When** i3pm detects monitor count, **Then** it reports 3 outputs and assigns workspaces accordingly (1-2 primary, 3-5 secondary, 6-9 tertiary)
2. **Given** a project is active with scoped applications, **When** I switch projects, **Then** windows from the old project hide across all three displays, and new project windows restore to their correct displays
3. **Given** three displays are configured, **When** I run `i3pm monitors status`, **Then** it shows HEADLESS-1, HEADLESS-2, and HEADLESS-3 with their workspace assignments

---

### Edge Cases

- What happens when a VNC client disconnects from one display while others remain connected? (Expected: That display remains active but unviewed; workspaces continue functioning)
- How does the system handle workspace focus when no VNC clients are connected? (Expected: Sway continues managing workspaces normally; they become visible when VNC clients reconnect)
- What happens if WayVNC instances fail to start on different ports due to port conflicts? (Expected: Clear error messages in systemd logs indicating which port failed and why)
- How does window positioning behave across displays with different resolutions? (Expected: Windows maintain their workspace assignment; positioning is relative to the output's resolution)
- What happens when I try to move a window to a workspace on a non-existent fourth display? (Expected: Graceful fallback to an existing display or error message)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST create three independent headless Wayland outputs (HEADLESS-1, HEADLESS-2, HEADLESS-3) at Sway compositor startup
- **FR-002**: System MUST run three separate WayVNC server instances, each bound to a unique port (5900, 5901, 5902) and capturing a single output (HEADLESS-1, HEADLESS-2, HEADLESS-3 respectively)
- **FR-003**: System MUST configure Sway workspace assignments to distribute workspaces 1-9 across three outputs (e.g., 1-3 on HEADLESS-1, 4-6 on HEADLESS-2, 7-9 on HEADLESS-3)
- **FR-004**: System MUST allow independent resolution configuration for each headless output via Sway output configuration
- **FR-005**: System MUST allow independent positioning configuration for each headless output to create a logical multi-monitor layout (horizontal, vertical, or custom)
- **FR-006**: System MUST persist WayVNC service configuration across VM reboots via systemd user services with auto-restart on failure
- **FR-007**: System MUST expose VNC ports (5900-5902) only on the Tailscale network interface (tailscale0) for security
- **FR-008**: System MUST integrate with i3pm monitor detection to recognize three headless outputs and apply workspace distribution rules
- **FR-009**: System MUST ensure each WayVNC instance starts only after Sway compositor is fully initialized (IPC socket available)
- **FR-010**: System MUST provide clear systemd service status and logging for each WayVNC instance to facilitate troubleshooting
- **FR-011**: System MUST use wlroots headless backend (WLR_BACKENDS=headless) with software rendering (WLR_RENDERER=pixman) for VM compatibility
- **FR-012**: System MUST set WLR_HEADLESS_OUTPUTS=3 in greetd auto-login wrapper and environment.sessionVariables to create three virtual displays at compositor startup

### Key Entities

- **Headless Output**: A virtual display created by the wlroots headless backend (e.g., HEADLESS-1, HEADLESS-2, HEADLESS-3), with configurable resolution, position, and scale, representing one "monitor" in the multi-display setup
- **WayVNC Instance**: A VNC server process bound to a specific headless output and TCP port, streaming that output's contents to VNC clients over Tailscale
- **Workspace Assignment**: A mapping between Sway workspace numbers (1-9) and headless outputs, determining which display shows which workspaces
- **Systemd Template Service**: A parameterized systemd user service (wayvnc@.service) that accepts output name and port as parameters to instantiate multiple VNC servers

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can connect three independent VNC clients simultaneously (one per port: 5900, 5901, 5902) and view distinct workspace content on each client
- **SC-002**: Each VNC stream updates in real-time with window changes (new windows, moves, resizes) with latency under 200ms over Tailscale connection
- **SC-003**: Workspace switching via keyboard shortcuts (Ctrl+1 through Ctrl+9) correctly activates workspaces on the appropriate display based on workspace-to-output assignments
- **SC-004**: After VM reboot, all three WayVNC services start automatically within 10 seconds of Sway compositor initialization
- **SC-005**: VNC ports (5900-5902) are NOT accessible from public internet (only via Tailscale), verified by attempting external connections
- **SC-006**: i3pm monitor detection command reports 3 outputs and correctly distributes workspaces according to multi-monitor rules
- **SC-007**: Users can modify resolution for any single output (e.g., change HEADLESS-2 to 2560x1440) and reload Sway configuration without affecting other outputs
- **SC-008**: All WayVNC service logs are accessible via journalctl for debugging (e.g., `journalctl --user -u wayvnc@HEADLESS-1 -f`)

## Assumptions *(mandatory for AI-generated specs)*

1. **VNC Protocol Choice**: We assume WayVNC remains the protocol (as stated in requirements) rather than alternatives like Sunshine/NVENC, which have known stability issues with headless wlroots on VMs
2. **Workspace Distribution**: We assume the standard i3pm multi-monitor workspace distribution (1-2 primary, 3-5 secondary, 6-9 tertiary) applies to headless displays just as it does to physical monitors
3. **Resolution Defaults**: We assume 1920x1080@60Hz for all three outputs unless user specifies otherwise, balancing clarity with VNC compression efficiency
4. **Port Selection**: We assume ports 5900-5902 are available and not used by other services on the Hetzner Cloud VM
5. **Tailscale Configuration**: We assume Tailscale is already configured and connected (networking.firewall.interfaces."tailscale0" rule exists in current config)
6. **systemd Template Approach**: We assume using systemd template services (wayvnc@.service) is the preferred approach over three separate service definitions for maintainability
7. **Greetd Auto-Login**: We assume the existing greetd auto-login mechanism (configurations/hetzner-sway.nix:66-87) should be extended to set WLR_HEADLESS_OUTPUTS=3 instead of 1
8. **Software Rendering**: We assume pixman software rendering (WLR_RENDERER=pixman) is required for Hetzner Cloud VMs (no GPU acceleration available)
9. **Single User**: We assume single-user configuration (vpittamp) rather than multi-user VNC sessions
10. **Sway-Config-Manager Integration**: We assume the existing sway-config-manager (Feature 047) should be updated to support multi-output configurations dynamically

## Open Questions (Maximum 3 Clarifications)

None - all critical decisions have reasonable defaults documented in Assumptions section. If user has specific preferences (e.g., different workspace distribution, alternative resolutions, different port numbers), these can be refined during planning phase.

## Dependencies

- **External**: wlroots headless backend, WayVNC 0.8+ (for headless output support), Sway 1.5+ (for runtime output creation), Tailscale
- **Internal**: Existing i3pm monitor detection/reassignment system (Feature 033), sway-config-manager (Feature 047), greetd auto-login configuration, systemd user services framework
- **Configuration Files**:
  - `/etc/nixos/configurations/hetzner-sway.nix` (greetd wrapper, environment variables, firewall rules)
  - `/etc/nixos/home-modules/desktop/sway.nix` (output configuration, workspace assignments)
  - `~/.config/i3/monitors-config.json` (i3pm monitor detection rules)

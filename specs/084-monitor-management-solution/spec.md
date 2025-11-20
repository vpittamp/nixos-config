# Feature Specification: M1 Hybrid Multi-Monitor Management

**Feature Branch**: `084-monitor-management-solution`
**Created**: 2025-11-19
**Status**: Draft
**Input**: User description: "M1 hybrid local plus VNC multi-monitor support with profile switching - same resolution as Hetzner, manual activation via menu, workspace expansion to 1-100+, keybinding Mod+Shift+M to cycle profiles"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Activate VNC Display from Local Machine (Priority: P1)

A user working on their M1 MacBook Pro wants to extend their workspace to an iPad or secondary computer via VNC. They press a keyboard shortcut or select from a menu to activate one or more virtual VNC displays alongside their physical Retina display.

**Why this priority**: This is the core value proposition - enabling users to expand their workspace without requiring additional physical monitors. The physical display remains primary for local work while VNC displays provide supplementary screen real estate accessible from any VNC client.

**Independent Test**: Can be fully tested by activating a VNC profile and connecting from a VNC client on another device. Delivers immediate value of extended desktop space.

**Acceptance Scenarios**:

1. **Given** user is on M1 with only physical display active, **When** user presses `Mod+Shift+M`, **Then** system presents profile selection menu showing available configurations (local-only, local+1vnc, local+2vnc)

2. **Given** profile menu is displayed, **When** user selects "local+1vnc", **Then** system creates a virtual display accessible via VNC on port 5900 within 2 seconds

3. **Given** VNC display is activated, **When** user connects via VNC client from another device, **Then** user sees the virtual display and can interact with windows on it

4. **Given** VNC display is active with windows, **When** user switches to "local-only" profile, **Then** windows from VNC display are moved to physical display and VNC service stops

---

### User Story 2 - Workspace Distribution Across Displays (Priority: P2)

A user with multiple displays active wants their workspaces automatically distributed across all available monitors according to sensible defaults, with the ability to customize which workspaces appear on which display.

**Why this priority**: Once displays are active, users need their workspace organization to make sense. Without automatic distribution, all workspaces would remain on the primary display, defeating the purpose of multiple monitors.

**Independent Test**: Can be tested by switching profiles and verifying workspaces move to appropriate displays. Delivers value of organized multi-display workflow.

**Acceptance Scenarios**:

1. **Given** user activates "local+2vnc" profile, **When** profile switch completes, **Then** workspaces are distributed: 1-3 on physical display, 4-6 on VNC-1, 7-9 on VNC-2

2. **Given** user has windows on workspace 5 (VNC-1), **When** user switches to "local-only" profile, **Then** workspace 5 and its windows are accessible on the physical display

3. **Given** user is in "local+1vnc" mode, **When** user creates workspace 50 (PWA workspace), **Then** system assigns it to appropriate display based on workspace-to-monitor role mapping

---

### User Story 3 - Visual Feedback for Monitor Status (Priority: P3)

A user wants to see at a glance which displays are currently active and which profile is in use, displayed in the system bar.

**Why this priority**: Visual feedback improves usability and helps users understand system state, but the feature is functional without it. This enhances the user experience of the core functionality.

**Independent Test**: Can be tested by switching profiles and observing top bar updates. Delivers value of situational awareness.

**Acceptance Scenarios**:

1. **Given** user switches to "local+1vnc" profile, **When** top bar updates, **Then** bar shows profile name and indicators for active displays (L for local, V1/V2 for VNC displays)

2. **Given** VNC display V1 has 3 workspaces assigned, **When** user views top bar, **Then** V1 indicator shows workspace count

3. **Given** profile switch is in progress, **When** user views top bar, **Then** update completes within 100ms of profile change

---

### User Story 4 - Secure Remote Access via Tailscale (Priority: P4)

A user wants VNC access restricted to their Tailscale network to ensure only their authorized devices can connect to the virtual displays.

**Why this priority**: Security is important but the feature works without it (with appropriate warnings). This ensures production-ready security posture.

**Independent Test**: Can be tested by attempting VNC connection from Tailscale device (succeeds) vs non-Tailscale device (fails). Delivers value of secure remote access.

**Acceptance Scenarios**:

1. **Given** VNC display is active, **When** user connects from device on Tailscale network, **Then** connection succeeds

2. **Given** VNC display is active, **When** connection attempt comes from non-Tailscale IP, **Then** connection is refused by firewall

---

### Edge Cases

- What happens when VNC client disconnects while windows are on that display? (Windows remain on virtual display until profile changes)
- How does system handle profile switch while VNC client is connected? (Client is disconnected gracefully with notification)
- What happens if user tries to create more virtual outputs than supported? (System limits to 2 VNC displays with user notification)
- How does system behave if virtual output creation fails? (Profile switch fails with error notification, previous profile remains active)
- What happens to fullscreen applications during profile switch? (Unfullscreen, move to available display, user can re-fullscreen)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support three monitor profiles: local-only (physical display only), local+1vnc (physical + 1 virtual), local+2vnc (physical + 2 virtual)
- **FR-002**: System MUST create virtual displays dynamically when profiles are activated (not at system startup)
- **FR-003**: System MUST provide VNC access to virtual displays on ports 5900 (VNC-1) and 5901 (VNC-2)
- **FR-004**: Users MUST be able to switch profiles via keyboard shortcut (`Mod+Shift+M`)
- **FR-005**: Users MUST be able to switch profiles via interactive menu
- **FR-006**: System MUST distribute workspaces across available displays when profile changes
- **FR-007**: System MUST move windows from disabled displays to remaining displays during profile switch
- **FR-008**: System MUST display current profile and active displays in the top bar
- **FR-009**: System MUST update top bar within 100ms of profile change
- **FR-010**: System MUST restrict VNC access to Tailscale network interface only
- **FR-011**: System MUST support workspaces numbered 1 through 100+ (no upper bound)
- **FR-012**: System MUST maintain physical display (eDP-1) as always-on primary display
- **FR-013**: Virtual displays MUST use 1920x1080 resolution at 60Hz
- **FR-014**: System MUST preserve window state (size, position) when moving between displays during profile switch
- **FR-015**: System MUST provide notification when profile switch completes or fails

### Key Entities

- **Monitor Profile**: Named configuration defining which displays are active (e.g., "local+1vnc"), their positions, and workspace assignments
- **Virtual Display**: Dynamically created headless output accessible via VNC, identified as HEADLESS-1 or HEADLESS-2
- **Physical Display**: The built-in Retina display (eDP-1) that is always active and serves as primary
- **Workspace Assignment**: Mapping of workspace numbers to monitor roles (primary/secondary/tertiary)
- **Display State**: Current enabled/disabled status of each display, persisted for the active profile

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can switch monitor profiles within 2 seconds including all display and service activation
- **SC-002**: VNC clients can connect to virtual displays within 5 seconds of profile activation
- **SC-003**: Top bar updates reflect profile changes within 100ms
- **SC-004**: 100% of windows from disabled displays are successfully moved to remaining displays during profile switch
- **SC-005**: Users can access workspaces 1-100+ without errors across all profile configurations
- **SC-006**: VNC connections from non-Tailscale networks are blocked with 100% effectiveness
- **SC-007**: Profile switching succeeds on first attempt in 99% of cases (less than 1% require retry)
- **SC-008**: System supports daily profile switching (10+ switches per day) without degradation or memory leaks

## Assumptions

- User has Tailscale configured and connected on M1 machine
- User has VNC client software on secondary device (iPad, other computer)
- GPU acceleration remains available for physical display when virtual displays are active
- Workspace-to-monitor assignment logic from Hetzner implementation (Feature 083) can be adapted for hybrid mode
- The i3pm daemon's existing profile management and Eww publisher components can be extended for M1

## Dependencies

- Feature 083 (Multi-Monitor Window Management) - provides profile switching foundation
- Feature 048 (Multi-Monitor Headless) - provides WayVNC service configuration patterns
- Feature 001 (Declarative Workspace-to-Monitor Assignment) - provides workspace distribution logic
- Feature 049 (Auto Workspace Monitor Redistribution) - provides window migration during profile changes

## Out of Scope

- Audio routing between physical and virtual displays
- Clipboard synchronization across VNC connections
- Multiple simultaneous VNC clients on same virtual display
- GPU-accelerated rendering on virtual displays (uses software rendering)
- Custom resolution per VNC display (all use 1920x1080)
- Integration with external HDMI/USB-C monitors (future enhancement)

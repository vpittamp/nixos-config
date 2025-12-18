# Feature Specification: Monitoring Panel Click-Through Fix and Docking Mode

**Feature Branch**: `125-convert-sidebar-split-pane`
**Created**: 2025-12-18
**Status**: Draft
**Input**: User description: "create a new feature to enhance our eww monitoring widget. when the widget is hidden, the mouse still thinks the ui is there which blocks our clicks in that area for all other applications. review prior git history from relevant branches to review how we've fixed this in the past. be careful to not lose optimizations that we've made to the widget to limit cpu usage. second, we want to update our sway / window configuration / project management solution to allow us to 'dock' the monitoring widget, and in doing so, other windows that share its monitor should only take the available space less the expanded monitoring widget. use grim to take screenshots to confirm how the ui looks before and after changes"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Click-Through When Panel Hidden (Priority: P1)

As a user, when the monitoring panel is hidden or collapsed, I want to be able to click on windows and UI elements in the area where the panel would normally appear, without the hidden panel intercepting my clicks.

**Why this priority**: This is a usability blocker. When the panel is hidden but still intercepts clicks, users cannot interact with a significant portion of their screen (550px width on the right side). This fundamentally breaks the expected behavior of a "hidden" panel.

**Independent Test**: Can be fully tested by hiding the monitoring panel and attempting to click on windows positioned in the right-side region where the panel would appear. Success means clicks reach the underlying windows.

**Acceptance Scenarios**:

1. **Given** the monitoring panel is hidden (not visible on screen), **When** I click on a window or UI element in the right 550px region of the monitor, **Then** my click is received by that window/element (not intercepted by the invisible panel)

2. **Given** the monitoring panel is hidden, **When** I drag a window into the right-side region where the panel would appear, **Then** I can interact with that window normally without interference

3. **Given** the monitoring panel is visible and in "overlay" mode (not docked), **When** I click on the panel, **Then** the panel receives my click and responds appropriately

4. **Given** the monitoring panel transitions from visible to hidden, **When** the hide animation completes, **Then** the click-through behavior activates immediately (within 100ms)

---

### User Story 2 - Docked Panel Mode with Reserved Space (Priority: P2)

As a user, I want to be able to "dock" the monitoring panel to the side of my screen, so that other windows automatically resize to fill only the remaining screen space (excluding the docked panel area).

**Why this priority**: This enables a permanent monitoring workflow where the panel is always visible alongside tiled windows. Without reserved space, tiled windows render underneath the panel, making content unreadable.

**Independent Test**: Can be fully tested by toggling dock mode and observing that existing and new tiled windows adjust their geometry to respect the reserved panel space.

**Acceptance Scenarios**:

1. **Given** the monitoring panel is in docked mode, **When** I tile a window on the same monitor, **Then** the window fills only the available space (monitor width minus panel width)

2. **Given** multiple windows are tiled on the monitor, **When** I enable dock mode for the monitoring panel, **Then** all existing tiled windows resize to accommodate the reserved panel space

3. **Given** the monitoring panel is docked, **When** I disable dock mode, **Then** tiled windows expand to fill the full monitor width

4. **Given** I am on a multi-monitor setup with the panel docked on monitor 1, **When** I tile windows on monitor 2, **Then** those windows use the full width of monitor 2 (unaffected by panel on monitor 1)

---

### User Story 3 - Toggle Between Overlay and Docked Modes (Priority: P2)

As a user, I want to press `Mod+Shift+M` to cycle between overlay mode (panel floats over windows) and docked mode (panel reserves screen space).

**Why this priority**: Different workflows benefit from different modes. Quick switching allows adapting to context (e.g., overlay for temporary checks, docked for extended monitoring sessions).

**Independent Test**: Can be fully tested by using the toggle mechanism and observing immediate mode switch with appropriate window geometry changes.

**Acceptance Scenarios**:

1. **Given** the panel is in overlay mode, **When** I press `Mod+Shift+M`, **Then** the panel transitions to docked mode and existing windows resize within 500ms

2. **Given** the panel is in docked mode, **When** I press `Mod+Shift+M`, **Then** the panel transitions to overlay mode and windows expand to full width within 500ms

3. **Given** I toggle dock mode, **When** I restart my session later, **Then** the panel remembers my last dock mode preference

---

### User Story 4 - Preserve CPU Optimizations (Priority: P1)

As a user, I want the monitoring panel to maintain its current low CPU usage (approximately 6% system load contribution) regardless of which mode (overlay vs docked) I choose.

**Why this priority**: High CPU usage from UI widgets degrades overall system performance and battery life. Previous optimizations (deflisten over defpoll, disabled unused tabs, extended polling intervals) must be preserved.

**Independent Test**: Can be tested by monitoring system CPU usage with the panel in each mode and during mode transitions.

**Acceptance Scenarios**:

1. **Given** the monitoring panel is visible in any mode, **When** I measure CPU usage over a 60-second period, **Then** the panel contributes less than 7% to total system load

2. **Given** the monitoring panel is hidden, **When** I measure CPU usage, **Then** the panel contributes negligible CPU load (under 1%)

3. **Given** I toggle between modes repeatedly, **When** I measure CPU usage, **Then** there are no sustained CPU spikes or memory leaks

---

### Edge Cases

- What happens when the panel is docked and the user connects/disconnects an external monitor?
  - Panel should remain docked to its configured monitor; space reservation applies only to that monitor

- What happens when switching workspaces while the panel is docked?
  - Docked panel reservation should persist across workspace switches on the same monitor

- How does the system handle rapid show/hide toggling (debounce)?
  - Existing 1-second debounce mechanism (lockfile) must be preserved to prevent crashes

- What happens if the user tries to dock the panel when screen width is too narrow?
  - Panel should refuse to dock if remaining usable width would be less than 400px; display a notification explaining the constraint

- What happens when the panel is docked but hidden (via `Mod+M`)?
  - Reserved screen space remains reserved; windows stay in reduced area for consistent layouts. Users wanting full-width windows should switch to overlay mode first.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow mouse clicks to pass through to underlying windows when the monitoring panel is hidden
- **FR-002**: System MUST provide a "docked" mode where the monitoring panel reserves screen space via Sway's exclusive zone mechanism
- **FR-003**: System MUST use `Mod+Shift+M` to cycle between overlay mode and docked mode (repurposing the existing focus mode keybinding)
- **FR-004**: System MUST ensure tiled windows on the same monitor as a docked panel automatically resize to fit the remaining screen space
- **FR-005**: System MUST persist the user's dock mode preference across session restarts
- **FR-006**: System MUST preserve existing CPU optimizations including: deflisten-based updates, disabled polling for unused tabs, 30-second build health polling interval
- **FR-007**: System MUST maintain the existing debounce mechanism (1-second lockfile) to prevent rapid toggle crashes
- **FR-008**: System MUST support dock mode on multi-monitor setups, affecting only the monitor where the panel is displayed
- **FR-009**: System MUST allow the panel to remain functional (clickable, scrollable) when visible in either mode
- **FR-010**: System MUST provide visual feedback indicating current mode (overlay vs docked) to the user
- **FR-011**: System MUST maintain reserved screen space when panel is docked but hidden (via `Mod+M`), ensuring consistent window layouts

### Key Entities

- **Monitoring Panel Window**: The eww layer-shell surface with configurable exclusive zone and focusability properties
- **Dock Mode State**: Boolean preference stored persistently, controlling whether the panel reserves screen space
- **Panel Visibility State**: Existing state tracking whether panel is shown/hidden (via eww open/close commands)
- **Exclusive Zone Configuration**: Sway layer-shell property determining space reservation (struts configuration)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can click on windows in the panel region within 100ms of panel being hidden (no click-blocking)
- **SC-002**: When docked, tiled windows use exactly (monitor_width - panel_width) horizontal space
- **SC-003**: Mode toggle (overlay to docked or vice versa) completes with visible window resize within 500ms
- **SC-004**: Panel CPU contribution remains under 7% during normal operation (matching current optimized baseline)
- **SC-005**: Dock mode preference persists correctly across 100% of session restarts
- **SC-006**: No increase in eww-monitoring-panel service restart frequency compared to current baseline

## Clarifications

### Session 2025-12-18

- Q: Which keybinding should toggle between overlay and docked modes? → A: `Mod+Shift+M` cycles through modes (overlay → docked → overlay), repurposing the existing focus mode keybinding
- Q: When panel is docked but hidden, should reserved space remain? → A: Yes, space remains reserved when hidden (windows stay in reduced area) for consistent layouts

## Assumptions

- The existing eww-monitoring-panel service architecture will be preserved (Nix-based configuration, yuck widgets, systemd service)
- The panel will remain anchored to the right side of the screen (no support for left/top/bottom docking in this feature)
- The existing keybinding `Mod+M` for toggle visibility is preserved; `Mod+Shift+M` is repurposed from focus mode to dock mode cycling
- Screenshot verification will use grim tool as specified by user
- The default mode for new installations will be overlay (matching current behavior)

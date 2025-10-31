# Feature Specification: Waybar Integration

**Feature Branch**: `052-waybar-integration`
**Created**: 2025-10-31
**Status**: Draft
**Input**: User description: "Integrate Waybar as enhanced status bar replacement for swaybar with GTK styling, hover effects, and click handlers while preserving i3pm event-driven architecture"

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.
  
  Assign priorities (P1, P2, P3, etc.) to each story, where P1 is the most critical.
  Think of each story as a standalone slice of functionality that can be:
  - Developed independently
  - Tested independently
  - Deployed independently
  - Demonstrated to users independently
-->

### User Story 1 - Visual Status Bar with Icons and Hover Effects (Priority: P1)

As a system user, I want to see battery, WiFi, volume, and system metrics with clear icons and visual feedback when I hover over them, so that I can quickly understand my system's status and get detailed information on demand.

**Why this priority**: This is the core visual enhancement that justifies the migration from swaybar to Waybar. It provides immediate value by making system information more accessible and visually appealing.

**Independent Test**: Can be fully tested by viewing the status bar and hovering over modules. Delivers instant visual feedback and improved information density.

**Acceptance Scenarios**:

1. **Given** the status bar is visible, **When** I look at the battery module, **Then** I see an icon representing the current charge level (full, 3/4, 1/2, 1/4, low) with the percentage displayed
2. **Given** I hover over the battery icon, **When** the cursor enters the module area, **Then** the module changes appearance (color, glow, or highlight) and shows a tooltip with detailed battery information (time remaining, charging status, health)
3. **Given** the status bar is visible, **When** I look at the WiFi module, **Then** I see the network icon, SSID name, and signal strength with color-coded strength indication
4. **Given** I hover over any status module, **When** the cursor moves over it, **Then** a visual hover effect appears within 50ms

---

### User Story 2 - Interactive Click Handlers (Priority: P2)

As a system user, I want to click on status bar modules to perform quick actions (toggle mute, switch projects, open settings), so that I can control my system without using keyboard shortcuts.

**Why this priority**: Interactive controls significantly enhance usability for mouse users and provide alternative interaction methods beyond keyboard shortcuts.

**Independent Test**: Can be tested by clicking each module and verifying the expected action occurs. Works independently of other features.

**Acceptance Scenarios**:

1. **Given** the volume module is visible, **When** I click on it, **Then** the audio is muted/unmuted and the icon updates to reflect the new state
2. **Given** the volume module is visible, **When** I scroll up/down on it, **Then** the system volume increases/decreases by 5% and the percentage updates
3. **Given** the project module is visible, **When** I click on it, **Then** the project switcher (Walker) opens showing available projects
4. **Given** any status module is visible, **When** I right-click on it, **Then** a context menu with module-specific options appears

---

### User Story 3 - Preserved Event-Driven Architecture (Priority: P1)

As a system administrator, I want the i3pm daemon to continue broadcasting project context updates to the status bar in real-time, so that the existing event-driven architecture is maintained without performance degradation.

**Why this priority**: This is critical for maintaining system consistency. Breaking the event-driven integration would require rewriting the i3pm daemon and status update mechanism.

**Independent Test**: Can be tested by switching projects and verifying the status bar updates within 100ms without polling. Existing i3pm daemon tests confirm compatibility.

**Acceptance Scenarios**:

1. **Given** the i3pm daemon is running, **When** I switch to a different project using `pswitch nixos`, **Then** the status bar project module updates within 100ms to show "nixos"
2. **Given** the status bar is displaying project "stacks", **When** the daemon broadcasts a project change event, **Then** Waybar receives the signal and updates without requiring a restart
3. **Given** workspace mode is active (→ WS, ⇒ WS, ✖ WS), **When** I enter the mode, **Then** the status bar shows the mode indicator with the same visual appearance as before
4. **Given** existing status scripts are running, **When** Waybar starts, **Then** all custom modules execute the existing shell scripts without modification

---

### User Story 4 - CSS Styling and Customization (Priority: P3)

As a system administrator, I want to customize the status bar appearance using CSS (colors, fonts, spacing, borders), so that it matches my desktop theme and preferences.

**Why this priority**: Visual customization is valuable but not essential for core functionality. Can be implemented after basic integration is working.

**Independent Test**: Can be tested by modifying the CSS file and verifying visual changes appear immediately. Independent of other features.

**Acceptance Scenarios**:

1. **Given** a Waybar CSS configuration file exists, **When** I change the background color for the battery module, **Then** the module's background updates to the new color on next reload
2. **Given** I want to emphasize the project module, **When** I add a border and padding to it via CSS, **Then** the module displays the custom styling
3. **Given** I'm using the Catppuccin Mocha theme, **When** I apply theme colors to all modules, **Then** the status bar matches the existing color scheme
4. **Given** the CSS file is updated, **When** I reload Sway configuration, **Then** all CSS changes take effect without restarting the daemon

---

### Edge Cases

- What happens when Waybar fails to start but Sway is running?
  - System falls back to headless mode with no status bar, or displays error in notification

- How does the system handle signal-based updates if Waybar crashes mid-session?
  - i3pm daemon continues running, signals are queued, Waybar reconnects on restart and receives latest state

- What happens if custom module scripts have errors or timeouts?
  - Waybar displays error state for that module, other modules continue working

- How are multiple monitors handled with different resolutions?
  - Each monitor gets its own Waybar instance with appropriate scaling (HiDPI vs standard)

- What happens during transition if both swaybar and Waybar configurations exist?
  - Sway loads only one bar based on configuration precedence, old swaybar config is commented out

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display battery, WiFi, volume, Bluetooth, load, memory, and date/time with Font Awesome icons
- **FR-002**: System MUST show hover effects (color change, glow, or highlight) when cursor enters a module area
- **FR-003**: System MUST execute click handlers for volume (click to mute, scroll to adjust), project (click to switch), and other interactive modules
- **FR-004**: System MUST receive signals from i3pm daemon for project context updates without polling
- **FR-005**: System MUST support custom module definitions that execute existing shell scripts (project status, workspace mode indicator)
- **FR-006**: System MUST use CSS for styling all modules with per-module class selectors
- **FR-007**: System MUST display tooltips on hover with detailed information for battery (time remaining), WiFi (IP address), and volume (device name)
- **FR-008**: System MUST maintain dual-bar layout (top bar: system monitoring, bottom bar: project context + workspaces)
- **FR-009**: System MUST support multi-monitor configurations with independent Waybar instances per output
- **FR-010**: System MUST gracefully handle custom module script errors by showing error state without crashing
- **FR-011**: System MUST reload configuration via `swaymsg reload` without requiring daemon restart
- **FR-012**: System MUST preserve existing workspace mode indicators (→ WS, ⇒ WS, ✖ WS) with matching visual style

### Key Entities *(include if feature involves data)*

- **Waybar Configuration**: JSON-based module definitions, positions, and behavior settings (located in `~/.config/waybar/config`)
- **Waybar Stylesheet**: CSS file defining colors, fonts, spacing, hover effects, and module-specific styling
- **Custom Module Scripts**: Shell scripts executed by Waybar that provide dynamic content (project status, workspace mode state)
- **Signal Mappings**: Configuration defining which POSIX signals (RTMIN+N) trigger updates for which custom modules
- **Module State**: Current data displayed by each module (battery percentage, WiFi SSID, project name)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify system status (battery, network, volume) at a glance without reading text (via icons and color coding)
- **SC-002**: Hover effects appear within 50ms of cursor entering a module area
- **SC-003**: Click actions execute within 100ms (volume toggle, project switcher)
- **SC-004**: Status bar updates reflect daemon events within 100ms of signal broadcast (no polling overhead)
- **SC-005**: Custom module scripts execute without modification from current implementation (100% backward compatibility)
- **SC-006**: Visual appearance matches existing Catppuccin Mocha theme after CSS styling
- **SC-007**: Multi-monitor setup displays independent status bars on each output with correct workspace assignments
- **SC-008**: Configuration reload completes in under 500ms without daemon restart
- **SC-009**: System resource usage (CPU, memory) remains comparable to swaybar baseline (within 10% increase)
- **SC-010**: Tooltip information displays within 200ms of hover for all modules with extended data

## Assumptions *(if any)*

- Waybar is available in nixpkgs and supports NixOS declarative configuration
- Existing status bar scripts output data compatible with Waybar's expected JSON format (or can be easily adapted)
- i3pm daemon's signal-based broadcast mechanism works with Waybar's custom module signal handling
- Font Awesome fonts are already installed and available to Waybar
- CSS styling can fully replicate the Catppuccin Mocha color scheme
- GTK3 is acceptable as a dependency for the status bar
- Users have basic understanding of JSON and CSS for configuration customization

## Out of Scope *(if applicable)*

- Rewriting i3pm daemon to use different event broadcast mechanism
- Creating custom Waybar plugins in C++ (using custom modules with shell scripts instead)
- Wayland protocol extensions or compositor modifications
- Real-time graphs or animated visualizations beyond simple hover effects
- Integration with non-Sway window managers (feature is Sway-specific)
- Network manager GUI integration (using existing nmcli commands)
- Audio mixer GUI integration (using existing pactl/PipeWire controls)

## Dependencies *(if any)*

- **Waybar** must be installed and configured in NixOS
- **i3pm daemon** must continue running with signal broadcast capability
- **Font Awesome** fonts must be available for icon rendering
- **Existing status scripts** must output data in format compatible with Waybar custom modules
- **Sway configuration** must load Waybar instead of swaybar
- **GTK3** must be available for Waybar runtime

## Migration Strategy *(if replacing existing component)*

### Phase 1: Dual Configuration (Safe Rollback)
1. Keep existing swaybar configuration commented out in `swaybar.nix`
2. Add Waybar configuration alongside existing setup
3. Test Waybar with basic modules first (no custom scripts)
4. Verify multi-monitor behavior matches current setup

### Phase 2: Custom Module Integration
1. Port existing status scripts to Waybar custom module format
2. Configure signal-based updates for project context module
3. Test event-driven integration with i3pm daemon
4. Validate <100ms update latency

### Phase 3: Visual Enhancements
1. Apply CSS styling to match Catppuccin Mocha theme
2. Configure hover effects for all modules
3. Add click handlers for interactive modules
4. Implement tooltips with extended information

### Phase 4: Cleanup and Documentation
1. Remove swaybar configuration after 1-week stable operation
2. Document Waybar customization in CLAUDE.md
3. Create rollback instructions for emergency reversion
4. Update quickstart guide with new status bar capabilities

### Rollback Procedure
If issues arise, rollback by:
1. Comment out Waybar configuration in home-manager
2. Uncomment swaybar configuration
3. Run `home-manager switch --flake .#m1`
4. Reload Sway with `swaymsg reload`

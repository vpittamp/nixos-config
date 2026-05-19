# Feature Specification: Unified Eww Device Control Panel

**Feature Branch**: `116-use-eww-device`
**Created**: 2025-12-13
**Status**: Draft
**Input**: User description: "Create a feature to control device-related gauges/switches on bare metal using Eww. Determine the best placement (monitoring panel tab, top bar, etc.). Review open-source Eww examples for great UI. Integrate seamlessly, avoid duplication. Consider: Bluetooth, volume, brightness. Target ThinkPad and Ryzen machines."

## Clarifications

### Session 2025-12-13

- Q: How should the expanded top bar device panel be dismissed? → A: Click outside panel dismisses it (click-outside-to-close)
- Q: What is the relationship between top bar controls and monitoring panel Devices tab? → A: Top bar provides quick controls (sliders/toggles); Monitoring panel provides full dashboard with additional details

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quick Device Access from Top Bar (Priority: P1)

A developer working on their ThinkPad laptop needs to quickly adjust volume before a video call, check battery status, toggle Bluetooth to connect headphones, and reduce screen brightness as the room darkens. They want to do this without leaving their current workspace or opening a separate application.

**Why this priority**: This is the core use case - fast, non-disruptive device control during active work. Top bar placement provides constant visibility and one-click access matching OS-native control center patterns users already know.

**Independent Test**: Can be fully tested by clicking the device indicator in the top bar, seeing the expanded control panel, adjusting a slider, and observing the device change in real-time.

**Acceptance Scenarios**:

1. **Given** user is working in any application on ThinkPad, **When** they click the volume icon in the top bar, **Then** an expanded panel appears showing a volume slider with current percentage and mute toggle
2. **Given** the volume panel is visible, **When** user drags the slider to 75%, **Then** system volume changes immediately with visual feedback confirming the new level
3. **Given** user has Bluetooth headphones nearby, **When** they click the Bluetooth icon in the top bar, **Then** they see Bluetooth on/off toggle and a list of paired devices with connection status
4. **Given** user is on a laptop with brightness control, **When** they click the brightness indicator, **Then** they see a slider to adjust display brightness (and keyboard backlight if present)
5. **Given** user is on Ryzen desktop (no battery/brightness), **When** they view the top bar, **Then** only applicable controls are shown (volume, Bluetooth, network status)

---

### User Story 2 - Hardware-Adaptive Device Detection (Priority: P2)

The user has multiple machines with different hardware capabilities: a ThinkPad laptop with battery, brightness control, fingerprint sensor, and TLP power management, versus a Ryzen desktop with neither battery nor brightness controls. The system should automatically detect available hardware and show only relevant controls.

**Why this priority**: Critical for multi-machine setups to avoid UI clutter and confusion. Controls for unavailable hardware waste space and create poor UX.

**Independent Test**: Can be verified by deploying the same configuration to both ThinkPad and Ryzen, observing that each shows only its available device controls.

**Acceptance Scenarios**:

1. **Given** user is on ThinkPad, **When** device panel loads, **Then** battery status, brightness controls, power profile selector, and all applicable sensors are visible
2. **Given** user is on Ryzen desktop, **When** device panel loads, **Then** only volume, Bluetooth, and network status are shown (no battery or brightness)
3. **Given** a Bluetooth adapter is disabled or not present, **When** device panel loads, **Then** the Bluetooth control is hidden or shows "Not Available"
4. **Given** thermal sensors are available, **When** device panel loads, **Then** temperature readings are displayed with appropriate icons

---

### User Story 3 - Comprehensive Device Dashboard in Monitoring Panel (Priority: P3)

A user wants a full device overview for system monitoring purposes - seeing all hardware metrics, power status, sensor readings, and device states in one place alongside their existing workspace/project monitoring. They access this via the monitoring panel's dedicated "Devices" tab.

**Why this priority**: Provides deep-dive capability when users need more than quick adjustments - useful for debugging hardware issues, monitoring thermals during heavy workloads, or checking detailed battery health.

**Independent Test**: Can be verified by pressing Mod+M to open monitoring panel, switching to Devices tab (Alt+7), and confirming all device information is displayed in an organized hierarchy.

**Acceptance Scenarios**:

1. **Given** user presses Mod+M to open monitoring panel, **When** they press Alt+7 (or click Devices tab), **Then** they see comprehensive device information organized by category
2. **Given** Devices tab is active, **When** user views audio section, **Then** they see current output device, volume level, microphone status, and can change output device
3. **Given** Devices tab is active on ThinkPad, **When** user views power section, **Then** they see battery percentage, estimated time remaining, charging status, current power profile, and charge thresholds
4. **Given** Devices tab is active, **When** user views sensors section, **Then** they see CPU temperature, fan speeds (if available), and thermal zone readings
5. **Given** user is in panel focus mode (Mod+Shift+M), **When** they navigate the Devices tab, **Then** keyboard navigation (j/k/Enter) works for interacting with controls

---

### User Story 4 - Remove Duplicate Controls and Consolidate (Priority: P4)

The user currently has device controls scattered across multiple widgets: volume in top bar, brightness in a separate quick panel (eww-quick-panel), and some controls are missing proper integration. They want a single, unified system that replaces all existing fragmented controls.

**Why this priority**: Eliminates confusion from multiple entry points, reduces maintenance burden, and creates a cohesive user experience. The existing quick panel duplicates some controls and should be deprecated.

**Independent Test**: Can be verified by confirming the eww-quick-panel is disabled/removed and all its controls are accessible via the new unified system.

**Acceptance Scenarios**:

1. **Given** user previously accessed brightness via quick panel, **When** they use the new device controls, **Then** brightness adjustment is available in both top bar expansion and monitoring panel tab
2. **Given** the eww-quick-panel module exists, **When** the feature is complete, **Then** it is disabled by default and replaced by the unified device controls
3. **Given** volume controls exist in top bar, **When** the feature is complete, **Then** volume remains in top bar but gains expanded slider functionality consistent with other device controls

---

### Edge Cases

- How is the expanded device panel dismissed? Clicking outside the panel closes it (click-outside-to-close pattern matching OS-native control centers)
- What happens when Bluetooth hardware is disabled at kernel level? Control should show "Disabled" state with option to describe how to enable
- How does the system handle rapidly changing values (e.g., volume during media playback)? Updates should be smooth without flickering (<100ms latency)
- What happens when a device operation fails (e.g., Bluetooth connect fails)? Clear error feedback with retry option
- How does the system handle multiple audio output devices? Allow selection from list with clear active indicator
- What happens when ThinkPad lid is closed (external monitor only)? Brightness controls should adapt to available displays
- How does the system handle VPN/Tailscale connection status? Show connection state in network section

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display device controls in an expandable panel accessible from the top bar indicators (volume, Bluetooth, battery)
- **FR-002**: System MUST detect available hardware at runtime and show only applicable controls per machine (ThinkPad vs Ryzen)
- **FR-003**: System MUST provide volume control with slider, percentage display, and mute toggle
- **FR-004**: System MUST provide Bluetooth toggle (on/off) with paired device list showing connection status
- **FR-005**: System MUST provide brightness control slider for laptop displays (when hardware is present)
- **FR-006**: System MUST provide keyboard backlight control for laptops with backlit keyboards (ThinkPad kbd_backlight device)
- **FR-007**: System MUST display battery percentage, charging status, and estimated time remaining on laptops
- **FR-008**: System MUST display power profile selector (performance/balanced/power-saver) on laptops using TLP
- **FR-009**: System MUST add a "Devices" tab (index 6, Alt+7) to the monitoring panel with comprehensive device information
- **FR-010**: System MUST show network connection status (WiFi SSID, Tailscale connection state)
- **FR-011**: System MUST display thermal readings (CPU temperature, fan speed where available) on bare metal machines
- **FR-012**: System MUST integrate with existing Catppuccin Mocha theme for visual consistency
- **FR-013**: System MUST support keyboard navigation in monitoring panel Devices tab (j/k/Enter/Escape)
- **FR-014**: System MUST deprecate the existing eww-quick-panel module, migrating all functionality to the unified system
- **FR-015**: System MUST use event-driven updates via deflisten where possible for <100ms latency
- **FR-016**: System MUST show graceful "Not Available" states for hardware that is disabled or missing

### Key Entities

- **DeviceControl**: A hardware component that can be monitored or controlled (volume, brightness, Bluetooth, battery, thermal)
- **DeviceState**: Current status of a device (value, enabled/disabled, connected/disconnected)
- **HardwareProfile**: Machine-specific configuration indicating available devices (ThinkPad has battery/brightness, Ryzen does not)
- **ControlAction**: User-initiated change to a device (set volume, toggle Bluetooth, adjust brightness)

### UI Architecture (Tiered Approach)

- **Top Bar (Quick Controls)**: Indicators with expandable panels for common adjustments - volume slider, brightness slider, Bluetooth toggle, battery status. Optimized for speed (<2 seconds to adjust).
- **Monitoring Panel Devices Tab (Full Dashboard)**: Comprehensive view with all device details - output device selection, detailed battery health, charge thresholds, thermal graphs, fan speeds, power profile history. Optimized for monitoring and troubleshooting.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can access and adjust volume from any workspace within 2 seconds (one click to expand, drag slider)
- **SC-002**: Device control panel updates in real-time with less than 100ms latency for continuous values (volume, brightness)
- **SC-003**: Hardware detection correctly identifies available devices on both ThinkPad and Ryzen with 100% accuracy (no false controls shown)
- **SC-004**: All device controls from the deprecated quick panel are accessible in the new unified system
- **SC-005**: Users can navigate the Devices tab in monitoring panel using keyboard only (no mouse required) in focus mode
- **SC-006**: The unified device controls maintain visual consistency with existing Eww widgets (Catppuccin Mocha theme, same pill styling, hover effects)
- **SC-007**: System works offline - device controls function without network connectivity (except VPN/network status obviously)
- **SC-008**: Memory usage for device monitoring stays under 50MB additional overhead

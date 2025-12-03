# Feature Specification: Unified Notification System with Eww Integration

**Feature Branch**: `110-improve-notifications-system`
**Created**: 2025-12-02
**Status**: Draft
**Input**: Integrate SwayNC notification system with Eww monitoring widget, providing real-time unread notification badge in top bar while maintaining SwayNC's rich feature set for notification management.

## Overview

This feature enhances the notification user experience by bridging SwayNC (the notification daemon) with the Eww top bar widget system. Users will see an at-a-glance notification badge showing unread count, with visual feedback (pulsing glow) for pending notifications. This follows the established pattern where backend systems provide data and Eww renders the display layer.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Unread Notification Count (Priority: P1)

As a user, I want to see how many unread notifications I have at a glance in the top bar, so I can decide whether to check them without disrupting my current workflow.

**Why this priority**: This is the core value proposition - users currently have no visibility into notification state without opening the control center. This solves the fundamental gap in notification awareness.

**Independent Test**: Can be fully tested by sending test notifications via `notify-send` and observing the badge count increment in the top bar, then opening/clearing notifications and verifying the count decrements.

**Acceptance Scenarios**:

1. **Given** the system is running with no notifications, **When** a new notification arrives, **Then** the top bar displays a badge showing "1" with visual emphasis (glow effect)
2. **Given** there are 5 unread notifications, **When** the user views the top bar, **Then** the badge displays "5" and is clearly visible against the bar background
3. **Given** there are 10+ notifications, **When** viewing the badge, **Then** it displays "9+" to prevent overflow
4. **Given** there are unread notifications, **When** all notifications are dismissed, **Then** the badge disappears and the icon returns to inactive state

---

### User Story 2 - Toggle Notification Center from Top Bar (Priority: P1)

As a user, I want to click the notification icon in the top bar to toggle the notification center panel, so I have quick access to review and manage notifications.

**Why this priority**: This is essential for the notification workflow - without a toggle mechanism, users cannot access their notifications from the top bar interface.

**Independent Test**: Can be tested by clicking the notification widget and observing the SwayNC control center opens/closes, and verifying the widget state updates to reflect visibility.

**Acceptance Scenarios**:

1. **Given** the notification center is closed, **When** the user clicks the notification icon, **Then** the SwayNC control center slides in from the right edge
2. **Given** the notification center is open, **When** the user clicks the notification icon again, **Then** the control center closes
3. **Given** the notification center is open, **When** the user clicks elsewhere or presses Escape, **Then** the control center closes and the icon state updates
4. **Given** the monitoring panel is open, **When** the user opens the notification center, **Then** both panels are visible side-by-side without overlap

---

### User Story 3 - Visual Distinction for Notification States (Priority: P2)

As a user, I want the notification icon to visually indicate different states (no notifications, has unread, Do Not Disturb), so I can understand my notification status without reading text.

**Why this priority**: Enhances usability by providing immediate visual feedback. Not as critical as core functionality but significantly improves the user experience.

**Independent Test**: Can be tested by transitioning through states (no notifications, new notification, enable DND) and observing icon changes.

**Acceptance Scenarios**:

1. **Given** there are no notifications and DND is off, **When** viewing the top bar, **Then** the icon appears in a muted/inactive style (bell outline)
2. **Given** there are unread notifications, **When** viewing the top bar, **Then** the icon appears active with a badge and subtle pulsing glow animation
3. **Given** Do Not Disturb is enabled, **When** viewing the top bar, **Then** the icon shows a DND indicator (bell with slash) regardless of notification count
4. **Given** the notification center is open, **When** viewing the top bar, **Then** the icon has an "active/selected" visual treatment

---

### User Story 4 - Consistent Theme Integration (Priority: P2)

As a user, I want the notification badge and control center to match the Catppuccin Mocha theme used throughout the desktop environment, so the notification system feels cohesive with other widgets.

**Why this priority**: Visual consistency is important for user experience but is secondary to functional requirements.

**Independent Test**: Can be tested by visual comparison of notification badge colors against other top bar elements (project pill, monitoring toggle, time widget).

**Acceptance Scenarios**:

1. **Given** the top bar is visible, **When** a notification badge appears, **Then** its colors match the Catppuccin Mocha palette (red/peach gradient for badge, blue glow for active state)
2. **Given** the notification center is open, **When** viewing its styling, **Then** transparency, border colors, and text colors match the monitoring panel styling
3. **Given** a notification has action buttons, **When** hovering over them, **Then** they follow the same hover/active transitions as other Eww widgets

---

### User Story 5 - Real-Time Badge Updates (Priority: P2)

As a user, I want the notification badge to update within 100ms of notification changes, so the count always reflects the current state without noticeable lag.

**Why this priority**: Responsiveness is expected but requires the event-driven architecture (deflisten pattern) to achieve. Important for perceived quality.

**Independent Test**: Can be tested by rapidly sending/dismissing notifications and observing badge updates occur without visible delay.

**Acceptance Scenarios**:

1. **Given** the badge shows "3" notifications, **When** a notification is dismissed, **Then** the badge updates to "2" within 100ms
2. **Given** 5 notifications arrive in rapid succession, **When** viewing the badge, **Then** it updates to "5" (not showing intermediate states incorrectly)
3. **Given** the SwayNC daemon restarts, **When** it reconnects, **Then** the badge accurately reflects the current notification count

---

### User Story 6 - Keyboard Tooltip for Accessibility (Priority: P3)

As a user, I want to see a tooltip when hovering over the notification icon showing the count and keyboard shortcut, so I can learn and use keyboard navigation.

**Why this priority**: Enhances discoverability but is a polish feature after core functionality works.

**Independent Test**: Can be tested by hovering over the notification icon and observing tooltip appears with correct information.

**Acceptance Scenarios**:

1. **Given** there are 3 notifications, **When** hovering over the notification icon, **Then** a tooltip shows "3 unread notifications (Mod+Shift+I)"
2. **Given** DND is enabled, **When** hovering over the icon, **Then** the tooltip indicates "Do Not Disturb enabled"
3. **Given** no notifications exist, **When** hovering, **Then** tooltip shows "No notifications"

---

### Edge Cases

- What happens when SwayNC daemon is not running or crashes?
  - The badge should show a special "error" state (red exclamation) or hide entirely, and automatically recover when SwayNC restarts
- How does the system handle very high notification volumes (50+ notifications)?
  - Badge caps display at "9+" to prevent visual overflow; full count visible in tooltip
- What happens during system wake from sleep?
  - Badge should resync state from SwayNC within 2 seconds of wake
- How does the badge behave when switching monitor profiles?
  - Badge state persists across profile switches; no flicker or reset
- What happens if notification center is opened via keyboard (Mod+Shift+I) vs click?
  - Both methods produce identical state; icon reflects "open" state regardless of trigger method

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display an unread notification count badge on the top bar notification icon when count > 0
- **FR-002**: System MUST update the badge count within 100ms of notification state changes (new notification, dismissal, clear all)
- **FR-003**: System MUST toggle the SwayNC control center when the notification icon is clicked
- **FR-004**: System MUST synchronize the icon visual state with the control center open/closed state
- **FR-005**: System MUST display distinct icon states for: no notifications, has unread, DND enabled, center open
- **FR-006**: System MUST apply Catppuccin Mocha theme colors consistently with other Eww widgets
- **FR-007**: System MUST cap badge display at "9+" for counts exceeding 9 to prevent overflow
- **FR-008**: System MUST show a pulsing glow animation on the badge when unread notifications exist
- **FR-009**: System MUST display an informative tooltip on hover including count and keyboard shortcut
- **FR-010**: System MUST gracefully handle SwayNC daemon unavailability (show error state or hide badge)
- **FR-011**: System MUST position the notification center to the left of the monitoring panel without overlap (458px from right edge)
- **FR-012**: System MUST use event-driven updates (not polling) for real-time responsiveness

### Key Entities

- **Notification State**: Represents the current notification status including count, DND status, and visibility of control center
- **Badge Display**: Visual representation of notification count with styling based on state
- **Control Center**: SwayNC's notification management panel positioned alongside the monitoring panel

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can see unread notification count without opening any panel (badge visible in top bar)
- **SC-002**: Badge updates reflect notification changes within 100ms (event-driven, no perceptible lag)
- **SC-003**: Users can toggle notification center with a single click on the top bar icon
- **SC-004**: Notification system styling passes visual consistency check against other Eww widgets (same color palette, transparency levels, hover effects)
- **SC-005**: System handles 50+ notifications without UI degradation or incorrect counts
- **SC-006**: Badge recovers accurate state within 2 seconds after SwayNC daemon restart
- **SC-007**: No additional CPU usage when notifications are idle (event-driven, not polling)

## Assumptions

- SwayNC is already installed and running as the notification daemon (confirmed in current config)
- The existing `toggle-swaync` wrapper script handles mutual exclusivity with monitoring panel
- The `swaync-client --subscribe` command provides real-time JSON event stream for notification state
- Eww's `deflisten` pattern is appropriate for real-time notification monitoring (proven with Feature 085)
- The notification center positioning (458px from right) already accounts for monitoring panel width (450px + 8px gap)
- The existing keyboard shortcut (Mod+Shift+I) for notification center toggle will be preserved

## Dependencies

- SwayNC notification daemon (already configured)
- Eww top bar system (Feature 060)
- Catppuccin Mocha theme colors (Feature 057)
- Toggle script for SwayNC (`toggle-swaync`)

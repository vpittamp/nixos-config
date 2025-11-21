# Feature Specification: Monitor Panel Focus Enhancement

**Feature Branch**: `086-monitor-focus-enhancement`
**Created**: 2025-11-21
**Status**: Draft
**Input**: User description: "Hybrid approach combining scratchpad-based visibility management with on-demand focus toggle for the Eww monitoring panel"

## Problem Statement

The Eww monitoring panel (Feature 085) lost click-through behavior after a merge conflict resolution. Currently, opening the panel steals focus from the active application, disrupting workflow. Users need the panel to remain visible as an overlay while working in other applications, with the ability to explicitly focus the panel when needed for keyboard interaction.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Non-Disruptive Panel Viewing (Priority: P1)

As a user with multiple projects and windows, I want the monitoring panel to display my workspace hierarchy without stealing focus from my current work, so I can glance at the panel while continuing to type in my editor or terminal.

**Why this priority**: This is the core regression - the panel currently steals focus, which is the primary pain point users experience. Without this, the panel is disruptive rather than helpful.

**Independent Test**: Open VS Code or a terminal, begin typing, press Mod+M to show panel - typing should continue in the original window without interruption.

**Acceptance Scenarios**:

1. **Given** I am typing in VS Code, **When** I press Mod+M to show the monitoring panel, **Then** my cursor remains in VS Code and I can continue typing without clicking back
2. **Given** the monitoring panel is visible, **When** I click on an application window behind it, **Then** that window receives focus and I can interact with it
3. **Given** the monitoring panel is visible and I click directly on the panel, **Then** the panel does NOT steal focus (click-through behavior by default)

---

### User Story 2 - Explicit Focus Lock for Keyboard Interaction (Priority: P2)

As a user who wants to interact with the panel using keyboard shortcuts (tab navigation, etc.), I want to explicitly lock focus to the panel with a keybinding, so I can use keyboard controls without mouse interaction.

**Why this priority**: Enables full keyboard-driven workflow. Secondary to P1 because most users will interact visually first; keyboard interaction is an advanced use case.

**Independent Test**: With panel visible, press Mod+Shift+M to focus the panel, use Alt+1-4 to switch tabs, then press Mod+Shift+M again to return focus to previous window.

**Acceptance Scenarios**:

1. **Given** the panel is visible but unfocused, **When** I press Mod+Shift+M, **Then** the panel receives keyboard focus and can accept key events
2. **Given** the panel has keyboard focus, **When** I press Alt+1/2/3/4, **Then** the corresponding tab is selected
3. **Given** the panel has keyboard focus, **When** I press Mod+Shift+M again, **Then** focus returns to the previously focused window

---

### User Story 3 - Clean Toggle Visibility (Priority: P2)

As a user, I want the panel to show/hide cleanly via Mod+M without stealing focus, so I can quickly check status and continue working.

**Why this priority**: Visibility toggle is the primary interaction. Research revealed scratchpad would steal focus on show, so using existing eww open/close which already works correctly.

**Independent Test**: Press Mod+M to toggle panel visibility - panel should smoothly show/hide without changing focus.

**Acceptance Scenarios**:

1. **Given** the panel is hidden, **When** I press Mod+M, **Then** the panel appears as overlay
2. **Given** the panel is visible, **When** I press Mod+M, **Then** the panel closes
3. **Given** the panel is visible, **When** I switch workspaces, **Then** the panel remains visible (sticky behavior preserved)

---

### Edge Cases

- What happens when panel is focused and user presses Mod+M to hide? Focus should return to previous window
- How does the system handle multiple monitors? Panel should stay on configured monitor
- What if the user spams Mod+M rapidly? Toggle should be debounced/idempotent

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Panel MUST use Eww `focusable: "ondemand"` to allow focus only when explicitly requested
- **FR-002**: Panel MUST have Sway window rule `no_focus` to prevent automatic focus on creation/updates
- **FR-003**: System MUST provide Mod+Shift+M keybinding to toggle focus lock on/off
- **FR-004**: When focus lock is toggled off, focus MUST return to the previously focused window (not arbitrary window)
- **FR-005**: Panel MUST use eww open/close for visibility management via Mod+M (scratchpad rejected - steals focus)
- **FR-006**: Panel MUST remain sticky across workspace switches
- **FR-007**: Panel MUST maintain its position and size when shown/hidden

### Key Entities

- **Focus State**: Whether panel is currently focused or unfocused
- **Previous Window**: Reference to the window that was focused before panel received focus (needed for FR-004)
- **Panel Visibility**: Whether panel is shown (eww window open) or hidden (eww window closed)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can type continuously in any application while panel is visible (0% keystroke loss)
- **SC-002**: Focus toggle (Mod+Shift+M) responds in under 100ms
- **SC-003**: Panel show/hide (Mod+M) completes in under 100ms
- **SC-004**: 100% of existing panel functionality (real-time updates, tab switching) preserved
- **SC-005**: Focus correctly returns to previous window after unlock in 100% of cases

## Assumptions

- Eww supports the `focusable: "ondemand"` value on Wayland (confirmed in docs)
- Sway `no_focus` rule works with eww windows (needs verification)
- Existing eww open/close behavior is sufficient for visibility management
- Existing tab switching shortcuts (Alt+1-4) will work when panel is focused

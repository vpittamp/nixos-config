# Feature Specification: Fix Window Focus/Click Issue

**Feature Branch**: `114-fix-window-focus-issue`
**Created**: 2025-12-13
**Status**: Draft
**Input**: User description: "We're experiencing a bug in our NixOS system (currently using ThinkPad), which appears to impact all configurations (ThinkPad, M1, Hetzner-Sway), where certain windows don't provide the ability to select/click content in their windows. If the window is maximized, the issue is resolved."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Diagnose Root Cause of Click Issue (Priority: P1)

As a system administrator, I need to identify the exact root cause of why certain windows cannot receive click/input events when tiled but work correctly when maximized, so that I can implement a targeted fix rather than a workaround.

**Why this priority**: Without understanding the root cause, any fix would be speculative and might not fully resolve the issue or could introduce new problems. Diagnosis must come first.

**Independent Test**: Can be fully tested by running diagnostic commands on affected windows and comparing their geometry/input region properties between tiled and maximized states.

**Acceptance Scenarios**:

1. **Given** a window that exhibits the click issue in tiled mode, **When** I run diagnostic tools to compare its state in tiled vs maximized mode, **Then** I can identify the specific property mismatch (geometry, input region, subsurface positioning, CSD handling, or coordinate calculation).

2. **Given** the diagnostic data from affected windows, **When** I analyze the differences, **Then** I can determine whether the issue is caused by: (a) window geometry vs surface size mismatch, (b) input region offset, (c) layer-shell or Eww panel interference, (d) smart_borders/hide_edge_borders configuration, (e) multi-monitor coordinate handling, or (f) XWayland client issues.

3. **Given** a confirmed root cause, **When** I document the findings, **Then** the fix can be targeted to the correct component (Sway config, application config, wlroots version, or Eww configuration).

---

### User Story 2 - Fix Click/Input Issue in Tiled Windows (Priority: P2)

As a user, I want to click and select content within any tiled window without needing to maximize it first, so that I can work efficiently with multiple windows visible simultaneously.

**Why this priority**: This is the core user-facing fix. Once the root cause is identified, implementing the fix is the primary deliverable.

**Independent Test**: Can be fully tested by opening affected applications in tiled mode and verifying all click/selection operations work correctly.

**Acceptance Scenarios**:

1. **Given** any application window in tiled (non-maximized) mode, **When** I click on content within the window, **Then** the click registers correctly at the intended location.

2. **Given** any application window in tiled mode, **When** I attempt to select text or interactive elements, **Then** the selection/interaction works identically to when the window is maximized.

3. **Given** the fix has been applied, **When** I use the system normally across all three configurations (ThinkPad, M1, Hetzner-Sway), **Then** no click/input issues occur in tiled windows.

4. **Given** windows with different border/gap configurations (with borders, without borders, smart_borders on/off), **When** I interact with them in tiled mode, **Then** all click/input operations function correctly regardless of border configuration.

---

### User Story 3 - Prevent Future Regressions (Priority: P3)

As a system maintainer, I need diagnostic tooling and documentation for this class of issue, so that if similar problems occur in the future they can be quickly diagnosed and resolved.

**Why this priority**: Ensures long-term system stability and reduces future debugging time.

**Independent Test**: Can be fully tested by running the diagnostic command on any window and verifying it reports relevant geometry/input information.

**Acceptance Scenarios**:

1. **Given** any Sway window, **When** I run a diagnostic command, **Then** I receive information about its geometry, input region, focus state, and any potential issues.

2. **Given** a window exhibiting unexpected input behavior, **When** I consult the troubleshooting documentation, **Then** I can follow a clear decision tree to identify the likely cause.

---

### Edge Cases

- What happens when a window is partially off-screen or spans multiple monitors?
- How does system handle XWayland applications vs native Wayland applications?
- What happens when Eww panels/overlays are visible alongside affected windows?
- How does the fix interact with scaling factors (e.g., 1.25x on ThinkPad)?
- What happens with floating windows that are resized smaller than their requested geometry?
- How does the fix handle windows with Client-Side Decorations (CSD)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow click events to reach tiled windows at the correct coordinates, matching behavior when the same window is maximized.
- **FR-002**: System MUST handle input events correctly for both native Wayland and XWayland applications in tiled mode.
- **FR-003**: System MUST maintain correct input behavior across all three target configurations (ThinkPad, M1, Hetzner-Sway).
- **FR-004**: System MUST provide a diagnostic command or tool to inspect window geometry, input region, and focus state for troubleshooting.
- **FR-005**: Fix MUST NOT break any existing functionality (floating windows, fullscreen, workspace switching, panel interactions).
- **FR-006**: Fix MUST work correctly with the existing smart_borders and hide_edge_borders configurations.
- **FR-007**: Fix MUST handle multi-monitor setups with different scaling factors.

### Key Entities

- **Window Geometry**: The compositor's understanding of window position and size (x, y, width, height).
- **Input Region**: The area of a window surface that accepts input events; may differ from visual bounds.
- **Surface**: The actual Wayland surface rendered by the client; may include subsurfaces for decorations.
- **XDG Shell Geometry**: Client-reported window bounds per xdg-shell protocol; used by compositor for coordinate mapping.
- **Layer-Shell Surface**: Special overlay windows (like Eww panels) that can intercept input events.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can click on any location within a tiled window and the click registers at the intended position with 100% accuracy (matches maximized behavior).
- **SC-002**: The fix works consistently across all three configurations (ThinkPad, M1, Hetzner-Sway) without configuration-specific workarounds.
- **SC-003**: No user-reported click/input issues in tiled windows after the fix is deployed.
- **SC-004**: Diagnostic tool provides actionable information for window geometry/input issues within 2 seconds of invocation.
- **SC-005**: Fix does not introduce performance degradation - window interactions remain responsive (no perceptible delay).
- **SC-006**: Fix is maintainable - documented root cause and solution enable future similar issues to be diagnosed within 15 minutes.

## Assumptions

- The issue is reproducible and not intermittent/timing-related (user reports consistent behavior).
- The issue affects "certain windows" - a specific set of applications or window types exhibits the problem, not all windows.
- Maximizing the window consistently resolves the issue, suggesting a geometry or coordinate calculation problem rather than a fundamental input stack issue.
- The same underlying cause affects all three configurations (shared Sway/Eww code), not separate per-platform bugs.
- The existing window diagnostic tools in the codebase (i3pm diagnose window, window-env) can be extended if needed.

## Research Summary

Based on research of Sway/wlroots issues and the codebase, the most likely root causes are:

1. **Window Geometry vs Input Region Mismatch**: The xdg-shell protocol allows clients to set window geometry that differs from surface size. If the compositor uses one for rendering but another for input mapping, clicks can miss their targets.

2. **Smart Borders/Gaps Configuration**: The `smart_borders: on` and `hide_edge_borders: smart` settings in appearance.json may cause the compositor to calculate different effective window bounds in tiled vs maximized mode.

3. **Eww Layer-Shell Panel Interference**: The monitoring panel uses `:stacking "fg"` (foreground) and `:focusable "ondemand"`, which could intercept input events even when visually hidden during CSS transitions.

4. **Multi-Monitor Coordinate Handling**: With scaling (1.25x on ThinkPad) and multiple outputs, coordinate translation between surface-local and layout-local coordinates can introduce errors.

5. **CSD (Client-Side Decoration) Handling**: Applications with CSD report geometry that may not account for all subsurfaces, causing input offset issues as documented in sway issue #5125.

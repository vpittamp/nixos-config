# Feature Specification: Multiple AI Indicators Per Terminal Window

**Feature Branch**: `136-multiple-indicators`
**Created**: 2025-12-24
**Status**: Draft
**Input**: User description: "currently we show a pulsating icon in the window tab of our eww-monitoring panel to represent a running llm process, however since our tmux terminals can contain multiple panes with multiple llm processes, we need to enhance our logic/architecture to allow for multiple llm processes per terminal window."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Multiple Active AI Sessions in One Terminal (Priority: P1)

As a developer running multiple AI CLI sessions in different tmux panes within the same terminal window, I want to see distinct indicators for each active session so I can monitor all my concurrent AI interactions at a glance.

**Why this priority**: This is the core feature - without displaying multiple indicators, the feature delivers no value. Currently, if a user has Claude Code in tmux pane 1 and Codex CLI in tmux pane 2 of the same Ghostty window, only one indicator shows. This hides active work and causes confusion.

**Independent Test**: Can be fully tested by opening a tmux session with two panes, running a different AI CLI in each pane, and verifying both indicators appear in the monitoring panel.

**Acceptance Scenarios**:

1. **Given** a terminal window with tmux running two panes (pane 1: Claude Code, pane 2: Codex CLI), **When** both AI CLIs are actively working, **Then** the window tab in the monitoring panel shows two distinct pulsating indicators (one for each CLI).

2. **Given** a terminal window with three tmux panes running three Claude Code instances, **When** all three are actively working, **Then** the window tab shows three pulsating Claude Code indicators.

3. **Given** a terminal window showing two AI indicators, **When** one of the AI sessions completes, **Then** that indicator transitions to "completed" state while the other remains "working".

---

### User Story 2 - Distinguish Between AI Tool Types in Multi-Session View (Priority: P2)

As a developer with multiple AI sessions in one terminal, I want to visually distinguish which indicator corresponds to which AI tool (Claude Code vs Codex vs Gemini) so I know which session needs attention.

**Why this priority**: Once multiple indicators are displayed, users need to differentiate between them. This builds on P1 and makes the feature usable rather than confusing.

**Independent Test**: Can be tested by running different AI tools in tmux panes and verifying each indicator uses the correct tool-specific icon/styling.

**Acceptance Scenarios**:

1. **Given** a terminal with Claude Code in pane 1 and Codex CLI in pane 2, **When** viewing the window tab, **Then** Claude Code indicator shows the Claude icon and Codex indicator shows the Codex icon.

2. **Given** multiple AI indicators for the same tool type (e.g., two Claude Code sessions), **When** viewing the window tab, **Then** each indicator includes a spatial position hint (e.g., "left pane", "right pane", or quadrant) to help users map indicators to their tmux layout.

---

### User Story 3 - Handle Indicator Overflow Gracefully (Priority: P3)

As a developer who may run many AI sessions in one terminal (power user scenario), I want the interface to handle many indicators gracefully so the UI remains usable.

**Why this priority**: Edge case handling - most users will have 2-3 concurrent sessions, but the system should degrade gracefully for power users with more.

**Independent Test**: Can be tested by running 5+ AI sessions in one terminal and verifying the UI remains functional and doesn't break layout.

**Acceptance Scenarios**:

1. **Given** a terminal window with 4 or more active AI sessions, **When** viewing the window tab, **Then** the first 3 indicators are shown normally plus a count badge (e.g., "+2 more") without breaking layout.

2. **Given** a terminal with overflow indicators (showing "+N more" badge), **When** the user hovers over the count badge, **Then** a tooltip reveals the full list of all active sessions with their states and spatial positions.

---

### Edge Cases

- What happens when an AI session starts in a new tmux pane while indicators are already showing? (Answer: New indicator appears within 2 seconds)
- What happens when a tmux pane is closed while its AI session indicator is showing? (Answer: Indicator transitions to idle and disappears after grace period)
- How does the system handle rapidly switching between session states? (Answer: State transitions are debounced to prevent flickering)
- What happens when the same AI CLI session is killed and restarted in the same pane? (Answer: New session ID, new indicator - old indicator times out)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST track multiple AI sessions per terminal window, maintaining distinct session state for each.

- **FR-002**: System MUST display a separate visual indicator for each active AI session within a single window tab.

- **FR-003**: System MUST correlate each AI process (PID) to its specific tmux pane or terminal context, not just the parent window.

- **FR-004**: System MUST maintain independent state transitions (idle/working/completed/attention) for each session within a window.

- **FR-005**: System MUST visually distinguish between different AI tool types (Claude Code, Codex, Gemini) when multiple are active in the same window.

- **FR-006**: System MUST support at least 5 concurrent AI sessions per terminal window without UI degradation.

- **FR-007**: System MUST handle session lifecycle events (start, end, state change) independently for each pane.

- **FR-008**: System MUST update indicators within 2 seconds of session state changes.

- **FR-009**: System MUST handle overflow by showing first 3 indicators plus a "+N more" count badge when more than 3 sessions are active, with tooltip on hover revealing the complete session list.

### Key Entities

- **Session**: Represents a single AI CLI conversation with unique session_id, tool type, state, and pane/window context.
- **Window Badge Set**: Collection of session indicators associated with a single terminal window (replaces current single-badge model).
- **Pane Context**: Identification of the specific tmux pane (or terminal context) where an AI session is running, including spatial position (left/right, top/bottom, or quadrant) for user-facing disambiguation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify all active AI sessions within a terminal window at a glance (no hidden/masked sessions).

- **SC-002**: Indicator count matches actual running AI sessions within 2 seconds of session state changes.

- **SC-003**: Users can distinguish between different AI tool types visually without clicking or hovering.

- **SC-004**: Interface remains functional and readable with up to 5 simultaneous AI sessions per window (3 visible indicators + overflow badge for additional sessions).

- **SC-005**: Session state transitions (working → completed) are accurately reflected per-session, not aggregated.

- **SC-006**: No regression in single-session behavior - users with one AI session per window see identical behavior to current implementation.

## Clarifications

### Session 2025-12-24

- Q: How should identical tool types (e.g., two Claude Code instances) be disambiguated for the user? → A: Use spatial position hints (left pane, right pane, or quadrant position)
- Q: When more than 3 AI sessions are active in one window, how should the UI handle overflow? → A: Show first 3 indicators + count badge ("+2 more"), tooltip reveals full list

## Assumptions

- Tmux pane PIDs can be resolved to the parent Ghostty/terminal window via existing daemon IPC mechanisms.
- The current pulse animation system can be extended to multiple concurrent elements without performance issues.
- Display space in the window tab area is sufficient for at least 3 indicators side-by-side (overflow handling covers cases beyond this).
- Users primarily use tmux for multi-pane setups; other terminal multiplexers (screen, zellij) are out of scope for initial implementation.

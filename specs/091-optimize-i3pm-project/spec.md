# Feature Specification: Optimize i3pm Project Switching Performance

**Feature Branch**: `091-optimize-i3pm-project`
**Created**: 2025-11-22
**Status**: Draft
**Input**: User description: "Optimize i3pm project switching performance from 5.3 seconds to under 200ms by parallelizing Sway IPC commands, eliminating duplicate tree queries, and implementing async command batching in the window filter daemon"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Instant Project Switching (Priority: P1)

As a developer using the i3pm project management system, when I switch between projects using Win+P, the switch completes instantly so that I can maintain my workflow momentum without waiting for windows to appear and disappear.

**Why this priority**: This is the core user-facing benefit. Currently, a 5+ second delay breaks concentration and creates frustration. Sub-200ms switching feels instantaneous to users and eliminates this friction.

**Independent Test**: Can be fully tested by switching between two projects and measuring the time from command initiation to project environment restoration completion. Delivers immediate workflow improvement.

**Acceptance Scenarios**:

1. **Given** I am working in project A, **When** I switch to project B using `i3pm project switch`, **Then** the switch completes in under 200 milliseconds
2. **Given** I am working in a project with 10 scoped windows, **When** I switch to a project with 15 scoped windows, **Then** all windows are hidden/shown within the 200ms target
3. **Given** I repeatedly switch between two projects, **When** I measure average switching time over 10 switches, **Then** the average remains under 200ms

---

### User Story 2 - Consistent Switching Performance (Priority: P2)

As a power user managing multiple projects simultaneously, when I switch between projects regardless of how many windows are open, the switching speed remains consistently fast so that I can predict and rely on the system's responsiveness.

**Why this priority**: Ensures the performance improvement scales across different usage patterns. Prevents performance degradation with window count.

**Independent Test**: Benchmark switching with varying window counts (5, 10, 20, 40 windows) and verify performance stays within acceptable bounds.

**Acceptance Scenarios**:

1. **Given** I have a project with 5 windows, **When** I switch to it, **Then** the switch takes under 150ms
2. **Given** I have a project with 40 windows, **When** I switch to it, **Then** the switch takes under 300ms (acceptable scaling)
3. **Given** I switch between projects multiple times in quick succession, **When** I measure latency variation, **Then** the standard deviation is less than 50ms

---

### User Story 3 - Notification Callback Reliability (Priority: P3)

As a user of Claude Code notification callbacks (Feature 090), when I click "Return to Window" on a notification, the callback completes quickly so that I'm not left waiting with uncertainty about whether my click registered.

**Why this priority**: Currently the callback needs a 6-second sleep to wait for project switching. Reducing this improves the user experience of Feature 090.

**Independent Test**: Send Claude Code notification from project A, switch to project B, click notification button, measure time to return to project A.

**Acceptance Scenarios**:

1. **Given** I'm in project B and receive a notification from project A, **When** I click "Return to Window", **Then** I'm returned to project A within 1 second
2. **Given** the callback sleep time is reduced from 6s to 1s, **When** I test cross-project navigation, **Then** it completes successfully 100% of the time

---

### Edge Cases

- What happens when switching to a project with no windows (empty project)?
- How does the system handle rapid successive switches (switch spam)?
- What happens if a window is being launched while a project switch occurs?
- How does performance scale with scratchpad windows vs. normal windows?
- What happens during a switch if the Sway IPC connection is temporarily slow or congested?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST complete project switches in under 200 milliseconds for projects with fewer than 20 windows
- **FR-002**: System MUST maintain sub-300ms switching performance for projects with up to 40 windows
- **FR-003**: System MUST process window show/hide commands in parallel rather than sequentially
- **FR-004**: System MUST eliminate duplicate Sway tree queries within a single project switch operation
- **FR-005**: System MUST batch independent Sway IPC commands where possible to reduce round-trip latency
- **FR-006**: System MUST preserve all existing window filtering logic and behavior (scoped vs. global windows)
- **FR-007**: System MUST maintain existing window state restoration accuracy (workspace numbers, floating states)
- **FR-008**: System MUST emit performance timing logs for project switch operations

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Average project switch time reduces from 5.3 seconds to under 200 milliseconds (96% improvement)
- **SC-002**: 95th percentile switch time is under 250 milliseconds
- **SC-003**: Standard deviation of switch times is less than 50 milliseconds (consistent performance)
- **SC-004**: Feature 090 notification callback sleep time can be reduced from 6 seconds to 1 second without reliability degradation
- **SC-005**: Performance improvement is measurable via automated benchmark suite (3+ test scenarios)
- **SC-006**: Zero regression in window filtering accuracy (scoped/global window handling remains 100% correct)

### Performance Targets by Window Count

| Window Count | Current (avg) | Target (avg) | Target (p95) |
|--------------|---------------|--------------|--------------|
| 5 windows    | 5.2s          | <150ms       | <200ms       |
| 10 windows   | 5.3s          | <180ms       | <230ms       |
| 20 windows   | 5.4s          | <200ms       | <250ms       |
| 40 windows   | 5.6s          | <300ms       | <400ms       |

## Scope *(mandatory)*

### In Scope

- Parallelizing window show/hide Sway IPC commands using `asyncio.gather()`
- Eliminating duplicate tree queries by caching tree snapshots within switch operations
- Implementing command batching for independent operations
- Adding performance instrumentation and benchmarking tools
- Reducing Feature 090's callback sleep time as a validation test

### Out of Scope

- Changes to window filtering logic or scoped/global window semantics
- Changes to workspace assignment or monitor management
- UI/UX changes to project switching interface (Eww widgets, keybindings)
- Modifications to project metadata storage or configuration formats
- Changes to mark-based app identification system (Feature 076)

## Assumptions *(mandatory)*

- Sway IPC can handle multiple concurrent commands without race conditions or state corruption
- `asyncio.gather()` in Python 3.11+ provides sufficient parallelization for the workload
- The daemon's event loop can process batched commands without blocking other operations
- Network/IPC latency to Sway is not the dominant bottleneck (assumption validated by benchmarks showing commands execute fast individually)
- Window count in active use remains under 100 windows per project (reasonable upper bound)

## Dependencies

- Python 3.11+ async/await capabilities
- `i3ipc.aio` library support for concurrent command execution
- Existing i3pm daemon architecture and event handling system
- Sway IPC stability under concurrent command load

## Performance Baseline

**Current Performance** (benchmarked 2025-11-22):
- Average switch time: 5.3 seconds
- Test configuration: Switching between two projects with typical window loads
- Bottleneck identified: Sequential `await conn.command()` calls in `window_filter.py`

**Identified Bottlenecks**:
1. **Sequential Window Commands** (lines 325-541 in `window_filter.py`): 60+ IPC commands executed one-at-a-time
2. **Duplicate Tree Queries**: Tree queried 2-3 times for the same data
3. **No Parallelization**: Window filtering and focus restoration run sequentially

**Optimization Potential**: Analysis suggests 50-65% improvement is achievable through parallelization alone.

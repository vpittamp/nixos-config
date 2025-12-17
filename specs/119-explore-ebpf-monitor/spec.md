# Feature Specification: eBPF-Based AI Agent Process Monitor

**Feature Branch**: `119-explore-ebpf-monitor`
**Created**: 2025-12-16
**Status**: Draft
**Input**: User description: "explore ebpf and how we can use it to monitor processes on our linux nixos system. specifically, we're looking to replace our current monitoring approach for ghostty terminals with tmux sessions where we run claude code and codex cli. we want to monitor when the agent is in progress of a long running task so we can switch to other work and be notified visually when the agent is complete and waiting for another user prompt."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Receive Notification When AI Agent Completes Task (Priority: P1)

As a developer running Claude Code or Codex CLI in a Ghostty terminal with tmux, I want to be notified when the AI agent finishes processing and is waiting for my next prompt, so that I can work on other tasks asynchronously and return when the agent is ready for input.

**Why this priority**: This is the core value proposition - enabling async workflows. Without reliable completion detection, the entire feature fails to deliver value. Users currently poll-check their terminals or keep them visible, losing productivity.

**Independent Test**: Can be fully tested by starting Claude Code, submitting a prompt, switching away, and verifying a notification appears when the AI stops and waits. Delivers immediate value by freeing users from constant terminal monitoring.

**Acceptance Scenarios**:

1. **Given** Claude Code is running in a tmux pane and actively processing a user prompt, **When** the AI completes its response and returns to an input-waiting state, **Then** a desktop notification appears within 2 seconds indicating the agent is ready for input.

2. **Given** Codex CLI is running in a tmux pane and executing a task, **When** the task completes and Codex waits for the next command, **Then** a desktop notification appears within 2 seconds with the project name and agent type.

3. **Given** the user has multiple AI sessions across different projects, **When** any of them completes, **Then** the notification identifies which specific session/project completed.

---

### User Story 2 - Visual Indicator Shows Agent Working Status (Priority: P2)

As a developer, I want to see a visual indicator (spinner/badge) on my monitoring panel showing which AI agents are currently working, so I can understand at a glance which sessions need my attention.

**Why this priority**: Enhances the notification system with persistent visual feedback. Users can scan the monitoring panel to see all active sessions without waiting for notifications.

**Independent Test**: Can be tested by starting an AI session and verifying the spinner appears in the eww monitoring panel. The badge should animate while processing and change to an attention icon when stopped.

**Acceptance Scenarios**:

1. **Given** Claude Code starts processing a prompt, **When** the monitoring panel refreshes, **Then** a spinning indicator appears next to that window's entry.

2. **Given** an AI agent finishes processing, **When** the monitoring panel refreshes, **Then** the spinner changes to a "needs attention" indicator (bell icon).

3. **Given** the user focuses the terminal window with a completed AI session, **When** they interact with the terminal, **Then** the badge clears automatically.

---

### User Story 3 - eBPF-Based Detection Replaces Polling (Priority: P3)

As a system administrator, I want AI agent state detection to use eBPF syscall tracing instead of polling tmux panes, so that detection is more accurate, has lower overhead, and responds faster to state changes.

**Why this priority**: Technical improvement that enhances P1 and P2. eBPF provides kernel-level visibility into process states without polling overhead. Detection latency improves from 300ms polling intervals to near-instant event-driven updates.

**Independent Test**: Can be tested by comparing CPU usage and detection latency between the current polling approach and eBPF-based detection. Should show reduced CPU usage and faster detection times.

**Acceptance Scenarios**:

1. **Given** the eBPF monitor service is running, **When** an AI process transitions from processing to waiting-for-input (blocked on stdin read), **Then** an event is generated within 100ms of the state change.

2. **Given** multiple AI processes are running across different tmux sessions, **When** any process changes state, **Then** only that specific process triggers an event (no polling of unrelated processes).

3. **Given** the eBPF monitor service is configured via NixOS, **When** the system rebuilds, **Then** all eBPF programs and dependencies are installed declaratively without manual intervention.

---

### User Story 4 - NixOS Declarative Configuration (Priority: P4)

As a NixOS user, I want the entire eBPF monitoring stack to be configured declaratively in my NixOS configuration, so that the setup is reproducible and version-controlled.

**Why this priority**: Aligns with NixOS philosophy and enables easy rollback/reproduction. Without declarative config, the feature cannot be reliably deployed across machines or after system reinstalls.

**Independent Test**: Can be tested by enabling the service in configuration.nix and running `nixos-rebuild switch`. The system should have all required tools (bpftrace, bcc) installed and the monitoring service running.

**Acceptance Scenarios**:

1. **Given** a NixOS configuration with the eBPF monitor module enabled, **When** `nixos-rebuild switch` completes, **Then** bpftrace/bcc packages are installed and the monitoring service is active.

2. **Given** the eBPF monitor is configured with custom parameters (detection targets, notification settings), **When** the system rebuilds, **Then** those parameters take effect without manual configuration.

---

### Edge Cases

- What happens when the AI process crashes instead of completing normally? (Detection should still trigger - process exit vs stdin wait are distinguishable)
- How does the system handle nested tmux sessions (tmux inside tmux)? (Focus on the innermost pane where the AI runs)
- What happens when the user runs multiple AI processes in the same tmux pane? (Track the process that holds stdin)
- What happens if eBPF is not available (e.g., older kernel, restricted permissions)? (Graceful degradation with clear error message)
- How does the system handle AI processes that use interactive prompts mid-task (e.g., confirmation dialogs)? (Distinguish brief input waits from task completion - use timing heuristics)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect when Claude Code or Codex CLI processes transition from active processing to waiting-for-input state
- **FR-002**: System MUST use eBPF tracepoints to monitor syscalls (read, poll, select) on stdin/tty file descriptors for target processes
- **FR-003**: System MUST identify target processes by process name ("claude", "codex") and parent process chain (tmux → shell → AI tool)
- **FR-004**: System MUST generate events when AI processes block on stdin read for longer than a configurable threshold (default: 1 second)
- **FR-005**: System MUST resolve the Sway window ID from the detected process (via process tree traversal to Ghostty parent)
- **FR-006**: System MUST write badge state files compatible with the existing badge format (`$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`)
- **FR-007**: System MUST trigger desktop notifications via the existing notification system (SwayNC) when agent completes
- **FR-008**: System MUST be installable and configurable entirely through NixOS module options
- **FR-009**: System MUST include bpftrace and required BCC/libbpf dependencies via nixpkgs
- **FR-010**: System MUST run as a system-level systemd service (root privileges required for eBPF) with badge files owned by the target user
- **FR-011**: System MUST support configurable list of process names to monitor (extensible beyond Claude/Codex)
- **FR-012**: System MUST handle process exit events (crash or normal termination) distinctly from input-waiting events
- **FR-013**: System MUST provide logging/diagnostics for troubleshooting detection issues
- **FR-014**: System MUST auto-restart on failure via systemd and scan for existing AI processes on startup to rebuild tracking state (ensuring continuity after crashes or reboots)

### Key Entities

- **MonitoredProcess**: Represents an AI process being tracked - includes PID, process name, parent PID chain, associated window ID, current state (working/waiting/exited), last state change timestamp
- **BadgeState**: Existing entity - window_id, state (working/stopped), source (claude-code/codex), project, timestamp, needs_attention
- **eBPFEvent**: Raw event from eBPF probes - syscall type, PID, file descriptor, timestamp, return value
- **ProcessStateChange**: Derived event - PID, old_state, new_state, window_id, project_name, timestamp

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: AI agent completion is detected and notification sent within 2 seconds of the agent returning to input-waiting state (improvement from current 300ms polling + 3s network idle detection = ~3.3s total)
- **SC-002**: Monitoring service CPU usage remains below 1% during steady-state operation (improvement from current polling approach)
- **SC-003**: False positive rate for completion detection is below 5% (incorrectly notifying when agent is still processing)
- **SC-004**: False negative rate for completion detection is below 1% (missing notifications when agent actually completes)
- **SC-005**: System correctly detects 100% of Claude Code and Codex CLI sessions without manual per-session configuration
- **SC-006**: NixOS module configuration allows full feature enablement with a single `services.ebpf-ai-monitor.enable = true` option
- **SC-007**: User can return to AI session within 3 clicks/keypresses from notification (matching current behavior)
- **SC-008**: All existing badge file consumers (eww monitoring panel, notification callbacks) continue working without modification

## Assumptions

- Kernel version supports eBPF with BTF (Kernel 5.2+ for most features, user's system runs 6.12.61 which is well above this)
- The eBPF monitor runs as a system-level service with root privileges (setcap approach rejected due to security concerns - see research.md for details)
- Claude Code and Codex CLI read user input from stdin (standard terminal input pattern)
- Ghostty terminal emulator is the primary terminal used (process tree traversal depends on this)
- tmux is used as the terminal multiplexer (pane/session structure is tmux-specific)
- The existing badge file format and eww monitoring panel integration should be preserved for compatibility
- SwayNC notification system is already configured and working

## Migration Strategy

- The existing `tmux-ai-monitor` polling-based service will be completely removed and replaced by the eBPF-based monitor
- No backward compatibility or feature flags required - this is a clean replacement in a dedicated branch
- The eBPF service will use the same badge file format to maintain compatibility with downstream consumers (eww panel, notifications)

## Out of Scope

- GUI configuration interface (CLI and Nix config only)
- Backward compatibility with tmux-ai-monitor (clean replacement)
- Support for terminal emulators other than Ghostty in this iteration
- Support for terminal multiplexers other than tmux in this iteration
- Monitoring non-AI processes (though the architecture should be extensible)
- Mobile/remote notifications (desktop only)
- Historical tracking/analytics of AI session durations
- Integration with AI tools beyond Claude Code and Codex CLI in this iteration

## Clarifications

### Session 2025-12-16

- Q: How should bpftrace obtain the privileges needed to attach eBPF probes? → A: Use setcap to grant CAP_BPF and CAP_PERFMON to bpftrace binary (no root needed)
- Q: What should happen when the eBPF monitor service fails or restarts? → A: Auto-restart on failure; on startup, scan for existing AI processes to rebuild state
- Q: What is the migration strategy from the current tmux-ai-monitor to eBPF-based monitoring? → A: Clean replacement - remove tmux-ai-monitor entirely, eBPF service takes over completely

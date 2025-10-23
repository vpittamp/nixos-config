# Feature Specification: Linux System Log Integration for Application Launch Tracking

**Feature Branch**: `029-linux-system-log`
**Created**: 2025-10-23
**Status**: Draft
**Input**: User description: "Linux system log integration for comprehensive application launch tracking"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View System Service Launches Alongside Window Events (Priority: P1)

As a developer debugging application startup issues, I need to see when systemd services start in relation to when their GUI windows appear, so I can diagnose slow startup times and dependency problems.

**Why this priority**: Provides immediate value by surfacing data that already exists in the system (journalctl). Requires no additional monitoring overhead. Addresses the core user request to "query the linux system for its logs/event history that correspond to launching applications."

**Independent Test**: Can be fully tested by querying `i3pm daemon events --source=systemd` and verifying that systemd service start events appear with proper timestamps and event formatting, even without any other event sources running.

**Acceptance Scenarios**:

1. **Given** systemd has started Firefox and VS Code services in the last hour, **When** user runs `i3pm daemon events --source=systemd --since="1 hour ago"`, **Then** events show "Started Firefox Web Browser" and "Started Code - OSS" with timestamps
2. **Given** user has active project context "nixos", **When** a systemd application service starts, **Then** event displays with project context tag
3. **Given** user runs `i3pm daemon events --source=all`, **When** Firefox service starts followed by window creation, **Then** both systemd service start and i3 window::new events appear in chronological order
4. **Given** user wants to export events for analysis, **When** running `i3pm daemon events --source=systemd --json`, **Then** output contains valid JSON with source="systemd" and event_type="systemd::service"

---

### User Story 2 - Monitor Background Process Activity (Priority: P2)

As a developer working on a multi-process application, I need to see when background processes (like rust-analyzer, docker-compose, language servers) start and stop, so I can understand the full lifecycle of my development environment and troubleshoot process-related issues.

**Why this priority**: Extends tracking beyond GUI applications to cover the complete development workflow. Requires implementing process monitoring but provides significant debugging value for complex multi-process systems.

**Independent Test**: Can be fully tested by launching the /proc monitoring daemon and verifying that non-GUI processes (like rust-analyzer, node, python) appear in `i3pm daemon events --source=proc` output, independent of window manager events.

**Acceptance Scenarios**:

1. **Given** /proc monitoring is active, **When** VS Code spawns rust-analyzer process, **Then** event shows "Process started: rust-analyzer" with timestamp
2. **Given** user runs docker-compose in terminal, **When** docker-compose spawns container processes, **Then** events show each process start with command line details
3. **Given** user views live event stream with `--follow`, **When** background processes start/stop, **Then** events appear in real-time with <1 second latency
4. **Given** user filters events by process name, **When** running `i3pm daemon events --source=proc | grep rust-analyzer`, **Then** only rust-analyzer related events appear
5. **Given** command line contains sensitive data (passwords, tokens), **When** event is logged, **Then** sensitive values are sanitized with "***" replacement

---

### User Story 3 - Correlate GUI Applications with Backend Services (Priority: P3)

As a developer analyzing application startup performance, I need to see the relationship between GUI window creation and the backend processes they spawn, so I can identify bottlenecks in the application initialization sequence.

**Why this priority**: Provides advanced debugging capabilities by showing causal relationships between events. Requires correlation logic and more sophisticated data analysis, making it lower priority than basic event visibility.

**Independent Test**: Can be fully tested by launching VS Code and verifying that the correlation view shows the window::new event followed by related process spawns (tsserver, rust-analyzer) in a hierarchical or tagged display format.

**Acceptance Scenarios**:

1. **Given** VS Code window opens at 07:28:47, **When** user runs `i3pm daemon events --correlate --since="07:28:00"`, **Then** display shows VS Code window with indented child events for rust-analyzer and typescript-language-server processes
2. **Given** multiple applications with backend processes are running, **When** viewing correlated events, **Then** each application's event tree is grouped separately
3. **Given** user wants to measure startup time, **When** viewing correlated events, **Then** time delta is displayed between parent window creation and last child process start

---

### Edge Cases

- What happens when journalctl is not available or returns no events? Display message "No systemd events found" and continue showing other event sources
- How does system handle /proc monitoring when permissions are denied for certain PIDs? Skip those PIDs silently and continue monitoring accessible processes
- What happens when systemd service names don't match application window classes? Display both independently; correlation is best-effort based on timing and name similarity
- How does system handle high-frequency process spawning (>100 processes/second)? Implement event batching with configurable sample rate to prevent overwhelming the event stream
- What happens when event sources have clock skew (systemd time vs i3 event time)? Use local system clock for all timestamps to ensure consistency
- How does system handle very large command lines (>1000 characters) from /proc? Truncate command lines to 500 characters with "..." indicator
- What happens when a process exits before it can be read from /proc? Silently skip the process; only successful reads are logged as events

## Requirements *(mandatory)*

### Functional Requirements

#### systemd Journal Integration (P1)

- **FR-001**: System MUST query systemd journal using `journalctl --user --output=json` for application launch events
- **FR-002**: System MUST parse systemd journal JSON output and convert to unified EventEntry format with source="systemd"
- **FR-003**: System MUST filter systemd events to application launches (unit types matching "app-*.service", "*.desktop" patterns)
- **FR-004**: System MUST support time-based queries with `--since` parameter (e.g., "1 hour ago", "today", ISO timestamp)
- **FR-005**: System MUST include systemd-specific fields in EventEntry: service unit name, systemd message, PID
- **FR-006**: Users MUST be able to query systemd events via `i3pm daemon events --source=systemd`
- **FR-007**: Users MUST be able to combine systemd events with i3 events via `i3pm daemon events --source=all`
- **FR-008**: System MUST preserve existing event formatting for user-readable output (timestamp, source badge, description)

#### Process Monitoring (P2)

- **FR-009**: System MUST monitor /proc filesystem for new process IDs at configurable interval (default 500ms)
- **FR-010**: System MUST read process details from /proc/{pid}/cmdline and /proc/{pid}/comm for each new PID
- **FR-011**: System MUST filter processes to "interesting" ones based on configurable allowlist (dev tools, GUI apps)
- **FR-012**: System MUST create EventEntry objects with source="proc" and event_type="process::start" for each detected process
- **FR-013**: System MUST handle FileNotFoundError and PermissionError gracefully when reading /proc entries (skip and continue)
- **FR-014**: System MUST sanitize command lines to remove sensitive data (password=*, token=*, API keys) before logging
- **FR-015**: System MUST limit command line length to 500 characters with "..." truncation indicator
- **FR-016**: Users MUST be able to start/stop process monitoring independently of other event sources
- **FR-017**: Users MUST be able to query process events via `i3pm daemon events --source=proc`

#### Unified Event Stream (P1)

- **FR-018**: System MUST expand EventEntry.source enum to include "systemd", "proc", "audit" values
- **FR-019**: System MUST merge events from multiple sources (i3, systemd, proc) sorted by timestamp
- **FR-020**: System MUST display source badge in event output ([i3], [systemd], [proc]) with distinct formatting
- **FR-021**: System MUST support filtering by single source (--source=systemd) or multiple sources (--source=all)
- **FR-022**: System MUST preserve existing event streaming capabilities (--follow, --limit, --type filters)
- **FR-023**: System MUST support JSON output format for all event sources via --json flag

#### Event Correlation (P3)

- **FR-024**: System MUST detect parent-child relationships between GUI windows and spawned processes based on timing proximity (within 5 seconds) and process hierarchy from /proc/{pid}/stat
- **FR-025**: Users MUST be able to view correlated events via `i3pm daemon events --correlate` flag
- **FR-026**: System MUST display correlated events in hierarchical format with indentation showing parent-child relationships
- **FR-027**: System MUST calculate and display time delta between parent event and related child events

### Key Entities

- **SystemdEvent**: Represents a systemd journal entry for an application or service launch
  - Service unit name (e.g., "app-firefox-123.service")
  - Systemd message (e.g., "Started Firefox Web Browser")
  - Timestamp from journal's __REALTIME_TIMESTAMP
  - Process ID from _PID field
  - Maps to EventEntry with source="systemd"

- **ProcessEvent**: Represents a process detected via /proc monitoring
  - Process ID (PID)
  - Command name from /proc/{pid}/comm
  - Full command line from /proc/{pid}/cmdline (sanitized)
  - Detection timestamp
  - Maps to EventEntry with source="proc"

- **UnifiedEventStream**: Merged view of events from multiple sources
  - Events from i3, systemd, proc sorted chronologically
  - Preserves source attribution for each event
  - Supports filtering, pagination, and live streaming
  - Maintains consistent EventEntry schema across all sources

- **EventCorrelation**: Relationship between a GUI window and its spawned processes
  - Parent event (window::new from i3)
  - Child events (process::start from proc)
  - Time delta between parent and children
  - Confidence score based on timing proximity and process hierarchy

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can view systemd application launch events within 1 second of running `i3pm daemon events --source=systemd`
- **SC-002**: System successfully parses and displays at least 95% of systemd journal entries for application services
- **SC-003**: Process monitoring detects new processes within 1 second of creation (given 500ms polling interval)
- **SC-004**: Unified event stream displays events from multiple sources in correct chronological order with timestamp accuracy within 1 second
- **SC-005**: Live event streaming (--follow) continues to display events from all sources with <2 second latency
- **SC-006**: Process monitoring overhead remains below 5% CPU usage even with 50+ processes starting per minute
- **SC-007**: Sensitive data (passwords, tokens) in command lines is sanitized in 100% of logged events
- **SC-008**: Event correlation correctly identifies parent-child relationships in at least 80% of cases where a GUI application spawns related processes within 5 seconds
- **SC-009**: Users can export event data in JSON format that is parseable by standard JSON tools (jq, python json module)
- **SC-010**: System handles journalctl unavailability gracefully, continuing to show other event sources without error

## Scope & Boundaries

### In Scope

- systemd journal query integration for user-level application services
- /proc filesystem monitoring for process detection
- Unified event stream merging i3, systemd, and proc sources
- Event correlation showing relationships between windows and processes
- Sensitive data sanitization in command lines
- JSON export for all event sources

### Out of Scope

- auditd integration (requires root privileges and system-level setup)
- System-wide service monitoring (only user-level services)
- Real-time audit system call tracing
- Historical process accounting (psacct/acct) integration
- Process resource usage tracking (CPU, memory)
- Network activity correlation with application launches
- Container/Docker-specific event tracking
- Cross-user event monitoring (privacy/security boundary)

## Assumptions

- systemd journal is available on the system (standard on NixOS)
- /proc filesystem is mounted and accessible (standard on Linux)
- User has permission to read their own journal entries via `journalctl --user`
- User has permission to read /proc entries for their own processes
- System clock is synchronized across all event sources (NTP or similar)
- Existing event database schema supports additional source values without migration
- Performance impact of 500ms /proc polling is acceptable for development use cases
- Most development-related processes of interest appear in /proc for at least 500ms before exiting

## Dependencies

- Existing i3pm daemon event system (Feature 015, Feature 017)
- EventEntry unified data model with source field
- Event formatting and display logic in daemon.ts
- systemd and journalctl availability
- /proc filesystem access
- Python asyncio for asynchronous process monitoring

## Constraints

- Process monitoring must not exceed 5% CPU overhead
- Event stream must maintain <2 second latency for live streaming
- Command line sanitization must not produce false positives that obscure legitimate debugging information
- Event correlation heuristics are best-effort; false positives/negatives are acceptable as long as majority of cases work correctly
- systemd journal queries are one-way; daemon cannot subscribe to live journal events (must poll or query on-demand)

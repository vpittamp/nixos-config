# Feature Specification: OpenTelemetry AI Assistant Monitoring

**Feature Branch**: `123-otel-tracing`
**Created**: 2025-12-16
**Status**: Draft
**Input**: User description: "Implement native OpenTelemetry-based AI assistant monitoring, replacing all legacy detection mechanisms with the optimal approach"

## Background

Current AI assistant monitoring uses multiple fragmented approaches:
- Polling-based tmux process detection (unreliable state changes)
- File-based badge system with polling/watching overhead
- Claude Code hooks writing to files
- eBPF syscall tracing (proven incompatible with async I/O)

Research identified that both Claude Code and Codex CLI have **native OpenTelemetry support** that emits rich telemetry events including session lifecycle, turn completion, and tool usage. This feature implements a unified, streaming approach that eliminates all intermediate state storage.

## Architecture

```
Claude Code ─┐                                      ┌─► EWW Top Bar
             ├──► OTLP Receiver ──► JSON stream ───┤
Codex CLI ───┘         │                            └─► Monitoring Panel
                       │
                       └──► Desktop Notifications
```

**Key Design Decisions:**
1. **No intermediate state files** - OTLP receiver streams directly to EWW via deflisten
2. **No polling** - Event-driven throughout the pipeline
3. **Single service** - One OTLP receiver handles all AI assistants
4. **Native telemetry** - No custom hooks or process detection

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real-Time Working State Indicator (Priority: P1)

As a developer using AI assistants, I want to see when my assistant is actively working, so I know whether to wait or continue other tasks.

**Why this priority**: Core functionality - visual feedback during AI processing is the primary user need.

**Independent Test**: Start Claude Code, submit a prompt, observe working indicator appears in top bar immediately.

**Acceptance Scenarios**:

1. **Given** Claude Code is idle, **When** I submit a prompt, **Then** a working indicator appears within 1 second
2. **Given** Codex CLI is idle, **When** I submit a prompt, **Then** a working indicator appears within 1 second
3. **Given** AI is showing working state, **When** processing completes, **Then** indicator transitions to attention state

---

### User Story 2 - Completion Notification (Priority: P1)

As a developer multitasking while AI processes, I want to be notified when AI completes, so I can return at the right moment.

**Why this priority**: Equal to working state - both are essential for effective workflow.

**Independent Test**: Submit prompt to Claude Code, switch windows, verify notification appears when complete.

**Acceptance Scenarios**:

1. **Given** AI is processing, **When** processing completes, **Then** desktop notification appears within 1 second
2. **Given** notification is shown, **When** I click it, **Then** focus returns to the AI terminal
3. **Given** AI completed, **When** I return to terminal manually, **Then** notification dismisses automatically

---

### User Story 3 - Multi-Session Awareness (Priority: P2)

As a developer running multiple AI sessions, I want to see all active sessions and their states, so I can manage parallel work.

**Why this priority**: Important for power users but not blocking for single-session usage.

**Independent Test**: Start Claude Code in two projects, verify both appear in monitoring panel with distinct states.

**Acceptance Scenarios**:

1. **Given** multiple AI sessions running, **When** I view monitoring panel, **Then** each session shows tool type, project, and state
2. **Given** one session completes, **When** another is still working, **Then** only the completed session changes state
3. **Given** a session is closed, **When** I view monitoring, **Then** that session is removed within 5 seconds

---

### User Story 4 - Session Metrics (Priority: P3)

As a developer tracking AI usage, I want to see token consumption per session, so I can understand usage patterns.

**Why this priority**: Analytics feature, nice-to-have after core functionality works.

**Independent Test**: Complete an AI interaction, check if token counts appear in session details.

**Acceptance Scenarios**:

1. **Given** an AI turn completes, **When** I view session details, **Then** input/output token counts are displayed
2. **Given** multiple turns in session, **When** I view metrics, **Then** cumulative totals are shown

---

### Edge Cases

- What happens when OTLP receiver is not running? AI tools continue working normally, no monitoring displayed
- What happens when AI tool doesn't have OTLP enabled? Session doesn't appear in monitoring (no fallback)
- What happens when network issues cause OTLP delivery failure? Receiver handles gracefully, may miss events
- What happens when user closes terminal mid-session? Session disappears from monitoring within timeout period

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST receive and parse OTLP HTTP data on a configurable port
- **FR-002**: System MUST identify sessions by unique thread/conversation ID from telemetry
- **FR-003**: System MUST detect "working" state from turn-started or prompt-submitted events
- **FR-004**: System MUST detect "completed" state from turn-completed events
- **FR-005**: System MUST output session state changes as JSON stream to stdout
- **FR-006**: System MUST send desktop notifications on session completion
- **FR-007**: System MUST track multiple concurrent sessions from different AI tools
- **FR-008**: System MUST expire stale sessions after configurable timeout
- **FR-009**: System MUST distinguish between Claude Code and Codex CLI sessions
- **FR-010**: System MUST extract project context from telemetry metadata when available

### Key Entities

- **OTLP Receiver**: Long-running service accepting OpenTelemetry Protocol HTTP requests
- **Session**: A tracked AI conversation, identified by thread ID, with state (working/completed/idle)
- **Telemetry Event**: OTLP log entry containing session lifecycle data (turn start, completion, tool use)
- **JSON Stream**: Newline-delimited JSON output consumed by EWW deflisten

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: State changes appear in UI within 1 second of AI event
- **SC-002**: Desktop notifications appear within 1 second of completion
- **SC-003**: System supports 10+ concurrent sessions without performance impact
- **SC-004**: OTLP receiver uses less than 30MB memory under normal load
- **SC-005**: No polling anywhere in the monitoring pipeline (fully event-driven)
- **SC-006**: Both Claude Code and Codex CLI sessions monitored identically

## Code Removal

This feature **replaces** the following components:

### Files to Remove

| Path | Reason |
|------|--------|
| `scripts/tmux-ai-monitor/` | Polling-based detection replaced by OTLP |
| `scripts/claude-hooks/prompt-submit-notification.sh` | OTLP events replace hook |
| `scripts/claude-hooks/stop-notification.sh` | OTLP events replace hook |
| `scripts/claude-hooks/stop-notification-handler.sh` | OTLP events replace hook |
| `scripts/claude-hooks/swaync-action-callback.sh` | OTLP notifications replace this |
| `home-modules/services/tmux-ai-monitor.nix` | Service replaced by OTLP receiver |
| `home-modules/desktop/eww-top-bar/scripts/ai-sessions-status.sh` | Badge polling replaced by deflisten |

### Files to Modify

| Path | Changes |
|------|---------|
| `home-modules/ai-assistants/claude-code.nix` | Remove state hooks (keep bash-history), configure full OTLP export |
| `home-modules/desktop/eww-top-bar/eww.yuck.nix` | Replace defpoll with deflisten for AI sessions |
| `home-modules/desktop/eww-top-bar/eww.scss.nix` | Update AI session widget styling if needed |
| `home-modules/desktop/eww-monitoring-panel.nix` | Replace badge consumption with stream data |
| Host configs (hetzner.nix, etc.) | Remove tmux-ai-monitor.enable references |

### Concepts to Eliminate

- Badge file system (`$XDG_RUNTIME_DIR/i3pm-badges/`)
- File-based state storage for AI sessions
- Polling-based AI process detection
- Hook-based state notification (for session state only)

## Assumptions

1. Claude Code 2.x+ with OTLP telemetry support
2. Codex CLI 0.70+ with `[otel]` config section
3. Available network port for OTLP receiver (default 4318)
4. systemd user services supported
5. EWW deflisten can consume long-running process stdout

## Out of Scope

- Cost/billing calculations
- Historical analytics or persistence
- Remote telemetry export
- AI assistants other than Claude Code and Codex CLI
- Fallback mechanisms for tools without OTLP support

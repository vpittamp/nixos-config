# Implementation Plan: Linux System Log Integration

**Branch**: `029-linux-system-log` | **Date**: 2025-10-23 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/029-linux-system-log/spec.md`

## Summary

Extend the i3pm event system to integrate Linux system logs (systemd journal via journalctl) and process monitoring (/proc filesystem) alongside existing i3 window manager events. This provides comprehensive application launch tracking covering GUI windows, system services, and background processes in a unified event stream with consistent formatting, filtering, and correlation capabilities.

**Technical Approach**:
- Query systemd journal using `journalctl --user --output=json` for on-demand event retrieval
- Implement async /proc filesystem monitoring loop for real-time process detection
- Extend existing EventEntry model to support new source types ("systemd", "proc")
- Merge events from multiple sources in chronological order
- Add correlation logic to detect parent-child relationships between GUI windows and spawned processes
- Preserve all existing event streaming capabilities (--follow, --limit, --type, --json)

## Technical Context

**Language/Version**: Python 3.11+ (matches existing i3-project daemon architecture)
**Primary Dependencies**:
- asyncio (async event handling)
- subprocess (journalctl query execution)
- pathlib (proc filesystem access)
- i3ipc.aio (existing i3 IPC integration)
- Pydantic (EventEntry data model validation)

**Storage**: SQLite database (existing event_log table with expanded source enum)
**Testing**: pytest with pytest-asyncio for async test scenarios
**Target Platform**: Linux (NixOS) with systemd and /proc filesystem
**Project Type**: Single project - extension to existing i3-project-event-daemon
**Performance Goals**:
- systemd query response: <1 second
- /proc monitoring detection latency: <1 second (500ms polling interval)
- Event stream latency: <2 seconds for all sources
- CPU overhead: <5% for process monitoring

**Constraints**:
- Process monitoring must not exceed 5% CPU usage
- Event correlation must achieve 80% accuracy for parent-child relationships
- Sensitive data sanitization must catch 100% of common patterns (password=*, token=*, key=*)
- Command line truncation at 500 characters

**Scale/Scope**:
- Support 50+ processes starting per minute without performance degradation
- 500-event circular buffer for event history
- Three independent user stories (P1: systemd, P2: proc monitoring, P3: correlation)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ Core Principles Compliance

**I. Modular Composition**: ✅ PASS
- Feature extends existing daemon module (`home-modules/desktop/i3-project-event-daemon/`)
- New functionality isolated in separate Python modules (systemd_query.py, proc_monitor.py, event_correlator.py)
- No duplication - reuses existing EventEntry model, event buffer, IPC server

**II. Reference Implementation Flexibility**: ✅ PASS
- Feature will be validated on Hetzner (reference platform) first
- All features work on NixOS with systemd and /proc (standard Linux)

**III. Test-Before-Apply**: ✅ PASS
- All changes will be tested with dry-build before switch
- Python daemon changes require systemctl restart for validation

**VI. Declarative Configuration**: ✅ PASS
- systemd journal queries are runtime operations (no config files)
- /proc monitoring uses allowlist in Python code (declaratively defined)
- No imperative post-install scripts required

**VII. Documentation as Code**: ✅ PASS
- Will generate quickstart.md, research.md, data-model.md
- Module headers will document new integration points
- CLAUDE.md will be updated with new event source usage

**X. Python Development & Testing Standards**: ✅ PASS
- Python 3.11+ with async/await patterns (asyncio)
- pytest with pytest-asyncio for async tests
- Type hints for all new functions
- Pydantic models for data validation
- Rich library for terminal UI (existing)
- Follows existing daemon architecture patterns

**XI. i3 IPC Alignment & State Authority**: ✅ PASS
- systemd and /proc are supplementary data sources, not state authority
- i3 IPC remains authoritative for window/workspace/output state
- Event correlation validates against i3 IPC window tree

**XII. Forward-Only Development**: ✅ PASS
- No legacy compatibility layers required
- New event sources integrate seamlessly with existing unified event system
- Existing --source flag extended to support new values (systemd, proc, all)

**XIII. Deno CLI Standards**: ⚠️ PARTIAL
- Deno CLI (daemon.ts) will add --source parameter handling
- No changes to Deno architecture required
- CLI remains thin client to Python daemon

### Constitution Alignment Summary

**No violations identified.** Feature extends existing architecture using established patterns. All new code follows Python Development & Testing Standards (Principle X). Event system already supports multiple sources via unified EventEntry model, making this a natural extension rather than architectural change.

## Project Structure

### Documentation (this feature)

```
specs/029-linux-system-log/
├── spec.md              # Feature specification (complete)
├── plan.md              # This file
├── research.md          # Phase 0 output - technology decisions and patterns
├── data-model.md        # Phase 1 output - EventEntry extensions and entities
├── quickstart.md        # Phase 1 output - usage guide
├── contracts/           # Phase 1 output - IPC protocol extensions
│   └── event-schema.json # EventEntry JSON schema with new fields
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```
home-modules/desktop/i3-project-event-daemon/
├── daemon.py                    # Main daemon (existing) - minimal changes
├── handlers.py                  # i3 event handlers (existing) - no changes
├── event_buffer.py              # Event storage (existing) - no changes
├── ipc_server.py                # JSON-RPC server (existing) - add query methods
├── models.py                    # EventEntry model (existing) - extend source enum
├── systemd_query.py             # NEW - journalctl integration
├── proc_monitor.py              # NEW - /proc filesystem monitoring
├── event_correlator.py          # NEW - parent-child relationship detection
└── README.md                    # Update with new event sources

home-modules/tools/i3pm-deno/
├── src/
│   ├── commands/
│   │   └── daemon.ts            # Extend --source flag handling
│   └── validation.ts            # Update EventNotificationSchema for new sources
└── deno.json

tests/i3-project-daemon/
├── unit/
│   ├── test_systemd_query.py    # NEW - systemd query parsing tests
│   ├── test_proc_monitor.py     # NEW - proc monitoring tests
│   └── test_event_correlator.py # NEW - correlation logic tests
└── integration/
    └── test_unified_stream.py   # NEW - multi-source event stream tests
```

**Structure Decision**: Single project extension to existing i3-project-event-daemon. New functionality isolated in three new Python modules that integrate with existing event buffer and IPC server. Deno CLI requires minimal changes to support new event sources in query parameters.

## Complexity Tracking

*No constitution violations requiring justification.*

## Phase 0: Research & Technology Decisions

### Research Tasks

1. **systemd Journal Query Patterns**
   - Best practices for journalctl JSON parsing
   - Time-based query syntax (--since, --until)
   - User-level vs system-level journal filtering
   - Performance characteristics of large journal queries

2. **Process Monitoring Patterns**
   - /proc filesystem polling vs inotify
   - Optimal polling intervals for process detection
   - Race condition handling (process exits before read)
   - Process filtering strategies (allowlist vs denylist)

3. **Sensitive Data Sanitization**
   - Common password/token patterns in command lines
   - Regex patterns for key=value extraction
   - False positive prevention
   - Balance between security and debuggability

4. **Event Correlation Algorithms**
   - Parent-child relationship detection via /proc/{pid}/stat
   - Timing proximity heuristics (window creation to process spawn)
   - Name similarity algorithms (window class vs process name)
   - Confidence scoring for correlation matches

5. **Python Asyncio Integration**
   - subprocess.run() vs asyncio.create_subprocess_exec()
   - AsyncIO event loop integration with existing daemon
   - Proper resource cleanup for subprocess handles
   - Error handling patterns for subprocess failures

### Research Outputs

**Output**: `research.md` with decisions and rationale for each research area

## Phase 1: Design Artifacts

### 1. Data Model Extensions (`data-model.md`)

**Entities to define**:

1. **SystemdEvent** (maps to EventEntry)
   - Fields: service_unit, systemd_message, pid, journal_timestamp
   - Mapping to EventEntry fields
   - Validation rules

2. **ProcessEvent** (maps to EventEntry)
   - Fields: pid, comm, cmdline_sanitized, parent_pid
   - Mapping to EventEntry fields
   - Sanitization rules

3. **EventCorrelation**
   - Fields: parent_event_id, child_event_ids[], confidence_score, time_delta
   - Relationship types: window_to_process, process_to_subprocess
   - Scoring algorithm

4. **EventEntry Extensions**
   - New source enum values: "systemd", "proc"
   - New optional fields for systemd/proc data
   - Schema versioning

### 2. API Contracts (`contracts/`)

**Files to generate**:

1. **event-schema.json** - EventEntry JSON schema with new fields
2. **ipc-extensions.md** - New JSON-RPC methods:
   - `query_systemd_events(since, until)` → EventEntry[]
   - `start_proc_monitoring()` → {status, pid}
   - `stop_proc_monitoring()` → {status}
   - `get_correlation(event_id)` → EventCorrelation

### 3. Quickstart Guide (`quickstart.md`)

**Sections**:
- Installation (no changes - part of existing daemon)
- Query systemd events: `i3pm daemon events --source=systemd --since="1 hour ago"`
- Enable process monitoring: Configuration flag in daemon startup
- View unified stream: `i3pm daemon events --source=all`
- Correlate events: `i3pm daemon events --correlate`
- Filter by process: `i3pm daemon events --source=proc | grep rust-analyzer`
- Export to JSON: `i3pm daemon events --source=all --json > events.json`

### 4. Agent Context Update

Run `.specify/scripts/bash/update-agent-context.sh claude` to add:
- Python asyncio subprocess patterns
- systemd journalctl integration
- /proc filesystem monitoring
- Event correlation algorithms

**Output**: Updated `.claude/context.md` with Linux system log integration patterns

## Phase 2: Task Breakdown

*Generated by `/speckit.tasks` command - not created by this plan*

Tasks will be organized by user story priority:
- **P1 Tasks**: systemd journal integration (FR-001 through FR-008)
- **P2 Tasks**: /proc monitoring (FR-009 through FR-017)
- **P3 Tasks**: Event correlation (FR-024 through FR-027)
- **Foundation Tasks**: EventEntry model extensions, unified stream merging (FR-018 through FR-023)

## Implementation Notes

### Integration Points

1. **daemon.py startup**
   - Initialize systemd query module
   - Start proc monitoring loop (optional, configurable)
   - Register IPC query methods for systemd/proc events

2. **event_buffer.py**
   - No changes required - already supports multiple sources
   - EventEntry model handles new source types

3. **ipc_server.py**
   - Add query_systemd_events() JSON-RPC method
   - Add start_proc_monitoring() / stop_proc_monitoring() methods
   - Add get_correlation() method

4. **Deno CLI (daemon.ts)**
   - Extend --source flag: add "systemd", "proc", "all" values
   - Add --correlate flag for correlation display
   - Update formatEvent() to handle systemd/proc event types

### Risk Mitigation

1. **Performance Risk**: /proc monitoring CPU usage
   - Mitigation: Configurable polling interval (default 500ms)
   - Mitigation: Process allowlist filtering
   - Mitigation: CPU usage monitoring in tests

2. **Accuracy Risk**: Sensitive data leakage in command lines
   - Mitigation: Comprehensive regex patterns for sanitization
   - Mitigation: Unit tests with known sensitive patterns
   - Mitigation: Truncation at 500 chars as secondary protection

3. **Reliability Risk**: journalctl unavailability
   - Mitigation: Graceful degradation (show other sources)
   - Mitigation: Clear error messages
   - Mitigation: Fallback to empty event list

4. **Complexity Risk**: Event correlation false positives
   - Mitigation: Confidence scoring (target 80% accuracy)
   - Mitigation: Display correlation as supplementary data, not authoritative
   - Mitigation: User can ignore correlation and view flat event stream

### Testing Strategy

**Unit Tests**:
- systemd JSON parsing with sample journal entries
- /proc cmdline parsing with various formats
- Sensitive data sanitization patterns
- Event correlation scoring algorithm

**Integration Tests**:
- Query systemd journal and verify EventEntry conversion
- Start/stop proc monitoring and verify events captured
- Merge events from i3 + systemd + proc in chronological order
- Validate correlation detection with known parent-child processes

**Scenario Tests**:
- Launch Firefox → verify systemd service start + i3 window::new
- Launch VS Code → verify window::new + rust-analyzer process spawn
- Stream events live → verify all sources appear with <2s latency

## Success Metrics

From spec.md Success Criteria:

- **SC-001**: systemd query response <1 second ✓
- **SC-002**: 95% journal entry parsing success ✓
- **SC-003**: /proc detection within 1 second ✓
- **SC-004**: Chronological ordering accuracy ✓
- **SC-005**: Live streaming <2 second latency ✓
- **SC-006**: CPU usage <5% for process monitoring ✓
- **SC-007**: 100% sensitive data sanitization ✓
- **SC-008**: 80% correlation accuracy ✓
- **SC-009**: JSON output parseable by jq/python ✓
- **SC-010**: Graceful degradation on journalctl failure ✓

## Post-Design Constitution Check

*Re-evaluation after Phase 1 design completion*

### ✅ All Principles Still Compliant

**Review of design decisions against constitution**:

1. **Modular Composition** ✅
   - Design creates 3 new isolated modules (systemd_query.py, proc_monitor.py, event_correlator.py)
   - Reuses existing EventEntry model with field extensions (no duplication)
   - IPC server extensions follow existing method registration pattern

2. **Python Development Standards** ✅
   - All new modules use async/await patterns (asyncio)
   - Type hints specified in data model for all new functions
   - Pydantic validation extends existing EventEntry model
   - Test structure follows existing pytest patterns

3. **i3 IPC Alignment** ✅
   - systemd and /proc are supplementary sources, not state authority
   - Event correlation validates against i3 IPC window tree (authoritative)
   - No parallel state tracking that could desync from i3

4. **Forward-Only Development** ✅
   - EventEntry source enum extension (not parallel implementation)
   - No legacy compatibility layers
   - Existing --source flag naturally extends to new values

**Design Changes**:
- Added 9 optional fields to EventEntry (backward compatible)
- Created EventCorrelation entity (new table, no migration needed)
- Extended IPC protocol with 5 new methods (additive, not breaking)

**Conclusion**: Design maintains architectural consistency with existing patterns. No constitution violations introduced.

## Next Steps

1. ✅ Phase 0: Execute research tasks → `research.md` complete
2. ✅ Phase 1: Design data models → `data-model.md` complete
3. ✅ Phase 1: Define API contracts → `contracts/` complete
4. ✅ Phase 1: Write quickstart guide → `quickstart.md` complete
5. ✅ Phase 1: Update agent context → CLAUDE.md updated
6. ✅ Post-design constitution check → No violations, all compliant
7. ⏭️ Phase 2: Run `/speckit.tasks` to generate implementation tasks
8. ⏭️ Phase 3: Run `/speckit.implement` to execute task-by-task implementation

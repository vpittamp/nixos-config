# Implementation Plan: Sway Tree Diff Monitor

**Branch**: `052-sway-tree-diff-monitor` | **Date**: 2025-11-07 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/052-sway-tree-diff-monitor/spec.md`

## Summary

Implement a real-time tree diff monitor for Sway compositor that tracks window management state changes with <10ms diff computation latency, <100ms display latency, and <25MB memory usage for 500 events. The monitor uses custom hash-based incremental diffing (xxHash + Merkle trees), correlates user actions (keypresses) with tree changes using 500ms time windows and confidence scoring, and provides multiple display modes (live streaming, historical query, detailed diff inspection) via a Textual-based TUI. Events are stored in a circular buffer (collections.deque) with optional JSON file persistence.

**Key Innovation**: Merkle tree hashing enables logarithmic diff performance - only 7 subtree hashes need recomputation when 1 window changes in a 100-window tree, achieving 2-8ms latency vs 2-5 seconds for libraries like DeepDiff.

---

## Technical Context

**Language/Version**: Python 3.11+ (matching existing i3pm daemon)

**Primary Dependencies**:
- `xxhash` - Fast non-cryptographic hashing (~1-2 GB/s throughput) for tree diffing
- `orjson` - 6x faster JSON serialization with deterministic key ordering
- `textual` - Full TUI framework with native async/await support and <100ms reactive updates
- `i3ipc.aio` - Async Sway IPC communication (already in project)
- `pydantic` v2 - Data validation and models (already in project)
- `rich` - Terminal formatting (already in project, inherited by Textual)

**Storage**:
- In-memory: Circular buffer (`collections.deque(maxlen=500)`) for event storage (~2.5 MB for 500 events)
- On-disk (optional): JSON files in `~/.local/share/sway-tree-monitor/` with 7-day retention

**Testing**:
- `pytest` with `pytest-asyncio` for async test support
- Unit tests for data models, diff algorithm, hash cache
- Integration tests for Sway IPC communication, event correlation
- Performance benchmarks for diff computation (target: <10ms p95)

**Target Platform**: Linux NixOS with Sway Wayland compositor (Hetzner Cloud reference, M1 Mac)

**Project Type**: Single project (Python daemon + CLI client)

**Performance Goals**:
- Tree diff computation: <10ms for 100-window trees (p95)
- Display latency: <100ms from Sway event to screen update
- Memory usage: <25MB total (2.5MB buffer + 12KB hash cache + 25KB correlation tracker)
- CPU usage: <2% average during active monitoring

**Constraints**:
- <10ms diff computation for 95% of events (100-window trees)
- <100ms real-time display latency (99% of cases)
- <25MB memory usage with 500-event circular buffer
- <2% CPU usage average (prevent impact on desktop performance)
- Async-safe (no threading, use asyncio for concurrency)

**Scale/Scope**:
- Support 50-200 concurrent windows in tree
- 500-event circular buffer (covers 1-2 hours typical usage)
- 5-10 events/minute typical frequency, bursts up to 50 events/second
- 3-5 KB per event (snapshot + diff + metadata)

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ **Passed All Gates**

| Principle | Compliance | Notes |
|-----------|------------|-------|
| **I. Modular Composition** | ✅ Pass | Implementation follows modular patterns: daemon (event collection), CLI (user interface), models (data structures), services (diff computation, correlation). No duplication with existing i3pm daemon - leverages shared patterns (EventBuffer, i3ipc.aio). |
| **II. Reference Implementation** | ✅ Pass | Validated on Hetzner Sway (reference configuration). Wayland-native design aligns with Sway/Wayland migration (Feature 047). Compatible with M1 (Wayland) and Hetzner (Wayland + VNC). |
| **III. Test-Before-Apply** | ✅ Pass | Standard dry-build workflow applies for NixOS package additions. Python code uses pytest with async support for validation before deployment. |
| **IV. Override Priority** | ✅ Pass | No NixOS option conflicts introduced. Python package additions use standard home-manager patterns with lib.optionals for conditional inclusion. |
| **V. Platform Flexibility** | ✅ Pass | Works on all Sway platforms (Hetzner, M1). WSL excluded (no Wayland compositor). Containers excluded (GUI not available). Detection via `config.services.sway.enable or false`. |
| **VI. Declarative Configuration** | ✅ Pass | All Python packages declared in `python-environment.nix`. Systemd service unit declared in NixOS modules. Optional TOML config for user preferences (not required). No imperative setup needed. |
| **VII. Documentation as Code** | ✅ Pass | Comprehensive documentation: research.md (algorithm choices), data-model.md (type definitions), contracts/ (API specs), quickstart.md (user guide), plan.md (this file). |
| **X. Python Development Standards** | ✅ Pass | Python 3.11+ with async/await, pytest-asyncio, Pydantic models, Rich/Textual UI, i3ipc.aio, standard logging. Follows existing i3pm daemon patterns. |
| **XI. i3 IPC Alignment** | ✅ Pass | Uses Sway IPC as authoritative source: `get_tree()` for snapshots, event subscriptions for triggers, no custom state tracking (daemon only caches hashes for performance). |
| **XII. Forward-Only Development** | ✅ Pass | No legacy compatibility needed. Clean implementation using modern tools (Textual, xxHash, orjson). Replaces manual tree inspection (no previous solution to preserve). |
| **XIV. Test-Driven Development** | ✅ Pass | Comprehensive test plan: unit tests (data models, diff algorithm), integration tests (Sway IPC, correlation), performance benchmarks (10ms target validation). Autonomous execution via pytest. |

**Complexity Justification**: None required - no constitutional violations.

---

## Project Structure

### Documentation (this feature)

```text
specs/052-sway-tree-diff-monitor/
├── plan.md                      # This file (implementation plan)
├── spec.md                      # Feature specification with user stories
├── research.md                  # Phase 0: Algorithm research, library evaluation
├── data-model.md                # Phase 1: TreeSnapshot, TreeDiff, EventCorrelation models
├── quickstart.md                # Phase 1: User guide with examples
└── contracts/                   # Phase 1: API specifications
    ├── cli.md                   # CLI command reference
    └── daemon-api.md            # JSON-RPC 2.0 API over Unix socket
```

### Source Code (repository root)

```text
home-modules/tools/sway-tree-monitor/
├── __init__.py                  # Package initialization
├── __main__.py                  # CLI entry point (Textual app)
├── daemon.py                    # Background daemon (Sway event listener)
├── models.py                    # Pydantic models (TreeSnapshot, TreeDiff, etc.)
├── diff/
│   ├── __init__.py
│   ├── hasher.py               # xxHash-based Merkle tree hashing
│   ├── differ.py               # Tree diff algorithm (hash-based traversal)
│   └── cache.py                # HashCache implementation
├── correlation/
│   ├── __init__.py
│   ├── tracker.py              # CorrelationTracker (time window + scoring)
│   └── scoring.py              # Multi-factor confidence scoring
├── buffer/
│   ├── __init__.py
│   └── event_buffer.py         # TreeEventBuffer (circular deque)
├── ui/
│   ├── __init__.py
│   ├── app.py                  # Main Textual app
│   ├── live_view.py            # Live streaming mode
│   ├── history_view.py         # Historical query mode
│   ├── diff_view.py            # Detailed diff inspection
│   └── stats_view.py           # Statistical summary
├── rpc/
│   ├── __init__.py
│   ├── server.py               # JSON-RPC 2.0 server (daemon side)
│   └── client.py               # JSON-RPC 2.0 client (CLI side)
└── README.md                    # Developer documentation

modules/services/sway-tree-monitor.nix
# Systemd service configuration (daemon auto-start)

tests/sway-tree-monitor/
├── unit/
│   ├── test_models.py          # Pydantic model validation
│   ├── test_hasher.py          # Hash computation correctness
│   ├── test_differ.py          # Diff algorithm accuracy
│   └── test_scoring.py         # Confidence scoring logic
├── integration/
│   ├── test_sway_ipc.py        # Sway IPC event subscription
│   ├── test_correlation.py     # End-to-end event correlation
│   └── test_buffer.py          # Circular buffer operations
├── performance/
│   └── benchmark_diff.py       # Diff computation latency (10ms target)
└── fixtures/
    ├── sample_trees.py         # Mock Sway tree snapshots (50/100/200 windows)
    └── sample_events.py        # Mock event sequences
```

**Structure Decision**: Single Python project pattern (Option 1) selected. No web frontend or mobile app components - terminal-only TUI via Textual. Daemon and CLI client share models and services but run as separate processes (daemon=background service, CLI=user interface). Follows existing i3pm daemon structure for consistency.

---

## Complexity Tracking

> **Not Applicable** - No constitutional violations requiring justification.

---

## Research Outcomes (Phase 0)

All technical unknowns resolved in `research.md`. Key findings:

### Tree Diffing Algorithm
- **Decision**: Custom hash-based incremental diffing with xxHash + Merkle trees
- **Performance**: 2-8ms for 100 windows (100-1000x faster than DeepDiff library)
- **Approach**: Top-down hash comparison skips unchanged subtrees, field-level diffs for changes
- **Libraries rejected**: DeepDiff (2-5s), jsondiff (too basic), tree edit distance (wrong problem)

### Event Correlation Strategy
- **Decision**: 500ms time window with multi-factor confidence scoring
- **Correlation method**: Hybrid (timestamp primary, sequence ID fallback)
- **Confidence factors**: Temporal proximity (40%), semantic matching (30%), exclusivity (20%), cascade position (10%)
- **Data structure**: Circular buffer + time-indexed map for O(log n) lookup

### Terminal UI Framework
- **Decision**: Textual (built on Rich, already in project)
- **Rationale**: Native async/await, <100ms reactive updates, multiple display modes, SSH/remote support
- **Alternative considered**: urwid (older API), py-cui (unmaintained)
- **Migration path**: Keep Rich for simple displays, use Textual for full interactive app

### Circular Buffer Implementation
- **Decision**: `collections.deque(maxlen=500)` with snapshot+diff storage
- **Performance**: <0.001ms append, <0.025ms query, ~2.5 MB memory for 500 events
- **Persistence**: Optional JSON files with 7-day retention (~420 KB/week)
- **Why no indexing**: At 500-event scale, linear scan is 10-30x faster than maintaining indices

---

## Design Artifacts (Phase 1)

### Data Models (`data-model.md`)

**Core Entities**:
1. `TreeSnapshot` - Complete Sway tree state (~3-5 KB)
2. `TreeDiff` - Changes between snapshots (~0.2-0.5 KB)
3. `UserAction` - Keypress/mouse/IPC command event
4. `EventCorrelation` - Link action → tree change (confidence score)
5. `TreeEvent` - Top-level record (snapshot + diff + correlation) (~5 KB)
6. `HashCache` - Merkle tree hash cache (~12 KB for 200 windows)
7. `FilterCriteria` - Query filter rules

**Memory Budget**:
- 500 events × 5 KB = 2.5 MB (10x under 25MB target)
- Hash cache: ~12 KB
- Correlation tracker: ~25 KB
- **Total: ~2.54 MB** ✅

### API Contracts (`contracts/`)

**CLI Commands** (`cli.md`):
1. `sway-tree-monitor live` - Real-time event stream (default)
2. `sway-tree-monitor history` - Historical query with filters
3. `sway-tree-monitor diff <EVENT_ID>` - Detailed event inspection
4. `sway-tree-monitor stats` - Statistical summary
5. `sway-tree-monitor export <FILE>` - Export to JSON
6. `sway-tree-monitor import <FILE>` - Import/replay events

**Daemon API** (`daemon-api.md`):
- Protocol: JSON-RPC 2.0 over Unix socket (`$XDG_RUNTIME_DIR/sway-tree-monitor.sock`)
- Methods: `ping`, `query_events`, `get_event`, `subscribe`, `get_statistics`, `export_events`, `import_events`, `get_daemon_status`
- Performance: <1ms ping, <2ms query, <100ms subscription latency

### User Guide (`quickstart.md`)

Comprehensive quick-start with:
- Installation steps (Python packages, systemd service)
- Common commands and workflows
- Troubleshooting guide
- Performance benchmarks
- Integration with i3pm

---

## Implementation Roadmap

### Phase 1: Core Diffing (P1 - User Story 1) - ~3-4 days
**Goal**: Real-time tree diff display with <10ms computation

1. Implement `TreeSnapshot` capture with `i3ipc.aio.Connection().get_tree()`
2. Implement xxHash-based Merkle tree computation (`diff/hasher.py`)
3. Implement hash-based diff algorithm (`diff/differ.py`)
4. Add field-level comparison for changed nodes
5. Unit tests for hasher and differ (pytest)
6. Performance benchmark (validate <10ms target)

**Deliverable**: Working diff engine with <10ms latency

### Phase 2: Circular Buffer & Event Storage (P1/P2) - ~1-2 days
**Goal**: Store 500 events in memory with fast queries

1. Implement `TreeEventBuffer` using `collections.deque(maxlen=500)`
2. Add query methods (filter by type, time range, significance)
3. Implement snapshot+diff storage pattern (memory optimization)
4. Add optional JSON file persistence
5. Unit tests for buffer operations

**Deliverable**: Event buffer with <0.025ms query latency, ~2.5 MB memory

### Phase 3: Event Correlation (P2 - User Story 2) - ~2-3 days
**Goal**: Correlate user actions with tree changes (500ms window)

1. Implement `CorrelationTracker` with time-indexed map
2. Add Sway binding event listener (keypress detection)
3. Calculate multi-factor confidence scores
4. Track cascade chains (primary → secondary → tertiary effects)
5. Unit tests for correlation logic
6. Integration test for end-to-end correlation

**Deliverable**: 95% correlation accuracy for direct actions

### Phase 4: Daemon & IPC (P1/P2) - ~2-3 days
**Goal**: Background daemon with JSON-RPC API

1. Implement daemon main loop (Sway event subscription)
2. Implement JSON-RPC 2.0 server over Unix socket (`rpc/server.py`)
3. Add systemd service unit configuration
4. Implement RPC methods (`ping`, `query_events`, `get_event`, etc.)
5. Add daemon health monitoring and auto-reconnect
6. Integration tests for daemon communication

**Deliverable**: Daemon with <100ms event processing latency

### Phase 5: Textual TUI (P1-P3) - ~3-4 days
**Goal**: Interactive terminal UI with multiple modes

1. Install Textual framework (add to `python-environment.nix`)
2. Implement main app skeleton (`ui/app.py`)
3. Implement live streaming mode (`ui/live_view.py`)
4. Implement historical query mode (`ui/history_view.py`)
5. Implement detailed diff inspection (`ui/diff_view.py`)
6. Implement statistical summary (`ui/stats_view.py`)
7. Add keyboard navigation and filtering
8. Integration tests for UI workflows

**Deliverable**: Full interactive TUI with <100ms reactive updates

### Phase 6: Enrichment & Polish (P2/P3) - ~2 days
**Goal**: Add context enrichment and final polish

1. Integrate /proc environ reading for I3PM_* variables (reuse existing pattern)
2. Add project association from window marks
3. Store enriched context with TreeSnapshot
4. Add configuration file support (TOML)
5. Add export/import functionality
6. Documentation updates

**Deliverable**: Context-enriched diffs, full feature set

**Total Estimated Time**: ~13-18 days

---

## Testing Strategy

### Unit Tests (~30% of test suite)
- Data models: Pydantic validation, field constraints
- Hash computation: Correctness, collision handling
- Diff algorithm: Accuracy, edge cases (empty trees, no changes, 100% changes)
- Confidence scoring: Multi-factor calculation, threshold logic
- Buffer operations: FIFO eviction, query filters

**Target**: >80% code coverage, <1ms per test

### Integration Tests (~40% of test suite)
- Sway IPC: Event subscription, tree queries, connection retry
- Event correlation: End-to-end keypress → tree change → correlation
- Daemon RPC: Client-server communication, JSON-RPC protocol
- Buffer persistence: Save/load from JSON files

**Target**: <100ms per test, realistic Sway tree fixtures

### Performance Benchmarks (~20% of test suite)
- Diff computation: 50/100/200 window trees, validate <10ms p95
- Query latency: 500-event buffer, validate <2ms
- Memory usage: 500 events, validate <25MB
- Display latency: Real-time updates, validate <100ms

**Target**: Automated CI validation, export metrics to JSON

### Manual Testing (~10% of effort)
- Live TUI testing with real Sway session
- Keyboard navigation and filtering
- SSH/remote terminal compatibility
- Integration with i3pm workflows

---

## Deployment

### NixOS Integration

**Package additions** (`home-modules/desktop/python-environment.nix`):
```nix
sharedPythonEnv = pkgs.python3.withPackages (ps: with ps; [
  # Existing
  i3ipc pydantic rich

  # New for Feature 052
  xxhash        # Fast hashing
  orjson        # 6x faster JSON
  textual       # TUI framework
]);
```

**Systemd service** (`modules/services/sway-tree-monitor.nix`):
```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.sway-tree-monitor;
in {
  options.services.sway-tree-monitor = {
    enable = lib.mkEnableOption "Sway tree diff monitor daemon";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.sway-tree-monitor = {
      Unit = {
        Description = "Sway Tree Diff Monitor Daemon";
        Documentation = "file:///etc/nixos/specs/052-sway-tree-diff-monitor/";
        After = [ "sway-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        Type = "notify";
        ExecStart = "${pkgs.python3.withPackages (ps: [ps.textual ps.xxhash ps.orjson])}/bin/sway-tree-monitor-daemon";
        Restart = "on-failure";
        RestartSec = "5s";

        # Resource limits
        MemoryMax = "50M";
        CPUQuota = "5%";
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}
```

---

## Success Metrics

From spec.md Success Criteria, measure after implementation:

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **SC-002**: Diff computation | <10ms (p95) | Performance benchmark test suite |
| **SC-003**: Memory usage | <25MB | Monitor during 8-hour session with 500 events |
| **SC-004**: CPU usage | <1% avg | `systemctl --user status sway-tree-monitor` |
| **SC-005**: Display latency | <100ms (p99) | Live TUI latency tracking |
| **SC-006**: Correlation accuracy | 90% | Manual validation with 100 test events |
| **SC-009**: Query latency | <200ms | Integration test with 1000-event buffer |
| **SC-010**: Event burst handling | 50 events/s × 5s | Stress test with synthetic events |

**User Validation**:
- **SC-001**: Debug time <2 minutes (vs 10+ manual inspection)
- **SC-012**: Developer satisfaction survey (target: 80% reduction in debug time)

---

## Risk Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **200-window trees exceed 10ms** | Medium | High | Implement graceful degradation (show "computing..." indicator); consider 15ms target for >150 windows; profile and optimize hot paths |
| **Hash collisions cause false negatives** | Very Low | Medium | Use 64-bit xxHash (collision probability ~1 in 10¹⁹); add validation mode that compares full trees periodically |
| **/proc reads slow down enrichment** | Low | Medium | Already benchmarked at <1ms p95 (Feature 057); make enrichment async and optional; cache results for 1 second |
| **Memory growth with hash cache** | Low | Low | Implement TTL-based eviction (60s); bounded by number of nodes (~12KB for 200 windows) |
| **Event correlation false positives** | Medium | Low | Use multi-factor confidence scoring; show multiple candidates when uncertain; user can inspect correlations |
| **Textual framework instability** | Low | Medium | Pin to stable version; fallback to Rich-only live display if Textual issues arise |

---

## Dependencies

### Python Packages (New)
```nix
xxhash        # Fast non-cryptographic hashing (~1-2 GB/s throughput)
orjson        # 6x faster JSON serialization with deterministic key ordering
textual       # Full TUI framework with async support
```

### Existing Infrastructure (Reuse)
- `i3ipc.aio` - Async Sway IPC (Feature 015)
- `pydantic` - Data validation (standard in i3pm)
- `rich` - Terminal formatting (inherited by Textual)
- EventBuffer pattern - Circular buffer (Feature 017)
- Window environment reading - /proc/<pid>/environ (Feature 057)

---

## Next Steps

**Planning complete**. Proceed to implementation task generation:

```bash
/speckit.tasks
```

This will generate `tasks.md` with dependency-ordered implementation tasks based on this plan.

**Ready to implement**: All research complete, design validated, performance targets achievable with significant margins (10-1000x headroom).

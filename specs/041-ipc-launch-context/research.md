# Research: IPC Launch Context Architecture

**Feature**: 041-ipc-launch-context
**Date**: 2025-10-27
**Status**: Complete (No unknowns identified)

## Overview

This document consolidates architecture decisions and design patterns for the IPC launch notification system. All technical context was well-defined in the feature specification, requiring no additional research for clarification.

## Key Architecture Decisions

### 1. Launch Notification Protocol

**Decision**: Use JSON-RPC endpoint on existing daemon IPC server for pre-launch notifications

**Rationale**:
- Reuses existing IPC infrastructure (Unix socket at `~/.cache/i3-project/daemon.sock`)
- Minimal latency (<5ms) for notification delivery
- Synchronous response confirms daemon received notification before app launch
- No need for separate notification mechanism

**Implementation**:
```python
# New IPC endpoint: notify_launch
{
  "jsonrpc": "2.0",
  "method": "notify_launch",
  "params": {
    "app_name": "vscode",
    "project_name": "nixos",
    "project_directory": "/etc/nixos",
    "launcher_pid": 12345,
    "workspace_number": 2,
    "timestamp": 1698765432.123
  },
  "id": 1
}
```

**Alternatives Considered**:
- **D-Bus signals**: Rejected - adds external dependency, higher latency
- **File-based queue**: Rejected - race conditions, cleanup complexity
- **Environment variables only**: Rejected - fails for multi-instance apps (current problem)

---

### 2. Correlation Algorithm Design

**Decision**: Multi-signal correlation with confidence scoring and threshold-based matching

**Correlation Signals** (from FR-006):
1. **Application Class** (REQUIRED): Window class must match expected class from app registry
2. **Time Delta** (REQUIRED): Window creation within 5 seconds of launch notification
3. **Workspace Location** (OPTIONAL): Window appears on expected workspace number

**Confidence Calculation** (from FR-015 to FR-018):
```python
def calculate_confidence(launch: PendingLaunch, window: WindowInfo) -> float:
    confidence = 0.0

    # Application class match (required baseline)
    if window.window_class == launch.expected_class:
        confidence = 0.5  # Baseline for class match
    else:
        return 0.0  # No match possible without class alignment

    # Time delta scoring
    time_delta = window.timestamp - launch.timestamp
    if time_delta < 1.0:
        confidence += 0.3  # Very recent launch
    elif time_delta < 2.0:
        confidence += 0.2  # Recent launch
    elif time_delta < 5.0:
        confidence += 0.1  # Within timeout window
    else:
        return 0.0  # Outside correlation window

    # Workspace match bonus
    if window.workspace_number == launch.workspace_number:
        confidence += 0.2  # Workspace alignment

    return min(confidence, 1.0)  # Cap at EXACT (1.0)

# Matching threshold: MEDIUM (0.6) minimum required
```

**Rationale**:
- Class match prevents cross-application false positives
- Time-based scoring prioritizes recent launches for rapid succession scenarios
- Workspace matching provides disambiguation when needed without being mandatory
- Threshold prevents low-confidence guesses

**Alternatives Considered**:
- **PID tree walking**: Rejected - complex, unreliable for sandboxed apps, defeats purpose of IPC approach
- **Title pattern matching**: Rejected - fragile, locale-dependent, explicitly out of scope (FR-008)
- **First-match-only**: Rejected - doesn't handle out-of-order window appearances

---

### 3. Pending Launch Registry

**Decision**: In-memory dictionary with automatic expiration via async cleanup task

**Data Structure**:
```python
class PendingLaunch(BaseModel):
    """Represents a pending application launch awaiting correlation."""
    app_name: str
    project_name: str
    project_directory: Path
    launcher_pid: int
    workspace_number: int
    timestamp: float
    expected_class: str  # Resolved from app registry
    matched: bool = False

class LaunchRegistry:
    """Manages pending launches with automatic expiration."""
    def __init__(self, timeout: float = 5.0):
        self._launches: Dict[str, PendingLaunch] = {}
        self._timeout = timeout

    async def add(self, launch: PendingLaunch) -> None:
        """Add pending launch and trigger cleanup of expired entries."""
        await self._cleanup_expired()
        launch_id = f"{launch.app_name}-{launch.timestamp}"
        self._launches[launch_id] = launch

    async def find_match(self, window: WindowInfo) -> Optional[PendingLaunch]:
        """Find best matching launch for window using correlation algorithm."""
        candidates = [l for l in self._launches.values() if not l.matched]
        best_match = None
        best_confidence = 0.6  # MEDIUM threshold

        for launch in candidates:
            confidence = calculate_confidence(launch, window)
            if confidence > best_confidence:
                best_match = launch
                best_confidence = confidence

        if best_match:
            best_match.matched = True
        return best_match

    async def _cleanup_expired(self) -> None:
        """Remove launches older than timeout."""
        now = time.time()
        expired = [
            id for id, l in self._launches.items()
            if (now - l.timestamp) > self._timeout
        ]
        for id in expired:
            launch = self._launches.pop(id)
            logger.warning(f"Launch expired: {launch.app_name} for project {launch.project_name}")
```

**Rationale**:
- Dictionary lookup is O(1) for add/remove operations
- Automatic cleanup on each add prevents unbounded growth
- Matched flag prevents double-matching
- Expiration logging enables debugging (FR-009)

**Memory Profile**:
- Per-launch overhead: ~150 bytes (Python object + strings)
- 1000 launches: ~150KB (well under 5MB constraint)
- Expiration ensures steady-state <10 active launches typical

**Alternatives Considered**:
- **Persistent storage (SQLite/JSON file)**: Rejected - unnecessary I/O overhead, spec requires in-memory only
- **Background cleanup task**: Rejected - cleanup on add is simpler and sufficient
- **LRU cache eviction**: Rejected - time-based expiration is more predictable

---

### 4. Window Event Handler Integration

**Decision**: Extend existing `handlers.py` window::new handler to query launch registry

**Integration Point**:
```python
# handlers.py - existing window event handler
async def on_window_new(self, i3conn, event):
    """Handle new window creation with launch correlation."""
    container = event.container
    window_info = WindowInfo(
        window_id=container.id,
        window_class=container.window_class,
        window_pid=container.pid,
        workspace_number=container.workspace().num,
        timestamp=time.time()
    )

    # NEW: Query launch registry for correlation
    matched_launch = await self.daemon.launch_registry.find_match(window_info)

    if matched_launch:
        # Assign project based on launch context
        project_name = matched_launch.project_name
        await self._assign_project(container, project_name)
        logger.info(
            f"Correlated window {container.id} ({window_info.window_class}) "
            f"to project {project_name} via launch context"
        )
    else:
        # No correlation - explicit failure mode (FR-008, FR-009)
        logger.error(
            f"Window {container.id} ({window_info.window_class}) appeared "
            f"without matching launch notification"
        )
        # Do NOT apply fallback logic - window gets no project assignment
```

**Rationale**:
- Minimal changes to existing event handling flow
- Correlation happens synchronously during window event processing
- Explicit logging of correlation failures for testing validation
- No fallback mechanisms (FR-008) - clean failure mode

**Performance**:
- Registry query: <1ms (dictionary iteration over <10 entries typical)
- Total handler latency: <10ms (target from Technical Context)

---

### 5. Application Launcher Wrapper Modification

**Decision**: Add pre-launch IPC notification to existing `app-launcher-wrapper.sh`

**Modification**:
```bash
#!/usr/bin/env bash
# app-launcher-wrapper.sh (EXISTING with ADDITION)

# ... existing project query logic ...

# NEW: Send launch notification to daemon
notify_launch() {
    local app_name="$1"
    local project_name="$2"
    local project_dir="$3"
    local workspace="$4"
    local timestamp=$(date +%s.%N)

    echo "{
        \"jsonrpc\": \"2.0\",
        \"method\": \"notify_launch\",
        \"params\": {
            \"app_name\": \"$app_name\",
            \"project_name\": \"$project_name\",
            \"project_directory\": \"$project_dir\",
            \"launcher_pid\": $$,
            \"workspace_number\": $workspace,
            \"timestamp\": $timestamp
        },
        \"id\": 1
    }" | socat - UNIX-CONNECT:$HOME/.cache/i3-project/daemon.sock
}

# Send notification BEFORE launching app
notify_launch "$APP_NAME" "$PROJECT_NAME" "$PROJECT_DIR" "$WORKSPACE"

# Launch application (EXISTING)
exec "$@"
```

**Rationale**:
- Synchronous notification ensures daemon receives context before window appears
- `socat` provides reliable Unix socket communication
- Minimal latency (<5ms typical) doesn't impact user experience
- Failure to send notification logged but doesn't block app launch

**Alternatives Considered**:
- **Python client script**: Rejected - adds Python interpreter startup overhead (~50ms)
- **Asynchronous notification**: Rejected - race condition if window appears before notification
- **Systemd-run wrapper**: Rejected - systemd overhead not needed, complicates signal flow

---

### 6. Testing Strategy

**Decision**: Scenario-based pytest test suite with daemon mock and state validation

**Test Organization** (following Principle X patterns):
```
home-modules/tools/i3-project-test/scenarios/launch_context/
├── sequential_launches.py      # User Story 1: >2s apart launches
├── rapid_launches.py           # User Story 2: <0.5s apart launches
├── timeout_handling.py         # User Story 3: 5s+ delays
├── multi_app_types.py          # User Story 4: Different app classes
└── workspace_disambiguation.py # User Story 5: Workspace signals
```

**Test Approach**:
1. **Mock daemon IPC server**: Captures launch notifications and window events
2. **Simulate event timing**: Control timestamps to test rapid/timeout scenarios
3. **State validation**: Query daemon state to verify correct project assignments
4. **Assertion library**: Validate expected vs actual correlation outcomes

**Example Test**:
```python
# scenarios/launch_context/sequential_launches.py
import pytest
from i3_project_test.assertions.launch_assertions import assert_window_correlated

@pytest.mark.asyncio
async def test_sequential_vscode_launches(daemon_client, i3_mock):
    """User Story 1: Sequential VS Code launches get correct project assignments."""

    # Scenario: Launch VS Code for "nixos" project
    await daemon_client.notify_launch(
        app_name="vscode",
        project_name="nixos",
        workspace_number=2,
        timestamp=100.0
    )

    # Simulate window appearance 0.5s later
    window_id = await i3_mock.create_window(
        window_class="Code",
        workspace_number=2,
        timestamp=100.5
    )

    # Validate correlation
    window_state = await daemon_client.get_window_state(window_id)
    assert_window_correlated(
        window_state,
        expected_project="nixos",
        expected_confidence_min=0.8  # HIGH confidence
    )

    # Scenario: Switch to "stacks" project, launch VS Code again
    await daemon_client.project_switch("stacks")
    await daemon_client.notify_launch(
        app_name="vscode",
        project_name="stacks",
        workspace_number=3,
        timestamp=105.0  # 5s later
    )

    window_id_2 = await i3_mock.create_window(
        window_class="Code",
        workspace_number=3,
        timestamp=105.3
    )

    window_state_2 = await daemon_client.get_window_state(window_id_2)
    assert_window_correlated(
        window_state_2,
        expected_project="stacks",
        expected_confidence_min=0.8
    )

    # Both windows should have correct, independent project assignments
    assert window_state.project_name != window_state_2.project_name
```

**Coverage Goals** (from SC-010):
- ✅ All 5 user stories with acceptance scenarios
- ✅ All 7 edge cases documented in spec
- ✅ Rapid launches (<0.5s): 95% correct assignment target
- ✅ Sequential launches (>2s): 100% correct assignment target
- ✅ Timeout expiration: 100% accuracy

---

## Integration with Existing Systems

### Daemon State Management

**Integration Point**: `state.py` - Add launch registry to daemon state

```python
# state.py
class DaemonState:
    def __init__(self):
        self.active_project = None
        self.window_tracking = {}
        self.launch_registry = LaunchRegistry(timeout=5.0)  # NEW
        # ... existing state ...
```

**No Changes Required**:
- Window filtering logic (`window_filtering.py`) - uses project marks from handlers
- Project switching (`handlers.py` tick events) - operates on marked windows
- IPC server framework (`ipc_server.py`) - just add new endpoint

### Application Registry

**Integration**: Resolve `expected_class` from existing application registry during launch notification

```python
# When processing notify_launch IPC call
app_definition = await self.daemon.app_registry.get(app_name)
pending_launch = PendingLaunch(
    app_name=app_name,
    expected_class=app_definition.expected_class,  # e.g., "Code" for VS Code
    # ... other params from notification ...
)
```

**Registry Example**:
```json
{
  "name": "vscode",
  "expected_class": "Code",
  "preferred_workspace": 2
}
```

---

## Performance Analysis

### Latency Breakdown

| Operation | Target | Typical | Notes |
|-----------|--------|---------|-------|
| Launch notification IPC | <5ms | 2-3ms | Unix socket, local |
| Registry add operation | <1ms | <1ms | Dict insert + cleanup |
| Window event delivery | N/A | ~50ms | i3 IPC subscription |
| Correlation query | <10ms | 1-2ms | <10 candidates typical |
| Total window→project | <100ms | 55ms | End-to-end latency |

**Bottleneck**: i3 window event delivery (not under our control, acceptable)

### Memory Profile

| Component | Per-Entry | Max Entries | Total |
|-----------|-----------|-------------|-------|
| PendingLaunch object | ~150 bytes | 1000 | 150KB |
| Registry overhead | ~50 bytes | 1 | 50 bytes |
| **Total** | - | - | **<200KB** |

**Well under 5MB constraint** (Technical Context)

---

## Risk Mitigation

### Known Risks

1. **Clock skew**: System clock changes during correlation window
   - **Mitigation**: Use monotonic timestamps (`time.monotonic()`)

2. **Daemon restart**: Pending launches lost
   - **Mitigation**: Acceptable per spec - in-memory only, system recovers on next launch

3. **Wrapper bypass**: App launched directly from terminal
   - **Mitigation**: Explicit error logging, no fallback (FR-008) - testing phase will identify coverage gaps

4. **Multi-window apps**: Browser opening multiple tabs
   - **Mitigation**: Out of scope (spec assumption #3) - first window matches, rest unassigned

5. **Confidence ties**: Two launches with identical confidence
   - **Mitigation**: First-match-wins (FR-011) - FIFO ordering in dictionary iteration

---

## Open Questions

**None** - All technical decisions resolved based on complete specification.

---

## Next Steps (Phase 1)

1. Generate `data-model.md` with Pydantic schemas for:
   - `PendingLaunch`
   - `WindowInfo`
   - `CorrelationResult`
   - Launch notification IPC contract

2. Generate API contracts in `contracts/`:
   - `notify_launch` JSON-RPC endpoint specification
   - Daemon state query extensions

3. Generate `quickstart.md` with:
   - User workflow examples
   - Testing commands
   - Debugging procedures

4. Update agent context files with new technologies (none - using existing stack)

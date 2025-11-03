# Data Model: Reliable Event-Driven Workspace Assignment

**Feature**: 053-workspace-assignment-enhancement
**Date**: 2025-11-02
**Design Phase**: Phase 1 - Data Structures

## Entity Definitions

### 1. Window Creation Event

**Source**: Sway IPC `window::new` event payload

**Purpose**: Represents a newly created window requiring workspace assignment

**Schema**:
```python
@dataclass
class WindowCreationEvent:
    """Window creation event from Sway IPC."""

    # Core identifiers
    container_id: int              # Sway container ID (con_id)
    window_id: Optional[int]       # X11 window ID (null for native Wayland)

    # Window properties
    app_id: Optional[str]          # Native Wayland app identifier
    window_class: Optional[str]    # X11 WM_CLASS class (from window_properties)
    window_instance: Optional[str] # X11 WM_CLASS instance
    window_title: str              # Window title

    # State
    workspace_number: int          # Current workspace (before assignment)
    output_name: str               # Current output (HEADLESS-1, eDP-1, etc.)
    is_floating: bool              # Floating vs tiled

    # Metadata
    pid: Optional[int]             # Process ID (for environment reading)
    timestamp: float               # Event receipt time

    # Property completeness indicator
    has_complete_properties: bool  # True if app_id/class is populated
```

**Validation Rules**:
- `container_id` MUST be positive integer
- At least one of `app_id`, `window_class`, or `window_title` MUST be present
- `workspace_number` MUST be in range 1-70
- `timestamp` MUST be Unix epoch seconds with microsecond precision

---

### 2. Event Subscription

**Purpose**: Tracks active event type subscriptions to Sway IPC

**Schema**:
```python
@dataclass
class EventSubscription:
    """Active event subscription to Sway IPC."""

    event_type: str                # "window", "workspace", "output", "tick", "mode"
    subscribed_at: datetime        # When subscription was established
    is_active: bool                # Subscription health status
    last_event_received: Optional[datetime]  # Most recent event timestamp
    event_count: int               # Total events received for this type

    # Health metrics
    subscription_failures: int     # Count of subscription attempts that failed
    last_failure: Optional[datetime]  # Most recent failure timestamp
    reconnect_attempts: int        # Auto-reconnect count
```

**State Transitions**:
```
[Not Subscribed] --subscribe()--> [Active]
[Active] --connection_lost()--> [Disconnected]
[Disconnected] --reconnect()--> [Active]
[Disconnected] --max_retries_exceeded()--> [Failed]
```

**Validation Rules**:
- `event_type` MUST be one of: "window", "workspace", "output", "tick", "mode", "shutdown"
- `is_active = True` implies `last_event_received` within last 60 seconds OR subscription just established
- `subscription_failures` increments on each failed subscription attempt
- `reconnect_attempts` resets to 0 on successful subscription

---

### 3. PWA Window

**Purpose**: Represents a Progressive Web App window with unique application identifier

**Schema**:
```python
@dataclass
class PWAWindow:
    """Progressive Web App window properties."""

    # Identifiers
    container_id: int              # Sway container ID
    pwa_type: str                  # "firefox" or "chrome"
    pwa_id: str                    # ULID (Firefox) or instance pattern (Chrome)

    # Firefox PWA properties
    ffpwa_ulid: Optional[str]      # 26-character ULID (e.g., "01K666N2V6BQMDSBMX3AY74TY7")

    # Chrome PWA properties
    chrome_instance: Optional[str] # URL-based instance (e.g., "chat.google.com__work")

    # Application metadata
    display_name: Optional[str]    # Human-readable name from registry
    app_name: Optional[str]        # Registry key (e.g., "youtube-pwa")

    # Assignment
    preferred_workspace: Optional[int]  # Target workspace from registry
    scope: str                     # "scoped" or "global"
```

**Identifier Patterns**:

**Firefox PWAs**:
- `pwa_type = "firefox"`
- `pwa_id = ffpwa_ulid` (e.g., "FFPWA-01K666N2V6BQMDSBMX3AY74TY7")
- `app_id` field contains full FFPWA-* string

**Chrome PWAs**:
- `pwa_type = "chrome"`
- `pwa_id = chrome_instance` (e.g., "chat.google.com__work")
- `window_class = "Google-chrome"` (generic)

**Validation Rules**:
- If `pwa_type == "firefox"`, then `ffpwa_ulid` MUST match pattern `^[0-9A-Z]{26}$`
- If `pwa_type == "chrome"`, then `chrome_instance` MUST be present
- `scope` MUST be either "scoped" or "global"
- `preferred_workspace` MUST be in range 1-70 if present

---

### 4. Launch Notification

**Purpose**: Pre-launch message from wrapper script indicating expected window creation

**Schema**:
```python
@dataclass
class LaunchNotification:
    """Pre-launch notification for window correlation."""

    # Launch context
    launch_id: str                 # Unique identifier (app_name-timestamp)
    app_name: str                  # Application identifier
    project_name: Optional[str]    # Project context (if scoped app)

    # Expected window properties
    expected_class: str            # Expected WM_CLASS or app_id
    expected_title_pattern: Optional[str]  # Regex pattern for title matching

    # Assignment target
    workspace_number: Optional[int]  # Target workspace (Priority 0)
    workspace_source: str          # "explicit" or "registry_default"

    # Correlation signals
    launch_workspace: int          # Workspace where launch command executed
    launch_timestamp: float        # When launch notification sent
    ttl_seconds: float             # Time-to-live (default 5.0)

    # State
    is_matched: bool               # Whether window was correlated
    matched_window_id: Optional[int]  # Container ID if matched
    correlation_confidence: Optional[float]  # Match confidence score
```

**Lifecycle**:
```
[Created] --launch_wrapper_sends()--> [Pending]
[Pending] --window_correlates()--> [Matched]
[Pending] --ttl_expires()--> [Expired]
```

**Validation Rules**:
- `launch_timestamp` MUST be within last `ttl_seconds`
- `workspace_number` MUST be in range 1-70 if present
- `correlation_confidence` MUST be in range 0.0-1.0 if present
- `is_matched = True` implies `matched_window_id` is present

---

### 5. Assignment Record

**Purpose**: Historical record of workspace assignment for diagnostics and tracking

**Schema**:
```python
@dataclass
class AssignmentRecord:
    """Historical workspace assignment record."""

    # Window identification
    window_id: int                 # Container ID
    window_class: str              # Application identifier
    window_title: str              # Window title at assignment time

    # Assignment details
    source_workspace: int          # Workspace where window was created
    target_workspace: int          # Workspace where window was assigned
    assignment_source: str         # Priority tier used (see Assignment Source enum)

    # Timing
    event_received_at: datetime    # When window::new event received
    assignment_completed_at: datetime  # When move command completed
    latency_ms: float              # Time from event receipt to assignment

    # Correlation
    launch_correlation: bool       # Whether launch notification was used
    launch_id: Optional[str]       # Launch notification ID if correlated

    # Validation
    was_successful: bool           # Whether assignment command succeeded
    error_message: Optional[str]   # Error details if failed
```

**Assignment Source Values**:
```python
class AssignmentSource(Enum):
    LAUNCH_NOTIFICATION = "launch_notification"  # Priority 0 (NEW)
    APP_HANDLER = "app_handler"                  # Priority 1
    TARGET_WORKSPACE_ENV = "target_workspace_env"  # Priority 2
    APP_NAME_REGISTRY = "app_name_registry"      # Priority 3
    CLASS_EXACT_MATCH = "class_exact_match"      # Priority 4a
    CLASS_INSTANCE_MATCH = "class_instance_match"  # Priority 4b
    CLASS_NORMALIZED_MATCH = "class_normalized_match"  # Priority 4c
    NO_MATCH = "no_match"                        # Fallback (no assignment)
```

**Performance Metrics**:
- `latency_ms` target: <100ms for Priority 0-3, <200ms for Priority 4
- `was_successful = True` target: >99.9% success rate
- `launch_correlation = True` target: >80% for PWAs (when using walker launcher)

---

### 6. Event Gap

**Purpose**: Represents potential missed events detected by gap analysis

**Schema**:
```python
@dataclass
class EventGap:
    """Detected gap in window event sequence."""

    # Gap identification
    gap_id: str                    # Unique identifier (timestamp-based)
    detection_method: str          # "window_id_sequence" or "subscription_health"

    # Gap details
    last_received_window_id: int   # Last window ID before gap
    next_received_window_id: int   # Next window ID after gap
    gap_size: int                  # Number of potentially missed events

    # Timing
    detected_at: datetime          # When gap was detected
    gap_start_estimate: datetime   # Estimated start of gap
    gap_end_estimate: datetime     # Estimated end of gap

    # Context
    subscription_status: dict      # State of all subscriptions at detection time
    recent_errors: List[str]       # Error messages preceding gap

    # Resolution
    was_recoverable: bool          # Whether missed events could be recovered
    recovery_method: Optional[str]  # "startup_scan" or "manual_reassignment"
```

**Detection Methods**:

1. **Window ID Sequence Gap**:
   - Compare consecutive window container IDs
   - Gap detected if difference > 1
   - Indicates potential missed `window::new` events

2. **Subscription Health**:
   - Monitor time since last event for each subscription type
   - Gap suspected if no events for >60 seconds during active session
   - May indicate subscription failure or IPC connection issue

**Validation Rules**:
- `gap_size = next_received_window_id - last_received_window_id - 1`
- `gap_size` MUST be > 0
- `detection_method` MUST be one of defined methods
- `was_recoverable = True` implies `recovery_method` is present

---

### 7. Assignment Configuration

**Purpose**: Single source of truth for workspace assignment rules

**Schema**:
```python
@dataclass
class AssignmentConfiguration:
    """Consolidated workspace assignment configuration."""

    # Schema version
    version: str                   # "1.0" (for future migrations)

    # Global assignments (apply to all projects)
    global_assignments: List[AssignmentRule]

    # Project-specific overrides
    project_assignments: Dict[str, List[AssignmentRule]]

    # Output-specific assignments
    output_assignments: Dict[str, List[AssignmentRule]]

    # Metadata
    last_modified: datetime
    source_file: str               # Path to configuration file
```

**Assignment Rule Schema**:
```python
@dataclass
class AssignmentRule:
    """Single workspace assignment rule."""

    # Match criteria
    app_name: str                  # Application identifier (registry key)
    expected_class: str            # Window class/app_id pattern
    match_type: str                # "exact", "regex", "prefix"

    # Assignment target
    workspace_number: int          # Target workspace (1-70)

    # Conditions (optional filters)
    project_filter: Optional[str]  # Only apply for specific project
    output_filter: Optional[str]   # Only apply for specific output

    # Priority
    priority: int                  # Lower number = higher priority
```

**File Format** (JSON):
```json
{
  "version": "1.0",
  "global_assignments": [
    {
      "app_name": "youtube-pwa",
      "expected_class": "FFPWA-01K666N2V6BQMDSBMX3AY74TY7",
      "match_type": "exact",
      "workspace_number": 4,
      "priority": 1
    }
  ],
  "project_assignments": {},
  "output_assignments": {},
  "last_modified": "2025-11-02T12:00:00Z",
  "source_file": "~/.config/i3/workspace-assignments.json"
}
```

**Migration from Application Registry**:
- Extract `preferred_workspace` field from app registry entries
- Convert to `AssignmentRule` with `match_type = "exact"`
- Maintain single source in application registry (don't duplicate)

---

## Relationships

### Window Creation → Assignment

```
WindowCreationEvent
    ↓ (correlation)
LaunchNotification? (optional, if launched via walker)
    ↓ (workspace resolution)
AssignmentConfiguration
    ↓ (execution)
AssignmentRecord (created after assignment)
```

### Event Subscription → Event Delivery

```
EventSubscription (active)
    ↓ (emits)
WindowCreationEvent
    ↓ (gap detection)
EventGap? (if sequence broken)
    ↓ (health monitoring)
EventSubscription (status update)
```

### PWA Launch → Window Assignment

```
Walker Launch Command
    ↓ (sends)
LaunchNotification
    ↓ (creates)
PWAWindow
    ↓ (receives event)
WindowCreationEvent
    ↓ (correlation)
LaunchNotification (matched)
    ↓ (priority 0 assignment)
AssignmentRecord
```

---

## State Machines

### Event Subscription Lifecycle

```
┌──────────────────┐
│  Not Subscribed  │
└─────────┬────────┘
          │ subscribe()
          ↓
     ┌────────┐
     │ Active │←──────────┐
     └───┬────┘           │
         │                │
         │ connection_lost()  reconnect()
         ↓                │
   ┌──────────────┐       │
   │ Disconnected │───────┘
   └──────┬───────┘
          │ max_retries_exceeded()
          ↓
      ┌────────┐
      │ Failed │
      └────────┘
```

### Launch Notification Correlation

```
┌──────────┐
│ Created  │
└────┬─────┘
     │ launch_wrapper_sends()
     ↓
┌─────────┐
│ Pending │
└────┬────┘
     │
     ├─→ window_correlates() ──→ ┌─────────┐
     │                            │ Matched │
     │                            └─────────┘
     │
     └─→ ttl_expires() ──────────→ ┌─────────┐
                                    │ Expired │
                                    └─────────┘
```

### Workspace Assignment Priority Resolution

```
Window Creation Event
    ↓
┌──────────────────────────────┐
│ Priority 0: Launch           │ (NEW - highest priority)
│ Notification Workspace       │
└──────────┬───────────────────┘
           │ (if no match)
           ↓
┌──────────────────────────────┐
│ Priority 1: App Handler      │
└──────────┬───────────────────┘
           │ (if no match)
           ↓
┌──────────────────────────────┐
│ Priority 2: I3PM_TARGET_     │
│ WORKSPACE env var            │
└──────────┬───────────────────┘
           │ (if no match)
           ↓
┌──────────────────────────────┐
│ Priority 3: I3PM_APP_NAME    │
│ Registry Lookup              │
└──────────┬───────────────────┘
           │ (if no match)
           ↓
┌──────────────────────────────┐
│ Priority 4: Class Matching   │
│ (exact → instance →          │
│  normalized)                 │
└──────────┬───────────────────┘
           │ (if no match)
           ↓
       [No Assignment]
      (window stays on current workspace)
```

---

## Data Validation Rules

### Cross-Entity Consistency

1. **Assignment Record ↔ Window Creation Event**:
   - `AssignmentRecord.window_id` MUST match `WindowCreationEvent.container_id`
   - `AssignmentRecord.event_received_at` MUST be ≤ `assignment_completed_at`
   - `AssignmentRecord.latency_ms` MUST equal time difference (with tolerance ±5ms for rounding)

2. **Launch Notification ↔ Assignment Record**:
   - If `AssignmentRecord.launch_correlation = True`, then matching `LaunchNotification` MUST exist
   - If `LaunchNotification.is_matched = True`, then corresponding `AssignmentRecord` MUST exist
   - `LaunchNotification.workspace_number` SHOULD equal `AssignmentRecord.target_workspace` (when used)

3. **PWA Window ↔ Assignment Configuration**:
   - `PWAWindow.app_name` MUST have matching entry in `AssignmentConfiguration.global_assignments`
   - `PWAWindow.preferred_workspace` MUST match `AssignmentRule.workspace_number` for that app
   - `PWAWindow.pwa_id` MUST match `AssignmentRule.expected_class` pattern

### Temporal Consistency

1. **Event Sequencing**:
   - `WindowCreationEvent.timestamp` MUST be ≥ `LaunchNotification.launch_timestamp` (if correlated)
   - `AssignmentRecord.event_received_at` MUST be ≥ `WindowCreationEvent.timestamp`
   - `EventGap.detected_at` MUST be ≥ `gap_end_estimate`

2. **Subscription Health**:
   - If `EventSubscription.is_active = True`, then `last_event_received` MUST be within 60 seconds OR subscription is new
   - If `event_count > 0`, then `last_event_received` MUST be present

### Business Logic Constraints

1. **Workspace Range**:
   - ALL workspace numbers MUST be in range 1-70
   - Target workspace MUST exist before assignment (implicit creation allowed)

2. **Assignment Source Priority**:
   - If `AssignmentRecord.assignment_source = LAUNCH_NOTIFICATION`, then `launch_correlation = True`
   - If `launch_correlation = True`, then `assignment_source` MUST be `LAUNCH_NOTIFICATION` (Priority 0 always wins)

3. **PWA Identifier Uniqueness**:
   - No two `PWAWindow` instances SHOULD have same `pwa_id` with different `display_name`
   - Firefox PWA ULIDs MUST be unique across all registered PWAs

---

## Performance Constraints

### Latency Targets

| Operation | Target Latency | Max Acceptable |
|-----------|---------------|----------------|
| Launch notification to window creation | <500ms | 1000ms |
| Window creation event to assignment start | <50ms | 100ms |
| Assignment command execution | <50ms | 100ms |
| Total end-to-end (launch → assigned) | <600ms | 1000ms |

### Resource Limits

| Resource | Limit | Rationale |
|----------|-------|-----------|
| Assignment record history | 1000 records | Prevent memory growth |
| Event gap history | 100 gaps | Diagnostic purposes only |
| Launch notification TTL | 5 seconds | Prevent stale correlation |
| Event subscription reconnect attempts | 10 attempts | Exponential backoff limit |

---

## Data Storage

### Persistent Storage

**Application Registry** (`~/.config/i3/application-registry.json`):
- Authoritative source for PWA definitions
- Contains `preferred_workspace` field
- Rebuilt on each NixOS/home-manager rebuild

**Workspace Assignments** (`~/.config/sway/workspace-assignments.json`):
- Currently empty (assignments in app registry)
- Reserved for future rule-based assignments
- NOT used by current implementation

### In-Memory Storage

**Daemon State** (Python process memory):
- `EventSubscription` status for each event type
- `LaunchNotification` pending queue (max 50 entries)
- `AssignmentRecord` recent history (max 1000 records)
- `EventGap` detection history (max 100 gaps)

**Event Buffer** (circular buffer):
- Max 500 events
- Includes `WindowCreationEvent` metadata
- Used for diagnostic queries

### Configuration Files

**Sway Configuration** (`~/.config/sway/config`):
- MUST NOT contain `assign` directives (removed in this feature)
- Only contains window rules for floating/fullscreen behavior
- Generated by Nix configuration

---

## Migration Strategy

### Phase 1: Remove Native Assignments

1. **Extract existing assignments** from Sway config
   ```bash
   grep "assign \[" ~/.config/sway/config > /tmp/existing-assignments.txt
   ```

2. **Verify coverage** in application registry
   - All extracted assignments MUST have matching entry in `app-registry-data.nix`
   - Add missing PWAs to registry if needed

3. **Remove from Sway config**
   - Delete `assign` directives from `home-modules/desktop/sway.nix`
   - Rebuild and verify no native assignments remain

### Phase 2: Enhance Daemon Assignment

1. **Add Priority 0 tier** (launch notification workspace)
2. **Add delayed property re-check** (100ms retry)
3. **Add event gap detection**

### Phase 3: Validation

1. **Test PWA assignments**
   - Launch each PWA from walker
   - Verify appears on correct workspace
   - Check assignment latency <1000ms

2. **Verify event delivery**
   - Monitor daemon logs for all window::new events
   - Run `i3pm diagnose events --type=window`
   - Ensure 100% event delivery (no gaps)

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02

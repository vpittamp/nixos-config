# Data Model: Linux System Log Integration

**Feature**: 029-linux-system-log
**Created**: 2025-10-23
**Related**: [spec.md](./spec.md) | [research.md](./research.md)

## Overview

This document defines the data model extensions required to support systemd journal integration and /proc filesystem monitoring in the i3pm event system. The design extends the existing unified `EventEntry` model to accommodate new event sources while maintaining backward compatibility.

## Existing Foundation

### EventEntry (Current Model)

The existing unified event model defined in `models.py:144-209`:

```python
@dataclass
class EventEntry:
    """Unified event log entry for all system events."""

    # Metadata (Always present)
    event_id: int
    event_type: str                     # "window::new", "project::switch", etc.
    timestamp: datetime
    source: str                         # "i3" | "ipc" | "daemon"
    processing_duration_ms: float = 0.0
    error: Optional[str] = None

    # Window events (window::*)
    window_id: Optional[int] = None
    window_class: Optional[str] = None
    window_title: Optional[str] = None
    window_instance: Optional[str] = None
    workspace_name: Optional[str] = None

    # Project events (project::*)
    project_name: Optional[str] = None
    # ... (other event-specific fields)
```

**Current source validation**:
```python
if self.source not in ("i3", "ipc", "daemon"):
    raise ValueError(f"Invalid source: {self.source}")
```

## Model Extensions

### 1. EventEntry Source Enum Extension

**Change**: Extend `source` field validation to include new event sources.

**Before**:
```python
source: str  # "i3" | "ipc" | "daemon"
```

**After**:
```python
source: str  # "i3" | "ipc" | "daemon" | "systemd" | "proc"
```

**Validation Update** (models.py:206):
```python
# Before
if self.source not in ("i3", "ipc", "daemon"):
    raise ValueError(f"Invalid source: {self.source}")

# After
if self.source not in ("i3", "ipc", "daemon", "systemd", "proc"):
    raise ValueError(f"Invalid source: {self.source}")
```

**Rationale**: Preserves existing validation pattern while extending to support new event sources. No schema migration required for existing events.

### 2. New Event-Specific Fields for systemd

Add optional fields to `EventEntry` for systemd journal events:

```python
# ===== SYSTEMD EVENTS (systemd::*) =====
systemd_unit: Optional[str] = None          # Service unit name (e.g., "app-firefox-123.service")
systemd_message: Optional[str] = None       # systemd message (e.g., "Started Firefox Web Browser")
systemd_pid: Optional[int] = None           # Process ID from journal _PID field
journal_cursor: Optional[str] = None        # Journal cursor for event position (for pagination)
```

**Field Mapping**:

| journalctl JSON field | EventEntry field | Notes |
|----------------------|------------------|-------|
| `_SYSTEMD_UNIT` | `systemd_unit` | Service unit name |
| `MESSAGE` | `systemd_message` | Human-readable message |
| `_PID` | `systemd_pid` | Process ID |
| `__CURSOR` | `journal_cursor` | Cursor for pagination |
| `__REALTIME_TIMESTAMP` | `timestamp` | Convert to datetime |

**Example EventEntry** (systemd service start):
```python
EventEntry(
    event_id=1001,
    event_type="systemd::service::start",
    timestamp=datetime.fromisoformat("2025-10-23T07:28:47.123456"),
    source="systemd",
    systemd_unit="app-firefox-12345.service",
    systemd_message="Started Firefox Web Browser",
    systemd_pid=54321,
    journal_cursor="s=abc123...",
    processing_duration_ms=0.5
)
```

### 3. New Event-Specific Fields for /proc Monitoring

Add optional fields to `EventEntry` for process monitoring events:

```python
# ===== PROCESS EVENTS (process::*) =====
process_pid: Optional[int] = None           # Process ID
process_name: Optional[str] = None          # Command name from /proc/{pid}/comm
process_cmdline: Optional[str] = None       # Full command line (sanitized, truncated to 500 chars)
process_parent_pid: Optional[int] = None    # Parent process ID from /proc/{pid}/stat
process_start_time: Optional[int] = None    # Process start time from /proc/{pid}/stat (for correlation)
```

**Field Sources**:

| /proc path | EventEntry field | Notes |
|-----------|------------------|-------|
| `/proc/{pid}/comm` | `process_name` | Command name (max 16 chars from kernel) |
| `/proc/{pid}/cmdline` | `process_cmdline` | Full command line, sanitized, truncated to 500 chars |
| `/proc/{pid}/stat` field 4 | `process_parent_pid` | Parent PID for hierarchy detection |
| `/proc/{pid}/stat` field 22 | `process_start_time` | Process start time in jiffies (for correlation) |

**Example EventEntry** (process detected):
```python
EventEntry(
    event_id=1002,
    event_type="process::start",
    timestamp=datetime.now(),
    source="proc",
    process_pid=54322,
    process_name="rust-analyzer",
    process_cmdline="/usr/bin/rust-analyzer",
    process_parent_pid=54321,  # Parent is VS Code (PID 54321)
    process_start_time=12345678,  # jiffies since boot
    processing_duration_ms=1.2
)
```

### 4. Sensitive Data Sanitization

**Implementation**: Apply sanitization before setting `process_cmdline` field.

**Sanitization Function**:
```python
def sanitize_cmdline(cmdline: str, max_length: int = 500) -> str:
    """Sanitize command line by redacting sensitive values.

    Args:
        cmdline: Raw command line from /proc/{pid}/cmdline
        max_length: Maximum length before truncation

    Returns:
        Sanitized and truncated command line
    """
    # Patterns to redact (from research.md)
    patterns = [
        r'(password|passwd|pwd)=\S+',
        r'(token|auth|key|secret)=\S+',
        r'(api[_-]?key)=\S+',
        r'--password\s+\S+',
        r'-p\s+\S+',  # Common -p password flag
    ]

    sanitized = cmdline
    for pattern in patterns:
        sanitized = re.sub(pattern, r'\1=***', sanitized, flags=re.IGNORECASE)

    # Truncate to max length
    if len(sanitized) > max_length:
        sanitized = sanitized[:max_length] + "..."

    return sanitized
```

**Example**:
```python
# Before
cmdline = "mysql -u admin -p SuperSecret123 -h localhost"

# After sanitization
cmdline = "mysql -u admin -p *** -h localhost"
```

## New Entity: EventCorrelation

**Purpose**: Represent detected relationships between GUI windows and spawned processes.

**Definition**:
```python
@dataclass
class EventCorrelation:
    """Correlation between a parent event and related child events.

    Used to show relationships like:
    - GUI window creation → backend process spawns
    - Process spawn → subprocess spawns
    """

    # Correlation metadata
    correlation_id: int                     # Unique correlation ID
    created_at: datetime                    # When correlation was detected
    confidence_score: float                 # 0.0-1.0 confidence in correlation accuracy

    # Event relationships
    parent_event_id: int                    # Parent event (e.g., window::new)
    child_event_ids: List[int]              # Child events (e.g., process::start[])
    correlation_type: str                   # "window_to_process" | "process_to_subprocess"

    # Timing information
    time_delta_ms: float                    # Time between parent and first child event
    detection_window_ms: float = 5000.0     # Time window used for detection (default 5s)

    # Correlation factors (for debugging)
    timing_factor: float = 0.0              # 0.0-1.0 score for timing proximity
    hierarchy_factor: float = 0.0           # 0.0-1.0 score for process hierarchy match
    name_similarity: float = 0.0            # 0.0-1.0 score for name similarity
    workspace_match: bool = False           # Whether events happened in same workspace

    def __post_init__(self) -> None:
        """Validate correlation."""
        if not 0.0 <= self.confidence_score <= 1.0:
            raise ValueError(f"confidence_score must be 0.0-1.0, got {self.confidence_score}")
        if self.time_delta_ms < 0:
            raise ValueError(f"time_delta_ms cannot be negative: {self.time_delta_ms}")
        if self.correlation_type not in ("window_to_process", "process_to_subprocess"):
            raise ValueError(f"Invalid correlation_type: {self.correlation_type}")
        if not self.child_event_ids:
            raise ValueError("child_event_ids cannot be empty")
```

**Confidence Scoring Algorithm** (from research.md):

```python
def calculate_confidence(
    timing_factor: float,      # 0.0-1.0 based on time proximity
    hierarchy_factor: float,   # 0.0-1.0 based on parent_pid match
    name_similarity: float,    # 0.0-1.0 based on name similarity
    workspace_match: bool      # Whether in same workspace
) -> float:
    """Calculate overall confidence score for correlation.

    Weights from research.md:
    - Timing: 40%
    - Hierarchy: 30%
    - Name similarity: 20%
    - Workspace: 10%

    Returns:
        Confidence score 0.0-1.0
    """
    score = (
        timing_factor * 0.40 +
        hierarchy_factor * 0.30 +
        name_similarity * 0.20 +
        (1.0 if workspace_match else 0.0) * 0.10
    )
    return min(1.0, max(0.0, score))
```

**Example Correlation**:
```python
# VS Code window opens → rust-analyzer process spawns

EventCorrelation(
    correlation_id=501,
    created_at=datetime.now(),
    confidence_score=0.85,

    parent_event_id=1000,  # window::new for Code
    child_event_ids=[1002, 1003],  # rust-analyzer, typescript-language-server
    correlation_type="window_to_process",

    time_delta_ms=1200.0,  # 1.2 seconds between window and first process

    # Correlation factors
    timing_factor=0.92,      # Within 5 seconds (high score)
    hierarchy_factor=1.0,    # Parent PID matches (perfect score)
    name_similarity=0.65,    # "Code" vs "rust-analyzer" (moderate similarity)
    workspace_match=True     # Both in workspace "1:term"
)
```

## Event Type Taxonomy

### New Event Types

**systemd Events** (`source="systemd"`):
```
systemd::service::start   - Service started
systemd::service::stop    - Service stopped
systemd::unit::failed     - Unit failed to start
```

**Process Events** (`source="proc"`):
```
process::start            - Process detected in /proc
process::spawn            - Process spawned (parent-child detected)
```

**Correlation Events** (generated from analysis):
```
correlation::detected     - New correlation created
```

### Event Type Naming Convention

Format: `{source}::{category}::{action}`

Examples:
- `i3::window::new` (existing)
- `systemd::service::start` (new)
- `proc::process::start` (new)

## Database Schema Extensions

### SQLite event_log Table

**Current Schema**:
```sql
CREATE TABLE event_log (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    source TEXT NOT NULL CHECK(source IN ('i3', 'ipc', 'daemon')),
    -- ... existing fields
);
```

**Extended Schema**:
```sql
-- Alter table to extend source check constraint
ALTER TABLE event_log DROP CONSTRAINT IF EXISTS check_source;

ALTER TABLE event_log ADD CONSTRAINT check_source
    CHECK(source IN ('i3', 'ipc', 'daemon', 'systemd', 'proc'));

-- Add new systemd fields
ALTER TABLE event_log ADD COLUMN systemd_unit TEXT;
ALTER TABLE event_log ADD COLUMN systemd_message TEXT;
ALTER TABLE event_log ADD COLUMN systemd_pid INTEGER;
ALTER TABLE event_log ADD COLUMN journal_cursor TEXT;

-- Add new process fields
ALTER TABLE event_log ADD COLUMN process_pid INTEGER;
ALTER TABLE event_log ADD COLUMN process_name TEXT;
ALTER TABLE event_log ADD COLUMN process_cmdline TEXT;
ALTER TABLE event_log ADD COLUMN process_parent_pid INTEGER;
ALTER TABLE event_log ADD COLUMN process_start_time INTEGER;

-- Indexes for performance
CREATE INDEX idx_event_log_source ON event_log(source);
CREATE INDEX idx_event_log_systemd_unit ON event_log(systemd_unit);
CREATE INDEX idx_event_log_process_pid ON event_log(process_pid);
CREATE INDEX idx_event_log_process_parent_pid ON event_log(process_parent_pid);
```

**Migration Strategy**:
- SQLite `ALTER TABLE` is additive only (no breaking changes)
- Existing events have NULL for new fields (valid)
- No data migration required
- Check constraint update via DROP + ADD

### New Table: event_correlations

```sql
CREATE TABLE event_correlations (
    correlation_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    confidence_score REAL NOT NULL CHECK(confidence_score >= 0.0 AND confidence_score <= 1.0),

    parent_event_id INTEGER NOT NULL,
    correlation_type TEXT NOT NULL CHECK(correlation_type IN ('window_to_process', 'process_to_subprocess')),

    time_delta_ms REAL NOT NULL,
    detection_window_ms REAL DEFAULT 5000.0,

    timing_factor REAL,
    hierarchy_factor REAL,
    name_similarity REAL,
    workspace_match INTEGER DEFAULT 0,  -- SQLite boolean

    FOREIGN KEY (parent_event_id) REFERENCES event_log(event_id) ON DELETE CASCADE
);

CREATE TABLE correlation_children (
    correlation_id INTEGER NOT NULL,
    child_event_id INTEGER NOT NULL,
    sequence_order INTEGER NOT NULL,  -- Order in which child was spawned

    PRIMARY KEY (correlation_id, child_event_id),
    FOREIGN KEY (correlation_id) REFERENCES event_correlations(correlation_id) ON DELETE CASCADE,
    FOREIGN KEY (child_event_id) REFERENCES event_log(event_id) ON DELETE CASCADE
);

-- Indexes
CREATE INDEX idx_correlations_parent ON event_correlations(parent_event_id);
CREATE INDEX idx_correlations_confidence ON event_correlations(confidence_score);
CREATE INDEX idx_correlation_children_child ON correlation_children(child_event_id);
```

## Zod Schema Extensions (Deno CLI)

### TypeScript EventNotification Interface

**Current** (validation.ts):
```typescript
export const EventNotificationSchema = z.object({
  event_id: z.number().int().nonnegative(),
  event_type: z.string(),
  source: z.enum(["i3", "ipc", "daemon"]),
  timestamp: z.string(),
  // ... existing fields
});
```

**Extended**:
```typescript
export const EventNotificationSchema = z.object({
  event_id: z.number().int().nonnegative(),
  event_type: z.string(),
  source: z.enum(["i3", "ipc", "daemon", "systemd", "proc"]),
  timestamp: z.string(),

  // Existing fields
  window_id: z.number().int().positive().nullable().optional(),
  window_class: z.string().nullable().optional(),
  // ... other existing fields

  // New systemd fields
  systemd_unit: z.string().nullable().optional(),
  systemd_message: z.string().nullable().optional(),
  systemd_pid: z.number().int().positive().nullable().optional(),
  journal_cursor: z.string().nullable().optional(),

  // New process fields
  process_pid: z.number().int().positive().nullable().optional(),
  process_name: z.string().nullable().optional(),
  process_cmdline: z.string().nullable().optional(),
  process_parent_pid: z.number().int().positive().nullable().optional(),
  process_start_time: z.number().int().nonnegative().nullable().optional(),
});

export type EventNotification = z.infer<typeof EventNotificationSchema>;
```

### EventCorrelation Schema (New)

```typescript
export const EventCorrelationSchema = z.object({
  correlation_id: z.number().int().nonnegative(),
  created_at: z.string(),
  confidence_score: z.number().min(0.0).max(1.0),

  parent_event_id: z.number().int().nonnegative(),
  child_event_ids: z.array(z.number().int().nonnegative()).min(1),
  correlation_type: z.enum(["window_to_process", "process_to_subprocess"]),

  time_delta_ms: z.number().nonnegative(),
  detection_window_ms: z.number().nonnegative().default(5000.0),

  timing_factor: z.number().min(0.0).max(1.0).optional(),
  hierarchy_factor: z.number().min(0.0).max(1.0).optional(),
  name_similarity: z.number().min(0.0).max(1.0).optional(),
  workspace_match: z.boolean().optional(),
});

export type EventCorrelation = z.infer<typeof EventCorrelationSchema>;
```

## Validation Rules

### EventEntry Validation

**Extended `__post_init__` validation**:

```python
def __post_init__(self) -> None:
    """Validate event entry."""
    # Existing validation
    if self.event_id < 0:
        raise ValueError(f"Invalid event_id: {self.event_id}")
    if not self.event_type:
        raise ValueError("event_type cannot be empty")
    if self.source not in ("i3", "ipc", "daemon", "systemd", "proc"):
        raise ValueError(f"Invalid source: {self.source}")
    if self.processing_duration_ms < 0:
        raise ValueError(f"Invalid processing_duration_ms: {self.processing_duration_ms}")

    # New validation: systemd events must have systemd_unit
    if self.source == "systemd" and not self.systemd_unit:
        raise ValueError("systemd events must have systemd_unit")

    # New validation: proc events must have process_pid and process_name
    if self.source == "proc":
        if not self.process_pid or not self.process_name:
            raise ValueError("proc events must have process_pid and process_name")

    # New validation: process_cmdline must be sanitized (no sensitive patterns)
    if self.process_cmdline:
        sensitive_patterns = ["password=", "token=", "key="]
        for pattern in sensitive_patterns:
            if pattern in self.process_cmdline.lower() and "***" not in self.process_cmdline:
                raise ValueError(f"process_cmdline contains unsanitized sensitive data: {pattern}")
```

### Data Integrity Rules

**Event Source Consistency**:
- Events with `source="systemd"` MUST have at least `systemd_unit` populated
- Events with `source="proc"` MUST have `process_pid` and `process_name` populated
- Events with `source="i3"` MUST NOT have systemd/proc fields populated (use None)

**Correlation Validity**:
- `parent_event_id` MUST reference an existing event
- `child_event_ids` MUST all reference existing events
- `time_delta_ms` MUST be >= 0
- `confidence_score` MUST be 0.0-1.0

## Summary

This data model extends the existing unified event system to support:
- ✅ systemd journal events via 4 new optional fields
- ✅ /proc process monitoring via 5 new optional fields
- ✅ Event correlation via new `EventCorrelation` entity
- ✅ Backward compatibility (existing events unchanged)
- ✅ Validation rules for data integrity
- ✅ Database schema extensions with proper indexing

All extensions follow existing patterns (optional fields, enum extension, Pydantic validation) to maintain architecture consistency.

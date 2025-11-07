# Data Model: Sway Tree Diff Monitor

**Feature Branch**: `052-sway-tree-diff-monitor`
**Date**: 2025-11-07
**Status**: Design Complete

## Overview

This document defines the data models for the Sway tree diff monitor, based on research findings from `research.md`. The models support high-performance tree diffing (<10ms), event correlation (500ms windows), and bounded memory usage (<25MB for 500 events).

---

## Core Entities

### 1. TreeSnapshot

Represents the complete Sway tree state at a specific point in time, including enriched context data.

```python
from dataclasses import dataclass, field
from typing import Dict, Optional, List
from datetime import datetime

@dataclass
class TreeSnapshot:
    """
    Complete Sway tree state at a point in time.

    Memory: ~3-5 KB per snapshot
    - tree_data: ~2.8 KB (50 windows, 5 workspaces)
    - enriched_data: ~0.1 KB
    - metadata: ~0.05 KB
    """
    snapshot_id: int
    """Unique monotonic ID for this snapshot"""

    timestamp_ms: int
    """Unix timestamp in milliseconds when snapshot was captured"""

    tree_data: Dict
    """Raw Sway tree JSON from i3.get_tree()"""

    enriched_data: Dict[int, WindowContext]
    """
    Window ID → enriched context mapping.
    Includes I3PM_* environment variables, project associations.
    """

    root_hash: str
    """xxHash of entire tree (for fast equality checks)"""

    event_source: str
    """Sway event type that triggered this snapshot (e.g., 'window::new', 'workspace::focus')"""

    captured_at: datetime = field(default_factory=datetime.now)
    """Human-readable timestamp"""

    def __post_init__(self):
        """Validate tree_data structure"""
        if not isinstance(self.tree_data, dict):
            raise ValueError("tree_data must be a dictionary")
        if 'type' not in self.tree_data:
            raise ValueError("tree_data must contain 'type' field")
```

#### WindowContext (Sub-model)

Enriched context for a single window, extracted from environment variables and window marks.

```python
@dataclass
class WindowContext:
    """
    Enriched context for a window, not native to Sway.

    Extracted from:
    - /proc/<pid>/environ (I3PM_* variables)
    - Window marks (project:*, app:*)
    - Launch context tracking
    """
    window_id: int
    """Sway window ID"""

    pid: Optional[int] = None
    """Process ID (from Sway tree)"""

    # Environment variables
    i3pm_app_id: Optional[str] = None
    """I3PM_APP_ID from process environment"""

    i3pm_app_name: Optional[str] = None
    """I3PM_APP_NAME from process environment"""

    i3pm_project_name: Optional[str] = None
    """I3PM_PROJECT_NAME from process environment"""

    i3pm_scope: Optional[str] = None
    """I3PM_SCOPE (scoped/global)"""

    # Window marks
    project_marks: List[str] = field(default_factory=list)
    """Project marks (e.g., ['project:nixos'])"""

    app_marks: List[str] = field(default_factory=list)
    """Application marks (e.g., ['app:vscode'])"""

    # Launch context
    launch_timestamp_ms: Optional[int] = None
    """When this window was launched (if tracked)"""

    launch_action: Optional[str] = None
    """User action that launched this window (if known)"""
```

---

### 2. TreeDiff

Represents the differences between two tree snapshots, optimized for memory efficiency.

```python
from enum import Enum
from typing import Any, List

class ChangeType(Enum):
    """Type of change detected in tree diff"""
    ADDED = "added"
    REMOVED = "removed"
    MODIFIED = "modified"

@dataclass
class FieldChange:
    """
    Single field-level change within a node.

    Example: Window geometry changed from {x: 100, y: 200} to {x: 150, y: 200}
    """
    field_path: str
    """JSONPath to changed field (e.g., 'rect.x', 'focused')"""

    old_value: Any
    """Previous value (None for ADDED changes)"""

    new_value: Any
    """New value (None for REMOVED changes)"""

    change_type: ChangeType
    """Type of change"""

    significance_score: float = 1.0
    """
    Significance of this change (0.0 to 1.0).

    Used for filtering noise:
    - 1.0: High significance (window added/removed, workspace change)
    - 0.5: Medium significance (focus change, window move)
    - 0.1: Low significance (minor geometry adjustment <10px)
    """

@dataclass
class NodeChange:
    """
    Change to a single node in the tree (window, workspace, output).

    Grouped by node for hierarchical display.
    """
    node_id: str
    """Unique node identifier (window ID, workspace name, output name)"""

    node_type: str
    """Type of node ('con', 'workspace', 'output', 'floating_con')"""

    change_type: ChangeType
    """Overall change type for this node"""

    field_changes: List[FieldChange]
    """List of field-level changes within this node"""

    node_path: str
    """
    Tree path to this node (e.g., 'outputs[0].workspaces[2].nodes[5]')
    For human-readable display in diffs.
    """

@dataclass
class TreeDiff:
    """
    Differences between two tree snapshots.

    Memory: ~0.2-0.5 KB per diff (only stores changes, not full trees)
    """
    diff_id: int
    """Unique monotonic ID for this diff"""

    before_snapshot_id: int
    """ID of 'before' snapshot"""

    after_snapshot_id: int
    """ID of 'after' snapshot"""

    node_changes: List[NodeChange]
    """List of all changed nodes"""

    computation_time_ms: float
    """How long diff computation took (for performance monitoring)"""

    total_changes: int = field(init=False)
    """Total number of field-level changes"""

    significance_score: float = field(init=False)
    """
    Overall significance (0.0 to 1.0).
    Max of all field significance scores.
    """

    def __post_init__(self):
        """Compute derived fields"""
        self.total_changes = sum(len(nc.field_changes) for nc in self.node_changes)

        if self.node_changes:
            self.significance_score = max(
                fc.significance_score
                for nc in self.node_changes
                for fc in nc.field_changes
            )
        else:
            self.significance_score = 0.0

    def get_changes_by_type(self, change_type: ChangeType) -> List[NodeChange]:
        """Filter node changes by type"""
        return [nc for nc in self.node_changes if nc.change_type == change_type]

    def has_significant_changes(self, threshold: float = 0.5) -> bool:
        """Check if diff contains significant changes (above threshold)"""
        return self.significance_score >= threshold
```

---

### 3. UserAction

Represents a user input event (keypress, mouse click, IPC command) that may trigger tree changes.

```python
from enum import Enum

class ActionType(Enum):
    """Type of user action"""
    KEYPRESS = "keypress"
    MOUSE_CLICK = "mouse_click"
    IPC_COMMAND = "ipc_command"
    BINDING = "binding"  # Sway key binding event

@dataclass
class UserAction:
    """
    User input event that may cause tree changes.

    Captured from:
    - Sway key binding events (binding type)
    - Sway IPC commands
    - Mouse events (if tracked)
    """
    action_id: int
    """Unique monotonic ID"""

    timestamp_ms: int
    """Unix timestamp in milliseconds"""

    action_type: ActionType
    """Type of action"""

    # Key binding details
    binding_symbol: Optional[str] = None
    """
    Key binding symbol (e.g., 'Mod4+2', 'Mod4+Shift+q')
    From Sway binding event.
    """

    binding_command: Optional[str] = None
    """
    Sway command executed by binding (e.g., 'workspace number 2', 'kill')
    """

    # IPC command details
    ipc_command: Optional[str] = None
    """Raw IPC command if action_type == IPC_COMMAND"""

    # Mouse details
    mouse_button: Optional[int] = None
    """Mouse button number (1=left, 2=middle, 3=right) if action_type == MOUSE_CLICK"""

    mouse_x: Optional[int] = None
    """Mouse X coordinate"""

    mouse_y: Optional[int] = None
    """Mouse Y coordinate"""

    # Metadata
    source: str = "sway"
    """
    Source of action event:
    - 'sway': From Sway IPC binding events
    - 'vnc': From VNC input tracking
    - 'manual': Manually logged action
    """

    def get_display_name(self) -> str:
        """Human-readable action description"""
        if self.action_type == ActionType.KEYPRESS and self.binding_symbol:
            return f"Key: {self.binding_symbol}"
        elif self.action_type == ActionType.BINDING:
            return f"Binding: {self.binding_symbol} → {self.binding_command}"
        elif self.action_type == ActionType.IPC_COMMAND:
            return f"Command: {self.ipc_command}"
        elif self.action_type == ActionType.MOUSE_CLICK:
            return f"Click: Button {self.mouse_button} at ({self.mouse_x}, {self.mouse_y})"
        else:
            return f"{self.action_type.value}"
```

---

### 4. EventCorrelation

Links user actions to tree changes with confidence scoring.

```python
@dataclass
class EventCorrelation:
    """
    Correlation between a user action and a tree change event.

    Represents causation hypothesis: "This action likely caused this tree change"
    """
    correlation_id: int
    """Unique ID"""

    user_action: UserAction
    """The user action (potential cause)"""

    tree_event_id: int
    """ID of the tree event (effect)"""

    time_delta_ms: int
    """Time between action and tree change (ms)"""

    confidence_score: float
    """
    Confidence that this action caused the tree change (0.0 to 1.0).

    Calculated using multi-factor model:
    - Temporal proximity (40% weight): Closer in time = higher confidence
    - Semantic matching (30% weight): Action type matches change type
    - Exclusivity (20% weight): Fewer competing actions = higher confidence
    - Cascade position (10% weight): Earlier in cascade = higher confidence
    """

    confidence_factors: Dict[str, float]
    """
    Breakdown of confidence score components:
    - 'temporal': 0-100 (time-based)
    - 'semantic': 0-100 (type matching)
    - 'exclusivity': 0-100 (competition)
    - 'cascade': 0-100 (cascade position)
    """

    cascade_level: int = 0
    """
    Position in cascade chain:
    - 0: Direct effect (primary change)
    - 1: Secondary effect (triggered by primary)
    - 2: Tertiary effect, etc.
    """

    def get_confidence_label(self) -> str:
        """Human-readable confidence interpretation"""
        if self.confidence_score >= 0.90:
            return "Caused by"
        elif self.confidence_score >= 0.70:
            return "Likely caused by"
        elif self.confidence_score >= 0.50:
            return "Possibly caused by"
        else:
            return "Unknown trigger"
```

---

### 5. TreeEvent

Top-level event record combining snapshot, diff, and correlation.

```python
@dataclass
class TreeEvent:
    """
    Complete event record: snapshot + diff + correlation.

    This is the primary entity stored in the circular buffer.

    Memory: ~5 KB per event
    - TreeSnapshot: ~3-5 KB
    - TreeDiff: ~0.2-0.5 KB
    - Metadata: ~0.2 KB
    """
    event_id: int
    """Unique monotonic ID (sequence ID)"""

    timestamp_ms: int
    """Unix timestamp in milliseconds"""

    event_type: str
    """
    Sway event type that triggered this:
    - 'window::new', 'window::close', 'window::focus', 'window::move'
    - 'workspace::focus', 'workspace::init', 'workspace::empty'
    - 'output::unplug' (rare)
    """

    snapshot: TreeSnapshot
    """After-state snapshot"""

    diff: TreeDiff
    """Changes from previous snapshot"""

    correlations: List[EventCorrelation]
    """
    User actions correlated with this tree change.

    Usually 0-2 correlations:
    - 0: Automatic/system-initiated change
    - 1: Single clear action
    - 2+: Ambiguous (multiple possible causes)
    """

    # Metadata
    sway_change: str
    """
    Sway event 'change' field value:
    - 'new', 'close', 'focus', 'move', 'floating', 'fullscreen', etc.
    """

    container_id: Optional[int] = None
    """Sway container ID from event (window ID or workspace ID)"""

    def get_best_correlation(self) -> Optional[EventCorrelation]:
        """Get highest-confidence correlation (or None if no correlations)"""
        if not self.correlations:
            return None
        return max(self.correlations, key=lambda c: c.confidence_score)

    def is_user_initiated(self, threshold: float = 0.70) -> bool:
        """Check if event was likely user-initiated (confidence >= threshold)"""
        best = self.get_best_correlation()
        return best is not None and best.confidence_score >= threshold
```

---

### 6. HashCache

Merkle tree hash cache for incremental diffing optimization.

```python
from dataclasses import dataclass
from typing import Dict
import time

@dataclass
class NodeFingerprint:
    """Cached hash for a single tree node"""
    node_id: str
    """Unique node identifier"""

    content_hash: str
    """xxHash of node fields (excluding volatile fields)"""

    subtree_hash: str
    """Merkle hash including all descendants"""

    timestamp: float
    """When this fingerprint was computed (for TTL eviction)"""

class HashCache:
    """
    Maintains node hashes between snapshots for fast comparison.

    Memory: ~50 bytes per node
    - 200 windows × 50 bytes = 10 KB
    - ~30 containers × 50 bytes = 1.5 KB
    Total: ~12 KB (negligible)

    TTL: 60 seconds (prevent stale hashes)
    """
    def __init__(self, max_age_seconds: float = 60.0):
        self.fingerprints: Dict[str, NodeFingerprint] = {}
        self.max_age = max_age_seconds

    def get_subtree_hash(self, node_id: str) -> Optional[str]:
        """Retrieve cached subtree hash for fast comparison"""
        fp = self.fingerprints.get(node_id)
        if fp and (time.time() - fp.timestamp) < self.max_age:
            return fp.subtree_hash
        return None

    def update(self, node_id: str, content_hash: str, subtree_hash: str):
        """Update cache with new hashes"""
        self.fingerprints[node_id] = NodeFingerprint(
            node_id=node_id,
            content_hash=content_hash,
            subtree_hash=subtree_hash,
            timestamp=time.time()
        )

    def cleanup_expired(self):
        """Remove expired fingerprints (called periodically)"""
        now = time.time()
        expired = [
            node_id for node_id, fp in self.fingerprints.items()
            if (now - fp.timestamp) >= self.max_age
        ]
        for node_id in expired:
            del self.fingerprints[node_id]
```

---

### 7. FilterCriteria

Defines rules for filtering event stream (User Story 5).

```python
from dataclasses import dataclass
from typing import Optional, List, Pattern
import re

@dataclass
class FilterCriteria:
    """
    Rules for filtering event stream.

    All filters are AND-combined (must all match).
    """
    # Event type filtering
    event_types: Optional[List[str]] = None
    """
    Include only these event types (e.g., ['window::new', 'window::close'])
    If None, include all types.
    """

    exclude_event_types: Optional[List[str]] = None
    """Exclude these event types"""

    # Time range
    since_ms: Optional[int] = None
    """Include only events after this timestamp (Unix ms)"""

    until_ms: Optional[int] = None
    """Include only events before this timestamp (Unix ms)"""

    # Significance threshold
    min_significance: Optional[float] = None
    """
    Minimum significance score (0.0 to 1.0).
    Filter out low-significance changes (e.g., minor geometry adjustments).
    """

    # Tree path filtering
    tree_path_pattern: Optional[Pattern] = None
    """
    Regex pattern for tree path (e.g., r'outputs\[0\]\.workspaces\[2\].*')
    Only show changes under matching paths.
    """

    # Window filtering
    window_class: Optional[str] = None
    """Filter by window class (e.g., 'Firefox', 'Code')"""

    window_title_pattern: Optional[Pattern] = None
    """Regex pattern for window title"""

    project_name: Optional[str] = None
    """Filter by I3PM project name"""

    # User action filtering
    user_initiated_only: bool = False
    """Only show events with user action correlation (confidence >= 70%)"""

    def matches(self, event: TreeEvent) -> bool:
        """Check if event matches all filter criteria"""
        # Event type filtering
        if self.event_types and event.event_type not in self.event_types:
            return False
        if self.exclude_event_types and event.event_type in self.exclude_event_types:
            return False

        # Time range
        if self.since_ms and event.timestamp_ms < self.since_ms:
            return False
        if self.until_ms and event.timestamp_ms > self.until_ms:
            return False

        # Significance
        if self.min_significance and event.diff.significance_score < self.min_significance:
            return False

        # User initiation
        if self.user_initiated_only and not event.is_user_initiated():
            return False

        # Window filtering (requires scanning diff for window changes)
        if self.window_class or self.window_title_pattern or self.project_name:
            if not self._matches_window_criteria(event):
                return False

        return True

    def _matches_window_criteria(self, event: TreeEvent) -> bool:
        """Check window-specific filter criteria"""
        # Implementation would scan event.diff.node_changes for window nodes
        # and check window properties against filters
        # (Details omitted for brevity)
        return True
```

---

## Relationships

```
TreeEvent (1) ─── (1) TreeSnapshot
          │
          └─── (1) TreeDiff
          │
          └─── (0..N) EventCorrelation ─── (1) UserAction

TreeSnapshot (1) ─── (0..N) WindowContext

TreeDiff (1) ─── (0..N) NodeChange ─── (1..N) FieldChange
```

---

## Memory Budget Analysis

### Per-Event Breakdown

```
TreeEvent:                      ~5 KB
├─ TreeSnapshot:               ~3-5 KB
│  ├─ tree_data (JSON):        ~2.8 KB (50 windows)
│  ├─ enriched_data:           ~0.1 KB (10 WindowContext × 10 bytes)
│  └─ metadata:                ~0.05 KB
├─ TreeDiff:                   ~0.2-0.5 KB
│  └─ node_changes:            ~0.2 KB (avg 5 NodeChange × 40 bytes)
└─ correlations:               ~0.1 KB (avg 1 EventCorrelation)
```

### Circular Buffer (500 Events)

```
500 events × 5 KB = 2.5 MB

Hash cache: ~12 KB (200 windows)
Correlation tracker: ~25 KB (50 pending actions)

Total: ~2.54 MB (10x under 25MB target)
```

### Scaling Analysis

| Windows | Tree Size | Event Size | 500-Event Buffer | Under Budget? |
|---------|-----------|------------|------------------|---------------|
| 50 | ~2.8 KB | ~5 KB | ~2.5 MB | ✅ Yes (10x margin) |
| 100 | ~5.5 KB | ~8 KB | ~4 MB | ✅ Yes (6x margin) |
| 200 | ~11 KB | ~14 KB | ~7 MB | ✅ Yes (3.5x margin) |

---

## Validation Rules

### TreeSnapshot
- `tree_data` must be valid Sway tree JSON with 'type' field
- `root_hash` must be 16-character hex string (xxHash64)
- `timestamp_ms` must be positive integer

### TreeDiff
- `before_snapshot_id` < `after_snapshot_id`
- `total_changes` must equal sum of all field changes
- `computation_time_ms` should be < 15ms (warn if higher)

### EventCorrelation
- `confidence_score` must be in range [0.0, 1.0]
- `time_delta_ms` must be >= 0
- `cascade_level` must be >= 0

### TreeEvent
- `event_type` must match Sway event pattern (window::*, workspace::*, output::*)
- If `correlations` is non-empty, highest confidence should be >= 0.5

---

## Pydantic Models (Type-Safe)

The above dataclasses should be implemented as Pydantic models for runtime validation:

```python
from pydantic import BaseModel, Field, field_validator

class TreeSnapshotModel(BaseModel):
    """Pydantic version with validation"""
    snapshot_id: int = Field(ge=0)
    timestamp_ms: int = Field(ge=0)
    tree_data: dict
    enriched_data: dict[int, WindowContext]
    root_hash: str = Field(pattern=r'^[0-9a-f]{16}$')
    event_source: str
    captured_at: datetime

    @field_validator('tree_data')
    @classmethod
    def validate_tree_structure(cls, v):
        if 'type' not in v:
            raise ValueError("tree_data must contain 'type' field")
        return v

# Similar Pydantic models for other entities...
```

---

## Conclusion

This data model provides:

1. ✅ **Memory efficiency**: ~2.5 MB for 500 events (10x under budget)
2. ✅ **Performance**: Optimized for <10ms diff computation via HashCache
3. ✅ **Type safety**: Pydantic models with validation
4. ✅ **Extensibility**: Clear separation of concerns (snapshot, diff, correlation)
5. ✅ **Rich context**: WindowContext enrichment with I3PM data
6. ✅ **Filtering**: FilterCriteria supports all User Story 5 requirements

**Next step**: Define API contracts (CLI commands, IPC endpoints) in `contracts/` directory.

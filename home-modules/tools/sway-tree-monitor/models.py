"""Data models for Sway Tree Diff Monitor

This module defines all Pydantic models for the tree diff monitor,
including snapshots, diffs, events, correlations, and filtering criteria.

Based on spec: /etc/nixos/specs/064-sway-tree-diff-monitor/data-model.md
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional, Pattern
import re

from pydantic import BaseModel, Field, field_validator


# =============================================================================
# Enumerations
# =============================================================================

class ChangeType(Enum):
    """Type of change detected in tree diff"""
    ADDED = "added"
    REMOVED = "removed"
    MODIFIED = "modified"


class ActionType(Enum):
    """Type of user action"""
    KEYPRESS = "keypress"
    MOUSE_CLICK = "mouse_click"
    IPC_COMMAND = "ipc_command"
    BINDING = "binding"  # Sway key binding event


# =============================================================================
# Window Context (Enrichment)
# =============================================================================

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


# =============================================================================
# Tree Snapshot
# =============================================================================

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

    tree_data: Dict[str, Any]
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


# =============================================================================
# Tree Diff
# =============================================================================

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


# =============================================================================
# User Actions
# =============================================================================

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


# =============================================================================
# Event Correlation
# =============================================================================

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


# =============================================================================
# Tree Event
# =============================================================================

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


# =============================================================================
# Hash Cache
# =============================================================================

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


# =============================================================================
# Filter Criteria
# =============================================================================

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
        # Scan event.diff.node_changes for window nodes
        # and check window properties against filters
        # For now, simplified implementation
        # TODO: Implement detailed window matching based on tree data
        return True

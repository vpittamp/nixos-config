"""Output event detection service for Feature 102.

This service distinguishes between output::connected, output::disconnected,
and output::profile_changed events by caching output state and computing
diffs when Sway output events occur.

Feature 102: User Story 5 - Output Event Distinction
"""

import asyncio
import logging
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from i3ipc import aio

logger = logging.getLogger(__name__)


class OutputEventType(str, Enum):
    """Specific output event types."""
    CONNECTED = "connected"
    DISCONNECTED = "disconnected"
    PROFILE_CHANGED = "profile_changed"
    UNSPECIFIED = "unspecified"


@dataclass
class OutputState:
    """Snapshot of a single output's state.

    Feature 102: Used for state diffing to detect change type.
    """
    name: str
    active: bool
    dpms: bool = True  # Display power management state
    current_mode: Optional[str] = None  # e.g., "2560x1600"
    scale: float = 1.0
    # Additional properties for profile detection
    transform: Optional[str] = None  # none, 90, 180, 270
    position_x: int = 0
    position_y: int = 0

    @classmethod
    def from_i3_output(cls, output: Any) -> "OutputState":
        """Create OutputState from i3ipc output object.

        Args:
            output: i3ipc Output object from get_outputs()

        Returns:
            OutputState snapshot
        """
        # Extract current mode string
        mode_str = None
        if hasattr(output, 'current_mode') and output.current_mode:
            mode = output.current_mode
            mode_str = f"{mode.width}x{mode.height}"
        elif hasattr(output, 'rect') and output.rect:
            mode_str = f"{output.rect.width}x{output.rect.height}"

        return cls(
            name=output.name,
            active=getattr(output, 'active', False),
            dpms=getattr(output, 'dpms', True),
            current_mode=mode_str,
            scale=getattr(output, 'scale', 1.0),
            transform=getattr(output, 'transform', None),
            position_x=output.rect.x if hasattr(output, 'rect') and output.rect else 0,
            position_y=output.rect.y if hasattr(output, 'rect') and output.rect else 0,
        )

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "name": self.name,
            "active": self.active,
            "dpms": self.dpms,
            "current_mode": self.current_mode,
            "scale": self.scale,
            "transform": self.transform,
            "position_x": self.position_x,
            "position_y": self.position_y,
        }


@dataclass
class OutputDiff:
    """Result of comparing old and new output states.

    Feature 102: Contains the detected change type and changed properties.
    """
    output_name: str
    event_type: OutputEventType
    old_state: Optional[OutputState] = None
    new_state: Optional[OutputState] = None
    changed_properties: Dict[str, Dict[str, Any]] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for event logging."""
        return {
            "output_name": self.output_name,
            "event_type": self.event_type.value,
            "old_state": self.old_state.to_dict() if self.old_state else None,
            "new_state": self.new_state.to_dict() if self.new_state else None,
            "changed_properties": self.changed_properties,
        }


class OutputEventService:
    """Service for detecting specific output event types.

    Feature 102: Caches output state and computes diffs to distinguish
    between connected/disconnected/profile_changed events.
    """

    def __init__(self) -> None:
        """Initialize the output event service."""
        self._cached_outputs: Dict[str, OutputState] = {}
        self._current_profile: Optional[str] = None
        self._initialized: bool = False
        self._lock = asyncio.Lock()

    async def initialize(self, conn: "aio.Connection") -> None:
        """Initialize by caching current output state.

        Args:
            conn: i3ipc async connection

        Should be called on daemon startup.
        """
        async with self._lock:
            try:
                outputs = await conn.get_outputs()
                self._cached_outputs = {
                    o.name: OutputState.from_i3_output(o)
                    for o in outputs
                    if o.name and not o.name.startswith("__")  # Skip internal outputs
                }
                self._initialized = True
                logger.info(
                    f"[Feature 102] OutputEventService initialized with "
                    f"{len(self._cached_outputs)} outputs: "
                    f"{list(self._cached_outputs.keys())}"
                )
            except Exception as e:
                logger.error(f"[Feature 102] Failed to initialize OutputEventService: {e}")
                self._initialized = False

    async def detect_change(
        self,
        conn: "aio.Connection"
    ) -> List[OutputDiff]:
        """Detect output changes by comparing current state to cache.

        Args:
            conn: i3ipc async connection

        Returns:
            List of OutputDiff objects describing each detected change
        """
        if not self._initialized:
            await self.initialize(conn)
            return [OutputDiff(
                output_name="all",
                event_type=OutputEventType.UNSPECIFIED,
            )]

        async with self._lock:
            try:
                # Get current output state
                outputs = await conn.get_outputs()
                current_outputs = {
                    o.name: OutputState.from_i3_output(o)
                    for o in outputs
                    if o.name and not o.name.startswith("__")
                }

                diffs: List[OutputDiff] = []

                # Find new outputs (connected)
                for name, state in current_outputs.items():
                    if name not in self._cached_outputs:
                        diffs.append(OutputDiff(
                            output_name=name,
                            event_type=OutputEventType.CONNECTED,
                            old_state=None,
                            new_state=state,
                        ))
                        logger.debug(f"[Feature 102] Output {name} connected")

                # Find removed outputs (disconnected)
                for name, old_state in self._cached_outputs.items():
                    if name not in current_outputs:
                        diffs.append(OutputDiff(
                            output_name=name,
                            event_type=OutputEventType.DISCONNECTED,
                            old_state=old_state,
                            new_state=None,
                        ))
                        logger.debug(f"[Feature 102] Output {name} disconnected")

                # Find changed outputs (profile_changed)
                for name, new_state in current_outputs.items():
                    if name in self._cached_outputs:
                        old_state = self._cached_outputs[name]
                        changes = self._compute_property_diff(old_state, new_state)
                        if changes:
                            diffs.append(OutputDiff(
                                output_name=name,
                                event_type=OutputEventType.PROFILE_CHANGED,
                                old_state=old_state,
                                new_state=new_state,
                                changed_properties=changes,
                            ))
                            logger.debug(
                                f"[Feature 102] Output {name} profile changed: {changes}"
                            )

                # Update cache
                self._cached_outputs = current_outputs

                return diffs if diffs else [OutputDiff(
                    output_name="all",
                    event_type=OutputEventType.UNSPECIFIED,
                )]

            except Exception as e:
                logger.error(f"[Feature 102] Failed to detect output changes: {e}")
                return [OutputDiff(
                    output_name="unknown",
                    event_type=OutputEventType.UNSPECIFIED,
                )]

    def _compute_property_diff(
        self,
        old: OutputState,
        new: OutputState
    ) -> Dict[str, Dict[str, Any]]:
        """Compute which properties changed between states.

        Args:
            old: Previous output state
            new: Current output state

        Returns:
            Dict mapping property name to {before, after} values
        """
        changes = {}

        if old.active != new.active:
            changes["active"] = {"before": old.active, "after": new.active}

        if old.dpms != new.dpms:
            changes["dpms"] = {"before": old.dpms, "after": new.dpms}

        if old.current_mode != new.current_mode:
            changes["current_mode"] = {"before": old.current_mode, "after": new.current_mode}

        if old.scale != new.scale:
            changes["scale"] = {"before": old.scale, "after": new.scale}

        if old.transform != new.transform:
            changes["transform"] = {"before": old.transform, "after": new.transform}

        if old.position_x != new.position_x or old.position_y != new.position_y:
            changes["position"] = {
                "before": f"{old.position_x},{old.position_y}",
                "after": f"{new.position_x},{new.position_y}",
            }

        return changes

    def get_current_state(self) -> Dict[str, OutputState]:
        """Get the current cached output state.

        Returns:
            Dict mapping output name to OutputState
        """
        return dict(self._cached_outputs)

    def get_output_count(self) -> int:
        """Get the number of tracked outputs.

        Returns:
            Number of outputs in cache
        """
        return len(self._cached_outputs)

    def get_active_outputs(self) -> List[str]:
        """Get names of active outputs.

        Returns:
            List of active output names
        """
        return [
            name for name, state in self._cached_outputs.items()
            if state.active
        ]


# Global singleton instance
_output_event_service: Optional[OutputEventService] = None


def get_output_event_service() -> Optional[OutputEventService]:
    """Get the global OutputEventService instance."""
    return _output_event_service


def init_output_event_service() -> OutputEventService:
    """Initialize the global OutputEventService."""
    global _output_event_service
    _output_event_service = OutputEventService()
    logger.info("[Feature 102] Initialized OutputEventService")
    return _output_event_service

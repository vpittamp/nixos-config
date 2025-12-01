"""Correlation service for causality tracking.

Feature 102: Uses Python contextvars for async-safe correlation_id
propagation across event handlers.

This enables grouping of related events (e.g., all events caused by
a project switch) for causality chain visualization in the Log tab.
"""

import contextvars
import logging
import uuid
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)


# ContextVar for async correlation propagation (auto-propagates through await and create_task)
_correlation_id: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    'correlation_id', default=None
)
_causality_depth: contextvars.ContextVar[int] = contextvars.ContextVar(
    'causality_depth', default=0
)
_root_event_type: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    'root_event_type', default=None
)


@dataclass
class CorrelationContext:
    """Represents an active correlation context for causality tracking.

    Feature 102: Tracks the root event and current depth in a causality chain.
    """
    correlation_id: str
    root_event_type: str
    depth: int = 0
    parent_correlation_id: Optional[str] = None


class CorrelationService:
    """Manages correlation_id propagation for causality tracking.

    Feature 102: This service provides methods to:
    - Create new root correlations (e.g., at project::switch)
    - Enter child contexts (depth tracking for indentation)
    - Get current correlation for event logging

    Uses Python contextvars for async-safe propagation.
    """

    def __init__(self) -> None:
        """Initialize the correlation service."""
        self._active_chains: dict[str, CorrelationContext] = {}
        self._stats = {
            "chains_created": 0,
            "events_correlated": 0,
        }

    def new_root(self, root_event_type: str) -> str:
        """Start a new causality chain at a root event.

        Args:
            root_event_type: The type of root event (e.g., "project::switch")

        Returns:
            The new correlation_id for this chain
        """
        correlation_id = str(uuid.uuid4())

        # Set in contextvars
        _correlation_id.set(correlation_id)
        _causality_depth.set(0)
        _root_event_type.set(root_event_type)

        # Track active chain
        context = CorrelationContext(
            correlation_id=correlation_id,
            root_event_type=root_event_type,
            depth=0,
        )
        self._active_chains[correlation_id] = context
        self._stats["chains_created"] += 1

        logger.debug(
            f"[Feature 102] New correlation chain {correlation_id[:8]} "
            f"for {root_event_type}"
        )
        return correlation_id

    def enter_child(self) -> int:
        """Enter a child context (increases depth for indentation).

        Call this when a root event triggers sub-events.

        Returns:
            The new causality depth (for indentation in UI)
        """
        current_depth = _causality_depth.get()
        new_depth = current_depth + 1
        _causality_depth.set(new_depth)
        return new_depth

    def exit_child(self) -> int:
        """Exit a child context (decreases depth).

        Returns:
            The new causality depth after exit
        """
        current_depth = _causality_depth.get()
        new_depth = max(0, current_depth - 1)
        _causality_depth.set(new_depth)
        return new_depth

    def get_current(self) -> Optional[CorrelationContext]:
        """Get the current correlation context (if active).

        Returns:
            Current CorrelationContext or None if no active chain
        """
        correlation_id = _correlation_id.get()
        if not correlation_id:
            return None

        return CorrelationContext(
            correlation_id=correlation_id,
            root_event_type=_root_event_type.get() or "",
            depth=_causality_depth.get(),
        )

    def get_correlation_id(self) -> Optional[str]:
        """Get just the current correlation_id.

        Returns:
            Current correlation_id or None
        """
        return _correlation_id.get()

    def get_depth(self) -> int:
        """Get the current causality depth.

        Returns:
            Current depth (0 for root events)
        """
        return _causality_depth.get()

    def end_chain(self, correlation_id: Optional[str] = None) -> None:
        """End a causality chain.

        Args:
            correlation_id: Specific chain to end (or current if None)
        """
        if correlation_id is None:
            correlation_id = _correlation_id.get()

        if correlation_id:
            self._active_chains.pop(correlation_id, None)
            _correlation_id.set(None)
            _causality_depth.set(0)
            _root_event_type.set(None)

    def clear_context(self) -> None:
        """Clear the current correlation context.

        Use this to ensure no stale correlation leaks to unrelated events.
        """
        _correlation_id.set(None)
        _causality_depth.set(0)
        _root_event_type.set(None)

    def get_stats(self) -> dict:
        """Get correlation service statistics.

        Returns:
            Dictionary with chains_created and events_correlated
        """
        return {
            **self._stats,
            "active_chains": len(self._active_chains),
        }


# Global singleton instance (initialized by daemon)
_correlation_service: Optional[CorrelationService] = None


def get_correlation_service() -> Optional[CorrelationService]:
    """Get the global CorrelationService instance."""
    return _correlation_service


def init_correlation_service() -> CorrelationService:
    """Initialize the global CorrelationService."""
    global _correlation_service
    _correlation_service = CorrelationService()
    logger.info("[Feature 102] Initialized CorrelationService")
    return _correlation_service


# Convenience functions that use the global instance
def new_correlation(root_event_type: str) -> Optional[str]:
    """Create a new correlation chain at a root event.

    Args:
        root_event_type: The root event type (e.g., "project::switch")

    Returns:
        New correlation_id or None if service not initialized
    """
    service = get_correlation_service()
    if service:
        return service.new_root(root_event_type)
    return None


def get_correlation_context() -> tuple[Optional[str], int]:
    """Get current correlation_id and depth for event logging.

    Returns:
        Tuple of (correlation_id, causality_depth)
    """
    service = get_correlation_service()
    if service:
        return service.get_correlation_id(), service.get_depth()
    return None, 0


def enter_child_context() -> int:
    """Enter a child context (increases causality depth).

    Returns:
        New depth level
    """
    service = get_correlation_service()
    if service:
        return service.enter_child()
    return 0


def exit_child_context() -> int:
    """Exit a child context (decreases causality depth).

    Returns:
        New depth level
    """
    service = get_correlation_service()
    if service:
        return service.exit_child()
    return 0


def end_correlation() -> None:
    """End the current correlation chain."""
    service = get_correlation_service()
    if service:
        service.end_chain()


def clear_correlation() -> None:
    """Clear correlation context without ending the chain."""
    service = get_correlation_service()
    if service:
        service.clear_context()

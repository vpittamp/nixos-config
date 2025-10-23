"""Event correlation module for i3pm event system.

This module provides functionality to detect and score relationships between
GUI window events and spawned process events using multi-factor heuristic scoring.

Feature: 029-linux-system-log
User Story: US3 - Correlate Events
"""

import logging
import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from difflib import SequenceMatcher
from pathlib import Path
from typing import Dict, Any, List, Optional, Set, Tuple

from .models import EventEntry, EventCorrelation

logger = logging.getLogger(__name__)


# Correlation configuration
CONFIDENCE_THRESHOLD = 0.35  # 35% minimum confidence (lowered temporarily - hierarchy not implemented)
DETECTION_WINDOW_MS = 5000.0  # 5 seconds time window for detecting correlations

# Weights for confidence scoring (must sum to 1.0)
WEIGHTS = {
    "timing": 0.40,      # 40%: Timing is strong signal for startup correlation
    "hierarchy": 0.30,   # 30%: Process hierarchy is authoritative
    "name": 0.20,        # 20%: Name similarity is weak (many false positives)
    "workspace": 0.10,   # 10%: Workspace co-location is bonus signal
}

# Known IDE → language server patterns for name similarity
IDE_LANGUAGE_SERVER_PATTERNS = {
    "code": ["rust-analyzer", "typescript-language-server", "pyright", "gopls", "clangd", "git", "node", "npm", "deno"],
    "nvim": ["rust-analyzer", "typescript-language-server", "pyright", "gopls", "clangd"],
    "emacs": ["eglot", "lsp-mode", "rust-analyzer", "gopls"],
    "vim": ["rust-analyzer", "gopls", "pyright"],
}


@dataclass
class CorrelationFactors:
    """Individual correlation factor scores for debugging."""
    timing_score: float       # 0.0-1.0: Timing proximity
    hierarchy_score: float    # 0.0-1.0: Process hierarchy match
    name_score: float         # 0.0-1.0: Name similarity
    workspace_score: float    # 0.0-1.0: Workspace co-location


class EventCorrelator:
    """Detect correlations between window events and process spawns."""

    def __init__(self) -> None:
        """Initialize event correlator."""
        self.next_correlation_id = 1
        self.correlations: Dict[int, EventCorrelation] = {}  # correlation_id → EventCorrelation

    async def detect_correlations(
        self,
        events: List[EventEntry],
        time_window_ms: float = DETECTION_WINDOW_MS
    ) -> List[EventCorrelation]:
        """Scan event list for correlations between window and process events.

        Args:
            events: List of EventEntry objects sorted by timestamp
            time_window_ms: Time window for correlation detection (default: 5000ms)

        Returns:
            List of detected EventCorrelation objects
        """
        correlations = []

        # Filter to window::new events (potential parents)
        window_events = [e for e in events if e.event_type == "window::new"]

        # Filter to process::start events (potential children)
        process_events = [e for e in events if e.event_type == "process::start"]

        logger.debug(f"Detecting correlations: {len(window_events)} windows, {len(process_events)} processes")

        # For each window event, find matching process events
        for window_event in window_events:
            child_events = []
            factors_list = []
            all_candidates = []  # Track all for debugging

            for process_event in process_events:
                # Calculate correlation factors
                factors = self._calculate_factors(
                    window_event,
                    process_event,
                    time_window_ms
                )

                # Calculate confidence score
                confidence = self._calculate_confidence(factors)

                # Store for debugging
                all_candidates.append((process_event, factors, confidence))

                # Check if above threshold
                if confidence >= CONFIDENCE_THRESHOLD:
                    child_events.append(process_event)
                    factors_list.append((factors, confidence))
                    logger.debug(
                        f"Correlation found: window {window_event.window_class} → "
                        f"process {process_event.process_name} (confidence: {confidence:.2f})"
                    )

            # Debug: Log top 3 candidates even if they didn't pass threshold
            if not child_events and all_candidates:
                all_candidates.sort(key=lambda x: x[2], reverse=True)
                top_3 = all_candidates[:3]
                logger.debug(f"No correlations above {CONFIDENCE_THRESHOLD:.0%} for window '{window_event.window_class}'")
                for proc_event, factors, conf in top_3:
                    logger.debug(
                        f"  Candidate: {proc_event.process_name} - "
                        f"confidence={conf:.2f} (timing={factors.timing_score:.2f}, "
                        f"hierarchy={factors.hierarchy_score:.2f}, name={factors.name_score:.2f}, "
                        f"workspace={factors.workspace_score:.2f})"
                    )

            # If we found correlated children, create EventCorrelation
            if child_events:
                # Calculate time delta to first child
                time_delta_ms = (
                    child_events[0].timestamp - window_event.timestamp
                ).total_seconds() * 1000

                # Use factors from first (highest confidence) child
                first_factors = factors_list[0][0]
                first_confidence = factors_list[0][1]

                correlation = EventCorrelation(
                    correlation_id=self.next_correlation_id,
                    created_at=datetime.now(),
                    confidence_score=first_confidence,
                    parent_event_id=window_event.event_id,
                    child_event_ids=[e.event_id for e in child_events],
                    correlation_type="window_to_process",
                    time_delta_ms=time_delta_ms,
                    detection_window_ms=time_window_ms,
                    timing_factor=first_factors.timing_score,
                    hierarchy_factor=first_factors.hierarchy_score,
                    name_similarity=first_factors.name_score,
                    workspace_match=(first_factors.workspace_score > 0),
                )

                self.correlations[self.next_correlation_id] = correlation
                correlations.append(correlation)
                self.next_correlation_id += 1

        logger.info(f"Detected {len(correlations)} correlations")
        return correlations

    def _calculate_factors(
        self,
        window_event: EventEntry,
        process_event: EventEntry,
        time_window_ms: float
    ) -> CorrelationFactors:
        """Calculate all correlation factors for a window-process pair.

        Args:
            window_event: Parent window event
            process_event: Child process event
            time_window_ms: Maximum time window for correlation

        Returns:
            CorrelationFactors with individual scores
        """
        # 1. Timing proximity (40%)
        timing_score = self._calculate_timing_score(
            window_event.timestamp,
            process_event.timestamp,
            time_window_ms
        )

        # 2. Process hierarchy (30%)
        hierarchy_score = self._calculate_hierarchy_score(
            window_event.window_id,  # Window's X11 ID (may be used as PID proxy)
            process_event.process_pid,
            process_event.process_parent_pid
        )

        # 3. Name similarity (20%)
        name_score = self._calculate_name_similarity(
            window_event.window_class or "",
            process_event.process_name or ""
        )

        # 4. Workspace co-location (10%)
        workspace_score = self._calculate_workspace_score(
            window_event.workspace_name or "",
            window_event.workspace_name or ""  # TODO: Get workspace from process event context
        )

        return CorrelationFactors(
            timing_score=timing_score,
            hierarchy_score=hierarchy_score,
            name_score=name_score,
            workspace_score=workspace_score
        )

    def _calculate_timing_score(
        self,
        window_created: datetime,
        process_created: datetime,
        max_window_ms: float
    ) -> float:
        """Calculate timing proximity score (0.0 to 1.0).

        Args:
            window_created: When window was created
            process_created: When process was spawned
            max_window_ms: Maximum time difference to consider (milliseconds)

        Returns:
            Score from 0.0 (no correlation) to 1.0 (perfect timing match)
        """
        # Process must be spawned AFTER window (or very close before)
        time_diff_ms = (process_created - window_created).total_seconds() * 1000

        # Process spawned before window? Unlikely to be related (penalize)
        if time_diff_ms < -1000:  # Allow 1 second tolerance
            return 0.0

        # Process spawned long after window? Unlikely to be startup-related
        if time_diff_ms > max_window_ms:
            return 0.0

        # Linear decay: 1.0 at t=0, 0.0 at t=max_window_ms
        # Score = 1 - (time_diff / max_window)
        score = 1.0 - (abs(time_diff_ms) / max_window_ms)
        return max(0.0, min(1.0, score))  # Clamp to [0.0, 1.0]

    def _calculate_hierarchy_score(
        self,
        window_pid: Optional[int],
        process_pid: Optional[int],
        process_parent_pid: Optional[int]
    ) -> float:
        """Calculate process hierarchy score (0.0 or 1.0).

        Args:
            window_pid: Window's process ID
            process_pid: Process ID to correlate
            process_parent_pid: Process parent PID

        Returns:
            1.0 if hierarchy match found, 0.0 otherwise
        """
        if not process_pid or not process_parent_pid:
            return 0.0

        # Check if process is direct child of window (PPID matches window PID)
        # Note: window_id from i3 is X11 window ID, not PID
        # For proper hierarchy detection, we'd need to map X11 window ID to PID
        # For MVP, we'll check process ancestry via /proc
        try:
            ancestry = self._get_process_ancestry(process_pid, max_depth=5)
            # Check if window PID (if available) is in ancestry
            # For now, return 0.0 since window_id is X11 ID not PID
            # TODO: Implement X11 window ID → PID mapping
            return 0.0
        except Exception as e:
            logger.debug(f"Hierarchy check failed: {e}")
            return 0.0

    def _get_process_ancestry(self, pid: int, max_depth: int = 5) -> List[int]:
        """Get list of ancestor PIDs (pid, parent, grandparent, ...).

        Args:
            pid: Process ID to start from
            max_depth: Maximum depth to traverse

        Returns:
            List of PIDs from child to ancestor
        """
        ancestry = [pid]
        current = pid

        for _ in range(max_depth):
            parent = self._get_parent_pid(current)
            if parent is None or parent == 0 or parent == 1:  # Reached init/systemd
                break
            if parent in ancestry:  # Cycle detection
                break
            ancestry.append(parent)
            current = parent

        return ancestry

    def _get_parent_pid(self, pid: int) -> Optional[int]:
        """Get parent PID from /proc/{pid}/stat.

        Args:
            pid: Process ID

        Returns:
            Parent PID, or None if unable to read
        """
        try:
            stat_file = Path(f"/proc/{pid}/stat")
            stat_content = stat_file.read_text()

            # Format: PID (comm) state PPID ...
            # Find closing parenthesis of comm (last one before state field)
            comm_end = stat_content.rfind(')')
            if comm_end == -1:
                return None

            # Fields after comm: state, ppid, pgrp, session, tty_nr, ...
            fields_after_comm = stat_content[comm_end + 1:].split()

            # PPID is field 3 (index 1 in fields_after_comm: state=0, ppid=1)
            ppid = int(fields_after_comm[1])
            return ppid

        except (FileNotFoundError, ProcessLookupError, ValueError, IndexError):
            return None

    def _calculate_name_similarity(self, window_class: str, process_name: str) -> float:
        """Calculate name similarity score (0.0 to 1.0).

        Uses multiple heuristics:
        - Exact match (1.0)
        - Substring match (0.7)
        - Known IDE patterns (0.8)
        - Fuzzy string similarity (0.0-0.6)

        Args:
            window_class: Window class (e.g., "Code", "firefox")
            process_name: Process comm name (e.g., "rust-analyzer", "firefox")

        Returns:
            Similarity score from 0.0 to 1.0
        """
        window_lower = window_class.lower()
        process_lower = process_name.lower()

        # Exact match
        if window_lower == process_lower:
            return 1.0

        # Substring match (e.g., "Code" in "code-server")
        if window_lower in process_lower or process_lower in window_lower:
            return 0.7

        # Known IDE → language server patterns
        for ide, servers in IDE_LANGUAGE_SERVER_PATTERNS.items():
            if window_lower == ide and process_lower in servers:
                return 0.8  # Strong signal: known IDE spawns known language server

        # Fuzzy similarity (Levenshtein-like)
        fuzzy = SequenceMatcher(None, window_lower, process_lower).ratio()
        return fuzzy * 0.6  # Scale down fuzzy matches (max 0.6 to be weaker than known patterns)

    def _calculate_workspace_score(self, window_workspace: str, process_workspace: str) -> float:
        """Calculate workspace co-location score (0.0 or 1.0).

        Args:
            window_workspace: Workspace where window was created
            process_workspace: Workspace context for process (if available)

        Returns:
            1.0 if same workspace, 0.0 otherwise
        """
        if not window_workspace or not process_workspace:
            return 0.0

        return 1.0 if window_workspace == process_workspace else 0.0

    def _calculate_confidence(self, factors: CorrelationFactors) -> float:
        """Calculate overall confidence score for correlation.

        Weights from research.md:
        - Timing: 40%
        - Hierarchy: 30%
        - Name similarity: 20%
        - Workspace: 10%

        Args:
            factors: Individual correlation factor scores

        Returns:
            Confidence score 0.0-1.0
        """
        score = (
            factors.timing_score * WEIGHTS["timing"] +
            factors.hierarchy_score * WEIGHTS["hierarchy"] +
            factors.name_score * WEIGHTS["name"] +
            factors.workspace_score * WEIGHTS["workspace"]
        )
        return min(1.0, max(0.0, score))

    def get_correlation(self, correlation_id: int) -> Optional[EventCorrelation]:
        """Get correlation by ID.

        Args:
            correlation_id: Correlation ID to lookup

        Returns:
            EventCorrelation if found, None otherwise
        """
        return self.correlations.get(correlation_id)

    def get_correlations_by_parent(self, parent_event_id: int) -> List[EventCorrelation]:
        """Get all correlations for a parent event.

        Args:
            parent_event_id: Parent event ID

        Returns:
            List of EventCorrelation objects
        """
        return [
            c for c in self.correlations.values()
            if c.parent_event_id == parent_event_id
        ]

    def get_correlations_by_child(self, child_event_id: int) -> List[EventCorrelation]:
        """Get all correlations that include a child event.

        Args:
            child_event_id: Child event ID

        Returns:
            List of EventCorrelation objects
        """
        return [
            c for c in self.correlations.values()
            if child_event_id in c.child_event_ids
        ]

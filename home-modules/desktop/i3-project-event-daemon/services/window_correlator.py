"""Window-to-Launch Correlation Engine.

This module implements the multi-signal correlation algorithm that matches newly
created windows to pending launch notifications. Uses application class, timing
proximity, and workspace location to determine correlation confidence.

Feature 041: IPC Launch Context - T009
"""

import logging
from typing import Dict

from ..models import PendingLaunch, LaunchWindowInfo

logger = logging.getLogger(__name__)


def calculate_confidence(
    launch: PendingLaunch,
    window: LaunchWindowInfo
) -> tuple[float, Dict[str, any]]:
    """
    Calculate correlation confidence score for a launch-window pair.

    Correlation signals (from spec FR-006, FR-015 to FR-018):
    1. Application class match (REQUIRED baseline): 0.5
    2. Time delta (<1s: +0.3, <2s: +0.2, <5s: +0.1)
    3. Workspace match (OPTIONAL bonus): +0.2

    Threshold: MEDIUM (0.6) minimum for project assignment (FR-016)

    Feature 041: T039 - Enhanced to return workspace signals

    Args:
        launch: Pending launch awaiting correlation
        window: Newly created window information

    Returns:
        tuple: (confidence_score, signals_used_dict)
            - confidence_score: float from 0.0 to 1.0
            - signals_used_dict: Dictionary of correlation signals for debugging
    """
    confidence = 0.0
    signals: Dict[str, any] = {}

    # Signal 1: Application class match (REQUIRED)
    # Case-insensitive comparison (Fix: code vs Code mismatch)
    window_class_lower = (window.window_class or "").lower()
    expected_class_lower = (launch.expected_class or "").lower()

    if window_class_lower == expected_class_lower:
        confidence = 0.5  # Baseline for class match
        signals["class_match"] = True
        logger.debug(f"Class match: {window.window_class} == {launch.expected_class} (case-insensitive)")
    else:
        # No match possible without class alignment
        signals["class_match"] = False
        signals["window_class"] = window.window_class
        signals["expected_class"] = launch.expected_class
        logger.debug(
            f"Class mismatch: {window.window_class} != {launch.expected_class}, "
            "returning confidence=0.0"
        )
        return 0.0, signals

    # Signal 2: Time delta scoring (REQUIRED)
    time_delta = window.timestamp - launch.timestamp
    signals["time_delta"] = time_delta

    if time_delta < 0:
        # Window appeared before launch notification (should not happen)
        logger.warning(
            f"Window {window.window_id} timestamp ({window.timestamp}) is before "
            f"launch timestamp ({launch.timestamp}). Clock skew?"
        )
        signals["error"] = "negative_time_delta"
        return 0.0, signals
    elif time_delta < 1.0:
        confidence += 0.3  # Very recent launch
        signals["time_score"] = 0.3
        logger.debug(f"Time delta {time_delta:.3f}s < 1s, adding 0.3")
    elif time_delta < 2.0:
        confidence += 0.2  # Recent launch
        signals["time_score"] = 0.2
        logger.debug(f"Time delta {time_delta:.3f}s < 2s, adding 0.2")
    elif time_delta < 5.0:
        confidence += 0.1  # Within timeout window
        signals["time_score"] = 0.1
        logger.debug(f"Time delta {time_delta:.3f}s < 5s, adding 0.1")
    else:
        # Outside correlation window
        signals["time_score"] = 0.0
        logger.debug(
            f"Time delta {time_delta:.3f}s >= 5s, outside correlation window, "
            "returning confidence=0.0"
        )
        signals["error"] = "time_delta_exceeds_timeout"
        return 0.0, signals

    # Signal 3: Workspace match bonus (OPTIONAL)
    # T039: Enhanced workspace signal tracking for User Story 5
    signals["launch_workspace"] = launch.workspace_number
    signals["window_workspace"] = window.workspace_number

    if window.workspace_number == launch.workspace_number:
        confidence += 0.2  # Workspace alignment
        signals["workspace_match"] = True
        signals["workspace_bonus"] = 0.2
        logger.debug(
            f"Workspace match: {window.workspace_number} == {launch.workspace_number}, "
            "adding 0.2"
        )
    else:
        signals["workspace_match"] = False
        signals["workspace_bonus"] = 0.0
        logger.debug(
            f"Workspace mismatch: {window.workspace_number} != {launch.workspace_number}, "
            "no bonus (reduces confidence but doesn't prevent matching)"
        )

    # Cap at EXACT (1.0)
    final_confidence = min(confidence, 1.0)
    logger.debug(f"Final confidence: {final_confidence:.2f}, signals: {signals}")

    return final_confidence, signals

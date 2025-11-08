"""Multi-Factor Confidence Scoring for User Action Correlation

Calculates confidence that a user action caused a tree change event.

Scoring Factors:
1. Temporal Proximity (40%): How close in time was the action to the effect?
2. Semantic Relevance (30%): Does the action type match the effect type?
3. Exclusivity (20%): Was this the only action in the time window?
4. Cascade Strength (10%): How many effects are in the cascade chain?

Final Score: [0.0, 1.0] with confidence labels:
- 0.9-1.0: "very likely" (🟢)
- 0.7-0.9: "likely" (🟡)
- 0.5-0.7: "possible" (🟠)
- 0.3-0.5: "unlikely" (🔴)
- 0.0-0.3: "very unlikely" (⚫)
"""

from typing import List, Dict, Tuple
from enum import Enum

from ..models import UserAction, ActionType, EventCorrelation


class ConfidenceLevel(Enum):
    """Confidence level labels for correlation scores"""
    VERY_LIKELY = "very likely"
    LIKELY = "likely"
    POSSIBLE = "possible"
    UNLIKELY = "unlikely"
    VERY_UNLIKELY = "very unlikely"


def calculate_confidence(
    action: UserAction,
    event_type: str,
    time_delta_ms: int,
    competing_actions: int = 0,
    cascade_depth: int = 0
) -> Tuple[float, ConfidenceLevel, str]:
    """
    Calculate multi-factor confidence score for correlation.

    Args:
        action: The user action being evaluated
        event_type: Type of tree change event (e.g., "window::new")
        time_delta_ms: Time between action and event
        competing_actions: Number of other actions in the same time window
        cascade_depth: Depth in cascade chain (0 = primary, 1+ = secondary)

    Returns:
        Tuple of (confidence_score, confidence_level, reasoning)
    """
    # Factor 1: Temporal Proximity (40%)
    temporal_score = _score_temporal_proximity(time_delta_ms)
    temporal_weight = 0.40

    # Factor 2: Semantic Relevance (30%)
    semantic_score = _score_semantic_relevance(action.action_type, event_type)
    semantic_weight = 0.30

    # Factor 3: Exclusivity (20%)
    exclusivity_score = _score_exclusivity(competing_actions)
    exclusivity_weight = 0.20

    # Factor 4: Cascade Strength (10%)
    cascade_score = _score_cascade_strength(cascade_depth)
    cascade_weight = 0.10

    # Calculate weighted final score
    final_score = (
        temporal_score * temporal_weight +
        semantic_score * semantic_weight +
        exclusivity_score * exclusivity_weight +
        cascade_score * cascade_weight
    )

    # Get confidence level
    confidence_level = _get_confidence_level(final_score)

    # Generate reasoning
    reasoning = _generate_reasoning(
        temporal_score, semantic_score, exclusivity_score, cascade_score,
        time_delta_ms, action.action_type, event_type, competing_actions, cascade_depth
    )

    return final_score, confidence_level, reasoning


def _score_temporal_proximity(time_delta_ms: int) -> float:
    """
    Score based on how close in time the action and event occurred.

    Scoring:
    - 0-50ms: 1.0 (immediate effect, very likely causal)
    - 50-100ms: 0.9 (very quick effect, likely causal)
    - 100-200ms: 0.7 (quick effect, probably causal)
    - 200-350ms: 0.5 (delayed effect, possibly causal)
    - 350-500ms: 0.3 (slow effect, unlikely but possible)

    Args:
        time_delta_ms: Time between action and event

    Returns:
        Score [0.0, 1.0]
    """
    if time_delta_ms <= 50:
        return 1.0
    elif time_delta_ms <= 100:
        return 0.9
    elif time_delta_ms <= 200:
        return 0.7
    elif time_delta_ms <= 350:
        return 0.5
    else:
        return 0.3


def _score_semantic_relevance(action_type: ActionType, event_type: str) -> float:
    """
    Score based on whether action type matches event type.

    Since all Sway binding events use ActionType.BINDING, we provide
    moderate relevance for all matches (the specific binding command
    would need to be parsed for more granular matching).

    Args:
        action_type: Type of user action
        event_type: Type of tree change event

    Returns:
        Score [0.0, 1.0]
    """
    # For BINDING type (which is what Sway uses for all key bindings),
    # we give moderate relevance since we don't parse the binding_command
    # to determine specific semantic matches
    if action_type == ActionType.BINDING:
        # Binding could cause any window/workspace event
        if event_type.startswith('window::') or event_type.startswith('workspace::'):
            return 0.6  # Moderate relevance
        return 0.3  # Lower relevance for other events

    # For IPC commands
    if action_type == ActionType.IPC_COMMAND:
        return 0.7  # IPC commands are likely intentional

    # For keypresses and mouse clicks
    if action_type == ActionType.KEYPRESS:
        return 0.5  # Keypresses could cause various events

    if action_type == ActionType.MOUSE_CLICK:
        # Mouse clicks are likely to cause focus/move events
        if 'focus' in event_type or 'move' in event_type:
            return 0.7
        return 0.4

    # Default: low relevance but not impossible
    return 0.2


def _score_exclusivity(competing_actions: int) -> float:
    """
    Score based on how many competing actions exist in the time window.

    Scoring:
    - 0 competing actions: 1.0 (only action, very likely causal)
    - 1 competing action: 0.7 (2 candidates, likely one of them)
    - 2 competing actions: 0.5 (3 candidates, uncertain)
    - 3+ competing actions: 0.3 (many candidates, unlikely)

    Args:
        competing_actions: Number of other actions in time window (excluding this one)

    Returns:
        Score [0.0, 1.0]
    """
    if competing_actions == 0:
        return 1.0
    elif competing_actions == 1:
        return 0.7
    elif competing_actions == 2:
        return 0.5
    else:
        return 0.3


def _score_cascade_strength(cascade_depth: int) -> float:
    """
    Score based on position in cascade chain.

    Scoring:
    - Depth 0 (primary): 1.0 (direct effect)
    - Depth 1 (secondary): 0.7 (immediate cascade)
    - Depth 2 (tertiary): 0.4 (second-order cascade)
    - Depth 3+: 0.2 (weak cascade)

    Args:
        cascade_depth: Depth in cascade chain (0 = primary effect)

    Returns:
        Score [0.0, 1.0]
    """
    if cascade_depth == 0:
        return 1.0
    elif cascade_depth == 1:
        return 0.7
    elif cascade_depth == 2:
        return 0.4
    else:
        return 0.2


def _get_confidence_level(score: float) -> ConfidenceLevel:
    """Map score to confidence level enum"""
    if score >= 0.9:
        return ConfidenceLevel.VERY_LIKELY
    elif score >= 0.7:
        return ConfidenceLevel.LIKELY
    elif score >= 0.5:
        return ConfidenceLevel.POSSIBLE
    elif score >= 0.3:
        return ConfidenceLevel.UNLIKELY
    else:
        return ConfidenceLevel.VERY_UNLIKELY


def _generate_reasoning(
    temporal_score: float,
    semantic_score: float,
    exclusivity_score: float,
    cascade_score: float,
    time_delta_ms: int,
    action_type: ActionType,
    event_type: str,
    competing_actions: int,
    cascade_depth: int
) -> str:
    """
    Generate human-readable reasoning for the confidence score.

    Example: "Very likely: Action occurred 45ms before event (temporal: 1.0),
             action type matches event (semantic: 1.0), no competing actions
             (exclusivity: 1.0), direct effect (cascade: 1.0)"
    """
    parts = []

    # Temporal
    if temporal_score >= 0.9:
        parts.append(f"immediate effect ({time_delta_ms}ms)")
    elif temporal_score >= 0.7:
        parts.append(f"quick effect ({time_delta_ms}ms)")
    else:
        parts.append(f"delayed effect ({time_delta_ms}ms)")

    # Semantic
    if semantic_score >= 0.9:
        parts.append("action type matches event")
    elif semantic_score >= 0.6:
        parts.append("action category matches event")
    else:
        parts.append("weak semantic match")

    # Exclusivity
    if competing_actions == 0:
        parts.append("only action in window")
    else:
        parts.append(f"{competing_actions + 1} competing actions")

    # Cascade
    if cascade_depth == 0:
        parts.append("direct effect")
    elif cascade_depth == 1:
        parts.append("secondary effect")
    else:
        parts.append(f"cascade depth {cascade_depth}")

    return ", ".join(parts)


def update_correlation_with_scoring(
    correlation: EventCorrelation,
    event_type: str,
    competing_actions: int = 0,
    cascade_depth: int = 0
) -> EventCorrelation:
    """
    Update an existing correlation with multi-factor confidence scoring.

    This replaces the simple temporal-only score from CorrelationTracker
    with a full multi-factor score.

    Args:
        correlation: Existing correlation with temporal score
        event_type: Type of tree change event
        competing_actions: Number of competing actions
        cascade_depth: Depth in cascade chain

    Returns:
        Updated correlation with refined confidence score
    """
    new_confidence, confidence_level, reasoning = calculate_confidence(
        action=correlation.user_action,
        event_type=event_type,
        time_delta_ms=correlation.time_delta_ms,
        competing_actions=competing_actions,
        cascade_depth=cascade_depth
    )

    # Calculate individual factor scores for confidence_factors dict
    temporal_score = _score_temporal_proximity(correlation.time_delta_ms)
    semantic_score = _score_semantic_relevance(correlation.user_action.action_type, event_type)
    exclusivity_score = _score_exclusivity(competing_actions)
    cascade_score = _score_cascade_position(cascade_depth)

    # Create new correlation with updated values, preserving all required fields
    return EventCorrelation(
        correlation_id=correlation.correlation_id,
        user_action=correlation.user_action,
        tree_event_id=correlation.tree_event_id,
        time_delta_ms=correlation.time_delta_ms,
        confidence_score=new_confidence,
        confidence_factors={
            'temporal': temporal_score * 100,
            'semantic': semantic_score * 100,
            'exclusivity': exclusivity_score * 100,
            'cascade': cascade_score * 100
        },
        cascade_level=cascade_depth
    )

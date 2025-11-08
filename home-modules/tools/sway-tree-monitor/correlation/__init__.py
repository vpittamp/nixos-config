"""User Action Correlation

This module tracks user actions (keypresses, window focus) and correlates
them with tree change events to determine causality.

Key components:
- CorrelationTracker: Tracks actions within 500ms time window
- CascadeTracker: Tracks primary → secondary → tertiary effect chains
- Multi-factor confidence scoring: Temporal + semantic + exclusivity + cascade
"""

from .tracker import CorrelationTracker
from .scoring import calculate_confidence, update_correlation_with_scoring, ConfidenceLevel
from .cascade import CascadeTracker

__all__ = [
    'CorrelationTracker',
    'CascadeTracker',
    'calculate_confidence',
    'update_correlation_with_scoring',
    'ConfidenceLevel',
]

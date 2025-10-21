"""Pattern-based window classification with 4-level precedence resolution."""

from dataclasses import dataclass
from typing import Optional, Literal, List

# Import local models
from .pattern import PatternRule
from .window_rules import WindowRule


@dataclass
class Classification:
    """Window classification result with source attribution.

    Attributes:
        scope: Classification scope (scoped or global)
        workspace: Optional target workspace (1-9)
        source: Source of classification decision for debugging
        matched_rule: Optional WindowRule that matched (for debugging)

    Examples:
        >>> cls = Classification("scoped", workspace=2, source="project")
        >>> cls.scope
        'scoped'
        >>> cls.source
        'project'

        >>> cls = Classification("global", workspace=None, source="default")
        >>> cls.workspace is None
        True
    """

    scope: Literal["scoped", "global"]
    workspace: Optional[int]
    source: Literal["project", "window_rule", "app_classes", "default"]
    matched_rule: Optional[WindowRule] = None

    def __post_init__(self):
        """Validate classification."""
        if self.workspace is not None and not (1 <= self.workspace <= 9):
            raise ValueError(f"Workspace must be 1-9, got {self.workspace}")

    def to_json(self) -> dict:
        """Serialize to JSON-compatible dict."""
        result = {
            "scope": self.scope,
            "workspace": self.workspace,
            "source": self.source,
        }

        if self.matched_rule:
            result["matched_pattern"] = self.matched_rule.pattern_rule.pattern

        return result


def classify_window(
    window_class: str,
    window_title: str = "",
    active_project_scoped_classes: Optional[List[str]] = None,
    window_rules: Optional[List[WindowRule]] = None,
    app_classification_patterns: Optional[List[PatternRule]] = None,
    app_classification_scoped: Optional[List[str]] = None,
    app_classification_global: Optional[List[str]] = None,
) -> Classification:
    """Classify window using 4-level precedence hierarchy.

    Precedence (highest to lowest):
    1. Project scoped_classes (priority 1000) - active project's window classes
    2. Window rules (priority 200-500) - user-defined window-rules.json
    3. App classification patterns (priority 100) - app-classes.json patterns
    4. App classification lists (priority 50) - app-classes.json scoped/global lists

    Args:
        window_class: Window WM_CLASS to classify
        window_title: Optional window title for title-based patterns
        active_project_scoped_classes: Active project's scoped_classes list
        window_rules: Loaded window rules from window-rules.json
        app_classification_patterns: App classification patterns from app-classes.json
        app_classification_scoped: App classification scoped list
        app_classification_global: App classification global list

    Returns:
        Classification object with scope, workspace, and source attribution

    Examples:
        >>> # Project match (priority 1000)
        >>> cls = classify_window("Code", active_project_scoped_classes=["Code"])
        >>> cls.scope
        'scoped'
        >>> cls.source
        'project'

        >>> # Window rule match (priority 200-500)
        >>> from i3_project_manager.models.pattern import PatternRule
        >>> rule = WindowRule(PatternRule("glob:FFPWA-*", "global", 200), workspace=4)
        >>> cls = classify_window("FFPWA-01ABC", window_rules=[rule])
        >>> cls.workspace
        4
        >>> cls.source
        'window_rule'
    """
    # Priority 1000: Project scoped_classes
    if active_project_scoped_classes and window_class in active_project_scoped_classes:
        return Classification(
            scope="scoped",
            workspace=None,
            source="project",
        )

    # Priority 200-500: Window rules (sorted by priority)
    if window_rules:
        for rule in window_rules:
            if rule.matches(window_class, window_title):
                return Classification(
                    scope=rule.scope,
                    workspace=rule.workspace,
                    source="window_rule",
                    matched_rule=rule,
                )

    # Priority 100: App classification patterns
    if app_classification_patterns:
        for pattern in app_classification_patterns:
            if pattern.matches(window_class):
                return Classification(
                    scope=pattern.scope,
                    workspace=None,
                    source="app_classes",
                )

    # Priority 50: App classification literal lists
    if app_classification_scoped and window_class in app_classification_scoped:
        return Classification(
            scope="scoped",
            workspace=None,
            source="app_classes",
        )

    if app_classification_global and window_class in app_classification_global:
        return Classification(
            scope="global",
            workspace=None,
            source="app_classes",
        )

    # Default: global (unscoped)
    return Classification(
        scope="global",
        workspace=None,
        source="default",
    )

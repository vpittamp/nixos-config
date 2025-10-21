"""Classification data models for the wizard TUI."""

from dataclasses import dataclass, field
from typing import Literal, Optional


@dataclass
class AppClassification:
    """Classification state of an application in the wizard.

    Attributes:
        app_name: Human-readable application name (e.g., "Visual Studio Code")
        window_class: WM_CLASS for i3 matching (e.g., "Code")
        desktop_file: Path to .desktop file
        current_scope: Current classification (scoped, global, or unclassified)
        suggested_scope: System-suggested classification (None if no suggestion)
        suggestion_reasoning: Explanation for suggestion
        suggestion_confidence: Confidence [0.0, 1.0] in suggestion
        user_modified: True if user explicitly changed classification

    Examples:
        >>> app = AppClassification(
        ...     app_name="Ghostty Terminal",
        ...     window_class="Ghostty",
        ...     desktop_file="/usr/share/applications/ghostty.desktop",
        ...     current_scope="unclassified",
        ...     suggested_scope="scoped",
        ...     suggestion_reasoning="Terminal emulator - typically project-scoped",
        ...     suggestion_confidence=0.9
        ... )
        >>> app.accept_suggestion()
        >>> app.current_scope
        'scoped'
        >>> app.user_modified
        True
    """

    app_name: str
    window_class: str
    desktop_file: str
    current_scope: Literal["scoped", "global", "unclassified"]
    suggested_scope: Optional[Literal["scoped", "global"]] = None
    suggestion_reasoning: str = ""
    suggestion_confidence: float = 0.0
    user_modified: bool = False

    def __post_init__(self):
        """Validate classification state."""
        if not self.app_name:
            raise ValueError("app_name cannot be empty")

        if not self.window_class:
            raise ValueError("window_class cannot be empty")

        if not self.desktop_file:
            raise ValueError("desktop_file cannot be empty")

        if not (0.0 <= self.suggestion_confidence <= 1.0):
            raise ValueError(
                f"suggestion_confidence must be in [0.0, 1.0], got {self.suggestion_confidence}"
            )

    def accept_suggestion(self):
        """Accept the system suggestion (update current_scope)."""
        if self.suggested_scope is None:
            raise ValueError("No suggestion to accept")

        self.current_scope = self.suggested_scope
        self.user_modified = True

    def classify_as(self, scope: Literal["scoped", "global"]):
        """Manually classify application (overrides suggestion)."""
        self.current_scope = scope
        self.user_modified = True


@dataclass
class WizardState:
    """State of the classification wizard session.

    Attributes:
        apps: List of all discovered applications
        selected_indices: Set of currently selected app indices
        filter_status: Current filter (all, unclassified, scoped, global)
        sort_by: Current sort field
        undo_stack: Stack of previous states for undo/redo
        changes_made: True if any classifications have been modified

    Examples:
        >>> state = WizardState(apps=[app1, app2, app3])
        >>> state.selected_indices = {0, 1}
        >>> filtered = state.get_filtered_apps()
        >>> sorted_apps = state.get_sorted_apps(filtered)
    """

    apps: list[AppClassification] = field(default_factory=list)
    selected_indices: set[int] = field(default_factory=set)
    filter_status: Literal["all", "unclassified", "scoped", "global"] = "all"
    sort_by: Literal["name", "class", "status", "confidence"] = "name"
    undo_stack: list[dict] = field(default_factory=list)
    changes_made: bool = False

    def get_filtered_apps(self) -> list[AppClassification]:
        """Get apps matching current filter."""
        if self.filter_status == "all":
            return self.apps
        return [app for app in self.apps if app.current_scope == self.filter_status]

    def get_sorted_apps(self, apps: list[AppClassification]) -> list[AppClassification]:
        """Sort apps by current sort field."""
        if self.sort_by == "name":
            return sorted(apps, key=lambda a: a.app_name.lower())
        elif self.sort_by == "class":
            return sorted(apps, key=lambda a: a.window_class.lower())
        elif self.sort_by == "status":
            return sorted(apps, key=lambda a: a.current_scope)
        else:  # confidence
            return sorted(apps, key=lambda a: a.suggestion_confidence, reverse=True)

    def save_undo_state(self):
        """Save current state to undo stack."""
        state_snapshot = {
            "apps": [vars(app).copy() for app in self.apps],
            "selected_indices": list(self.selected_indices),
            "filter_status": self.filter_status,
            "sort_by": self.sort_by,
        }
        self.undo_stack.append(state_snapshot)

        # Limit undo stack to 20 snapshots to prevent memory bloat
        if len(self.undo_stack) > 20:
            self.undo_stack.pop(0)

    def undo(self):
        """Restore previous state from undo stack."""
        if not self.undo_stack:
            raise ValueError("Nothing to undo")

        state_snapshot = self.undo_stack.pop()

        # Restore apps from snapshot
        self.apps = [
            AppClassification(**app_dict) for app_dict in state_snapshot["apps"]
        ]
        self.selected_indices = set(state_snapshot["selected_indices"])
        self.filter_status = state_snapshot["filter_status"]
        self.sort_by = state_snapshot["sort_by"]
        self.changes_made = True

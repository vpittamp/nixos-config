"""DetailPanel widget for displaying app classification details.

Shows comprehensive information about the currently selected application
including desktop file properties, classification reasoning, and suggestions.
"""

from textual.widgets import Static
from textual.reactive import reactive
from typing import Optional

from i3_project_manager.models.classification import AppClassification


class DetailPanel(Static):
    """Panel displaying detailed app classification information.

    Shows:
    - Application name and window class
    - Desktop file path
    - Current classification status
    - System suggestion with reasoning
    - Confidence score
    - User modification status

    Attributes:
        selected_app: Currently selected app (reactive property)
    """

    # Reactive property - updates display when app changes
    selected_app: reactive[Optional[AppClassification]] = reactive(None)

    def __init__(
        self,
        *,
        name: str = "detail-panel",
        id: str = "detail-panel",
        classes: str = "",
    ):
        """Initialize the detail panel.

        Args:
            name: Widget name
            id: Widget ID
            classes: CSS classes
        """
        super().__init__(
            name=name,
            id=id,
            classes=classes,
        )

    def watch_selected_app(
        self, old_app: Optional[AppClassification], new_app: Optional[AppClassification]
    ):
        """React to selected app changes.

        Updates panel content when a different app is selected.

        Args:
            old_app: Previously selected app
            new_app: Newly selected app
        """
        if new_app is None:
            self.update(self._render_empty())
        else:
            self.update(self._render_app(new_app))

    def _render_empty(self) -> str:
        """Render empty state when no app selected.

        Returns:
            Markdown-formatted empty state message
        """
        return """
# Application Details

*No application selected*

Use arrow keys to navigate the application list.
"""

    def _render_app(self, app: AppClassification) -> str:
        """Render detailed information for an application.

        Args:
            app: AppClassification to display

        Returns:
            Markdown-formatted app details
        """
        # Format confidence
        confidence_pct = int(app.suggestion_confidence * 100)
        confidence_bar = self._render_confidence_bar(app.suggestion_confidence)

        # Format status
        status_icon = {
            "scoped": "🟢",
            "global": "🔵",
            "unclassified": "⚪",
        }.get(app.current_scope, "?")

        # Format suggestion
        suggestion_text = (
            f"**{app.suggested_scope.upper()}**"
            if app.suggested_scope
            else "*No suggestion*"
        )

        # Format modification status
        modified_text = "✓ Modified by user" if app.user_modified else "Default"

        return f"""
# {app.app_name}

## Classification

**Status:** {status_icon} {app.current_scope.upper()}
**Modified:** {modified_text}

## Suggestion

**Recommended:** {suggestion_text}
**Confidence:** {confidence_pct}% {confidence_bar}

{self._render_reasoning(app)}

## Properties

**Window Class:** `{app.window_class}`
**Desktop File:** `{app.desktop_file}`

---

*Press [bold]s[/bold] for Scoped • [bold]g[/bold] for Global • [bold]u[/bold] for Unknown*
"""

    def _render_reasoning(self, app: AppClassification) -> str:
        """Render suggestion reasoning section.

        Args:
            app: AppClassification with reasoning

        Returns:
            Markdown-formatted reasoning text
        """
        if not app.suggestion_reasoning:
            return ""

        return f"""
**Reasoning:**
> {app.suggestion_reasoning}
"""

    def _render_confidence_bar(self, confidence: float) -> str:
        """Render a visual confidence bar.

        Args:
            confidence: Confidence value [0.0, 1.0]

        Returns:
            Unicode bar chart representation
        """
        if confidence <= 0:
            return "░░░░░░░░░░"

        # 10-segment bar
        filled = int(confidence * 10)
        empty = 10 - filled

        return "█" * filled + "░" * empty

    def set_app(self, app: Optional[AppClassification]):
        """Set the displayed application.

        Args:
            app: AppClassification to display, or None to clear
        """
        self.selected_app = app

"""Inspector screen for real-time window inspection.

Provides the main inspector UI with property display, classification status,
pattern matches, and keyboard-driven actions.
"""

from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Header, Footer, Static
from textual.containers import Horizontal, Vertical, Container, ScrollableContainer
from textual.binding import Binding
from textual.reactive import reactive
from typing import Optional

from i3_project_manager.models.inspector import WindowProperties
from i3_project_manager.tui.widgets.property_display import PropertyDisplay


class InspectorScreen(Screen):
    """Main inspector screen with property display and actions.

    Layout:
    - Header with window title
    - Property display table (left 60%)
    - Classification status panel (right 40% top)
    - Pattern matches panel (right 40% bottom)
    - Footer with keybindings

    Keyboard Bindings:
    - s: Mark as scoped
    - g: Mark as global
    - u: Unclassify (remove from lists)
    - p: Create pattern rule
    - r: Refresh properties
    - l: Toggle live mode
    - c: Copy WM_CLASS to clipboard
    - Esc: Exit inspector

    T079: InspectorScreen implementation
    FR-111 through FR-122: Inspector requirements
    """

    CSS = """
    #main-container {
        height: 100%;
        width: 100%;
    }

    #property-container {
        width: 60%;
        border: solid $primary;
    }

    #classification-container {
        width: 40%;
        height: 50%;
        border: solid $accent;
    }

    #pattern-container {
        width: 40%;
        height: 50%;
        border: solid $accent;
    }

    .panel {
        padding: 1;
    }

    .panel-title {
        background: $primary;
        color: $text;
        padding: 0 1;
        text-style: bold;
    }

    #status-bar {
        dock: bottom;
        height: 1;
        background: $surface;
        color: $text;
        padding: 0 1;
    }

    .classification-scoped {
        color: $success;
        text-style: bold;
    }

    .classification-global {
        color: $primary;
        text-style: bold;
    }

    .classification-unclassified {
        color: $warning;
    }

    .live-mode-on {
        color: $success;
        text-style: bold;
    }

    .live-mode-off {
        color: $text 50%;
    }
    """

    BINDINGS = [
        Binding("s", "classify_scoped", "Scoped", show=True),
        Binding("g", "classify_global", "Global", show=True),
        Binding("u", "unclassify", "Unclassify", show=False),
        Binding("p", "create_pattern", "Pattern", show=True),
        Binding("r", "refresh", "Refresh", show=True),
        Binding("l", "toggle_live", "Live Mode", show=True),
        Binding("c", "copy_class", "Copy Class", show=True),
        Binding("escape", "exit_inspector", "Exit", show=True),
    ]

    # Reactive state
    window_props: reactive[Optional[WindowProperties]] = reactive(None)
    live_mode: reactive[bool] = reactive(False)
    status_message: reactive[str] = reactive("")

    def __init__(self, window_props: WindowProperties):
        """Initialize inspector screen.

        Args:
            window_props: Window properties to display
        """
        super().__init__()
        self.window_props = window_props

    def compose(self) -> ComposeResult:
        """Compose the inspector layout."""
        yield Header()

        # Main content area with horizontal split
        with Horizontal(id="main-container"):
            # Left side: Property display table
            with Vertical(id="property-container", classes="panel"):
                yield Static(
                    "Window Properties",
                    id="property-title",
                    classes="panel-title",
                )
                yield PropertyDisplay(id="property-table")

            # Right side: Classification status + Pattern matches
            with Vertical(id="right-container"):
                # Top: Classification status
                with ScrollableContainer(id="classification-container", classes="panel"):
                    yield Static(
                        "Classification Status",
                        id="classification-title",
                        classes="panel-title",
                    )
                    yield Static(
                        id="classification-status",
                        classes="classification-content",
                    )

                # Bottom: Pattern matches
                with ScrollableContainer(id="pattern-container", classes="panel"):
                    yield Static(
                        "Pattern Matches",
                        id="pattern-title",
                        classes="panel-title",
                    )
                    yield Static(
                        id="pattern-matches",
                        classes="pattern-content",
                    )

        # Status bar
        yield Static(
            "Ready • Use keyboard shortcuts to inspect and classify",
            id="status-bar",
            classes="status",
        )

        yield Footer()

    def on_mount(self) -> None:
        """Initialize screen when mounted."""
        # Populate property display
        property_table = self.query_one("#property-table", PropertyDisplay)
        property_table.set_properties(self.window_props)

        # Update classification status
        self._update_classification_status()

        # Update pattern matches
        self._update_pattern_matches()

        # Focus property table
        property_table.focus()

    def _update_classification_status(self):
        """Update classification status panel."""
        if not self.window_props:
            return

        classification_panel = self.query_one("#classification-status", Static)

        # Format classification with colors
        current = self.window_props.current_classification.upper()
        source = self.window_props.format_classification_source()

        # Build status text with Rich markup
        status_lines = [
            f"**Current:** [{self._get_classification_class(current)}]{current}[/]",
            f"**Source:** {source}",
            "",
        ]

        # Add suggestion if available
        if self.window_props.suggested_classification:
            confidence_pct = int(self.window_props.suggestion_confidence * 100)
            suggested = self.window_props.suggested_classification.upper()
            status_lines.append(f"**Suggested:** {suggested} ({confidence_pct}% confidence)")
            status_lines.append("")

        # Add reasoning
        if self.window_props.reasoning:
            status_lines.append("**Reasoning:**")
            status_lines.append(self.window_props.reasoning)

        classification_panel.update("\n".join(status_lines))

    def _update_pattern_matches(self):
        """Update pattern matches panel."""
        if not self.window_props:
            return

        pattern_panel = self.query_one("#pattern-matches", Static)

        if not self.window_props.pattern_matches:
            pattern_panel.update(
                "No pattern rules match this window class.\n\n"
                "**Potential patterns:**\n"
                f"  • glob:{self.window_props.window_class}*\n"
                f"  • regex:^{self.window_props.window_class}$"
            )
        else:
            lines = [f"**Matching patterns ({len(self.window_props.pattern_matches)}):**\n"]
            for pattern in self.window_props.pattern_matches:
                lines.append(f"  • {pattern}")
            pattern_panel.update("\n".join(lines))

    def _get_classification_class(self, classification: str) -> str:
        """Get CSS class for classification color.

        Args:
            classification: Classification scope

        Returns:
            CSS class name for coloring
        """
        if "SCOPED" in classification:
            return "classification-scoped"
        elif "GLOBAL" in classification:
            return "classification-global"
        else:
            return "classification-unclassified"

    def watch_status_message(self, old: str, new: str) -> None:
        """Update status bar when status message changes."""
        if new:
            status_bar = self.query_one("#status-bar", Static)
            status_bar.update(new)

    def watch_live_mode(self, old: bool, new: bool) -> None:
        """Update live mode indicator."""
        status_bar = self.query_one("#status-bar", Static)
        if new:
            status_bar.update(
                "[live-mode-on]● Live Mode ON[/] • Properties update automatically"
            )
        else:
            status_bar.update(
                "[live-mode-off]○ Live Mode OFF[/] • Press 'l' to enable live updates"
            )

    # Action handlers (to be implemented by InspectorApp)
    async def action_classify_scoped(self) -> None:
        """Mark window as scoped (handled by app)."""
        pass  # Implemented in InspectorApp

    async def action_classify_global(self) -> None:
        """Mark window as global (handled by app)."""
        pass  # Implemented in InspectorApp

    async def action_unclassify(self) -> None:
        """Remove window classification (handled by app)."""
        pass  # Implemented in InspectorApp

    async def action_create_pattern(self) -> None:
        """Create pattern rule (handled by app)."""
        pass  # Implemented in InspectorApp

    async def action_refresh(self) -> None:
        """Refresh window properties (handled by app)."""
        pass  # Implemented in InspectorApp

    async def action_toggle_live(self) -> None:
        """Toggle live mode (handled by app)."""
        pass  # Implemented in InspectorApp

    async def action_copy_class(self) -> None:
        """Copy WM_CLASS to clipboard (handled by app)."""
        pass  # Implemented in InspectorApp

    async def action_exit_inspector(self) -> None:
        """Exit inspector."""
        self.dismiss(None)

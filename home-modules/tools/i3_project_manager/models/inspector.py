"""Data models for window inspector.

Defines WindowProperties dataclass containing all window metadata,
classification status, and reasoning for the inspector TUI.
"""

from dataclasses import dataclass, field
from typing import Optional, List


@dataclass
class WindowProperties:
    """Complete window properties for inspector display.

    Contains all metadata extracted from i3 window container plus
    classification status and AI reasoning.

    Attributes:
        window_id: i3 container ID (con_id)
        window_class: WM_CLASS property (may be None for some windows)
        instance: WM_INSTANCE property
        title: Window title (container.name)
        marks: List of i3 marks on this window
        workspace: Workspace name/number
        output: Output name (monitor)
        floating: Whether window is floating
        fullscreen: Whether window is fullscreen
        focused: Whether window is currently focused
        current_classification: Current scope (scoped/global/unclassified)
        classification_source: How classification determined (explicit/pattern/heuristic)
        suggested_classification: AI-suggested classification
        suggestion_confidence: Confidence score [0.0, 1.0]
        reasoning: Human-readable explanation of classification
        pattern_matches: List of pattern rules matching this window

    T074: WindowProperties dataclass
    FR-113: Extract all window properties
    FR-114: Extract classification status
    FR-115: Generate classification reasoning

    Examples:
        >>> props = WindowProperties(
        ...     window_id=94489280512,
        ...     window_class="Ghostty",
        ...     instance="ghostty",
        ...     title="nvim /etc/nixos/configuration.nix",
        ...     marks=["nixos"],
        ...     workspace="1",
        ...     output="eDP-1",
        ...     floating=False,
        ...     fullscreen=False,
        ...     focused=True,
        ...     current_classification="scoped",
        ...     classification_source="explicit",
        ...     suggested_classification="scoped",
        ...     suggestion_confidence=0.95,
        ...     reasoning="Terminal emulator - project-scoped by default.",
        ... )
        >>> props.window_class
        'Ghostty'
    """

    # Window metadata from i3
    window_id: int
    window_class: Optional[str]
    instance: Optional[str]
    title: str
    marks: List[str] = field(default_factory=list)
    workspace: str = ""
    output: str = ""
    floating: bool = False
    fullscreen: bool = False
    focused: bool = False

    # Classification status
    current_classification: str = "unclassified"  # scoped, global, or unclassified
    classification_source: str = "-"  # explicit, pattern:<name>, heuristic, or -
    suggested_classification: Optional[str] = None  # AI suggestion
    suggestion_confidence: float = 0.0  # [0.0, 1.0]
    reasoning: str = ""  # Human-readable explanation
    pattern_matches: List[str] = field(default_factory=list)  # Matching pattern rules

    def format_floating(self) -> str:
        """Format floating state as Yes/No.

        Returns:
            "Yes" if floating, "No" otherwise
        """
        return "Yes" if self.floating else "No"

    def format_fullscreen(self) -> str:
        """Format fullscreen state as Yes/No.

        Returns:
            "Yes" if fullscreen, "No" otherwise
        """
        return "Yes" if self.fullscreen else "No"

    def format_focused(self) -> str:
        """Format focused state as Yes/No.

        Returns:
            "Yes" if focused, "No" otherwise
        """
        return "Yes" if self.focused else "No"

    def format_marks(self) -> str:
        """Format marks list for display.

        Returns:
            Formatted mark list like "[nixos, urgent]" or "-" if empty
        """
        if not self.marks:
            return "-"
        return f"[{', '.join(self.marks)}]"

    def format_window_class(self) -> str:
        """Format window class for display.

        Returns:
            Window class or "Unknown" if None
        """
        return self.window_class or "Unknown"

    def format_classification_source(self) -> str:
        """Format classification source for human readability.

        Returns:
            Human-readable source description
        """
        if self.classification_source == "explicit":
            return "explicit (defined in app-classes.json)"
        elif self.classification_source.startswith("pattern:"):
            pattern_name = self.classification_source.split(":", 1)[1]
            return f"pattern rule: {pattern_name}"
        elif self.classification_source == "heuristic":
            return "heuristic (category-based suggestion)"
        else:
            return self.classification_source

    def to_property_dict(self) -> dict[str, str]:
        """Convert to property dictionary for display in table.

        Returns:
            Dictionary mapping property names to formatted values

        Examples:
            >>> props.to_property_dict()
            {
                'Window ID (con)': '94489280512',
                'WM_CLASS': 'Ghostty',
                'WM_INSTANCE': 'ghostty',
                'Title': 'nvim /etc/nixos/configuration.nix',
                ...
            }
        """
        return {
            "Window ID (con)": str(self.window_id),
            "WM_CLASS": self.format_window_class(),
            "WM_INSTANCE": self.instance or "-",
            "Title": self.title or "-",
            "Workspace": self.workspace or "-",
            "Output": self.output or "-",
            "i3 Marks": self.format_marks(),
            "Floating": self.format_floating(),
            "Fullscreen": self.format_fullscreen(),
            "Focused": self.format_focused(),
        }

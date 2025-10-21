"""Pattern rule data model for window class classification."""

from dataclasses import dataclass
from typing import Literal
import re
import fnmatch


@dataclass(frozen=True)
class PatternRule:
    """Pattern-based window class classification rule.

    Attributes:
        pattern: Pattern string with optional prefix (glob:, regex:, or literal)
        scope: Classification scope (scoped or global)
        priority: Precedence for matching (higher = evaluated first)
        description: Optional human-readable description

    Examples:
        >>> rule = PatternRule("glob:pwa-*", "global", priority=100)
        >>> rule.matches("pwa-youtube")
        True
        >>> rule.matches("firefox")
        False

        >>> rule = PatternRule("regex:^(neo)?vim$", "scoped", priority=90)
        >>> rule.matches("vim")
        True
        >>> rule.matches("neovim")
        True
        >>> rule.matches("gvim")
        False
    """

    pattern: str
    scope: Literal["scoped", "global"]
    priority: int = 0
    description: str = ""

    def __post_init__(self):
        """Validate pattern syntax and priority."""
        if not self.pattern:
            raise ValueError("Pattern cannot be empty")

        if self.priority < 0:
            raise ValueError("Priority must be non-negative")

        # Validate pattern syntax
        pattern_type, raw_pattern = self._parse_pattern()

        if pattern_type == "regex":
            try:
                re.compile(raw_pattern)
            except re.error as e:
                raise ValueError(f"Invalid regex pattern '{raw_pattern}': {e}")

        # Glob patterns validated by fnmatch.translate (no explicit check needed)

    def _parse_pattern(self) -> tuple[str, str]:
        """Parse pattern into (type, raw_pattern) tuple.

        Returns:
            ("glob", "pwa-*") for "glob:pwa-*"
            ("regex", "^vim$") for "regex:^vim$"
            ("literal", "Code") for "Code"
        """
        if self.pattern.startswith("glob:"):
            return ("glob", self.pattern[5:])
        elif self.pattern.startswith("regex:"):
            return ("regex", self.pattern[6:])
        else:
            return ("literal", self.pattern)

    def matches(self, window_class: str) -> bool:
        """Test if window class matches this pattern.

        Args:
            window_class: Window class string to test (e.g., "pwa-youtube")

        Returns:
            True if window class matches pattern, False otherwise
        """
        pattern_type, raw_pattern = self._parse_pattern()

        if pattern_type == "literal":
            return window_class == raw_pattern
        elif pattern_type == "glob":
            return fnmatch.fnmatch(window_class, raw_pattern)
        else:  # regex
            return bool(re.search(raw_pattern, window_class))

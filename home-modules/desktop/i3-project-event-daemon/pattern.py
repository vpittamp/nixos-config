"""Pattern rule data model for window class classification."""

from dataclasses import dataclass
from typing import Literal
import re
import fnmatch


@dataclass(frozen=True)
class PatternRule:
    """Pattern-based window class and title classification rule.

    Attributes:
        pattern: Pattern string with optional prefix (glob:, regex:, pwa:, title:, or literal)
        scope: Classification scope (scoped or global)
        priority: Precedence for matching (higher = evaluated first)
        description: Optional human-readable description

    Pattern Types:
        - literal: Exact class match (default)
        - glob: Glob pattern for class (e.g., "glob:FFPWA-*")
        - regex: Regex pattern for class (e.g., "regex:^Code$")
        - pwa: PWA detection (e.g., "pwa:YouTube") - matches FFPWA-* AND title
        - title: Title pattern (e.g., "title:^Yazi:") - matches window title

    Examples:
        >>> rule = PatternRule("glob:FFPWA-*", "global", priority=200)
        >>> rule.matches("FFPWA-01K666N2V6BQMDSBMX3AY74TY7")
        True

        >>> rule = PatternRule("pwa:YouTube", "global", priority=200)
        >>> rule.matches("FFPWA-01ABC", "Music - YouTube")
        True
        >>> rule.matches("firefox", "Music - YouTube")
        False

        >>> rule = PatternRule("title:^Yazi:", "scoped", priority=230)
        >>> rule.matches("com.mitchellh.ghostty", "Yazi: /etc/nixos")
        True
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

        if pattern_type == "regex" or pattern_type == "title_regex":
            try:
                re.compile(raw_pattern)
            except re.error as e:
                raise ValueError(f"Invalid regex pattern '{raw_pattern}': {e}")

        # Glob patterns validated by fnmatch.translate (no explicit check needed)
        # PWA and title_glob patterns have no additional validation

    def _parse_pattern(self) -> tuple[str, str]:
        """Parse pattern into (type, raw_pattern) tuple.

        Returns:
            ("glob", "pwa-*") for "glob:pwa-*"
            ("regex", "^vim$") for "regex:^vim$"
            ("literal", "Code") for "Code"
            ("pwa", "YouTube") for "pwa:YouTube"
            ("title", "^Yazi:") for "title:^Yazi:"
            ("title_glob", "*lazygit*") for "title:glob:*lazygit*"
            ("title_regex", "^k9s") for "title:regex:^k9s"
        """
        if self.pattern.startswith("pwa:"):
            keyword = self.pattern[4:]
            if not keyword:
                raise ValueError("PWA keyword cannot be empty")
            return ("pwa", keyword)
        elif self.pattern.startswith("title:glob:"):
            pattern = self.pattern[11:]
            if not pattern:
                raise ValueError("Title pattern cannot be empty")
            return ("title_glob", pattern)
        elif self.pattern.startswith("title:regex:"):
            pattern = self.pattern[12:]
            if not pattern:
                raise ValueError("Title pattern cannot be empty")
            return ("title_regex", pattern)
        elif self.pattern.startswith("title:"):
            pattern = self.pattern[6:]
            if not pattern:
                raise ValueError("Title pattern cannot be empty")
            # Default title: prefix uses regex matching
            return ("title_regex", pattern)
        elif self.pattern.startswith("glob:"):
            return ("glob", self.pattern[5:])
        elif self.pattern.startswith("regex:"):
            return ("regex", self.pattern[6:])
        else:
            return ("literal", self.pattern)

    def matches(self, window_class: str, window_title: str = "") -> bool:
        """Test if window class/title matches this pattern.

        Args:
            window_class: Window class string to test (e.g., "FFPWA-01ABC")
            window_title: Optional window title for pwa: and title: patterns

        Returns:
            True if window class/title matches pattern, False otherwise

        Examples:
            >>> rule = PatternRule("pwa:YouTube", "global", 200)
            >>> rule.matches("FFPWA-01ABC", "Music - YouTube")
            True
            >>> rule.matches("firefox", "Music - YouTube")
            False

            >>> rule = PatternRule("title:^Yazi:", "scoped", 230)
            >>> rule.matches("com.mitchellh.ghostty", "Yazi: /etc/nixos")
            True
        """
        pattern_type, raw_pattern = self._parse_pattern()

        # PWA patterns: FFPWA-* class AND title contains keyword
        if pattern_type == "pwa":
            # Must be a Firefox PWA (FFPWA-*)
            if not window_class.startswith("FFPWA-"):
                return False
            # Must have keyword in title (case-insensitive)
            if not window_title:
                return False
            return raw_pattern.lower() in window_title.lower()

        # Title patterns: match window title only
        elif pattern_type == "title_glob":
            if not window_title:
                return False
            return fnmatch.fnmatch(window_title, raw_pattern)

        elif pattern_type == "title_regex":
            if not window_title:
                return False
            return bool(re.search(raw_pattern, window_title))

        # Class patterns: match window class only
        elif pattern_type == "literal":
            return window_class == raw_pattern
        elif pattern_type == "glob":
            return fnmatch.fnmatch(window_class, raw_pattern)
        else:  # regex
            return bool(re.search(raw_pattern, window_class))

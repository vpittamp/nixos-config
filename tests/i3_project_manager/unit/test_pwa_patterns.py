"""Unit tests for PWA pattern matching (Feature 021: User Story 2, T029).

Tests PWA and title pattern matching functionality:
- pwa: prefix patterns (matches FFPWA-* class AND title)
- title: prefix patterns (matches window title only)
- Pattern precedence and priority handling
"""

import pytest
from home_modules.desktop.i3_project_event_daemon.pattern import PatternRule


class TestPWAPatternMatching:
    """Test PWA-specific pattern matching."""

    def test_pwa_pattern_with_matching_class_and_title(self):
        """PWA pattern should match when both class and title match."""
        rule = PatternRule("pwa:YouTube", "global", priority=200)

        # Should match FFPWA-* class with YouTube in title
        assert rule.matches(
            window_class="FFPWA-01K666N2V6BQMDSBMX3AY74TY7",
            window_title="Introducing ChatGPT Atlas - YouTube"
        )

    def test_pwa_pattern_with_non_ffpwa_class(self):
        """PWA pattern should NOT match non-FFPWA classes even if title matches."""
        rule = PatternRule("pwa:YouTube", "global", priority=200)

        # Regular Firefox with YouTube title should NOT match
        assert not rule.matches(
            window_class="firefox",
            window_title="YouTube - Watch Videos"
        )

    def test_pwa_pattern_with_ffpwa_but_wrong_title(self):
        """PWA pattern should NOT match FFPWA class if title doesn't match."""
        rule = PatternRule("pwa:YouTube", "global", priority=200)

        # FFPWA class but wrong title
        assert not rule.matches(
            window_class="FFPWA-01K666N2V6BQMDSBMX3AY74TY7",
            window_title="Google AI Studio"
        )

    def test_pwa_pattern_case_insensitive_title(self):
        """PWA pattern title matching should be case-insensitive."""
        rule = PatternRule("pwa:YouTube", "global", priority=200)

        # Title with different casing
        assert rule.matches(
            window_class="FFPWA-01K666N2V6BQMDSBMX3AY74TY7",
            window_title="YOUTUBE video player"
        )

    def test_pwa_pattern_partial_title_match(self):
        """PWA pattern should match if keyword appears anywhere in title."""
        rule = PatternRule("pwa:AI Studio", "global", priority=200)

        # Title contains "AI Studio" among other text
        assert rule.matches(
            window_class="FFPWA-01ABC",
            window_title="Conversation - Google AI Studio - Mozilla Firefox"
        )

    def test_multiple_pwa_patterns_different_apps(self):
        """Multiple PWA patterns should match their respective apps."""
        youtube_rule = PatternRule("pwa:YouTube", "global", priority=200)
        ai_rule = PatternRule("pwa:AI Studio", "global", priority=200)

        # YouTube PWA
        assert youtube_rule.matches(
            "FFPWA-01K666N2V6BQMDSBMX3AY74TY7",
            "Music Video - YouTube"
        )
        assert not ai_rule.matches(
            "FFPWA-01K666N2V6BQMDSBMX3AY74TY7",
            "Music Video - YouTube"
        )

        # AI Studio PWA
        assert ai_rule.matches(
            "FFPWA-02XYZ",
            "Google AI Studio - Chat"
        )
        assert not youtube_rule.matches(
            "FFPWA-02XYZ",
            "Google AI Studio - Chat"
        )


class TestTitlePatternMatching:
    """Test title-based pattern matching for terminal apps."""

    def test_title_pattern_regex_match(self):
        """Title pattern with regex should match window title."""
        rule = PatternRule("title:^Yazi:", "scoped", priority=230)

        # Should match when title starts with "Yazi:"
        assert rule.matches(
            window_class="com.mitchellh.ghostty",
            window_title="Yazi: /etc/nixos"
        )

    def test_title_pattern_no_match(self):
        """Title pattern should NOT match when title doesn't match."""
        rule = PatternRule("title:^Yazi:", "scoped", priority=230)

        # Plain ghostty without Yazi title
        assert not rule.matches(
            window_class="com.mitchellh.ghostty",
            window_title="/home/user"
        )

    def test_title_pattern_works_with_any_class(self):
        """Title patterns should work regardless of window class."""
        rule = PatternRule("title:^lazygit", "scoped", priority=220)

        # Should match in ghostty
        assert rule.matches(
            window_class="com.mitchellh.ghostty",
            window_title="lazygit - nixos"
        )

        # Should also match in alacritty
        assert rule.matches(
            window_class="Alacritty",
            window_title="lazygit - nixos"
        )

    def test_title_pattern_glob_syntax(self):
        """Title pattern can use glob syntax."""
        rule = PatternRule("title:glob:*lazygit*", "scoped", priority=220)

        # Glob match
        assert rule.matches(
            window_class="com.mitchellh.ghostty",
            window_title="Running lazygit in nixos"
        )

    def test_title_pattern_literal_syntax(self):
        """Title pattern with literal match."""
        rule = PatternRule("title:k9s", "global", priority=210)

        # Exact title match
        assert rule.matches(
            window_class="com.mitchellh.ghostty",
            window_title="k9s"
        )

        # Should NOT match partial
        assert not rule.matches(
            window_class="com.mitchellh.ghostty",
            window_title="k9s - cluster"
        )


class TestPatternPriority:
    """Test pattern priority and precedence."""

    def test_title_pattern_higher_priority_than_class(self):
        """Title patterns should take priority over class patterns when both match."""
        # This is tested via classify_window() integration
        # Just verify patterns can be created with correct priorities
        title_rule = PatternRule("title:^Yazi:", "scoped", priority=230)
        class_rule = PatternRule("com.mitchellh.ghostty", "scoped", priority=240)

        assert title_rule.priority == 230
        assert class_rule.priority == 240

    def test_pwa_pattern_priority(self):
        """PWA patterns should have standard priority around 200."""
        pwa_rule = PatternRule("pwa:YouTube", "global", priority=200)
        assert pwa_rule.priority == 200


class TestPatternValidation:
    """Test pattern validation for PWA and title patterns."""

    def test_empty_pwa_keyword_invalid(self):
        """PWA pattern must have non-empty keyword."""
        with pytest.raises(ValueError, match="PWA keyword cannot be empty"):
            PatternRule("pwa:", "global", priority=200)

    def test_empty_title_pattern_invalid(self):
        """Title pattern must have non-empty pattern."""
        with pytest.raises(ValueError, match="Title pattern cannot be empty"):
            PatternRule("title:", "scoped", priority=200)

    def test_invalid_regex_in_title_pattern(self):
        """Title pattern with invalid regex should raise ValueError."""
        with pytest.raises(ValueError, match="Invalid regex pattern"):
            PatternRule("title:regex:[invalid(", "scoped", priority=200)

    def test_pwa_pattern_validation(self):
        """PWA patterns should validate successfully."""
        # Should not raise
        rule = PatternRule("pwa:YouTube", "global", priority=200)
        assert rule.pattern == "pwa:YouTube"


class TestBackwardCompatibility:
    """Test that existing pattern types still work."""

    def test_glob_pattern_still_works(self):
        """Existing glob patterns should continue working."""
        rule = PatternRule("glob:FFPWA-*", "global", priority=200)
        assert rule.matches("FFPWA-01K666N2V6BQMDSBMX3AY74TY7")

    def test_regex_pattern_still_works(self):
        """Existing regex patterns should continue working."""
        rule = PatternRule("regex:^Code$", "scoped", priority=250)
        assert rule.matches("Code")
        assert not rule.matches("Code-OSS")

    def test_literal_pattern_still_works(self):
        """Existing literal patterns should continue working."""
        rule = PatternRule("firefox", "global", priority=150)
        assert rule.matches("firefox")
        assert not rule.matches("firefox-esr")

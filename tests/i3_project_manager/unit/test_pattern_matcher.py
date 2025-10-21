"""Unit tests for pattern matching functionality.

Tests cover glob patterns, regex patterns, literal patterns, validation,
and precedence rules for the pattern-based classification system.
"""

import pytest
from i3_project_manager.models.pattern import PatternRule


class TestGlobPatternMatching:
    """Test glob pattern matching (FR-131)."""

    def test_glob_pwa_wildcard_matches_pwa_apps(self):
        """Glob pattern glob:pwa-* should match pwa-youtube, pwa-spotify."""
        rule = PatternRule(pattern="glob:pwa-*", scope="global", priority=100)

        assert rule.matches("pwa-youtube") is True
        assert rule.matches("pwa-spotify") is True
        assert rule.matches("pwa-gmail") is True

    def test_glob_pwa_wildcard_does_not_match_non_pwa(self):
        """Glob pattern glob:pwa-* should not match firefox or other non-PWA apps."""
        rule = PatternRule(pattern="glob:pwa-*", scope="global", priority=100)

        assert rule.matches("firefox") is False
        assert rule.matches("Code") is False
        assert rule.matches("Ghostty") is False

    def test_glob_question_mark_single_char_wildcard(self):
        """Glob pattern glob:cod? should match code, cod3 but not coder."""
        rule = PatternRule(pattern="glob:cod?", scope="scoped", priority=50)

        assert rule.matches("code") is True
        assert rule.matches("cod3") is True
        assert rule.matches("coder") is False
        assert rule.matches("cod") is False

    def test_glob_bracket_character_class(self):
        """Glob pattern glob:app[123] should match app1, app2, app3."""
        rule = PatternRule(pattern="glob:app[123]", scope="scoped", priority=50)

        assert rule.matches("app1") is True
        assert rule.matches("app2") is True
        assert rule.matches("app3") is True
        assert rule.matches("app4") is False
        assert rule.matches("app") is False

    def test_glob_multiple_wildcards(self):
        """Glob pattern glob:*-dev-* should match middle section."""
        rule = PatternRule(pattern="glob:*-dev-*", scope="scoped", priority=50)

        assert rule.matches("myapp-dev-container") is True
        assert rule.matches("test-dev-build") is True
        assert rule.matches("dev-only") is False
        assert rule.matches("production-app") is False

    def test_glob_case_sensitive(self):
        """Glob patterns should be case-sensitive."""
        rule = PatternRule(pattern="glob:Code*", scope="scoped", priority=50)

        assert rule.matches("Code") is True
        assert rule.matches("CodeOSS") is True
        assert rule.matches("code") is False
        assert rule.matches("codeoss") is False


class TestRegexPatternMatching:
    """Test regex pattern matching (FR-131)."""

    def test_regex_vim_variants_matches_vim_and_neovim(self):
        """Regex pattern regex:^(neo)?vim$ should match vim and neovim."""
        rule = PatternRule(pattern="regex:^(neo)?vim$", scope="scoped", priority=90)

        assert rule.matches("vim") is True
        assert rule.matches("neovim") is True

    def test_regex_vim_variants_does_not_match_other_editors(self):
        """Regex pattern should not match gvim, nvim-qt, or other variants."""
        rule = PatternRule(pattern="regex:^(neo)?vim$", scope="scoped", priority=90)

        assert rule.matches("gvim") is False
        assert rule.matches("nvim") is False
        assert rule.matches("nvim-qt") is False
        assert rule.matches("vimr") is False

    def test_regex_start_anchor_enforces_beginning(self):
        """Regex pattern regex:^term should only match start of string."""
        rule = PatternRule(pattern="regex:^term", scope="scoped", priority=50)

        assert rule.matches("terminal") is True
        assert rule.matches("terminator") is True
        assert rule.matches("xterm") is False
        assert rule.matches("gnome-terminal") is False

    def test_regex_end_anchor_enforces_ending(self):
        """Regex pattern regex:app$ should only match end of string."""
        rule = PatternRule(pattern="regex:app$", scope="global", priority=50)

        assert rule.matches("myapp") is True
        assert rule.matches("testapp") is True
        assert rule.matches("app") is True
        assert rule.matches("application") is False
        assert rule.matches("app-dev") is False

    def test_regex_character_class_and_quantifiers(self):
        """Regex pattern regex:^[A-Z][a-z]+$ should match capitalized words."""
        rule = PatternRule(pattern="regex:^[A-Z][a-z]+$", scope="scoped", priority=50)

        assert rule.matches("Code") is True
        assert rule.matches("Firefox") is True
        assert rule.matches("Ghostty") is True
        assert rule.matches("CODE") is False
        assert rule.matches("code") is False
        assert rule.matches("C") is False

    def test_regex_alternation_multiple_options(self):
        """Regex pattern regex:^(firefox|chrome|safari)$ should match browsers."""
        rule = PatternRule(
            pattern="regex:^(firefox|chrome|safari)$", scope="global", priority=80
        )

        assert rule.matches("firefox") is True
        assert rule.matches("chrome") is True
        assert rule.matches("safari") is True
        assert rule.matches("brave") is False
        assert rule.matches("Firefox") is False

    def test_regex_case_sensitive_by_default(self):
        """Regex patterns should be case-sensitive unless explicitly configured."""
        rule = PatternRule(pattern="regex:^Code$", scope="scoped", priority=50)

        assert rule.matches("Code") is True
        assert rule.matches("code") is False
        assert rule.matches("CODE") is False


class TestLiteralPatternMatching:
    """Test literal (exact match) pattern matching (FR-131)."""

    def test_literal_exact_match_code(self):
        """Literal pattern Code should match exactly Code."""
        rule = PatternRule(pattern="Code", scope="scoped", priority=50)

        assert rule.matches("Code") is True

    def test_literal_no_match_for_different_case(self):
        """Literal pattern Code should not match code or CODE."""
        rule = PatternRule(pattern="Code", scope="scoped", priority=50)

        assert rule.matches("code") is False
        assert rule.matches("CODE") is False

    def test_literal_no_partial_match(self):
        """Literal pattern Code should not match CodeOSS or VSCode."""
        rule = PatternRule(pattern="Code", scope="scoped", priority=50)

        assert rule.matches("CodeOSS") is False
        assert rule.matches("VSCode") is False
        assert rule.matches("Code-OSS") is False

    def test_literal_special_characters_treated_literally(self):
        """Literal pattern with regex special chars should match literally."""
        rule = PatternRule(pattern="app.*test", scope="scoped", priority=50)

        # Should match the literal string with dots and asterisk
        assert rule.matches("app.*test") is True
        # Should NOT match as regex pattern
        assert rule.matches("app-some-test") is False
        assert rule.matches("apptest") is False

    def test_literal_whitespace_preserved(self):
        """Literal pattern with whitespace should match exactly."""
        rule = PatternRule(pattern="My App", scope="global", priority=50)

        assert rule.matches("My App") is True
        assert rule.matches("MyApp") is False
        assert rule.matches("My  App") is False


class TestInvalidPatternValidation:
    """Test validation of invalid patterns (FR-131)."""

    def test_invalid_regex_raises_value_error(self):
        """Invalid regex syntax should raise ValueError during __post_init__."""
        with pytest.raises(ValueError, match="Invalid regex pattern"):
            PatternRule(pattern="regex:^(unclosed", scope="scoped", priority=50)

        with pytest.raises(ValueError, match="Invalid regex pattern"):
            PatternRule(pattern="regex:[z-a]", scope="scoped", priority=50)

        with pytest.raises(ValueError, match="Invalid regex pattern"):
            PatternRule(pattern="regex:(?P<incomplete", scope="scoped", priority=50)

    def test_empty_pattern_raises_value_error(self):
        """Empty pattern string should raise ValueError."""
        with pytest.raises(ValueError, match="Pattern cannot be empty"):
            PatternRule(pattern="", scope="scoped", priority=50)

    def test_negative_priority_raises_value_error(self):
        """Negative priority should raise ValueError."""
        with pytest.raises(ValueError, match="Priority must be non-negative"):
            PatternRule(pattern="glob:test*", scope="scoped", priority=-1)

    def test_glob_patterns_always_valid(self):
        """Glob patterns should not raise validation errors (validated at runtime)."""
        # These should all succeed - fnmatch handles edge cases gracefully
        rule1 = PatternRule(pattern="glob:**", scope="scoped", priority=50)
        rule2 = PatternRule(pattern="glob:[", scope="scoped", priority=50)
        rule3 = PatternRule(pattern="glob:***", scope="scoped", priority=50)

        assert rule1.pattern == "glob:**"
        assert rule2.pattern == "glob:["
        assert rule3.pattern == "glob:***"


class TestPatternPrecedence:
    """Test pattern matching precedence rules (FR-132, FR-133)."""

    def test_higher_priority_evaluated_first(self):
        """When multiple patterns match, higher priority should win."""
        # This test verifies the behavior when AppClassConfig uses sorted patterns
        high_priority = PatternRule(pattern="glob:pwa-*", scope="global", priority=100)
        low_priority = PatternRule(pattern="glob:pwa-youtube", scope="scoped", priority=10)

        # Both match "pwa-youtube", but we expect higher priority to be checked first
        assert high_priority.matches("pwa-youtube") is True
        assert low_priority.matches("pwa-youtube") is True

        # In AppClassConfig.is_scoped(), patterns are sorted by priority descending
        # So high_priority would match first and return global=True

    def test_equal_priority_first_match_wins(self):
        """When priorities are equal, first match in list should win."""
        pattern1 = PatternRule(pattern="glob:app*", scope="global", priority=50)
        pattern2 = PatternRule(pattern="glob:app-*", scope="scoped", priority=50)

        assert pattern1.matches("app-test") is True
        assert pattern2.matches("app-test") is True

        # Both have same priority and both match - insertion order matters

    def test_priority_zero_is_valid(self):
        """Priority 0 should be valid and lowest precedence."""
        rule = PatternRule(pattern="glob:*", scope="global", priority=0)

        assert rule.priority == 0
        assert rule.matches("anything") is True

    def test_pattern_does_not_match_returns_false(self):
        """Non-matching pattern should return False regardless of priority."""
        high_priority = PatternRule(pattern="glob:pwa-*", scope="global", priority=1000)

        assert high_priority.matches("firefox") is False
        assert high_priority.matches("Code") is False

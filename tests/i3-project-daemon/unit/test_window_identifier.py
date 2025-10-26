"""
Unit tests for window class normalization and tiered matching.

Tests the 3-tier matching strategy:
1. Exact match (case-sensitive)
2. Instance match (WM_CLASS instance field, case-insensitive)
3. Normalized match (strip reverse-domain prefix, lowercase)

Part of Feature 039 - Task T023
Success Criteria: SC-013 (20+ apps tested), SC-003 (95% successful matches)
"""

import pytest
from typing import Tuple


# Simplified window identifier functions for testing
# (In production, these would be in services/window_identifier.py)

def normalize_class(class_name: str) -> str:
    """
    Strip reverse-domain prefix and lowercase.

    Examples:
        "com.mitchellh.ghostty" → "ghostty"
        "org.kde.dolphin" → "dolphin"
        "firefox" → "firefox"
    """
    if not class_name:
        return "unknown"

    if "." in class_name:
        parts = class_name.split(".")
        # Check if first part is reverse-domain prefix
        if len(parts) > 1 and parts[0].lower() in {"com", "org", "io", "net", "dev", "app", "de"}:
            class_name = parts[-1]  # Take last component

    return class_name.lower()


def match_window_class(
    expected: str, actual_class: str, actual_instance: str = ""
) -> Tuple[bool, str]:
    """
    Match window class with tiered fallback strategy.

    Args:
        expected: Expected class name (from config/registry)
        actual_class: Actual WM_CLASS class field
        actual_instance: Actual WM_CLASS instance field

    Returns:
        (matched, match_type)
        Match types: "exact", "instance", "normalized", "none"
    """
    # Tier 1: Exact match (case-sensitive)
    if expected == actual_class:
        return (True, "exact")

    # Tier 2: Instance match (case-insensitive)
    if actual_instance and expected.lower() == actual_instance.lower():
        return (True, "instance")

    # Tier 3: Normalized match
    expected_norm = normalize_class(expected)
    actual_norm = normalize_class(actual_class)
    if expected_norm == actual_norm:
        return (True, "normalized")

    return (False, "none")


class TestWindowClassNormalization:
    """Tests for normalize_class() function."""

    def test_simple_class_names(self):
        """Test normalization of simple class names (no dots)."""
        assert normalize_class("firefox") == "firefox"
        assert normalize_class("Chrome") == "chrome"
        assert normalize_class("Code") == "code"
        assert normalize_class("Alacritty") == "alacritty"

    def test_reverse_domain_notation_com(self):
        """Test normalization of com.* reverse-domain notation."""
        assert normalize_class("com.mitchellh.ghostty") == "ghostty"
        assert normalize_class("com.google.Chrome") == "chrome"
        assert normalize_class("com.github.Electron") == "electron"

    def test_reverse_domain_notation_org(self):
        """Test normalization of org.* reverse-domain notation."""
        assert normalize_class("org.kde.dolphin") == "dolphin"
        assert normalize_class("org.gnome.Nautilus") == "nautilus"
        assert normalize_class("org.mozilla.firefox") == "firefox"

    def test_reverse_domain_notation_io(self):
        """Test normalization of io.* reverse-domain notation."""
        assert normalize_class("io.github.shiftey.Desktop") == "desktop"
        assert normalize_class("io.elementary.appcenter") == "appcenter"

    def test_reverse_domain_notation_net(self):
        """Test normalization of net.* reverse-domain notation."""
        assert normalize_class("net.sourceforge.qterminal") == "qterminal"

    def test_reverse_domain_notation_de(self):
        """Test normalization of de.* reverse-domain notation (German)."""
        assert normalize_class("de.haeckerfelix.Shortwave") == "shortwave"

    def test_multiple_dot_segments(self):
        """Test classes with multiple dot segments."""
        assert normalize_class("com.example.app.MainWindow") == "mainwindow"
        assert normalize_class("org.freedesktop.IBus.Panel") == "panel"

    def test_non_reverse_domain_dots(self):
        """Test classes with dots that aren't reverse-domain notation."""
        # If first segment isn't recognized prefix, keep full name
        assert normalize_class("FFPWA.some.id") == "ffpwa.some.id"
        assert normalize_class("Random.Dots.Here") == "random.dots.here"

    def test_empty_and_none(self):
        """Test edge cases: empty strings, None."""
        assert normalize_class("") == "unknown"
        assert normalize_class("   ") == "   "  # Whitespace preserved

    def test_case_sensitivity(self):
        """Test that normalization lowercases."""
        assert normalize_class("UPPERCASE") == "uppercase"
        assert normalize_class("MixedCase") == "mixedcase"
        assert normalize_class("com.Example.App") == "app"


class TestAliasMatching:
    """Tests for window class alias support (T048)."""

    def test_single_alias_match(self):
        """Test matching window against a single alias."""
        # Config: "ghostty" with aliases ["com.mitchellh.ghostty"]
        aliases = ["com.mitchellh.ghostty"]

        # Should match the alias
        for alias in aliases:
            matched, match_type = match_window_class(alias, "com.mitchellh.ghostty", "ghostty")
            assert matched is True, f"Should match alias {alias}"

    def test_multiple_aliases_match(self):
        """Test matching window against multiple aliases."""
        # Config: "ghostty" with multiple alias formats
        test_cases = [
            ("ghostty", "ghostty", "ghostty", True),  # Simple name
            ("com.mitchellh.ghostty", "com.mitchellh.ghostty", "ghostty", True),  # Full reverse-domain
            ("Ghostty", "com.mitchellh.ghostty", "ghostty", True),  # Case variation
        ]

        for alias, actual_class, actual_instance, should_match in test_cases:
            matched, _ = match_window_class(alias, actual_class, actual_instance)
            assert matched == should_match, f"Alias {alias} match={matched}, expected={should_match}"

    def test_alias_priority_with_normalization(self):
        """Test that aliases work with tiered matching."""
        # All these should successfully match "com.mitchellh.ghostty"
        test_configs = [
            "ghostty",  # Normalized match
            "com.mitchellh.ghostty",  # Exact match
            "Ghostty",  # Instance or normalized match
        ]

        for config in test_configs:
            matched, match_type = match_window_class(config, "com.mitchellh.ghostty", "ghostty")
            assert matched is True, f"Config {config} should match via some tier"
            assert match_type in ["exact", "instance", "normalized"], f"Unexpected match type: {match_type}"

    def test_vscode_aliases(self):
        """Test VS Code with multiple alias formats."""
        # VS Code can be referred to as: "vscode", "code", "Code", "visual-studio-code"
        vscode_aliases = ["vscode", "code", "Code"]

        for alias in vscode_aliases:
            matched, match_type = match_window_class(alias, "Code", "code")
            assert matched is True, f"VS Code alias {alias} should match"

    def test_firefox_aliases(self):
        """Test Firefox with multiple alias formats."""
        # Firefox can be: "firefox", "Firefox", "org.mozilla.firefox"
        firefox_aliases = ["firefox", "Firefox", "org.mozilla.firefox"]

        for alias in firefox_aliases:
            matched, _ = match_window_class(alias, "firefox", "Navigator")
            assert matched is True, f"Firefox alias {alias} should match"


class TestTieredMatching:
    """Tests for tiered window class matching."""

    def test_tier1_exact_match(self):
        """Test Tier 1: Exact match (case-sensitive)."""
        # Exact matches
        assert match_window_class("firefox", "firefox", "") == (True, "exact")
        assert match_window_class("Code", "Code", "") == (True, "exact")
        assert match_window_class("Alacritty", "Alacritty", "") == (True, "exact")

        # Case mismatch - should NOT match at tier 1
        assert match_window_class("firefox", "Firefox", "") != (True, "exact")

    def test_tier2_instance_match(self):
        """Test Tier 2: Instance match (case-insensitive)."""
        # Instance matches
        assert match_window_class("ghostty", "com.mitchellh.ghostty", "ghostty") == (True, "instance")
        assert match_window_class("code", "Code", "code") == (True, "instance")
        assert match_window_class("dolphin", "org.kde.dolphin", "dolphin") == (True, "instance")

        # Case-insensitive instance matching
        assert match_window_class("Ghostty", "com.mitchellh.ghostty", "ghostty") == (True, "instance")
        assert match_window_class("ghostty", "com.mitchellh.ghostty", "Ghostty") == (True, "instance")

    def test_tier3_normalized_match(self):
        """Test Tier 3: Normalized match."""
        # Normalized matches (strips reverse-domain prefix)
        assert match_window_class("ghostty", "com.mitchellh.ghostty", "") == (True, "normalized")
        assert match_window_class("dolphin", "org.kde.dolphin", "") == (True, "normalized")
        assert match_window_class("firefox", "org.mozilla.firefox", "") == (True, "normalized")

        # Case-insensitive normalized match
        assert match_window_class("Ghostty", "com.mitchellh.ghostty", "") == (True, "normalized")
        assert match_window_class("DOLPHIN", "org.kde.dolphin", "") == (True, "normalized")

    def test_no_match(self):
        """Test when no tier matches."""
        matched, match_type = match_window_class("expected", "completely-different", "also-different")
        assert matched is False
        assert match_type == "none"

    def test_priority_order(self):
        """Test that exact match takes priority over instance match."""
        # If exact match succeeds, should use "exact" not "instance"
        assert match_window_class("ghostty", "ghostty", "ghostty") == (True, "exact")

        # If exact fails but instance succeeds
        assert match_window_class("ghostty", "com.mitchellh.ghostty", "ghostty") == (True, "instance")

        # If exact and instance fail but normalized succeeds
        assert match_window_class("ghostty", "com.mitchellh.ghostty", "other") == (True, "normalized")


class TestRealWorldApplications:
    """
    Test window class matching with 20+ real-world applications.

    Success Criteria: SC-013 (20+ apps), SC-003 (95% successful matches)
    """

    @pytest.fixture
    def real_world_apps(self):
        """
        Real application window classes collected from actual systems.

        Format: (app_name_in_config, actual_wm_class, actual_wm_instance)
        """
        return [
            # Terminal emulators
            ("ghostty", "com.mitchellh.ghostty", "ghostty"),
            ("alacritty", "Alacritty", "Alacritty"),
            ("kitty", "kitty", "kitty"),
            ("wezterm", "org.wezfurlong.wezterm", "wezterm"),
            ("konsole", "org.kde.konsole", "konsole"),

            # Browsers
            ("firefox", "firefox", "Navigator"),
            ("chrome", "Google-chrome", "google-chrome"),
            ("brave", "brave-browser", "brave-browser"),
            ("chromium", "Chromium", "chromium"),

            # Editors and IDEs
            ("vscode", "Code", "code"),
            ("neovim", "neovim", "neovim"),
            ("emacs", "Emacs", "emacs"),
            ("sublime", "sublime_text", "sublime_text"),
            ("intellij", "jetbrains-idea", "jetbrains-idea"),

            # File managers
            ("dolphin", "org.kde.dolphin", "dolphin"),
            ("nautilus", "org.gnome.Nautilus", "org.gnome.Nautilus"),
            ("thunar", "Thunar", "thunar"),
            ("pcmanfm", "Pcmanfm", "pcmanfm"),

            # Communication
            ("slack", "Slack", "slack"),
            ("discord", "discord", "discord"),
            ("teams", "Microsoft Teams - Preview", "microsoft teams - preview"),
            ("zoom", "zoom", "zoom"),

            # Development tools
            ("postman", "Postman", "postman"),
            ("dbeaver", "DBeaver", "DBeaver"),
            ("gitkraken", "GitKraken", "gitkraken"),

            # PWAs (Firefox)
            ("youtube-pwa", "FFPWA-01234567890", "ffpwa-01234567890"),
            ("google-chat-pwa", "FFPWA-chat12345", "ffpwa-chat12345"),

            # Utilities
            ("calculator", "gnome-calculator", "gnome-calculator"),
            ("calendar", "org.gnome.Calendar", "org.gnome.Calendar"),
            ("system-monitor", "gnome-system-monitor", "gnome-system-monitor"),
        ]

    def test_all_apps_match_successfully(self, real_world_apps):
        """
        Test that all 20+ real-world apps can be matched successfully.

        Uses tiered matching to find best match.
        """
        total_apps = len(real_world_apps)
        successful_matches = 0

        for app_config, actual_class, actual_instance in real_world_apps:
            matched, match_type = match_window_class(app_config, actual_class, actual_instance)

            if matched:
                successful_matches += 1
            else:
                print(f"\n❌ Failed to match: config={app_config}, class={actual_class}, instance={actual_instance}")

        # Calculate success rate
        success_rate = (successful_matches / total_apps) * 100

        assert total_apps >= 20, f"Need at least 20 apps, got {total_apps}"
        assert success_rate >= 95, f"Success rate {success_rate:.1f}% < 95% (SC-003)"

        print(f"\n✓ Window class matching test:")
        print(f"  - Total apps tested: {total_apps}")
        print(f"  - Successful matches: {successful_matches}")
        print(f"  - Success rate: {success_rate:.1f}%")

    def test_exact_match_apps(self, real_world_apps):
        """Test apps that should match via Tier 1 (exact)."""
        exact_match_apps = [
            ("firefox", "firefox", "Navigator"),
            ("kitty", "kitty", "kitty"),
            ("discord", "discord", "discord"),
        ]

        for app_config, actual_class, actual_instance in exact_match_apps:
            matched, match_type = match_window_class(app_config, actual_class, actual_instance)
            assert matched is True
            assert match_type == "exact", f"{app_config} should match exactly"

    def test_instance_match_apps(self, real_world_apps):
        """Test apps that should match via Tier 2 (instance)."""
        instance_match_apps = [
            ("ghostty", "com.mitchellh.ghostty", "ghostty"),
            ("dolphin", "org.kde.dolphin", "dolphin"),
            ("wezterm", "org.wezfurlong.wezterm", "wezterm"),
        ]

        for app_config, actual_class, actual_instance in instance_match_apps:
            matched, match_type = match_window_class(app_config, actual_class, actual_instance)
            assert matched is True
            assert match_type == "instance", f"{app_config} should match via instance"

    def test_normalized_match_apps(self):
        """Test apps that should match via Tier 3 (normalized)."""
        # Apps without helpful instance field, rely on normalization
        normalized_apps = [
            ("nautilus", "org.gnome.Nautilus", "org.gnome.Nautilus"),
            ("calendar", "org.gnome.Calendar", "org.gnome.Calendar"),
        ]

        for app_config, actual_class, actual_instance in normalized_apps:
            matched, match_type = match_window_class(app_config, actual_class, actual_instance)
            assert matched is True
            assert match_type == "normalized", f"{app_config} should match via normalization"

    def test_case_insensitive_matching(self):
        """Test case-insensitive matching works across tiers."""
        # Config uses lowercase, window uses uppercase
        test_cases = [
            ("chrome", "Google-chrome", "google-chrome"),  # Instance match
            ("vscode", "Code", "code"),  # Instance match
            ("alacritty", "Alacritty", "Alacritty"),  # Exact fails, falls to normalized
        ]

        for app_config, actual_class, actual_instance in test_cases:
            matched, match_type = match_window_class(app_config, actual_class, actual_instance)
            assert matched is True, f"{app_config} should match {actual_class} case-insensitively"

    def test_pwa_instance_differentiation(self):
        """
        Test PWA instance differentiation.

        Firefox PWAs use FFPWA-{id} pattern. Instance field helps differentiate.
        """
        youtube_pwa = ("youtube-pwa", "FFPWA-01234567890", "ffpwa-01234567890")
        chat_pwa = ("google-chat-pwa", "FFPWA-chat12345", "ffpwa-chat12345")

        # YouTube PWA
        matched_yt, match_type_yt = match_window_class(*youtube_pwa)
        assert matched_yt is False  # Should NOT match (different IDs)

        # But if we configure with FFPWA class
        matched_yt2, match_type_yt2 = match_window_class("FFPWA-01234567890", "FFPWA-01234567890", "ffpwa-01234567890")
        assert matched_yt2 is True
        assert match_type_yt2 == "exact"

        # Chat PWA (different instance)
        matched_chat, match_type_chat = match_window_class("FFPWA-chat12345", "FFPWA-chat12345", "ffpwa-chat12345")
        assert matched_chat is True
        assert match_type_chat == "exact"


class TestEdgeCases:
    """Edge case tests for window class matching."""

    def test_empty_strings(self):
        """Test handling of empty/None values."""
        # Empty expected
        matched, match_type = match_window_class("", "firefox", "Navigator")
        assert matched is False

        # Empty actual_class
        matched, match_type = match_window_class("firefox", "", "Navigator")
        assert matched is False

        # All empty
        matched, match_type = match_window_class("", "", "")
        assert matched is False

    def test_whitespace_handling(self):
        """Test trimming/handling of whitespace."""
        # Exact match with whitespace
        matched, match_type = match_window_class("firefox", "firefox ", "")
        assert matched is False  # Exact match is strict

        # Normalized would lowercase but not trim
        assert normalize_class("  spaces  ") == "  spaces  "

    def test_special_characters(self):
        """Test classes with special characters."""
        test_cases = [
            ("my-app", "my-app", "my-app"),
            ("app_name", "app_name", "app_name"),
            ("App@Name", "App@Name", ""),
        ]

        for expected, actual_class, actual_instance in test_cases:
            matched, _ = match_window_class(expected, actual_class, actual_instance)
            assert matched is True

    def test_numeric_classes(self):
        """Test classes with numbers."""
        assert normalize_class("app123") == "app123"
        assert normalize_class("com.example.app2") == "app2"

    def test_very_long_class_names(self):
        """Test handling of very long class names."""
        long_class = "com.very.long.domain.name.with.many.segments.application.name"
        normalized = normalize_class(long_class)
        assert normalized == "name"  # Should take last segment


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

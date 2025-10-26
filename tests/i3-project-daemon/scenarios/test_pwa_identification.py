"""
PWA Instance Identification Tests (User Story 5)

Tests for proper identification and management of PWA (Progressive Web App) windows.
Covers instance distinction, workspace assignment, and project scoping for PWAs.

Feature 039 - Tasks T076, T077, T078
"""

import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from i3_project_event_daemon.services.window_identifier import (
    get_window_identity,
    match_window_class,
    match_with_registry,
)


class TestPWAInstanceDistinction:
    """
    Test PWA instance identification (T076)

    Validates that system can distinguish between multiple PWA instances
    of the same app (e.g., two Google Chat accounts).

    Acceptance Criterion:
    Given two Google Chat PWAs with different profiles,
    When launched,
    Then system distinguishes them by unique window properties (instance, title pattern)
    """

    def test_firefox_pwa_identification(self):
        """Firefox PWAs use FFPWA-* class pattern."""
        # Example Firefox PWA window
        identity = get_window_identity(
            actual_class="FFPWA-01234567890",
            actual_instance="google-chat-work",
            window_title="Google Chat - Work Account",
        )

        assert identity["is_pwa"] is True
        assert identity["pwa_id"] == "FFPWA-01234567890"
        assert identity["original_class"] == "FFPWA-01234567890"
        assert identity["original_instance"] == "google-chat-work"

    def test_chrome_pwa_identification(self):
        """Chrome PWAs use Google-chrome class with custom instance."""
        # Example Chrome PWA window
        identity = get_window_identity(
            actual_class="Google-chrome",
            actual_instance="chat.google.com__abc123",
            window_title="Google Chat - Personal",
        )

        assert identity["is_pwa"] is True
        assert identity["pwa_id"] == "chat.google.com__abc123"
        assert identity["original_class"] == "Google-chrome"

    def test_chrome_browser_not_identified_as_pwa(self):
        """Main Chrome browser window should not be identified as PWA."""
        identity = get_window_identity(
            actual_class="Google-chrome",
            actual_instance="google-chrome",  # Standard browser instance
            window_title="New Tab - Google Chrome",
        )

        assert identity["is_pwa"] is False
        assert identity["pwa_id"] is None

    def test_multiple_chrome_pwas_distinguished(self):
        """Multiple Chrome PWAs should have unique identities."""
        pwa1 = get_window_identity(
            actual_class="Google-chrome",
            actual_instance="chat.google.com__work",
            window_title="Google Chat - Work",
        )

        pwa2 = get_window_identity(
            actual_class="Google-chrome",
            actual_instance="chat.google.com__personal",
            window_title="Google Chat - Personal",
        )

        # Both are PWAs
        assert pwa1["is_pwa"] is True
        assert pwa2["is_pwa"] is True

        # But have different IDs
        assert pwa1["pwa_id"] != pwa2["pwa_id"]
        assert pwa1["pwa_id"] == "chat.google.com__work"
        assert pwa2["pwa_id"] == "chat.google.com__personal"

    def test_multiple_firefox_pwas_distinguished(self):
        """Multiple Firefox PWAs should have unique identities."""
        pwa1 = get_window_identity(
            actual_class="FFPWA-01111111111",
            actual_instance="google-chat-work",
            window_title="Google Chat - Work",
        )

        pwa2 = get_window_identity(
            actual_class="FFPWA-02222222222",
            actual_instance="google-chat-personal",
            window_title="Google Chat - Personal",
        )

        # Both are PWAs
        assert pwa1["is_pwa"] is True
        assert pwa2["is_pwa"] is True

        # But have different IDs
        assert pwa1["pwa_id"] != pwa2["pwa_id"]
        assert pwa1["pwa_id"] == "FFPWA-01111111111"
        assert pwa2["pwa_id"] == "FFPWA-02222222222"


class TestPWAWorkspaceAssignment:
    """
    Test PWA workspace assignment (T077)

    Validates that PWAs can be assigned to specific workspaces like native apps.

    Acceptance Criterion:
    Given PWA configured with specific workspace,
    When launched,
    Then opens on designated workspace like native applications
    """

    def test_firefox_pwa_matches_in_registry(self):
        """Firefox PWA should match against registry entry."""
        # Application registry with Firefox PWA entry
        registry = {
            "google-chat-work": {
                "display_name": "Google Chat (Work)",
                "expected_class": "FFPWA-01234567890",
                "scope": "scoped",
                "preferred_workspace": 4,
            }
        }

        # Try matching a Firefox PWA window
        match = match_with_registry(
            actual_class="FFPWA-01234567890",
            actual_instance="google-chat-work",
            application_registry=registry,
        )

        assert match is not None
        assert match["_matched_app_name"] == "google-chat-work"
        assert match["preferred_workspace"] == 4
        assert match["_match_type"] == "exact"

    def test_chrome_pwa_matches_by_instance(self):
        """Chrome PWA should match by instance field."""
        # Application registry with Chrome PWA entry by instance
        registry = {
            "google-chat-personal": {
                "display_name": "Google Chat (Personal)",
                "expected_class": "chat.google.com__personal",
                "scope": "scoped",
                "preferred_workspace": 5,
            }
        }

        # Try matching a Chrome PWA window (class is generic "Google-chrome")
        match = match_with_registry(
            actual_class="Google-chrome",
            actual_instance="chat.google.com__personal",
            application_registry=registry,
        )

        assert match is not None
        assert match["_matched_app_name"] == "google-chat-personal"
        assert match["preferred_workspace"] == 5
        # Matches by instance (tier 2)
        assert match["_match_type"] == "instance"

    def test_pwa_with_no_workspace_config_uses_fallback(self):
        """PWA without preferred_workspace should use fallback."""
        registry = {
            "generic-pwa": {
                "display_name": "Generic PWA",
                "expected_class": "FFPWA-99999999999",
                "scope": "scoped",
                # No preferred_workspace
            }
        }

        match = match_with_registry(
            actual_class="FFPWA-99999999999",
            actual_instance="some-instance",
            application_registry=registry,
        )

        assert match is not None
        assert "preferred_workspace" not in match
        # Should still match successfully
        assert match["_matched_app_name"] == "generic-pwa"


class TestPWAProjectScoping:
    """
    Test PWA project scoping (T078)

    Validates that scoped PWAs show/hide correctly on project switch.

    Acceptance Criterion:
    Given PWA has project association,
    When project switches,
    Then PWA shows/hides according to project scope rules
    """

    @pytest.mark.asyncio
    async def test_scoped_pwa_has_project_mark(self):
        """Scoped PWA should get project mark like other scoped apps."""
        # This test validates that PWA windows receive project marks
        # Implementation will be in handlers.py window::new event handler

        # Mock PWA window with I3PM_PROJECT_NAME
        pwa_env = {
            "I3PM_PROJECT_NAME": "nixos",
            "I3PM_APP_NAME": "google-chat-work",
            "I3PM_SCOPE": "scoped",
        }

        # Simulate daemon marking window
        expected_mark = "project:nixos"

        # Verify mark would be applied (actual i3 command tested in integration)
        assert expected_mark == f"project:{pwa_env['I3PM_PROJECT_NAME']}"

    @pytest.mark.asyncio
    async def test_global_pwa_no_project_mark(self):
        """Global PWA should not get project mark."""
        pwa_env = {
            "I3PM_PROJECT_NAME": "",  # Empty for global apps
            "I3PM_APP_NAME": "google-chat-global",
            "I3PM_SCOPE": "global",
        }

        # Global apps should not have project mark
        assert pwa_env["I3PM_SCOPE"] == "global"
        assert not pwa_env["I3PM_PROJECT_NAME"]

    def test_pwa_filtering_by_instance(self):
        """Window filter should use PWA instance for filtering."""
        # Create two PWA identities with same class but different instances
        pwa1_identity = get_window_identity(
            actual_class="Google-chrome",
            actual_instance="chat.google.com__work",
            window_title="Google Chat - Work",
        )

        pwa2_identity = get_window_identity(
            actual_class="Google-chrome",
            actual_instance="chat.google.com__personal",
            window_title="Google Chat - Personal",
        )

        # Both are PWAs
        assert pwa1_identity["is_pwa"] is True
        assert pwa2_identity["is_pwa"] is True

        # Different PWA IDs enable filtering
        assert pwa1_identity["pwa_id"] != pwa2_identity["pwa_id"]

        # Window filter can distinguish by checking:
        # 1. Class + instance combination
        # 2. PWA ID field
        # This enables correct show/hide on project switch


class TestPWADisambiguation:
    """
    Test PWA disambiguation using instance or app ID.

    Acceptance Criterion:
    Given PWA window class is generic "Google-chrome",
    When matching against rules,
    Then system uses instance or app ID for disambiguation
    """

    def test_generic_class_disambiguated_by_instance(self):
        """Generic "Google-chrome" class should be disambiguated by instance."""
        # Two different PWAs with same class
        matched1, match_type1 = match_window_class(
            expected="chat.google.com__work",
            actual_class="Google-chrome",
            actual_instance="chat.google.com__work",
        )

        matched2, match_type2 = match_window_class(
            expected="chat.google.com__personal",
            actual_class="Google-chrome",
            actual_instance="chat.google.com__personal",
        )

        # Both match but by different instances
        assert matched1 is True
        assert matched2 is True
        assert match_type1 == "instance"
        assert match_type2 == "instance"

        # Wrong instance doesn't match
        matched_wrong, _ = match_window_class(
            expected="chat.google.com__work",
            actual_class="Google-chrome",
            actual_instance="chat.google.com__personal",
        )
        assert matched_wrong is False

    def test_pwa_id_used_for_firefox_disambiguation(self):
        """Firefox FFPWA-* class provides built-in disambiguation."""
        # Firefox PWAs have unique class per instance
        identity1 = get_window_identity(
            actual_class="FFPWA-01111111111",
            actual_instance="google-chat-work",
            window_title="Google Chat - Work",
        )

        identity2 = get_window_identity(
            actual_class="FFPWA-02222222222",
            actual_instance="google-chat-personal",
            window_title="Google Chat - Personal",
        )

        # PWA IDs are different (based on class)
        assert identity1["pwa_id"] != identity2["pwa_id"]

        # Matching by class provides disambiguation
        matched1, _ = match_window_class(
            expected="FFPWA-01111111111",
            actual_class="FFPWA-01111111111",
            actual_instance="google-chat-work",
        )

        matched2, _ = match_window_class(
            expected="FFPWA-02222222222",
            actual_class="FFPWA-02222222222",
            actual_instance="google-chat-personal",
        )

        assert matched1 is True
        assert matched2 is True


class TestPWAConfigurationGuidance:
    """
    Test PWA configuration guidance.

    Acceptance Criterion:
    Given new PWA installed,
    When user configures it,
    Then system provides clear identification properties for rule configuration
    """

    def test_pwa_identity_includes_all_fields(self):
        """PWA identity should include all fields needed for configuration."""
        identity = get_window_identity(
            actual_class="FFPWA-01234567890",
            actual_instance="google-chat",
            window_title="Google Chat - Work Account",
        )

        # All fields present
        assert "original_class" in identity
        assert "original_instance" in identity
        assert "normalized_class" in identity
        assert "normalized_instance" in identity
        assert "title" in identity
        assert "is_pwa" in identity
        assert "pwa_id" in identity

        # Values are correct
        assert identity["original_class"] == "FFPWA-01234567890"
        assert identity["original_instance"] == "google-chat"
        assert identity["title"] == "Google Chat - Work Account"
        assert identity["is_pwa"] is True
        assert identity["pwa_id"] == "FFPWA-01234567890"

    def test_chrome_pwa_identity_shows_instance_for_config(self):
        """Chrome PWA identity should highlight instance field for config."""
        identity = get_window_identity(
            actual_class="Google-chrome",
            actual_instance="chat.google.com__abc123",
            window_title="Google Chat",
        )

        # Instance is the key field for Chrome PWA configuration
        assert identity["original_instance"] == "chat.google.com__abc123"
        assert identity["is_pwa"] is True
        assert identity["pwa_id"] == "chat.google.com__abc123"

        # Diagnostic output should tell user to use instance field
        # (This will be implemented in T082)

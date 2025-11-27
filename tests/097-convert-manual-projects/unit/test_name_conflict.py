"""
Unit tests for project name conflict resolution.

Feature 097: Git-Based Project Discovery and Management
Task T016: Test conflict name resolution logic

Tests the `generate_unique_name()` function that handles cases where
multiple repositories have the same directory name.
"""

import pytest


class TestNameConflictResolution:
    """Test cases for resolving project name conflicts."""

    def test_unique_name_returned_unchanged(self):
        """A unique name should be returned as-is."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            generate_unique_name
        )

        existing_names = {"project-a", "project-b", "project-c"}
        result = generate_unique_name("my-app", existing_names)

        assert result == "my-app"

    def test_conflicting_name_gets_suffix_2(self):
        """First conflict should get -2 suffix."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            generate_unique_name
        )

        existing_names = {"my-app", "other-project"}
        result = generate_unique_name("my-app", existing_names)

        assert result == "my-app-2"

    def test_multiple_conflicts_increment_suffix(self):
        """Multiple conflicts should increment suffix: -2, -3, etc."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            generate_unique_name
        )

        existing_names = {"my-app", "my-app-2", "my-app-3"}
        result = generate_unique_name("my-app", existing_names)

        assert result == "my-app-4"

    def test_empty_existing_names_returns_unchanged(self):
        """With no existing names, any name should be unique."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            generate_unique_name
        )

        existing_names = set()
        result = generate_unique_name("new-project", existing_names)

        assert result == "new-project"

    def test_gaps_in_suffixes_uses_next_available(self):
        """Should use next available number, even if there are gaps."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            generate_unique_name
        )

        # Existing: my-app, my-app-2, my-app-4 (gap at 3)
        existing_names = {"my-app", "my-app-2", "my-app-4"}
        result = generate_unique_name("my-app", existing_names)

        # Should fill the gap: -3
        assert result == "my-app-3"

    def test_case_sensitive_matching(self):
        """Name matching should be case-sensitive."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            generate_unique_name
        )

        existing_names = {"My-App", "MY-APP"}
        result = generate_unique_name("my-app", existing_names)

        # Different case = no conflict
        assert result == "my-app"

    def test_special_characters_in_name(self):
        """Should handle names with dashes and underscores."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            generate_unique_name
        )

        existing_names = {"my-cool_project", "my-cool_project-2"}
        result = generate_unique_name("my-cool_project", existing_names)

        assert result == "my-cool_project-3"


class TestNameDerivationFromPath:
    """Test cases for deriving project names from directory paths."""

    def test_simple_directory_name(self):
        """Should use directory basename as project name."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            derive_project_name
        )
        from pathlib import Path

        result = derive_project_name(Path("/home/user/projects/my-awesome-app"))

        assert result == "my-awesome-app"

    def test_directory_with_trailing_slash(self):
        """Should handle paths with trailing slash."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            derive_project_name
        )
        from pathlib import Path

        # Path normalizes trailing slash
        result = derive_project_name(Path("/home/user/projects/my-app/"))

        assert result == "my-app"

    def test_nested_directory(self):
        """Should use only the last component."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            derive_project_name
        )
        from pathlib import Path

        result = derive_project_name(Path("/very/deeply/nested/project-name"))

        assert result == "project-name"

# Feature 111: Unit tests for branch parsing functions
"""Tests for parse_branch_description() and detect_branch_type().

User Story 2: Feature Purpose Attribution
- Convert branch names like "109-enhance-worktree-ux" to "Enhance Worktree UX"
- Detect branch types (main, feature, hotfix, release)
"""

import pytest


class TestParseBranchDescription:
    """Tests for parse_branch_description function."""

    def test_numbered_branch_with_dashes(self):
        """Test converting '109-enhance-worktree-ux' to 'Enhance Worktree Ux'."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("109-enhance-worktree-ux")

        # Python's title() converts 'ux' to 'Ux' (standard behavior)
        assert result == "Enhance Worktree Ux"

    def test_numbered_branch_with_underscores(self):
        """Test converting '111_visual_map_worktrees' to 'Visual Map Worktrees'."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("111_visual_map_worktrees")

        assert result == "Visual Map Worktrees"

    def test_numbered_branch_mixed_separators(self):
        """Test handling mixed dashes and underscores."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("100-feature_with_mixed-separators")

        assert result == "Feature With Mixed Separators"

    def test_main_branch(self):
        """Test that 'main' returns 'Main'."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("main")

        assert result == "Main"

    def test_master_branch(self):
        """Test that 'master' returns 'Master'."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("master")

        assert result == "Master"

    def test_hotfix_branch(self):
        """Test converting 'hotfix-critical-bug' to 'Critical Bug'."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("hotfix-critical-bug")

        # Should strip 'hotfix' prefix and title case the rest
        assert result == "Critical Bug"

    def test_release_branch(self):
        """Test converting 'release-v2.0' to 'V2.0'."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("release-v2.0")

        assert result == "V2.0"

    def test_feature_branch_prefix(self):
        """Test handling 'feature/new-feature' format."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("feature/new-feature")

        assert result == "New Feature"

    def test_long_description_truncation(self):
        """Test that very long descriptions are handled gracefully."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        long_branch = "100-this-is-a-very-long-branch-name-with-many-words"
        result = parse_branch_description(long_branch)

        # Should title case all words
        assert "This Is A Very Long" in result

    def test_empty_string(self):
        """Test handling empty string input."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("")

        assert result == ""

    def test_numbers_only(self):
        """Test handling branch name with only numbers."""
        from i3_project_manager.services.worktree_map_service import (
            parse_branch_description,
        )

        result = parse_branch_description("12345")

        # Should return as-is since there's no description
        assert result == "12345"


class TestDetectBranchType:
    """Tests for detect_branch_type function."""

    def test_main_branch(self):
        """Test that 'main' is detected as MAIN type."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = detect_branch_type("main")

        assert result == NodeType.MAIN

    def test_master_branch(self):
        """Test that 'master' is detected as MAIN type."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = detect_branch_type("master")

        assert result == NodeType.MAIN

    def test_hotfix_prefix(self):
        """Test that 'hotfix-*' is detected as HOTFIX type."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = detect_branch_type("hotfix-critical-bug")

        assert result == NodeType.HOTFIX

    def test_hotfix_contains(self):
        """Test that branch containing 'hotfix' is detected as HOTFIX type."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = detect_branch_type("emergency-hotfix-fix")

        assert result == NodeType.HOTFIX

    def test_release_prefix(self):
        """Test that 'release-*' is detected as RELEASE type."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = detect_branch_type("release-v2.0")

        assert result == NodeType.RELEASE

    def test_release_contains(self):
        """Test that branch containing 'release' is detected as RELEASE type."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = detect_branch_type("prepare-release-2.0")

        assert result == NodeType.RELEASE

    def test_numbered_feature_branch(self):
        """Test that '111-visual-map' is detected as FEATURE type."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = detect_branch_type("111-visual-map")

        assert result == NodeType.FEATURE

    def test_feature_prefix(self):
        """Test that 'feature/*' is detected as FEATURE type."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = detect_branch_type("feature/new-feature")

        assert result == NodeType.FEATURE

    def test_generic_branch(self):
        """Test that generic branch name defaults to FEATURE type."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = detect_branch_type("some-random-branch")

        assert result == NodeType.FEATURE

    def test_fix_branch(self):
        """Test that 'fix-*' branches are detected as FEATURE (not hotfix)."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        # 'fix' without 'hotfix' should be feature, not hotfix
        result = detect_branch_type("fix-typo")

        assert result == NodeType.FEATURE

    def test_case_insensitive(self):
        """Test that detection is case-insensitive."""
        from i3_project_manager.services.worktree_map_service import (
            detect_branch_type,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        assert detect_branch_type("MAIN") == NodeType.MAIN
        assert detect_branch_type("Hotfix-Bug") == NodeType.HOTFIX
        assert detect_branch_type("RELEASE-V1") == NodeType.RELEASE

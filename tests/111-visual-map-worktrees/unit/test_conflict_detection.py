# Feature 111: Unit tests for detect_potential_conflicts()
"""Tests for detecting potential merge conflicts between worktrees.

User Story 4: Merge Flow Visualization
- Detect when worktrees modify overlapping files
- Show conflict indicators on edges between conflicting branches
"""

import pytest


class TestDetectPotentialConflicts:
    """Tests for detect_potential_conflicts function."""

    def test_no_conflicts_different_files(self):
        """Test no conflicts when branches modify different files."""
        from i3_project_manager.services.git_utils import detect_potential_conflicts

        # Simulate two branches modifying different files
        branch1_files = ["src/main.py", "src/utils.py"]
        branch2_files = ["tests/test_main.py", "docs/README.md"]

        result = detect_potential_conflicts(branch1_files, branch2_files)

        assert result["has_conflict"] is False
        assert result["conflicting_files"] == []

    def test_conflict_with_overlapping_files(self):
        """Test conflict detected when branches modify same files."""
        from i3_project_manager.services.git_utils import detect_potential_conflicts

        branch1_files = ["src/main.py", "src/utils.py", "config.json"]
        branch2_files = ["src/main.py", "tests/test.py"]

        result = detect_potential_conflicts(branch1_files, branch2_files)

        assert result["has_conflict"] is True
        assert "src/main.py" in result["conflicting_files"]

    def test_multiple_conflicting_files(self):
        """Test multiple conflicting files are reported."""
        from i3_project_manager.services.git_utils import detect_potential_conflicts

        branch1_files = ["a.py", "b.py", "c.py"]
        branch2_files = ["b.py", "c.py", "d.py"]

        result = detect_potential_conflicts(branch1_files, branch2_files)

        assert result["has_conflict"] is True
        assert len(result["conflicting_files"]) == 2
        assert "b.py" in result["conflicting_files"]
        assert "c.py" in result["conflicting_files"]

    def test_empty_file_lists(self):
        """Test handling of empty file lists."""
        from i3_project_manager.services.git_utils import detect_potential_conflicts

        result = detect_potential_conflicts([], [])

        assert result["has_conflict"] is False
        assert result["conflicting_files"] == []

    def test_one_empty_list(self):
        """Test when one branch has no changes."""
        from i3_project_manager.services.git_utils import detect_potential_conflicts

        result = detect_potential_conflicts(["file.py"], [])

        assert result["has_conflict"] is False
        assert result["conflicting_files"] == []

    def test_case_sensitive_paths(self):
        """Test that file path comparison is case-sensitive."""
        from i3_project_manager.services.git_utils import detect_potential_conflicts

        branch1_files = ["File.py"]
        branch2_files = ["file.py"]

        result = detect_potential_conflicts(branch1_files, branch2_files)

        # Linux is case-sensitive, so these are different files
        assert result["has_conflict"] is False

    def test_conflict_count(self):
        """Test conflict count is accurate."""
        from i3_project_manager.services.git_utils import detect_potential_conflicts

        branch1_files = ["a.py", "b.py", "c.py", "d.py"]
        branch2_files = ["a.py", "b.py", "c.py", "e.py"]

        result = detect_potential_conflicts(branch1_files, branch2_files)

        assert result["conflict_count"] == 3

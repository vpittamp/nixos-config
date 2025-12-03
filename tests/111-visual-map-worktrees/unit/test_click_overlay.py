# Feature 111: Unit tests for generate_click_overlay_data()
"""Tests for generating click overlay data for interactive map.

User Story 3: Interactive Branch Navigation
- Generate node position data for Eww click overlays
- Include qualified_name for project switching
- Include tooltip content for hover display
"""

import pytest


class TestGenerateClickOverlayData:
    """Tests for generate_click_overlay_data function."""

    def test_returns_list_of_node_data(self):
        """Test that function returns a list of node data dictionaries."""
        from i3_project_manager.services.worktree_map_service import (
            generate_click_overlay_data,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        node = WorktreeNode(
            branch="main",
            branch_number=None,
            branch_description="Main",
            qualified_name="repo:main",
            node_type=NodeType.MAIN,
            x=200,
            y=50,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[node],
            edges=[],
            main_branch="main",
            width=400,
            height=300,
        )

        result = generate_click_overlay_data(map_data)

        assert isinstance(result, list)
        assert len(result) == 1

    def test_includes_position_data(self):
        """Test that each node includes x, y, and radius for overlay positioning."""
        from i3_project_manager.services.worktree_map_service import (
            generate_click_overlay_data,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        node = WorktreeNode(
            branch="111-feature",
            branch_number="111",
            branch_description="Feature",
            qualified_name="repo:111-feature",
            node_type=NodeType.FEATURE,
            x=150,
            y=100,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        result = generate_click_overlay_data(map_data)

        assert result[0]["x"] == 150
        assert result[0]["y"] == 100
        assert "radius" in result[0]  # For click area sizing

    def test_includes_qualified_name_for_switching(self):
        """Test that qualified_name is included for project switch command."""
        from i3_project_manager.services.worktree_map_service import (
            generate_click_overlay_data,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        node = WorktreeNode(
            branch="111-feature",
            branch_number="111",
            branch_description="Feature",
            qualified_name="vpittamp/nixos:111-feature",
            node_type=NodeType.FEATURE,
            x=150,
            y=100,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        result = generate_click_overlay_data(map_data)

        assert result[0]["qualified_name"] == "vpittamp/nixos:111-feature"

    def test_includes_tooltip_content(self):
        """Test that tooltip content is included for hover display."""
        from i3_project_manager.services.worktree_map_service import (
            generate_click_overlay_data,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        node = WorktreeNode(
            branch="111-feature",
            branch_number="111",
            branch_description="Feature",
            qualified_name="repo:111-feature",
            node_type=NodeType.FEATURE,
            x=150,
            y=100,
            ahead_of_parent=5,
            behind_parent=2,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        result = generate_click_overlay_data(map_data)

        assert "tooltip" in result[0]
        assert "111-feature" in result[0]["tooltip"]

    def test_includes_branch_label(self):
        """Test that branch label (number or abbreviated name) is included."""
        from i3_project_manager.services.worktree_map_service import (
            generate_click_overlay_data,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        node = WorktreeNode(
            branch="111-visual-map",
            branch_number="111",
            branch_description="Visual Map",
            qualified_name="repo:111-visual-map",
            node_type=NodeType.FEATURE,
            x=150,
            y=100,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        result = generate_click_overlay_data(map_data)

        assert result[0]["label"] == "111"

    def test_includes_node_type(self):
        """Test that node type is included for styling."""
        from i3_project_manager.services.worktree_map_service import (
            generate_click_overlay_data,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        node = WorktreeNode(
            branch="hotfix-critical",
            branch_number=None,
            branch_description="Critical",
            qualified_name="repo:hotfix-critical",
            node_type=NodeType.HOTFIX,
            x=150,
            y=100,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        result = generate_click_overlay_data(map_data)

        assert result[0]["type"] == "hotfix"

    def test_includes_active_and_dirty_flags(self):
        """Test that is_active and is_dirty flags are included."""
        from i3_project_manager.services.worktree_map_service import (
            generate_click_overlay_data,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        node = WorktreeNode(
            branch="111-feature",
            branch_number="111",
            branch_description="Feature",
            qualified_name="repo:111-feature",
            node_type=NodeType.FEATURE,
            x=150,
            y=100,
            is_active=True,
            is_dirty=True,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        result = generate_click_overlay_data(map_data)

        assert result[0]["is_active"] is True
        assert result[0]["is_dirty"] is True

    def test_empty_map_returns_empty_list(self):
        """Test that empty map returns empty list."""
        from i3_project_manager.services.worktree_map_service import (
            generate_click_overlay_data,
        )
        from i3_project_manager.models.worktree_relationship import WorktreeMap

        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[],
            edges=[],
            main_branch="main",
        )

        result = generate_click_overlay_data(map_data)

        assert result == []

    def test_multiple_nodes(self):
        """Test with multiple nodes returns data for all."""
        from i3_project_manager.services.worktree_map_service import (
            generate_click_overlay_data,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        nodes = [
            WorktreeNode(
                branch="main",
                branch_number=None,
                branch_description="Main",
                qualified_name="repo:main",
                node_type=NodeType.MAIN,
                x=200,
                y=50,
            ),
            WorktreeNode(
                branch="111-feature",
                branch_number="111",
                branch_description="Feature",
                qualified_name="repo:111-feature",
                node_type=NodeType.FEATURE,
                x=100,
                y=150,
            ),
            WorktreeNode(
                branch="112-another",
                branch_number="112",
                branch_description="Another",
                qualified_name="repo:112-another",
                node_type=NodeType.FEATURE,
                x=300,
                y=150,
            ),
        ]
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=nodes,
            edges=[],
            main_branch="main",
        )

        result = generate_click_overlay_data(map_data)

        assert len(result) == 3
        branches = [n["branch"] for n in result]
        assert "main" in branches
        assert "111-feature" in branches
        assert "112-another" in branches

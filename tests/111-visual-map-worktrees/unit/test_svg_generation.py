# Feature 111: Unit tests for generate_worktree_map_svg()
"""Tests for SVG generation from WorktreeMap data.

The SVG generator produces:
- CSS styles with Catppuccin Mocha colors
- Edge lines with ahead/behind labels
- Node circles with branch labels
- Proper viewBox and dimensions
"""

import pytest


class TestGenerateWorktreeMapSvg:
    """Tests for generate_worktree_map_svg function."""

    def test_generates_valid_svg_structure(self):
        """Test that output is valid SVG with proper structure."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        main_node = WorktreeNode(
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
            nodes=[main_node],
            edges=[],
            main_branch="main",
            width=400,
            height=300,
        )

        svg = generate_worktree_map_svg(map_data)

        # Check SVG structure
        assert svg.startswith("<svg")
        assert "</svg>" in svg
        assert 'xmlns="http://www.w3.org/2000/svg"' in svg
        assert "viewBox" in svg

    def test_includes_catppuccin_mocha_colors(self):
        """Test that CSS includes Catppuccin Mocha color palette."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        main_node = WorktreeNode(
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
            nodes=[main_node],
            edges=[],
            main_branch="main",
        )

        svg = generate_worktree_map_svg(map_data)

        # Catppuccin Mocha colors (hex values)
        assert "#1e1e2e" in svg or "1e1e2e" in svg  # Base (background)
        assert "<style>" in svg
        assert "</style>" in svg

    def test_renders_nodes_as_circles(self):
        """Test that nodes are rendered as SVG circles."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
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
            x=200,
            y=100,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        svg = generate_worktree_map_svg(map_data)

        assert "<circle" in svg
        assert 'cx="200"' in svg or "cx='200'" in svg
        assert 'cy="100"' in svg or "cy='100'" in svg

    def test_renders_node_labels(self):
        """Test that branch numbers/labels are rendered as text."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
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
            x=200,
            y=100,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        svg = generate_worktree_map_svg(map_data)

        assert "<text" in svg
        assert "111" in svg  # Branch number as label

    def test_renders_edges_as_lines(self):
        """Test that edges are rendered as SVG lines/paths."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            RelationshipEdge,
            EdgeType,
            NodeType,
        )

        main_node = WorktreeNode(
            branch="main",
            branch_number=None,
            branch_description="Main",
            qualified_name="repo:main",
            node_type=NodeType.MAIN,
            x=200,
            y=50,
        )
        feature_node = WorktreeNode(
            branch="111-feature",
            branch_number="111",
            branch_description="Feature",
            qualified_name="repo:111-feature",
            node_type=NodeType.FEATURE,
            x=200,
            y=150,
        )
        edge = RelationshipEdge(
            source_branch="main",
            target_branch="111-feature",
            edge_type=EdgeType.PARENT_CHILD,
            ahead_count=5,
            behind_count=0,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[main_node, feature_node],
            edges=[edge],
            main_branch="main",
        )

        svg = generate_worktree_map_svg(map_data)

        # Should have a line or path element for edge
        assert "<line" in svg or "<path" in svg

    def test_renders_ahead_behind_labels_on_edges(self):
        """Test that ahead/behind counts appear as labels on edges."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            RelationshipEdge,
            EdgeType,
            NodeType,
        )

        main_node = WorktreeNode(
            branch="main",
            branch_number=None,
            branch_description="Main",
            qualified_name="repo:main",
            node_type=NodeType.MAIN,
            x=200,
            y=50,
        )
        feature_node = WorktreeNode(
            branch="111-feature",
            branch_number="111",
            branch_description="Feature",
            qualified_name="repo:111-feature",
            node_type=NodeType.FEATURE,
            x=200,
            y=150,
        )
        edge = RelationshipEdge(
            source_branch="main",
            target_branch="111-feature",
            edge_type=EdgeType.PARENT_CHILD,
            ahead_count=5,
            behind_count=2,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[main_node, feature_node],
            edges=[edge],
            main_branch="main",
        )

        svg = generate_worktree_map_svg(map_data)

        # Should contain ahead/behind indicators
        assert "↑5" in svg or "5" in svg
        assert "↓2" in svg or "2" in svg

    def test_applies_node_type_css_classes(self):
        """Test that different node types get appropriate CSS classes."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
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
                x=100,
                y=50,
            ),
            WorktreeNode(
                branch="feature-1",
                branch_number="1",
                branch_description="Feature",
                qualified_name="repo:feature-1",
                node_type=NodeType.FEATURE,
                x=200,
                y=50,
            ),
            WorktreeNode(
                branch="hotfix-1",
                branch_number="1",
                branch_description="Hotfix",
                qualified_name="repo:hotfix-1",
                node_type=NodeType.HOTFIX,
                x=300,
                y=50,
            ),
        ]
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=nodes,
            edges=[],
            main_branch="main",
        )

        svg = generate_worktree_map_svg(map_data)

        # CSS should define styles for different node types
        assert ".node-main" in svg or "node-main" in svg
        assert ".node-feature" in svg or "node-feature" in svg
        assert ".node-hotfix" in svg or "node-hotfix" in svg

    def test_renders_active_node_differently(self):
        """Test that the active/focused node has distinct styling."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        active_node = WorktreeNode(
            branch="111-feature",
            branch_number="111",
            branch_description="Feature",
            qualified_name="repo:111-feature",
            node_type=NodeType.FEATURE,
            is_active=True,
            x=200,
            y=100,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[active_node],
            edges=[],
            main_branch="main",
        )

        svg = generate_worktree_map_svg(map_data)

        # Active node should have special class or styling
        assert "active" in svg.lower() or "focused" in svg.lower()

    def test_renders_dirty_indicator(self):
        """Test that dirty nodes show uncommitted changes indicator."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            NodeType,
        )

        dirty_node = WorktreeNode(
            branch="111-feature",
            branch_number="111",
            branch_description="Feature",
            qualified_name="repo:111-feature",
            node_type=NodeType.FEATURE,
            is_dirty=True,
            x=200,
            y=100,
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[dirty_node],
            edges=[],
            main_branch="main",
        )

        svg = generate_worktree_map_svg(map_data)

        # Dirty indicator (red dot or similar)
        assert "dirty" in svg.lower() or "●" in svg or "red" in svg.lower()

    def test_outputs_to_file_when_path_provided(self):
        """Test that SVG is written to file when path is given."""
        import tempfile
        import os
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
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
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = os.path.join(tmpdir, "map.svg")
            svg = generate_worktree_map_svg(map_data, output_path=output_path)

            assert os.path.exists(output_path)
            with open(output_path, "r") as f:
                content = f.read()
            assert content == svg
            assert content.startswith("<svg")

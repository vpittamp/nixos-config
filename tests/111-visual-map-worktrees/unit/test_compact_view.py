# Feature 111: Unit tests for generate_compact_svg()
"""Tests for compact map view generation.

User Story 6: Compact vs Expanded Map Views
- Support both compact panel view and expanded full-detail overlay
- Compact mode: smaller nodes, abbreviated labels for 10+ worktrees
- Remain readable with up to 15 worktrees in compact view
"""

import pytest


class TestGenerateCompactSvg:
    """Tests for generate_compact_svg function."""

    def test_compact_mode_returns_smaller_dimensions(self):
        """Test that compact mode produces smaller SVG dimensions."""
        from i3_project_manager.services.worktree_map_service import (
            generate_compact_svg,
            COMPACT_MAX_WIDTH,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeMap,
            WorktreeNode,
            NodeType,
            NodeStatus,
        )

        # Create a single node map
        node = WorktreeNode(
            branch="main",
            branch_number=None,
            branch_description="Main",
            qualified_name="test:main",
            node_type=NodeType.MAIN,
            status=NodeStatus.ACTIVE,
            x=100,
            y=100,
        )

        map_data = WorktreeMap(
            repository="test-repo",
            nodes=[node],
            edges=[],
            main_branch="main",
            width=400,
            height=500,
        )

        compact_svg = generate_compact_svg(map_data)

        # Compact should be constrained to max width
        assert 'width="' in compact_svg
        import re
        width_match = re.search(r'width="(\d+)"', compact_svg)
        assert width_match
        width = int(width_match.group(1))
        assert width <= COMPACT_MAX_WIDTH  # Should be at most 300

    def test_compact_mode_smaller_nodes(self):
        """Test that compact mode uses smaller node radius."""
        from i3_project_manager.services.worktree_map_service import (
            generate_compact_svg,
            DEFAULT_NODE_RADIUS,
            COMPACT_NODE_RADIUS,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeMap,
            WorktreeNode,
            NodeType,
            NodeStatus,
        )

        # Create a node at position
        node = WorktreeNode(
            branch="main",
            branch_number=None,
            branch_description="Main",
            qualified_name="test:main",
            node_type=NodeType.MAIN,
            status=NodeStatus.ACTIVE,
            x=100,
            y=100,
        )

        map_data = WorktreeMap(
            repository="test-repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        compact_svg = generate_compact_svg(map_data)

        # Verify smaller radius is used in SVG
        assert f'r="{COMPACT_NODE_RADIUS}"' in compact_svg
        # Verify default radius is NOT used
        assert f'r="{DEFAULT_NODE_RADIUS}"' not in compact_svg

    def test_compact_mode_abbreviated_labels(self):
        """Test that compact mode abbreviates long branch names."""
        from i3_project_manager.services.worktree_map_service import (
            generate_compact_svg,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeMap,
            WorktreeNode,
            NodeType,
            NodeStatus,
        )

        # Create a node with a long branch name
        node = WorktreeNode(
            branch="111-visual-map-worktrees",
            branch_number="111",
            branch_description="Visual Map Worktrees",
            qualified_name="test:111-visual-map-worktrees",
            node_type=NodeType.FEATURE,
            status=NodeStatus.ACTIVE,
            x=100,
            y=100,
        )

        map_data = WorktreeMap(
            repository="test-repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        compact_svg = generate_compact_svg(map_data)

        # In compact mode, should use branch number as label
        assert ">111<" in compact_svg
        # Full branch name should NOT appear as label
        assert ">111-visual-map-worktrees<" not in compact_svg

    def test_compact_mode_with_no_branch_number(self):
        """Test compact mode abbreviates branches without numbers."""
        from i3_project_manager.services.worktree_map_service import (
            generate_compact_svg,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeMap,
            WorktreeNode,
            NodeType,
            NodeStatus,
        )

        # Create a node without branch number
        node = WorktreeNode(
            branch="feature-long-descriptive-name",
            branch_number=None,
            branch_description="Long Descriptive Name",
            qualified_name="test:feature-long-descriptive-name",
            node_type=NodeType.FEATURE,
            status=NodeStatus.ACTIVE,
            x=100,
            y=100,
        )

        map_data = WorktreeMap(
            repository="test-repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        compact_svg = generate_compact_svg(map_data)

        # Should abbreviate to first 5 chars (featu)
        assert ">featu<" in compact_svg
        # Full branch name should NOT appear
        assert ">feature-long-descriptive-name<" not in compact_svg

    def test_compact_mode_reduced_spacing(self):
        """Test that compact mode uses tighter spacing between layers."""
        from i3_project_manager.services.worktree_map_service import (
            COMPACT_LAYER_HEIGHT,
            DEFAULT_LAYER_HEIGHT,
        )

        # Verify constant exists and is smaller
        assert COMPACT_LAYER_HEIGHT < DEFAULT_LAYER_HEIGHT

    def test_compact_svg_still_shows_status_indicators(self):
        """Test that compact mode preserves status indicators (dirty, merged, stale)."""
        from i3_project_manager.services.worktree_map_service import (
            generate_compact_svg,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeMap,
            WorktreeNode,
            NodeType,
            NodeStatus,
        )

        # Create a dirty node
        dirty_node = WorktreeNode(
            branch="dirty-branch",
            branch_number=None,
            branch_description="Dirty Branch",
            qualified_name="test:dirty-branch",
            node_type=NodeType.FEATURE,
            status=NodeStatus.ACTIVE,
            is_dirty=True,
            x=100,
            y=100,
        )

        # Create a merged node
        merged_node = WorktreeNode(
            branch="merged-branch",
            branch_number=None,
            branch_description="Merged Branch",
            qualified_name="test:merged-branch",
            node_type=NodeType.FEATURE,
            status=NodeStatus.MERGED,
            x=200,
            y=100,
        )

        map_data = WorktreeMap(
            repository="test-repo",
            nodes=[dirty_node, merged_node],
            edges=[],
            main_branch="main",
        )

        compact_svg = generate_compact_svg(map_data)

        # Should still have dirty indicator
        assert "dirty-indicator" in compact_svg
        # Should still have merged badge
        assert "merged-badge" in compact_svg

    def test_compact_svg_many_nodes_fits_in_panel(self):
        """Test that compact SVG with 10+ nodes still fits panel dimensions."""
        from i3_project_manager.services.worktree_map_service import (
            generate_compact_svg,
            COMPACT_MAX_WIDTH,
            COMPACT_MAX_HEIGHT,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeMap,
            WorktreeNode,
            NodeType,
            NodeStatus,
        )

        # Create 15 nodes (stress test)
        nodes = []
        for i in range(15):
            node = WorktreeNode(
                branch=f"{100 + i}-feature-{i}",
                branch_number=str(100 + i),
                branch_description=f"Feature {i}",
                qualified_name=f"test:{100 + i}-feature-{i}",
                node_type=NodeType.FEATURE,
                status=NodeStatus.ACTIVE,
                x=50 + (i % 5) * 50,  # 5 per row
                y=50 + (i // 5) * 50,  # 3 rows
            )
            nodes.append(node)

        map_data = WorktreeMap(
            repository="test-repo",
            nodes=nodes,
            edges=[],
            main_branch="main",
        )

        compact_svg = generate_compact_svg(map_data)

        # Extract dimensions
        import re
        width_match = re.search(r'width="(\d+)"', compact_svg)
        height_match = re.search(r'height="(\d+)"', compact_svg)

        assert width_match and height_match
        width = int(width_match.group(1))
        height = int(height_match.group(1))

        # Should fit in panel max dimensions
        assert width <= COMPACT_MAX_WIDTH
        assert height <= COMPACT_MAX_HEIGHT

    def test_compact_mode_parameter_integration(self):
        """Test that generate_worktree_map_svg respects compact_mode parameter."""
        from i3_project_manager.services.worktree_map_service import (
            generate_worktree_map_svg,
            DEFAULT_NODE_RADIUS,
            COMPACT_NODE_RADIUS,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeMap,
            WorktreeNode,
            NodeType,
            NodeStatus,
        )

        node = WorktreeNode(
            branch="main",
            branch_number=None,
            branch_description="Main",
            qualified_name="test:main",
            node_type=NodeType.MAIN,
            status=NodeStatus.ACTIVE,
            x=100,
            y=100,
        )

        map_data = WorktreeMap(
            repository="test-repo",
            nodes=[node],
            edges=[],
            main_branch="main",
        )

        # Default mode
        default_svg = generate_worktree_map_svg(map_data, compact_mode=False)
        assert f'r="{DEFAULT_NODE_RADIUS}"' in default_svg

        # Compact mode
        compact_svg = generate_worktree_map_svg(map_data, compact_mode=True)
        assert f'r="{COMPACT_NODE_RADIUS}"' in compact_svg

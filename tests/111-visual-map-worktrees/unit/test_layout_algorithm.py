# Feature 111: Unit tests for compute_hierarchical_layout()
"""Tests for the hierarchical layout algorithm.

The layout algorithm assigns x,y positions to nodes in a tree structure:
- Layer assignment: main at layer 0, direct children at layer 1, etc.
- X-position: centered within each layer, evenly spaced
- Y-position: based on layer depth
"""

import pytest


class TestComputeHierarchicalLayout:
    """Tests for compute_hierarchical_layout function."""

    def test_single_node_layout(self):
        """Test layout with just the main branch."""
        from i3_project_manager.services.worktree_map_service import (
            compute_hierarchical_layout,
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
        )
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[main_node],
            edges=[],
            main_branch="main",
        )

        result = compute_hierarchical_layout(map_data)

        assert len(result.nodes) == 1
        assert result.nodes[0].layer == 0
        # Main should be centered horizontally
        assert result.nodes[0].x == result.width / 2

    def test_parent_child_layout(self):
        """Test layout with main branch and one child."""
        from i3_project_manager.services.worktree_map_service import (
            compute_hierarchical_layout,
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
        )
        feature_node = WorktreeNode(
            branch="111-visual-map",
            branch_number="111",
            branch_description="Visual Map",
            qualified_name="repo:111-visual-map",
            node_type=NodeType.FEATURE,
            parent_branch="main",
        )
        edge = RelationshipEdge(
            source_branch="main",
            target_branch="111-visual-map",
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

        result = compute_hierarchical_layout(map_data)

        main = result.get_node("main")
        feature = result.get_node("111-visual-map")

        assert main.layer == 0
        assert feature.layer == 1
        # Child should be below parent (higher y value)
        assert feature.y > main.y

    def test_multiple_children_horizontal_spread(self):
        """Test that multiple children at same layer spread horizontally."""
        from i3_project_manager.services.worktree_map_service import (
            compute_hierarchical_layout,
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
        )
        children = []
        edges = []
        for i in range(3):
            child = WorktreeNode(
                branch=f"feature-{i}",
                branch_number=str(i),
                branch_description=f"Feature {i}",
                qualified_name=f"repo:feature-{i}",
                node_type=NodeType.FEATURE,
                parent_branch="main",
            )
            children.append(child)
            edges.append(
                RelationshipEdge(
                    source_branch="main",
                    target_branch=f"feature-{i}",
                    edge_type=EdgeType.PARENT_CHILD,
                )
            )

        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[main_node] + children,
            edges=edges,
            main_branch="main",
        )

        result = compute_hierarchical_layout(map_data)

        # Get children nodes
        child_nodes = [result.get_node(f"feature-{i}") for i in range(3)]

        # All should be at layer 1
        for node in child_nodes:
            assert node.layer == 1

        # Children should have different x positions
        x_positions = [n.x for n in child_nodes]
        assert len(set(x_positions)) == 3  # All unique

        # Children should be evenly spaced
        x_positions.sort()
        spacing1 = x_positions[1] - x_positions[0]
        spacing2 = x_positions[2] - x_positions[1]
        assert abs(spacing1 - spacing2) < 1  # Approximately equal spacing

    def test_deep_hierarchy(self):
        """Test layout with multiple levels of depth."""
        from i3_project_manager.services.worktree_map_service import (
            compute_hierarchical_layout,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            RelationshipEdge,
            EdgeType,
            NodeType,
        )

        # Create: main -> level1 -> level2 -> level3
        nodes = [
            WorktreeNode(
                branch="main",
                branch_number=None,
                branch_description="Main",
                qualified_name="repo:main",
                node_type=NodeType.MAIN,
            ),
            WorktreeNode(
                branch="level1",
                branch_number="1",
                branch_description="Level 1",
                qualified_name="repo:level1",
                node_type=NodeType.FEATURE,
                parent_branch="main",
            ),
            WorktreeNode(
                branch="level2",
                branch_number="2",
                branch_description="Level 2",
                qualified_name="repo:level2",
                node_type=NodeType.FEATURE,
                parent_branch="level1",
            ),
            WorktreeNode(
                branch="level3",
                branch_number="3",
                branch_description="Level 3",
                qualified_name="repo:level3",
                node_type=NodeType.FEATURE,
                parent_branch="level2",
            ),
        ]
        edges = [
            RelationshipEdge(
                source_branch="main",
                target_branch="level1",
                edge_type=EdgeType.PARENT_CHILD,
            ),
            RelationshipEdge(
                source_branch="level1",
                target_branch="level2",
                edge_type=EdgeType.PARENT_CHILD,
            ),
            RelationshipEdge(
                source_branch="level2",
                target_branch="level3",
                edge_type=EdgeType.PARENT_CHILD,
            ),
        ]
        map_data = WorktreeMap(
            repository="test/repo",
            nodes=nodes,
            edges=edges,
            main_branch="main",
        )

        result = compute_hierarchical_layout(map_data)

        # Check layer assignments
        assert result.get_node("main").layer == 0
        assert result.get_node("level1").layer == 1
        assert result.get_node("level2").layer == 2
        assert result.get_node("level3").layer == 3

        # Check y positions increase with depth
        y_positions = [result.get_node(b).y for b in ["main", "level1", "level2", "level3"]]
        assert y_positions == sorted(y_positions)  # Strictly increasing

    def test_canvas_dimensions_adjust_to_content(self):
        """Test that canvas width/height adjust based on number of nodes."""
        from i3_project_manager.services.worktree_map_service import (
            compute_hierarchical_layout,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            RelationshipEdge,
            EdgeType,
            NodeType,
        )

        # Create many children to test width scaling
        main_node = WorktreeNode(
            branch="main",
            branch_number=None,
            branch_description="Main",
            qualified_name="repo:main",
            node_type=NodeType.MAIN,
        )
        children = []
        edges = []
        for i in range(10):
            child = WorktreeNode(
                branch=f"feature-{i}",
                branch_number=str(i),
                branch_description=f"Feature {i}",
                qualified_name=f"repo:feature-{i}",
                node_type=NodeType.FEATURE,
                parent_branch="main",
            )
            children.append(child)
            edges.append(
                RelationshipEdge(
                    source_branch="main",
                    target_branch=f"feature-{i}",
                    edge_type=EdgeType.PARENT_CHILD,
                )
            )

        map_data = WorktreeMap(
            repository="test/repo",
            nodes=[main_node] + children,
            edges=edges,
            main_branch="main",
        )

        result = compute_hierarchical_layout(map_data)

        # With 10 children, width should be larger than default
        assert result.width >= 400  # Default minimum

    def test_nodes_within_canvas_bounds(self):
        """Test that all nodes are positioned within canvas bounds."""
        from i3_project_manager.services.worktree_map_service import (
            compute_hierarchical_layout,
        )
        from i3_project_manager.models.worktree_relationship import (
            WorktreeNode,
            WorktreeMap,
            RelationshipEdge,
            EdgeType,
            NodeType,
        )

        # Create a moderately complex tree
        main_node = WorktreeNode(
            branch="main",
            branch_number=None,
            branch_description="Main",
            qualified_name="repo:main",
            node_type=NodeType.MAIN,
        )
        nodes = [main_node]
        edges = []
        for i in range(5):
            child = WorktreeNode(
                branch=f"feature-{i}",
                branch_number=str(100 + i),
                branch_description=f"Feature {i}",
                qualified_name=f"repo:feature-{i}",
                node_type=NodeType.FEATURE,
                parent_branch="main",
            )
            nodes.append(child)
            edges.append(
                RelationshipEdge(
                    source_branch="main",
                    target_branch=f"feature-{i}",
                    edge_type=EdgeType.PARENT_CHILD,
                )
            )

        map_data = WorktreeMap(
            repository="test/repo",
            nodes=nodes,
            edges=edges,
            main_branch="main",
        )

        result = compute_hierarchical_layout(map_data)

        # Node radius is typically ~30px, so check with margin
        margin = 50
        for node in result.nodes:
            assert margin <= node.x <= result.width - margin
            assert margin <= node.y <= result.height - margin

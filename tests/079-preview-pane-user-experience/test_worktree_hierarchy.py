"""
Unit tests for worktree hierarchy grouping in project selection mode.

Feature 079: User Story 5 - Display worktrees grouped under parent projects
Tests FilterState.group_by_parent() method and indentation logic.
"""

import pytest
import sys
from pathlib import Path

# Add daemon module to path
daemon_path = Path(__file__).parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_path))

from models.project_filter import ProjectListItem, FilterState


class TestGroupByParent:
    """Test FilterState.group_by_parent() method."""

    def test_group_worktrees_under_parent(self):
        """T037: Worktrees are grouped under their parent projects."""
        state = FilterState()
        state.projects = [
            self._create_project("nixos", "NixOS Config", is_worktree=False, parent=None),
            self._create_project("nixos-079", "Preview Pane", is_worktree=True, parent="nixos"),
            self._create_project("nixos-078", "Eww Preview", is_worktree=True, parent="nixos"),
            self._create_project("dotfiles", "Dotfiles", is_worktree=False, parent=None),
        ]

        groups = state.group_by_parent()

        # Should have 2 groups (nixos with children, dotfiles standalone)
        assert len(groups) == 2

        # First group: nixos with worktrees
        nixos_group = groups[0]
        assert nixos_group["parent"].name == "nixos"
        assert len(nixos_group["children"]) == 2
        assert nixos_group["children"][0].name == "nixos-079"
        assert nixos_group["children"][1].name == "nixos-078"

        # Second group: dotfiles standalone
        dotfiles_group = groups[1]
        assert dotfiles_group["parent"].name == "dotfiles"
        assert len(dotfiles_group["children"]) == 0

    def test_orphan_worktrees_stay_separate(self):
        """Worktrees without a loaded parent remain ungrouped."""
        state = FilterState()
        state.projects = [
            self._create_project("nixos-079", "Preview Pane", is_worktree=True, parent="nixos"),
            self._create_project("dotfiles", "Dotfiles", is_worktree=False, parent=None),
        ]

        groups = state.group_by_parent()

        # Should have 2 groups (dotfiles root, then orphan worktree)
        assert len(groups) == 2

        # Root projects come first
        dotfiles_group = groups[0]
        assert dotfiles_group["parent"].name == "dotfiles"
        assert len(dotfiles_group["children"]) == 0

        # Orphan worktree becomes its own group (after roots)
        orphan_group = groups[1]
        assert orphan_group["parent"].name == "nixos-079"
        assert len(orphan_group["children"]) == 0

    def test_empty_project_list(self):
        """Empty project list returns empty groups."""
        state = FilterState()
        state.projects = []

        groups = state.group_by_parent()

        assert groups == []

    def test_all_root_projects(self):
        """All root projects (no worktrees) each become their own group."""
        state = FilterState()
        state.projects = [
            self._create_project("nixos", "NixOS", is_worktree=False, parent=None),
            self._create_project("dotfiles", "Dotfiles", is_worktree=False, parent=None),
            self._create_project("scripts", "Scripts", is_worktree=False, parent=None),
        ]

        groups = state.group_by_parent()

        assert len(groups) == 3
        for group in groups:
            assert len(group["children"]) == 0

    def test_multiple_levels_not_supported(self):
        """Hierarchy is single-level only (parent → children)."""
        state = FilterState()
        state.projects = [
            self._create_project("nixos", "NixOS", is_worktree=False, parent=None),
            self._create_project("nixos-079", "Preview", is_worktree=True, parent="nixos"),
            # This would be nested worktree of worktree (not supported)
            self._create_project("nixos-079-sub", "Sub", is_worktree=True, parent="nixos-079"),
        ]

        groups = state.group_by_parent()

        # Parent nixos has one child (079)
        # Sub-worktree becomes orphan since its parent (079) is itself a worktree
        nixos_group = next(g for g in groups if g["parent"].name == "nixos")
        assert len(nixos_group["children"]) == 1
        assert nixos_group["children"][0].name == "nixos-079"

        # Sub-worktree is orphan (parent is worktree, not root)
        # It could be grouped under nixos-079 OR be separate depending on implementation
        # For simplicity, we don't nest worktrees under other worktrees

    @staticmethod
    def _create_project(name: str, display_name: str, is_worktree: bool, parent: str) -> ProjectListItem:
        """Helper to create ProjectListItem for tests."""
        branch_num = name.split("-")[-1] if "-" in name and name.split("-")[-1].isdigit() else None
        full_branch = f"{branch_num}-{display_name.lower().replace(' ', '-')}" if branch_num else "main"
        return ProjectListItem(
            name=name,
            display_name=display_name,
            icon="📁" if not is_worktree else "🌿",
            is_worktree=is_worktree,
            parent_project_name=parent,
            directory_exists=True,
            relative_time="1h ago",
            full_branch_name=full_branch,
        )


class TestIndentationLevel:
    """Test indentation level calculation for hierarchy display."""

    def test_root_project_indentation_zero(self):
        """T038: Root projects have indentation level 0."""
        project = ProjectListItem(
            name="nixos",
            display_name="NixOS",
            icon="📁",
            is_worktree=False,
            parent_project_name=None,
            directory_exists=True,
            relative_time="1h ago",
            full_branch_name="main",
        )

        # Root projects are top-level (no indentation)
        indentation = project.indentation_level()
        assert indentation == 0

    def test_worktree_indentation_one(self):
        """T038: Worktrees have indentation level 1 (children of root)."""
        project = ProjectListItem(
            name="nixos-079",
            display_name="Preview",
            icon="🌿",
            is_worktree=True,
            parent_project_name="nixos",
            directory_exists=True,
            relative_time="1h ago",
            full_branch_name="079-preview-pane",
        )

        # Worktrees are children (level 1 indentation)
        indentation = project.indentation_level()
        assert indentation == 1

    def test_orphan_worktree_indentation_zero(self):
        """Orphan worktrees (no parent loaded) have indentation level 0."""
        project = ProjectListItem(
            name="nixos-079",
            display_name="Preview",
            icon="🌿",
            is_worktree=True,
            parent_project_name=None,  # No parent loaded
            directory_exists=True,
            relative_time="1h ago",
            full_branch_name="079-preview-pane",
        )

        # Orphan worktree is treated as root (no indentation)
        indentation = project.indentation_level()
        assert indentation == 0


class TestHierarchyRendering:
    """Test hierarchy structure for Eww widget rendering."""

    def test_hierarchy_structure_for_eww(self):
        """Hierarchy structure matches Eww widget expectations."""
        state = FilterState()
        state.projects = [
            TestGroupByParent._create_project("nixos", "NixOS", is_worktree=False, parent=None),
            TestGroupByParent._create_project("nixos-079", "Preview", is_worktree=True, parent="nixos"),
        ]

        groups = state.group_by_parent()

        # Structure should be suitable for Eww for-loop rendering
        group = groups[0]
        assert "parent" in group
        assert "children" in group
        assert hasattr(group["parent"], "name")
        assert hasattr(group["parent"], "display_name")
        assert hasattr(group["parent"], "icon")

    def test_group_preserves_selection_state(self):
        """Selected project remains selected after grouping."""
        state = FilterState()
        state.projects = [
            TestGroupByParent._create_project("nixos", "NixOS", is_worktree=False, parent=None),
            TestGroupByParent._create_project("nixos-079", "Preview", is_worktree=True, parent="nixos"),
        ]
        state.selected_index = 1  # Select worktree

        groups = state.group_by_parent()

        # Selection should be preserved in flat list
        selected = state.get_selected_project()
        assert selected.name == "nixos-079"

    def test_flat_list_order_matches_grouped_order(self):
        """Flat list iteration order matches visual hierarchy order."""
        state = FilterState()
        state.projects = [
            TestGroupByParent._create_project("nixos", "NixOS", is_worktree=False, parent=None),
            TestGroupByParent._create_project("nixos-079", "Preview", is_worktree=True, parent="nixos"),
            TestGroupByParent._create_project("nixos-078", "Eww", is_worktree=True, parent="nixos"),
            TestGroupByParent._create_project("dotfiles", "Dotfiles", is_worktree=False, parent=None),
        ]

        groups = state.group_by_parent()

        # Flat order should be: nixos, 079, 078, dotfiles
        flat_order = []
        for group in groups:
            flat_order.append(group["parent"].name)
            for child in group["children"]:
                flat_order.append(child.name)

        assert flat_order == ["nixos", "nixos-079", "nixos-078", "dotfiles"]

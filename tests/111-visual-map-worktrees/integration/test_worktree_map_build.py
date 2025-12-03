# Feature 111: Integration tests for build_worktree_map()
"""Integration tests for building complete WorktreeMap from repository data.

These tests verify the full pipeline:
- Discovery of worktrees in a repository
- Computing branch relationships (merge-base, ahead/behind)
- Building the complete WorktreeMap structure
- Integration with existing project management infrastructure
"""

import pytest
import tempfile
import subprocess
import os


class TestBuildWorktreeMap:
    """Integration tests for build_worktree_map function."""

    @pytest.fixture
    def git_repo_with_worktrees(self):
        """Create a temporary git repo with worktrees for testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Initialize main repo
            main_repo = os.path.join(tmpdir, "main-repo")
            os.makedirs(main_repo)
            subprocess.run(
                ["git", "init"], cwd=main_repo, capture_output=True, check=True
            )
            subprocess.run(
                ["git", "config", "user.email", "test@test.com"],
                cwd=main_repo,
                capture_output=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "Test"],
                cwd=main_repo,
                capture_output=True,
            )

            # Create initial commit on main
            readme = os.path.join(main_repo, "README.md")
            with open(readme, "w") as f:
                f.write("# Test Repo\n")
            subprocess.run(
                ["git", "add", "README.md"], cwd=main_repo, capture_output=True
            )
            subprocess.run(
                ["git", "commit", "-m", "Initial commit"],
                cwd=main_repo,
                capture_output=True,
            )

            # Create feature branch with commits
            subprocess.run(
                ["git", "checkout", "-b", "111-feature"],
                cwd=main_repo,
                capture_output=True,
            )
            feature_file = os.path.join(main_repo, "feature.py")
            with open(feature_file, "w") as f:
                f.write("# Feature code\n")
            subprocess.run(
                ["git", "add", "feature.py"], cwd=main_repo, capture_output=True
            )
            subprocess.run(
                ["git", "commit", "-m", "Add feature"],
                cwd=main_repo,
                capture_output=True,
            )

            # Go back to main and create worktree for feature branch
            subprocess.run(
                ["git", "checkout", "main"],
                cwd=main_repo,
                capture_output=True,
            )

            # Create worktree directory
            worktree_path = os.path.join(tmpdir, "worktree-111")
            subprocess.run(
                ["git", "worktree", "add", worktree_path, "111-feature"],
                cwd=main_repo,
                capture_output=True,
            )

            yield {
                "main_repo": main_repo,
                "worktree_path": worktree_path,
                "tmpdir": tmpdir,
            }

    def test_build_worktree_map_from_repo(self, git_repo_with_worktrees):
        """Test building a complete WorktreeMap from repository."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )

        main_repo = git_repo_with_worktrees["main_repo"]
        result = build_worktree_map(main_repo)

        assert result is not None
        assert result.repository is not None
        assert len(result.nodes) >= 1  # At least main branch

    def test_detects_main_branch(self, git_repo_with_worktrees):
        """Test that main branch is correctly identified."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )

        main_repo = git_repo_with_worktrees["main_repo"]
        result = build_worktree_map(main_repo)

        main_node = result.get_node("main")
        assert main_node is not None
        assert main_node.layer == 0  # Main should be at root layer

    def test_detects_feature_branches(self, git_repo_with_worktrees):
        """Test that feature branches are detected."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )

        main_repo = git_repo_with_worktrees["main_repo"]
        result = build_worktree_map(main_repo)

        feature_node = result.get_node("111-feature")
        assert feature_node is not None
        assert feature_node.branch_number == "111"

    def test_computes_ahead_behind_counts(self, git_repo_with_worktrees):
        """Test that ahead/behind counts are computed for edges."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )
        from i3_project_manager.models.worktree_relationship import EdgeType

        main_repo = git_repo_with_worktrees["main_repo"]
        result = build_worktree_map(main_repo)

        # Find edge from main to 111-feature
        edge = None
        for e in result.edges:
            if (
                e.source_branch == "main"
                and e.target_branch == "111-feature"
                and e.edge_type == EdgeType.PARENT_CHILD
            ):
                edge = e
                break

        assert edge is not None
        assert edge.ahead_count == 1  # Feature has 1 commit ahead

    def test_sets_node_positions_after_layout(self, git_repo_with_worktrees):
        """Test that nodes have x,y positions after layout computation."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )

        main_repo = git_repo_with_worktrees["main_repo"]
        result = build_worktree_map(main_repo)

        for node in result.nodes:
            assert node.x > 0
            assert node.y > 0

    def test_returns_empty_map_for_invalid_repo(self):
        """Test that invalid repo path returns empty/error map."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )

        result = build_worktree_map("/nonexistent/path")

        # Should return empty map or None, not crash
        assert result is None or len(result.nodes) == 0

    def test_includes_worktree_paths_in_nodes(self, git_repo_with_worktrees):
        """Test that worktree paths are included in node qualified_name."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )

        main_repo = git_repo_with_worktrees["main_repo"]
        result = build_worktree_map(main_repo)

        feature_node = result.get_node("111-feature")
        assert feature_node is not None
        # qualified_name should contain repo reference
        assert feature_node.qualified_name is not None
        assert len(feature_node.qualified_name) > 0


class TestBuildWorktreeMapWithMultipleBranches:
    """Tests for building maps with complex branch structures."""

    @pytest.fixture
    def complex_git_repo(self):
        """Create a git repo with multiple branches and hierarchy."""
        with tempfile.TemporaryDirectory() as tmpdir:
            main_repo = os.path.join(tmpdir, "complex-repo")
            os.makedirs(main_repo)
            subprocess.run(
                ["git", "init"], cwd=main_repo, capture_output=True, check=True
            )
            subprocess.run(
                ["git", "config", "user.email", "test@test.com"],
                cwd=main_repo,
                capture_output=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "Test"],
                cwd=main_repo,
                capture_output=True,
            )

            # Initial commit on main
            readme = os.path.join(main_repo, "README.md")
            with open(readme, "w") as f:
                f.write("# Complex Test Repo\n")
            subprocess.run(
                ["git", "add", "README.md"], cwd=main_repo, capture_output=True
            )
            subprocess.run(
                ["git", "commit", "-m", "Initial commit"],
                cwd=main_repo,
                capture_output=True,
            )

            # Create feature-1 from main
            subprocess.run(
                ["git", "checkout", "-b", "100-feature-one"],
                cwd=main_repo,
                capture_output=True,
            )
            f1 = os.path.join(main_repo, "feature1.py")
            with open(f1, "w") as f:
                f.write("# Feature 1\n")
            subprocess.run(["git", "add", "."], cwd=main_repo, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", "Feature 1"],
                cwd=main_repo,
                capture_output=True,
            )

            # Create feature-2 from main
            subprocess.run(
                ["git", "checkout", "main"], cwd=main_repo, capture_output=True
            )
            subprocess.run(
                ["git", "checkout", "-b", "101-feature-two"],
                cwd=main_repo,
                capture_output=True,
            )
            f2 = os.path.join(main_repo, "feature2.py")
            with open(f2, "w") as f:
                f.write("# Feature 2\n")
            subprocess.run(["git", "add", "."], cwd=main_repo, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", "Feature 2"],
                cwd=main_repo,
                capture_output=True,
            )

            # Create hotfix from main
            subprocess.run(
                ["git", "checkout", "main"], cwd=main_repo, capture_output=True
            )
            subprocess.run(
                ["git", "checkout", "-b", "hotfix-critical"],
                cwd=main_repo,
                capture_output=True,
            )
            hf = os.path.join(main_repo, "hotfix.py")
            with open(hf, "w") as f:
                f.write("# Hotfix\n")
            subprocess.run(["git", "add", "."], cwd=main_repo, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", "Hotfix"],
                cwd=main_repo,
                capture_output=True,
            )

            subprocess.run(
                ["git", "checkout", "main"], cwd=main_repo, capture_output=True
            )

            yield main_repo

    def test_detects_multiple_branches(self, complex_git_repo):
        """Test that multiple branches are detected."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )

        result = build_worktree_map(complex_git_repo)

        # Should have main + 3 branches
        assert len(result.nodes) >= 4

    def test_assigns_correct_branch_types(self, complex_git_repo):
        """Test that branch types are correctly detected."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )
        from i3_project_manager.models.worktree_relationship import NodeType

        result = build_worktree_map(complex_git_repo)

        main_node = result.get_node("main")
        hotfix_node = result.get_node("hotfix-critical")

        assert main_node.node_type == NodeType.MAIN
        if hotfix_node:
            assert hotfix_node.node_type == NodeType.HOTFIX

    def test_creates_parent_child_edges(self, complex_git_repo):
        """Test that parent-child relationships are detected."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )
        from i3_project_manager.models.worktree_relationship import EdgeType

        result = build_worktree_map(complex_git_repo)

        # All feature branches should have edge from main
        parent_child_edges = [
            e for e in result.edges if e.edge_type == EdgeType.PARENT_CHILD
        ]
        assert len(parent_child_edges) >= 1

        # Main should be source of at least one edge
        main_as_source = [e for e in parent_child_edges if e.source_branch == "main"]
        assert len(main_as_source) >= 1


class TestBuildWorktreeMapEdgeCases:
    """Edge case tests for build_worktree_map."""

    def test_handles_empty_repo(self):
        """Test handling of empty (no commits) repository."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.run(["git", "init"], cwd=tmpdir, capture_output=True)

            result = build_worktree_map(tmpdir)

            # Should handle gracefully - empty map or single node
            assert result is None or len(result.nodes) <= 1

    def test_handles_repo_with_only_main(self):
        """Test repo with only main branch (no features)."""
        from i3_project_manager.services.worktree_map_service import (
            build_worktree_map,
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.run(["git", "init"], cwd=tmpdir, capture_output=True)
            subprocess.run(
                ["git", "config", "user.email", "test@test.com"],
                cwd=tmpdir,
                capture_output=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "Test"],
                cwd=tmpdir,
                capture_output=True,
            )
            readme = os.path.join(tmpdir, "README.md")
            with open(readme, "w") as f:
                f.write("# Test\n")
            subprocess.run(["git", "add", "."], cwd=tmpdir, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", "Initial"],
                cwd=tmpdir,
                capture_output=True,
            )

            result = build_worktree_map(tmpdir)

            assert result is not None
            assert len(result.nodes) == 1
            assert result.nodes[0].branch in ["main", "master"]

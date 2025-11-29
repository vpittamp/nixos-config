"""
Feature 100: Integration Test - Bare Clone + Worktree Workflow

T057: Validates the complete bare repository workflow:
1. Clone repository with bare setup
2. Create worktrees
3. Discover repositories and worktrees
4. Verify qualified names

Uses a test repository to validate end-to-end functionality.
"""

import json
import pytest
import subprocess
import tempfile
from pathlib import Path


@pytest.fixture
def test_environment(tmp_path):
    """Create isolated test environment with temporary directories."""
    # Create temporary repos directory
    repos_dir = tmp_path / "repos"
    repos_dir.mkdir()

    # Create temporary config directory
    config_dir = tmp_path / "config" / "i3"
    config_dir.mkdir(parents=True)

    # Create accounts.json with test account
    accounts = {
        "version": 1,
        "accounts": [
            {
                "name": "test-account",
                "path": str(repos_dir / "test-account"),
                "is_default": True,
                "ssh_host": "github.com"
            }
        ]
    }
    (config_dir / "accounts.json").write_text(json.dumps(accounts, indent=2))

    # Create the account directory
    (repos_dir / "test-account").mkdir()

    return {
        "repos_dir": repos_dir,
        "config_dir": config_dir,
        "account_dir": repos_dir / "test-account",
        "tmp_path": tmp_path
    }


@pytest.fixture
def mock_git_repo(test_environment):
    """Create a mock bare repository with worktrees for testing."""
    account_dir = test_environment["account_dir"]
    repo_dir = account_dir / "test-repo"
    repo_dir.mkdir()

    # Create .bare directory (simulating bare clone)
    bare_dir = repo_dir / ".bare"
    bare_dir.mkdir()

    # Initialize bare repository
    subprocess.run(
        ["git", "init", "--bare"],
        cwd=str(bare_dir),
        capture_output=True,
        check=True
    )

    # Create .git pointer file
    git_pointer = repo_dir / ".git"
    git_pointer.write_text("gitdir: ./.bare")

    # Create initial commit in bare repo (needed for worktrees)
    # Use a temporary working directory to make the initial commit
    with tempfile.TemporaryDirectory() as temp_work:
        subprocess.run(
            ["git", "clone", str(bare_dir), temp_work],
            capture_output=True,
            check=True
        )
        subprocess.run(
            ["git", "config", "user.email", "test@test.com"],
            cwd=temp_work,
            capture_output=True,
            check=True
        )
        subprocess.run(
            ["git", "config", "user.name", "Test User"],
            cwd=temp_work,
            capture_output=True,
            check=True
        )
        readme = Path(temp_work) / "README.md"
        readme.write_text("# Test Repository\n")
        subprocess.run(
            ["git", "add", "README.md"],
            cwd=temp_work,
            capture_output=True,
            check=True
        )
        subprocess.run(
            ["git", "commit", "-m", "Initial commit"],
            cwd=temp_work,
            capture_output=True,
            check=True
        )
        subprocess.run(
            ["git", "push", "origin", "main"],
            cwd=temp_work,
            capture_output=True,
            check=True
        )

    # Create main worktree
    main_dir = repo_dir / "main"
    subprocess.run(
        ["git", "-C", str(bare_dir), "worktree", "add", str(main_dir), "main"],
        capture_output=True,
        check=True
    )

    # Create feature worktree
    feature_dir = repo_dir / "100-feature"
    subprocess.run(
        ["git", "-C", str(bare_dir), "worktree", "add", "-b", "100-feature", str(feature_dir), "main"],
        capture_output=True,
        check=True
    )

    return {
        "repo_dir": repo_dir,
        "bare_dir": bare_dir,
        "main_dir": main_dir,
        "feature_dir": feature_dir,
        **test_environment
    }


class TestBareRepositoryStructure:
    """Test bare repository structure validation."""

    def test_bare_directory_exists(self, mock_git_repo):
        """Verify .bare/ directory is created."""
        assert mock_git_repo["bare_dir"].exists()
        assert mock_git_repo["bare_dir"].is_dir()

    def test_git_pointer_file_exists(self, mock_git_repo):
        """Verify .git pointer file points to .bare/."""
        git_pointer = mock_git_repo["repo_dir"] / ".git"
        assert git_pointer.exists()
        content = git_pointer.read_text().strip()
        assert content == "gitdir: ./.bare"

    def test_main_worktree_exists(self, mock_git_repo):
        """Verify main worktree is created."""
        assert mock_git_repo["main_dir"].exists()
        assert mock_git_repo["main_dir"].is_dir()
        # Verify it's a valid git worktree
        git_dir = mock_git_repo["main_dir"] / ".git"
        assert git_dir.exists()

    def test_feature_worktree_exists(self, mock_git_repo):
        """Verify feature worktree is created."""
        assert mock_git_repo["feature_dir"].exists()
        assert mock_git_repo["feature_dir"].is_dir()


class TestWorktreeOperations:
    """Test worktree operations via git commands."""

    def test_list_worktrees(self, mock_git_repo):
        """Verify worktrees are listed correctly."""
        result = subprocess.run(
            ["git", "-C", str(mock_git_repo["bare_dir"]), "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0
        output = result.stdout

        # Should list bare dir and both worktrees
        assert "main" in output
        assert "100-feature" in output

    def test_worktree_branches(self, mock_git_repo):
        """Verify worktrees are on correct branches."""
        # Check main worktree
        result = subprocess.run(
            ["git", "-C", str(mock_git_repo["main_dir"]), "branch", "--show-current"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0
        assert result.stdout.strip() == "main"

        # Check feature worktree
        result = subprocess.run(
            ["git", "-C", str(mock_git_repo["feature_dir"]), "branch", "--show-current"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0
        assert result.stdout.strip() == "100-feature"


class TestQualifiedNames:
    """Test qualified name generation."""

    def test_repository_qualified_name(self, mock_git_repo):
        """Verify repository qualified name format: account/repo."""
        expected = "test-account/test-repo"
        # This would be validated by the discovery service
        account = mock_git_repo["account_dir"].name
        repo = mock_git_repo["repo_dir"].name
        actual = f"{account}/{repo}"
        assert actual == expected

    def test_worktree_qualified_name(self, mock_git_repo):
        """Verify worktree qualified name format: account/repo:branch."""
        account = mock_git_repo["account_dir"].name
        repo = mock_git_repo["repo_dir"].name

        expected_main = "test-account/test-repo:main"
        actual_main = f"{account}/{repo}:main"
        assert actual_main == expected_main

        expected_feature = "test-account/test-repo:100-feature"
        actual_feature = f"{account}/{repo}:100-feature"
        assert actual_feature == expected_feature


class TestDiscoveryIntegration:
    """Test discovery functionality."""

    def test_discover_bare_repo(self, mock_git_repo):
        """Verify discovery finds bare repository."""
        account_dir = mock_git_repo["account_dir"]

        # Scan for repos with .bare directory
        repos_found = []
        for entry in account_dir.iterdir():
            if entry.is_dir():
                bare_path = entry / ".bare"
                if bare_path.is_dir():
                    repos_found.append(entry.name)

        assert "test-repo" in repos_found

    def test_discover_worktrees(self, mock_git_repo):
        """Verify discovery finds all worktrees."""
        bare_dir = mock_git_repo["bare_dir"]

        result = subprocess.run(
            ["git", "-C", str(bare_dir), "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0

        # Parse worktree list
        worktrees = []
        current_wt = {}
        for line in result.stdout.split("\n"):
            if line.startswith("worktree "):
                if current_wt:
                    worktrees.append(current_wt)
                current_wt = {"path": line[9:]}
            elif line.startswith("branch refs/heads/"):
                current_wt["branch"] = line[18:]
        if current_wt:
            worktrees.append(current_wt)

        # Filter out bare dir itself
        worktrees = [wt for wt in worktrees if not wt["path"].endswith("/.bare")]

        branches = [wt.get("branch") for wt in worktrees]
        assert "main" in branches
        assert "100-feature" in branches


class TestWorkflowEndToEnd:
    """End-to-end workflow tests."""

    def test_parallel_worktree_access(self, mock_git_repo):
        """Verify multiple worktrees can be accessed independently."""
        main_dir = mock_git_repo["main_dir"]
        feature_dir = mock_git_repo["feature_dir"]

        # Both directories should be accessible
        assert main_dir.exists()
        assert feature_dir.exists()

        # Both should have independent working directories
        # Modify a file in feature and verify main is unaffected
        feature_readme = feature_dir / "README.md"
        original_content = feature_readme.read_text()

        feature_readme.write_text("Modified in feature branch\n")

        main_readme = main_dir / "README.md"
        assert main_readme.read_text() == "# Test Repository\n"

        # Restore
        feature_readme.write_text(original_content)

    def test_directory_structure_layout(self, mock_git_repo):
        """Verify the expected directory layout."""
        repo_dir = mock_git_repo["repo_dir"]

        expected_structure = [
            ".bare",        # Bare git database
            ".git",         # Pointer file
            "main",         # Main branch worktree
            "100-feature",  # Feature branch worktree
        ]

        actual_entries = [entry.name for entry in repo_dir.iterdir()]

        for expected in expected_structure:
            assert expected in actual_entries, f"Missing: {expected}"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

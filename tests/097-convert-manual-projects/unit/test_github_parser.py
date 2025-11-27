"""
Unit tests for GitHub CLI output parsing.

Feature 097: Git-Based Project Discovery and Management
Task T037: Test gh CLI output parsing

Tests parsing of `gh repo list` JSON output into structured GitHubRepo objects.
"""

import pytest


class TestGitHubOutputParser:
    """Test cases for parsing gh CLI output."""

    def test_parse_single_repo(self):
        """Should parse a single repository from gh output."""
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            GitHubRepo
        )

        gh_output = {
            "name": "my-project",
            "nameWithOwner": "user/my-project",
            "url": "https://github.com/user/my-project",
            "sshUrl": "git@github.com:user/my-project.git",
            "isPrivate": False,
            "isFork": False,
            "isArchived": False,
            "primaryLanguage": {"name": "Python"},
            "pushedAt": "2024-01-15T10:30:00Z"
        }

        repo = GitHubRepo.from_gh_json(gh_output)

        assert repo.name == "my-project"
        assert repo.full_name == "user/my-project"
        assert repo.clone_url == "https://github.com/user/my-project"
        assert repo.ssh_url == "git@github.com:user/my-project.git"
        assert repo.is_private is False
        assert repo.is_fork is False
        assert repo.is_archived is False
        assert repo.primary_language == "Python"

    def test_parse_private_repo(self):
        """Should correctly identify private repositories."""
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            GitHubRepo
        )

        gh_output = {
            "name": "private-project",
            "nameWithOwner": "user/private-project",
            "url": "https://github.com/user/private-project",
            "sshUrl": "git@github.com:user/private-project.git",
            "isPrivate": True,
            "isFork": False,
            "isArchived": False,
            "primaryLanguage": None,
            "pushedAt": "2024-01-10T08:00:00Z"
        }

        repo = GitHubRepo.from_gh_json(gh_output)

        assert repo.is_private is True
        assert repo.primary_language is None

    def test_parse_forked_repo(self):
        """Should correctly identify forked repositories."""
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            GitHubRepo
        )

        gh_output = {
            "name": "forked-project",
            "nameWithOwner": "user/forked-project",
            "url": "https://github.com/user/forked-project",
            "sshUrl": "git@github.com:user/forked-project.git",
            "isPrivate": False,
            "isFork": True,
            "isArchived": False,
            "primaryLanguage": {"name": "JavaScript"},
            "pushedAt": "2024-01-05T15:00:00Z"
        }

        repo = GitHubRepo.from_gh_json(gh_output)

        assert repo.is_fork is True

    def test_parse_archived_repo(self):
        """Should correctly identify archived repositories."""
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            GitHubRepo
        )

        gh_output = {
            "name": "old-project",
            "nameWithOwner": "user/old-project",
            "url": "https://github.com/user/old-project",
            "sshUrl": "git@github.com:user/old-project.git",
            "isPrivate": False,
            "isFork": False,
            "isArchived": True,
            "primaryLanguage": {"name": "Go"},
            "pushedAt": "2023-06-01T00:00:00Z"
        }

        repo = GitHubRepo.from_gh_json(gh_output)

        assert repo.is_archived is True

    def test_parse_multiple_repos(self):
        """Should parse multiple repositories from gh output."""
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            GitHubRepo
        )

        gh_output = [
            {
                "name": "repo-a",
                "nameWithOwner": "user/repo-a",
                "url": "https://github.com/user/repo-a",
                "sshUrl": "git@github.com:user/repo-a.git",
                "isPrivate": False,
                "isFork": False,
                "isArchived": False,
                "primaryLanguage": {"name": "Rust"},
                "pushedAt": "2024-01-20T12:00:00Z"
            },
            {
                "name": "repo-b",
                "nameWithOwner": "user/repo-b",
                "url": "https://github.com/user/repo-b",
                "sshUrl": "git@github.com:user/repo-b.git",
                "isPrivate": True,
                "isFork": False,
                "isArchived": False,
                "primaryLanguage": None,
                "pushedAt": "2024-01-18T09:00:00Z"
            }
        ]

        repos = [GitHubRepo.from_gh_json(r) for r in gh_output]

        assert len(repos) == 2
        assert repos[0].name == "repo-a"
        assert repos[0].primary_language == "Rust"
        assert repos[1].name == "repo-b"
        assert repos[1].is_private is True

    def test_parse_repo_with_null_language(self):
        """Should handle repositories with no primary language."""
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            GitHubRepo
        )

        gh_output = {
            "name": "config-repo",
            "nameWithOwner": "user/config-repo",
            "url": "https://github.com/user/config-repo",
            "sshUrl": "git@github.com:user/config-repo.git",
            "isPrivate": False,
            "isFork": False,
            "isArchived": False,
            "primaryLanguage": None,
            "pushedAt": "2024-01-01T00:00:00Z"
        }

        repo = GitHubRepo.from_gh_json(gh_output)

        assert repo.primary_language is None

    def test_parse_organization_repo(self):
        """Should parse organization repositories correctly."""
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            GitHubRepo
        )

        gh_output = {
            "name": "org-project",
            "nameWithOwner": "organization/org-project",
            "url": "https://github.com/organization/org-project",
            "sshUrl": "git@github.com:organization/org-project.git",
            "isPrivate": True,
            "isFork": False,
            "isArchived": False,
            "primaryLanguage": {"name": "TypeScript"},
            "pushedAt": "2024-01-25T14:00:00Z"
        }

        repo = GitHubRepo.from_gh_json(gh_output)

        assert repo.full_name == "organization/org-project"
        # Extract owner from full_name
        assert repo.full_name.split("/")[0] == "organization"

"""
GitHub service for Feature 097: Git-Based Project Discovery and Management.

Provides functions for:
- Listing GitHub repositories via gh CLI
- Checking authentication status
- Correlating GitHub repos with local clones

Per Constitution Principle X: Python 3.11+, async/await, Pydantic.
"""

import asyncio
import json
import logging
from typing import List

from ..models.discovery import (
    DiscoveryError,
    GitHubListResult,
    GitHubRepo,
)

logger = logging.getLogger(__name__)


async def check_auth() -> bool:
    """Check if gh CLI is authenticated with GitHub.

    Feature 097 T041: Authentication check before listing repos.

    Returns:
        True if authenticated, False otherwise
    """
    try:
        proc = await asyncio.create_subprocess_exec(
            "gh", "auth", "status",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()

        if proc.returncode == 0:
            logger.debug("[Feature 097] gh CLI authenticated")
            return True

        logger.warning(
            f"[Feature 097] gh CLI not authenticated: {stderr.decode()}"
        )
        return False

    except FileNotFoundError:
        logger.error("[Feature 097] gh CLI not found in PATH")
        return False
    except Exception as e:
        logger.error(f"[Feature 097] gh auth check failed: {e}")
        return False


async def list_repos(
    limit: int = 100,
    include_private: bool = True,
    include_forks: bool = True,
    include_archived: bool = False,
) -> GitHubListResult:
    """List GitHub repositories using gh CLI.

    Feature 097 T040: List repos via gh CLI.

    Args:
        limit: Maximum number of repos to fetch
        include_private: Include private repositories
        include_forks: Include forked repositories
        include_archived: Include archived repositories

    Returns:
        GitHubListResult with repos and any errors
    """
    errors: List[DiscoveryError] = []

    try:
        # Build gh repo list command
        # Using JSON output format with specific fields
        cmd = [
            "gh", "repo", "list",
            "--json", "name,nameWithOwner,url,sshUrl,isPrivate,isFork,isArchived,primaryLanguage,pushedAt,description",
            "--limit", str(limit),
        ]

        if not include_archived:
            cmd.extend(["--archived", "false"])

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()

        if proc.returncode != 0:
            error_msg = stderr.decode().strip()
            logger.error(f"[Feature 097] gh repo list failed: {error_msg}")
            errors.append(DiscoveryError(
                path="gh://repo/list",
                error_type="gh_cli_error",
                message=error_msg
            ))
            return GitHubListResult(
                success=False,
                repos=[],
                total_count=0,
                errors=errors
            )

        # Parse JSON output
        try:
            repos_data = json.loads(stdout.decode())
        except json.JSONDecodeError as e:
            logger.error(f"[Feature 097] Failed to parse gh output: {e}")
            errors.append(DiscoveryError(
                path="gh://repo/list",
                error_type="json_parse_error",
                message=str(e)
            ))
            return GitHubListResult(
                success=False,
                repos=[],
                total_count=0,
                errors=errors
            )

        # Convert to GitHubRepo objects
        repos: List[GitHubRepo] = []
        for repo_data in repos_data:
            try:
                repo = GitHubRepo.from_gh_json(repo_data)

                # Apply filters
                if not include_private and repo.is_private:
                    continue
                if not include_forks and repo.is_fork:
                    continue
                if not include_archived and repo.is_archived:
                    continue

                repos.append(repo)

            except Exception as e:
                logger.warning(
                    f"[Feature 097] Failed to parse repo {repo_data.get('name', 'unknown')}: {e}"
                )
                errors.append(DiscoveryError(
                    path=f"gh://repo/{repo_data.get('nameWithOwner', 'unknown')}",
                    error_type="parse_error",
                    message=str(e)
                ))

        logger.info(
            f"[Feature 097] Listed {len(repos)} GitHub repositories"
        )

        return GitHubListResult(
            success=True,
            repos=repos,
            total_count=len(repos),
            errors=errors
        )

    except FileNotFoundError:
        logger.error("[Feature 097] gh CLI not found in PATH")
        errors.append(DiscoveryError(
            path="gh://cli",
            error_type="not_found",
            message="gh CLI not found in PATH. Install with: nix-env -iA nixpkgs.gh"
        ))
        return GitHubListResult(
            success=False,
            repos=[],
            total_count=0,
            errors=errors
        )

    except Exception as e:
        logger.error(f"[Feature 097] GitHub discovery failed: {e}")
        errors.append(DiscoveryError(
            path="gh://repo/list",
            error_type="unexpected_error",
            message=str(e)
        ))
        return GitHubListResult(
            success=False,
            repos=[],
            total_count=0,
            errors=errors
        )


async def list_repos_for_user(
    username: str,
    limit: int = 100,
) -> GitHubListResult:
    """List public repositories for a specific GitHub user.

    Args:
        username: GitHub username
        limit: Maximum number of repos to fetch

    Returns:
        GitHubListResult with repos
    """
    errors: List[DiscoveryError] = []

    try:
        cmd = [
            "gh", "repo", "list", username,
            "--json", "name,nameWithOwner,url,sshUrl,isPrivate,isFork,isArchived,primaryLanguage,pushedAt,description",
            "--limit", str(limit),
        ]

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()

        if proc.returncode != 0:
            error_msg = stderr.decode().strip()
            errors.append(DiscoveryError(
                path=f"gh://user/{username}",
                error_type="gh_cli_error",
                message=error_msg
            ))
            return GitHubListResult(
                success=False,
                repos=[],
                total_count=0,
                errors=errors
            )

        repos_data = json.loads(stdout.decode())
        repos = [GitHubRepo.from_gh_json(r) for r in repos_data]

        return GitHubListResult(
            success=True,
            repos=repos,
            total_count=len(repos),
            errors=errors
        )

    except Exception as e:
        errors.append(DiscoveryError(
            path=f"gh://user/{username}",
            error_type="unexpected_error",
            message=str(e)
        ))
        return GitHubListResult(
            success=False,
            repos=[],
            total_count=0,
            errors=errors
        )

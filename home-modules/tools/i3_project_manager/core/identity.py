"""Identity and normalization utilities for i3-project-manager."""

import json
import os
import re
from typing import Any, Dict, Optional


_DISCOVERED_WORKTREE_CACHE: Dict[str, Any] = {
    "mtime_ns": None,
    "size": None,
    "by_path": {},
}

def normalize_session_name_key(value: Optional[str]) -> str:
    """Normalize session names so separator variants map to one logical key.
    Treats stacks/main, stacks_main, and stacks-main as the same identity.
    """
    raw = str(value or "").strip().lower()
    if not raw:
        return ""
    return re.sub(r"[^a-z0-9]+", "-", raw).strip("-")


def normalize_project_path(value: Optional[str]) -> Optional[str]:
    """Normalize a filesystem path for stable worktree identity lookup."""
    if not value or not isinstance(value, str):
        return None
    try:
        expanded = os.path.expanduser(value.strip())
        if not expanded:
            return None
        return os.path.realpath(expanded)
    except Exception:
        return str(value).strip() or None


def parse_context_key_project(value: Optional[str]) -> str:
    """Extract the qualified worktree name from `<qualified>::<mode>::<connection>`."""
    raw = str(value or "").strip()
    if not raw:
        return ""
    parts = raw.split("::")
    if len(parts) < 3:
        return ""
    return "::".join(parts[:-2]).strip()


def resolve_discovered_worktree(path_value: Optional[str]) -> Optional[Dict[str, str]]:
    """Resolve a canonical worktree entry from `repos.json` by normalized path."""
    normalized = normalize_project_path(path_value)
    if not normalized:
        return None

    repos_file = os.path.expanduser("~/.config/i3/repos.json")
    if not os.path.exists(repos_file):
        _DISCOVERED_WORKTREE_CACHE.update({
            "mtime_ns": None,
            "size": None,
            "by_path": {},
        })
        return None

    try:
        stat_result = os.stat(repos_file)
    except OSError:
        return None

    cached_mapping = _DISCOVERED_WORKTREE_CACHE.get("by_path")
    if (
        _DISCOVERED_WORKTREE_CACHE.get("mtime_ns") != stat_result.st_mtime_ns
        or _DISCOVERED_WORKTREE_CACHE.get("size") != stat_result.st_size
        or not isinstance(cached_mapping, dict)
    ):
        try:
            with open(repos_file, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except (OSError, json.JSONDecodeError):
            return None

        mapping: Dict[str, Dict[str, str]] = {}
        repositories = payload.get("repositories", []) if isinstance(payload, dict) else []
        for repo in repositories if isinstance(repositories, list) else []:
            if not isinstance(repo, dict):
                continue
            account = str(repo.get("account") or "").strip()
            repo_name = str(repo.get("name") or "").strip()
            repo_qualified = f"{account}/{repo_name}" if account and repo_name else ""
            if not repo_qualified:
                continue
            worktrees = repo.get("worktrees", [])
            if not isinstance(worktrees, list):
                continue
            for worktree in worktrees:
                if not isinstance(worktree, dict):
                    continue
                branch = str(worktree.get("branch") or "").strip()
                worktree_path = normalize_project_path(worktree.get("path"))
                if not branch or not worktree_path:
                    continue
                mapping[worktree_path] = {
                    "qualified_name": f"{repo_qualified}:{branch}",
                    "repo_qualified_name": repo_qualified,
                    "account": account,
                    "repo_name": repo_name,
                    "branch": branch,
                    "path": worktree_path,
                }

        _DISCOVERED_WORKTREE_CACHE.update({
            "mtime_ns": stat_result.st_mtime_ns,
            "size": stat_result.st_size,
            "by_path": mapping,
        })
        cached_mapping = mapping

    if not isinstance(cached_mapping, dict):
        return None
    entry = cached_mapping.get(normalized)
    if not isinstance(entry, dict):
        return None
    return dict(entry)

def project_names_match(
    preferred_project: Optional[str], candidate_project: Optional[str]
) -> bool:
    """Best-effort project name matching across short/qualified forms."""
    if not preferred_project or not candidate_project:
        return False

    preferred = preferred_project.strip().lower()
    candidate = candidate_project.strip().lower()
    if not preferred or not candidate:
        return False
    if preferred == candidate:
        return True

    def normalize(name: str) -> str:
        return re.sub(r"[:/]+", "/", name)
        
    pref_norm = normalize(preferred)
    cand_norm = normalize(candidate)
    
    if pref_norm.endswith("/" + cand_norm) or cand_norm.endswith("/" + pref_norm):
        return True
        
    return normalize_session_name_key(preferred) == normalize_session_name_key(candidate)

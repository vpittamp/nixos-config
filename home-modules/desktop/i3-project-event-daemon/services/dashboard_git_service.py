"""Dashboard git snapshot normalization helpers."""

from __future__ import annotations

import hashlib
import json
import re
import time
from typing import Any, Dict, Optional, Tuple


class DashboardGitService:
    """Pure helpers for dashboard worktree/session git status fields."""

    def __init__(
        self,
        *,
        ttl_current: float = 3.0,
        ttl_visible: float = 8.0,
        ttl_background: float = 20.0,
        ttl_failure: float = 30.0,
    ) -> None:
        self.ttl_current = ttl_current
        self.ttl_visible = ttl_visible
        self.ttl_background = ttl_background
        self.ttl_failure = ttl_failure

    def snapshot_ttl(self, priority: str, *, success: bool = True) -> float:
        """Return the cache TTL for a live git snapshot priority bucket."""
        if not success:
            return self.ttl_failure
        normalized = str(priority or "background").strip().lower()
        if normalized == "current":
            return self.ttl_current
        if normalized == "visible":
            return self.ttl_visible
        return self.ttl_background

    @staticmethod
    def snapshot_freshness(age_seconds: int, ttl_seconds: float, *, success: bool) -> str:
        """Classify a cached git snapshot by freshness."""
        if not success:
            return "stale"
        if age_seconds <= ttl_seconds:
            return "fresh"
        if age_seconds <= (ttl_seconds * 3):
            return "aging"
        return "stale"

    @staticmethod
    def snapshot_state(*, has_conflicts: bool, dirty_count: int) -> str:
        """Normalize the visual git state label."""
        if has_conflicts:
            return "conflicted"
        if dirty_count > 0:
            return "dirty"
        return "clean"

    @staticmethod
    def parse_ahead_behind(branch_header: str) -> Tuple[int, int]:
        """Parse ahead/behind counts from `git status --porcelain=v1 --branch`."""
        ahead = 0
        behind = 0
        match = re.search(r"\[([^\]]+)\]", str(branch_header or ""))
        if not match:
            return ahead, behind
        for part in match.group(1).split(","):
            normalized = str(part or "").strip()
            if normalized.startswith("ahead "):
                try:
                    ahead = int(normalized.split()[-1])
                except (TypeError, ValueError):
                    ahead = 0
            elif normalized.startswith("behind "):
                try:
                    behind = int(normalized.split()[-1])
                except (TypeError, ValueError):
                    behind = 0
        return ahead, behind

    @staticmethod
    def build_status_strings(snapshot: Dict[str, Any]) -> Tuple[str, str, str]:
        """Build compact and expanded git status labels for UI consumers."""
        state = str(snapshot.get("state") or "unknown").strip()
        dirty_count = int(snapshot.get("dirty_count") or 0)
        ahead = int(snapshot.get("ahead") or 0)
        behind = int(snapshot.get("behind") or 0)
        branch = str(snapshot.get("branch") or "").strip()
        head_oid_short = str(snapshot.get("head_oid_short") or "").strip()
        freshness = str(snapshot.get("freshness") or "").strip()
        age_seconds = int(snapshot.get("age_seconds") or 0)

        compact_parts = []
        if state == "conflicted":
            compact_parts.append("!")
        elif dirty_count > 0:
            compact_parts.append(f"● {dirty_count}")
        if ahead > 0:
            compact_parts.append(f"↑{ahead}")
        if behind > 0:
            compact_parts.append(f"↓{behind}")
        compact = " ".join(compact_parts)

        if state == "conflicted":
            label = "Conflict"
        elif dirty_count > 0:
            label = "Dirty"
        elif ahead > 0 or behind > 0:
            label = "Synced" if ahead == 0 and behind == 0 else "Tracked"
        else:
            label = "Clean"

        tooltip_parts = []
        branch_bits = [bit for bit in [branch, head_oid_short] if bit]
        if branch_bits:
            tooltip_parts.append("Branch: " + " @ ".join(branch_bits))

        status_bits = []
        staged_count = int(snapshot.get("staged_count") or 0)
        modified_count = int(snapshot.get("modified_count") or 0)
        untracked_count = int(snapshot.get("untracked_count") or 0)
        if state == "conflicted":
            status_bits.append("conflicts")
        if staged_count > 0:
            status_bits.append(f"{staged_count} staged")
        if modified_count > 0:
            status_bits.append(f"{modified_count} modified")
        if untracked_count > 0:
            status_bits.append(f"{untracked_count} untracked")
        if not status_bits:
            status_bits.append("clean")
        tooltip_parts.append("Status: " + ", ".join(status_bits))

        sync_bits = []
        if ahead > 0:
            sync_bits.append(f"{ahead} to push")
        if behind > 0:
            sync_bits.append(f"{behind} to pull")
        if sync_bits:
            tooltip_parts.append("Sync: " + ", ".join(sync_bits))

        if freshness:
            tooltip_parts.append(f"Snapshot: {freshness} ({age_seconds}s old)")

        return compact, label, "\n".join(tooltip_parts)

    @staticmethod
    def cache_fingerprint(snapshot: Dict[str, Any]) -> str:
        """Return a stable fingerprint for git-state change detection."""
        payload = {
            "qualified_name": str(snapshot.get("qualified_name") or "").strip(),
            "branch": str(snapshot.get("branch") or "").strip(),
            "head_oid_short": str(snapshot.get("head_oid_short") or "").strip(),
            "state": str(snapshot.get("state") or "").strip(),
            "has_conflicts": bool(snapshot.get("has_conflicts", False)),
            "staged_count": int(snapshot.get("staged_count") or 0),
            "modified_count": int(snapshot.get("modified_count") or 0),
            "untracked_count": int(snapshot.get("untracked_count") or 0),
            "dirty_count": int(snapshot.get("dirty_count") or 0),
            "ahead": int(snapshot.get("ahead") or 0),
            "behind": int(snapshot.get("behind") or 0),
            "available": bool(snapshot.get("available", False)),
            "probe_success": bool(snapshot.get("probe_success", False)),
        }
        return hashlib.sha256(
            json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()

    def decorate_cached_snapshot(
        self,
        snapshot: Dict[str, Any],
        *,
        priority: str,
        attribution: str,
    ) -> Dict[str, Any]:
        """Attach freshness and UI strings to a cached git snapshot."""
        decorated = dict(snapshot)
        age_seconds = int(max(0, time.time() - float(snapshot.get("snapshot_at") or 0)))
        freshness = self.snapshot_freshness(
            age_seconds,
            self.snapshot_ttl(
                priority,
                success=bool(snapshot.get("probe_success", False)),
            ),
            success=bool(snapshot.get("probe_success", False)),
        )
        decorated["age_seconds"] = age_seconds
        decorated["freshness"] = freshness
        decorated["attribution"] = attribution
        compact, label, tooltip = self.build_status_strings(decorated)
        decorated["status_compact"] = compact
        decorated["status_label"] = label
        decorated["status_tooltip"] = tooltip
        decorated["show_chip"] = bool(compact)
        return decorated

    @staticmethod
    def apply_snapshot_to_session(
        session: Dict[str, Any],
        snapshot: Optional[Dict[str, Any]],
    ) -> None:
        """Copy git snapshot fields onto a session row payload."""
        if not isinstance(session, dict):
            return
        if not isinstance(snapshot, dict):
            session["git_snapshot"] = {}
            session["git_state"] = "unknown"
            session["git_compact"] = ""
            session["git_freshness"] = ""
            session["git_attribution"] = ""
            session["git_tooltip"] = ""
            return
        session["git_snapshot"] = dict(snapshot)
        session["git_state"] = str(snapshot.get("state") or "unknown").strip()
        session["git_compact"] = str(snapshot.get("status_compact") or "").strip()
        session["git_freshness"] = str(snapshot.get("freshness") or "").strip()
        session["git_attribution"] = str(snapshot.get("attribution") or "").strip()
        session["git_tooltip"] = str(snapshot.get("status_tooltip") or "").strip()

    @staticmethod
    def apply_snapshot_to_worktree(
        worktree: Dict[str, Any],
        snapshot: Optional[Dict[str, Any]],
    ) -> None:
        """Overlay live git data onto a dashboard worktree payload."""
        if not isinstance(worktree, dict) or not isinstance(snapshot, dict):
            return
        worktree["git_state"] = str(snapshot.get("state") or "unknown").strip()
        worktree["git_freshness"] = str(snapshot.get("freshness") or "").strip()
        worktree["git_status_compact"] = str(snapshot.get("status_compact") or "").strip()
        worktree["git_status_tooltip"] = str(snapshot.get("status_tooltip") or "").strip()
        if worktree["git_state"] == "unknown":
            return
        worktree["is_clean"] = worktree["git_state"] == "clean"
        worktree["has_conflicts"] = bool(snapshot.get("has_conflicts", False))
        worktree["ahead"] = int(snapshot.get("ahead") or 0)
        worktree["behind"] = int(snapshot.get("behind") or 0)
        worktree["staged_count"] = int(snapshot.get("staged_count") or 0)
        worktree["modified_count"] = int(snapshot.get("modified_count") or 0)
        worktree["untracked_count"] = int(snapshot.get("untracked_count") or 0)
        worktree["dirty_count"] = int(snapshot.get("dirty_count") or 0)

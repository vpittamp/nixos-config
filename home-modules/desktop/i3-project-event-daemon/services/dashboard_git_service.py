"""Dashboard git snapshot normalization helpers."""

from __future__ import annotations

import hashlib
import json
import re
import time
import asyncio
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple


class DashboardGitService:
    """Pure helpers for dashboard worktree/session git status fields."""

    def __init__(
        self,
        *,
        ttl_current: float = 3.0,
        ttl_visible: float = 8.0,
        ttl_background: float = 20.0,
        ttl_failure: float = 30.0,
        git_probe_timeout_seconds: float = 2.5,
    ) -> None:
        self.ttl_current = ttl_current
        self.ttl_visible = ttl_visible
        self.ttl_background = ttl_background
        self.ttl_failure = ttl_failure
        self.git_probe_timeout_seconds = git_probe_timeout_seconds
        self._snapshot_cache: Dict[str, Dict[str, Any]] = {}
        self._snapshot_tasks: Dict[str, asyncio.Task] = {}

    def cached_snapshot_for_path(self, worktree_path: str) -> Optional[Dict[str, Any]]:
        """Return an already-probed snapshot for a checkout, without probing.

        build_spaces is synchronous and cannot await a probe, so a space with no
        sessions to inherit git fields from reads whatever hydration has already
        cached for its own checkout.
        """
        entry = self._snapshot_cache.get(str(worktree_path or "").strip())
        snapshot = entry.get("snapshot") if isinstance(entry, dict) else None
        return snapshot if isinstance(snapshot, dict) else None

    def clear_snapshot_cache(self) -> None:
        """Clear all cached live git snapshots."""
        self._snapshot_cache.clear()

    async def run_git_probe_command(
        self,
        repo_path: Path,
        *args: str,
    ) -> Tuple[int, str, str]:
        """Run a bounded git command for live session/worktree status."""
        proc: Optional[asyncio.subprocess.Process] = None
        try:
            proc = await asyncio.create_subprocess_exec(
                "git",
                *args,
                cwd=str(repo_path),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(),
                timeout=self.git_probe_timeout_seconds,
            )
            return (
                int(proc.returncode or 0),
                stdout.decode("utf-8", errors="replace").strip(),
                stderr.decode("utf-8", errors="replace").strip(),
            )
        except asyncio.TimeoutError:
            if proc is not None:
                proc.kill()
                await proc.communicate()
            return (-1, "", "timeout")
        except Exception as exc:
            return (-1, "", str(exc))

    async def probe_git_snapshot(
        self,
        *,
        worktree_path: str,
        qualified_name: str = "",
        branch_hint: str = "",
    ) -> Dict[str, Any]:
        """Probe live git state for a specific worktree path."""
        path = Path(str(worktree_path or "").strip())
        now = int(time.time())
        # Path.is_dir() hits the filesystem; keep the blocking stat off the loop.
        if not await asyncio.to_thread(path.is_dir):
            return {
                "available": False,
                "worktree_path": str(path),
                "qualified_name": str(qualified_name or "").strip(),
                "branch": str(branch_hint or "").strip(),
                "head_oid_short": "",
                "state": "unknown",
                "staged_count": 0,
                "modified_count": 0,
                "untracked_count": 0,
                "dirty_count": 0,
                "ahead": 0,
                "behind": 0,
                "repo_root": "",
                "snapshot_at": now,
                "source": "git_probe",
                "probe_success": False,
            }

        top_level_task = self.run_git_probe_command(path, "rev-parse", "--show-toplevel")
        head_task = self.run_git_probe_command(path, "rev-parse", "--short", "HEAD")
        status_task = self.run_git_probe_command(path, "status", "--porcelain=v1", "--branch")
        top_level_result, head_result, status_result = await asyncio.gather(
            top_level_task,
            head_task,
            status_task,
        )

        repo_root = top_level_result[1] if top_level_result[0] == 0 else ""
        head_oid_short = head_result[1][:7] if head_result[0] == 0 and head_result[1] else ""

        branch = str(branch_hint or "").strip()
        ahead = 0
        behind = 0
        staged_count = 0
        modified_count = 0
        untracked_count = 0
        has_conflicts = False

        lines = [
            line for line in status_result[1].splitlines()
            if str(line or "").strip()
        ] if status_result[0] == 0 else []
        if lines and lines[0].startswith("## "):
            header = lines[0][3:]
            header_branch = header.split("...", 1)[0].strip()
            if header_branch and header_branch != "HEAD (no branch)":
                branch = header_branch
            ahead, behind = self.parse_ahead_behind(header)
            lines = lines[1:]

        for line in lines:
            if len(line) < 2:
                continue
            x_status = line[0]
            y_status = line[1]
            if (
                x_status == "U"
                or y_status == "U"
                or (x_status == "A" and y_status == "A")
                or (x_status == "D" and y_status == "D")
            ):
                has_conflicts = True
            if x_status not in {" ", "?"}:
                staged_count += 1
            if y_status in {"M", "D"}:
                modified_count += 1
            if x_status == "?" and y_status == "?":
                untracked_count += 1

        dirty_count = staged_count + modified_count + untracked_count
        probe_success = status_result[0] == 0
        # A failed/timed-out status probe parses zero lines; reporting that as
        # 'clean' would fake a pristine worktree. Report 'unknown' instead.
        state = self.snapshot_state(
            has_conflicts=has_conflicts,
            dirty_count=dirty_count,
        ) if probe_success else "unknown"
        return {
            "available": bool(repo_root or probe_success),
            "worktree_path": str(path),
            "qualified_name": str(qualified_name or "").strip(),
            "branch": branch,
            "head_oid_short": head_oid_short,
            "state": state,
            "has_conflicts": has_conflicts,
            "staged_count": staged_count,
            "modified_count": modified_count,
            "untracked_count": untracked_count,
            "dirty_count": dirty_count,
            "ahead": ahead,
            "behind": behind,
            "repo_root": repo_root,
            "snapshot_at": now,
            "source": "git_probe",
            "probe_success": probe_success,
        }

    async def refresh_git_snapshot(
        self,
        *,
        worktree_path: str,
        qualified_name: str = "",
        branch_hint: str = "",
        notify: bool,
        notify_state_change: Optional[Callable[[str], Awaitable[None]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Refresh one worktree's live git snapshot and update cache."""
        normalized_path = str(worktree_path or "").strip()
        if not normalized_path:
            return None

        previous_entry = self._snapshot_cache.get(normalized_path, {})
        previous_snapshot = previous_entry.get("snapshot", {}) if isinstance(previous_entry, dict) else {}
        snapshot = await self.probe_git_snapshot(
            worktree_path=normalized_path,
            qualified_name=qualified_name,
            branch_hint=branch_hint,
        )
        fingerprint = self.cache_fingerprint(snapshot)
        self._snapshot_cache[normalized_path] = {
            "snapshot": snapshot,
            "fingerprint": fingerprint,
        }

        previous_fingerprint = ""
        if isinstance(previous_snapshot, dict) and previous_snapshot:
            previous_fingerprint = self.cache_fingerprint(previous_snapshot)
        if notify and previous_fingerprint and previous_fingerprint != fingerprint and notify_state_change is not None:
            await notify_state_change("ai_session_git_changed")
        return snapshot

    def ensure_git_snapshot_refresh(
        self,
        *,
        worktree_path: str,
        qualified_name: str = "",
        branch_hint: str = "",
        notify_state_change: Optional[Callable[[str], Awaitable[None]]] = None,
    ) -> None:
        """Schedule a background git refresh if one is not already running."""
        normalized_path = str(worktree_path or "").strip()
        if not normalized_path:
            return
        task = self._snapshot_tasks.get(normalized_path)
        if task is not None and not task.done():
            return

        async def runner() -> None:
            try:
                await self.refresh_git_snapshot(
                    worktree_path=normalized_path,
                    qualified_name=qualified_name,
                    branch_hint=branch_hint,
                    notify=True,
                    notify_state_change=notify_state_change,
                )
            finally:
                current = self._snapshot_tasks.get(normalized_path)
                if current is task_ref:
                    self._snapshot_tasks.pop(normalized_path, None)

        task_ref = asyncio.create_task(runner())
        self._snapshot_tasks[normalized_path] = task_ref

    async def get_or_schedule_git_snapshot(
        self,
        *,
        worktree_path: str,
        qualified_name: str = "",
        branch_hint: str = "",
        priority: str,
        attribution: str,
        notify_state_change: Optional[Callable[[str], Awaitable[None]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Return the best available git snapshot, refreshing lazily when possible."""
        normalized_path = str(worktree_path or "").strip()
        if not normalized_path:
            return None

        entry = self._snapshot_cache.get(normalized_path)
        if isinstance(entry, dict) and isinstance(entry.get("snapshot"), dict):
            decorated = self.decorate_cached_snapshot(
                entry["snapshot"],
                priority=priority,
                attribution=attribution,
            )
            if decorated["freshness"] == "fresh":
                return decorated
            # Serve the cached snapshot for every priority, including "current",
            # and refresh behind it. This call runs inside the dashboard notify
            # lock, so awaiting a probe here (three git subprocesses, 2.5s
            # timeout each) stalled the whole event fanout — including unrelated
            # focus deltas queued behind the lock — whenever the cache aged out.
            # The row already carries a fresh/aging/stale marker for the UI, and
            # the background refresh emits ai_session_git_changed when it lands,
            # so the value converges within one notify cycle.
            self.ensure_git_snapshot_refresh(
                worktree_path=normalized_path,
                qualified_name=qualified_name,
                branch_hint=branch_hint,
                notify_state_change=notify_state_change,
            )
            return decorated

        # No cache entry at all: a first probe still runs inline, because
        # returning None here would ship a session row with no git fields and
        # no marker to explain the gap.
        if entry is None:
            refreshed = await self.refresh_git_snapshot(
                worktree_path=normalized_path,
                qualified_name=qualified_name,
                branch_hint=branch_hint,
                notify=False,
                notify_state_change=notify_state_change,
            )
            if isinstance(refreshed, dict):
                return self.decorate_cached_snapshot(
                    refreshed,
                    priority=priority,
                    attribution=attribution,
                )

        self.ensure_git_snapshot_refresh(
            worktree_path=normalized_path,
            qualified_name=qualified_name,
            branch_hint=branch_hint,
            notify_state_change=notify_state_change,
        )
        return None

    @staticmethod
    def session_checkout_path(session: Dict[str, Any]) -> str:
        """Return the checkout a session row should be git-probed at.

        The pane's own checkout is the identity: it is derived per row from
        `git rev-parse --show-toplevel` on that pane's cwd, so it is correct for
        a worktree an agent created five seconds ago. A row with no checkout is
        not inside a work tree at all, and probing its cwd would burn three git
        subprocesses to learn "unknown" — which is exactly what a row with no
        snapshot already reports.
        """
        if not isinstance(session, dict):
            return ""
        return str(session.get("checkout_path") or "").strip()

    async def hydrate_runtime_git_state(
        self,
        runtime_snapshot: Dict[str, Any],
        sessions: List[Dict[str, Any]],
        *,
        get_or_schedule_git_snapshot: Optional[Callable[..., Awaitable[Optional[Dict[str, Any]]]]] = None,
    ) -> None:
        """Attach live git snapshots to session rows, keyed by each row's checkout.

        Probing used to be gated on the session's project_name being present in
        the `repos.json`-derived worktree inventory. That inventory is only
        rebuilt by a producer no workflow reaches any more, so every worktree an
        agent created with plain `git worktree add` failed the gate and silently
        rendered with no git status at all. Targets are now the live rows' own
        checkouts, which also shrinks the probe set from "inventory rows with
        windows" to "live sessions".
        """
        target_specs: Dict[str, Dict[str, str]] = {}

        current_session_key = str(runtime_snapshot.get("current_session_key") or "").strip()
        current_session = next(
            (
                session for session in sessions
                if isinstance(session, dict) and str(session.get("session_key") or "").strip() == current_session_key
            ),
            None,
        )
        for session in sessions:
            if not isinstance(session, dict):
                continue
            if bool(session.get("is_remote_herdr", False)):
                continue
            checkout_path = self.session_checkout_path(session)
            if not checkout_path:
                continue
            priority = "current" if session is current_session else "visible"
            branch_hint = str(session.get("branch_label") or "").strip()
            qualified_name = str(
                session.get("canonical_project_name")
                or session.get("project_name")
                or session.get("project")
                or ""
            ).strip()
            existing = target_specs.get(checkout_path)
            if existing is None:
                target_specs[checkout_path] = {
                    "priority": priority,
                    "attribution": "exact_worktree",
                    "branch_hint": branch_hint,
                    "qualified_name": qualified_name,
                }
                continue
            if priority == "current":
                existing["priority"] = "current"
            if branch_hint and not str(existing.get("branch_hint") or "").strip():
                existing["branch_hint"] = branch_hint
            if qualified_name and not str(existing.get("qualified_name") or "").strip():
                existing["qualified_name"] = qualified_name

        get_snapshot = get_or_schedule_git_snapshot or self.get_or_schedule_git_snapshot
        snapshots_by_path: Dict[str, Dict[str, Any]] = {}
        for checkout_path, spec in target_specs.items():
            snapshot = await get_snapshot(
                worktree_path=checkout_path,
                qualified_name=str(spec.get("qualified_name") or "").strip(),
                branch_hint=str(spec.get("branch_hint") or "").strip(),
                priority=str(spec.get("priority") or "background"),
                attribution=str(spec.get("attribution") or "exact_worktree"),
            )
            if isinstance(snapshot, dict):
                snapshots_by_path[checkout_path] = snapshot

        for session in sessions:
            if not isinstance(session, dict):
                continue
            if bool(session.get("is_remote_herdr", False)):
                continue
            self.apply_snapshot_to_session(
                session,
                snapshots_by_path.get(self.session_checkout_path(session)),
            )

        # Deliberately NOT applied to the space rows here: the payload's spaces
        # come from a fresh build_spaces() call at assembly time, so mutating
        # these would write to a throwaway object. Probing above is what matters
        # — it fills the cache that build_spaces reads via
        # cached_snapshot_for_path().

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
        if not bool(snapshot.get("probe_success", True)):
            # A failed probe carries zeroed counts, so the fake-clean state and
            # compact string must not be published. Session rows are rebuilt
            # fresh each snapshot and carry no prior git_* keys, so returning
            # here would drop the chip entirely; write the honest "unknown /
            # stale" fields instead and leave the count-bearing keys alone.
            session["git_state"] = "unknown"
            session["git_freshness"] = str(snapshot.get("freshness") or "stale").strip()
            session["git_attribution"] = str(snapshot.get("attribution") or "").strip()
            session["git_tooltip"] = str(snapshot.get("status_tooltip") or "").strip()
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
        if not bool(snapshot.get("probe_success", True)):
            # A failed probe carries zeroed counts; keep the worktree's genuine
            # counts from the repository scan instead of overwriting with zeros.
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

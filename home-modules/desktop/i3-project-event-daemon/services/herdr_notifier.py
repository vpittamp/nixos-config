"""Desktop notifications for Herdr agent state changes.

Herdr can post its own toasts (``[ui.toast] delivery = "system"``), but it does
so by shelling out to ``notify-send`` with nothing but a summary and a body::

    app_name "notify-send"   summary "claude needs attention"
    body "nixos-config - 2 - 4"   actions []   hints {urgency, sender-pid}

The pane it is about is not in there. Those trailing numbers are the workspace
and tab *display* indices, which renumber as tabs open and close, and two agents
of the same kind in one workspace differ by nothing else -- both were observed
within two minutes on this machine ("claude needs attention" on tab 4, "claude
finished" on tab 3). So a consumer cannot tell which pane to switch to, and text
matching cannot recover it. The app name is not even "herdr", so a consumer
cannot tell the notification came from Herdr at all.

The daemon already subscribes to ``pane.agent_status_changed`` for every pane and
holds the enriched dashboard row (repo, branch, title, session key, focus
target). Emitting the notification from here instead lets it carry the pane
identity as freedesktop hints, which the Quickshell shell turns into a "Switch
to pane" button. Herdr's own delivery is set to "off" in
home-modules/terminal/herdr.nix so the two never double-post.

Why hints rather than freedesktop actions: a notification action is delivered
back to the *sending* process over D-Bus, and the sender here is a fire-and-
forget ``notify-send`` that has already exited. The button has to be handled
shell-side, so what the notification must carry is identity, not behaviour.
"""

from __future__ import annotations

import asyncio
import logging
import shutil
import time
from typing import Any, Awaitable, Callable, Dict, List, Optional, Set

logger = logging.getLogger(__name__)

# Hint names the Quickshell shell reads (windows/../shell.qml,
# herdrNotificationSessionKey). Freedesktop reserves no namespace for private
# hints beyond the "x-" convention, so these are prefixed with the daemon.
HINT_SESSION = "x-i3pm-herdr-session"
HINT_PANE = "x-i3pm-herdr-pane"
HINT_HOST = "x-i3pm-herdr-host"
HINT_STATE = "x-i3pm-herdr-state"

# States worth interrupting for. "working" and "unknown" never notify; "idle"
# only notifies as the tail of a working -> idle transition, which is what
# Herdr itself calls "finished".
ATTENTION_BLOCKED = "blocked"
ATTENTION_DONE = "done"


class HerdrNotifier:
    """Emit pane-addressable desktop notifications for Herdr agent transitions."""

    def __init__(
        self,
        *,
        notify_send: Optional[str] = None,
        dedupe_window: float = 8.0,
        settle_seconds: float = 3.0,
        enabled: bool = True,
        spawn: Optional[Callable[[List[str]], Awaitable[None]]] = None,
        now: Optional[Callable[[], float]] = None,
    ) -> None:
        self._notify_send = notify_send
        self._notify_send_resolved = notify_send is not None
        self._dedupe_window = max(0.0, float(dedupe_window))
        # A transition is only news if it lasts. Agent detection reads the
        # terminal, so a screen that momentarily looks like a prompt -- or an
        # agent that touches idle between two tool calls in one turn -- would
        # otherwise fire a notification for something the user never sees. The
        # announcement waits this long and is dropped if the pane has moved on;
        # Herdr's own toast had a delay_seconds for the same reason.
        self._settle_seconds = max(0.0, float(settle_seconds))
        self._enabled = bool(enabled)
        self._spawn = spawn or self._default_spawn
        self._now = now or time.monotonic
        self._pending: Dict[str, "asyncio.Future[None]"] = {}
        # Keyed by session key, which is unique across hosts.
        self._last_state: Dict[str, str] = {}
        self._last_notified_at: Dict[str, float] = {}
        # A remote host's first payload is a full snapshot, not a diff. Seeding
        # its states without notifying stops a reconnect from re-announcing
        # every agent that was already blocked while the link was down.
        self._seeded_hosts: Set[str] = set()

    # ------------------------------------------------------------------
    # Entry points
    # ------------------------------------------------------------------
    def note_local_status(
        self,
        *,
        row: Optional[Dict[str, Any]],
        status_state: str,
    ) -> Optional[Dict[str, Any]]:
        """Consider one local ``pane.agent_status_changed`` event for notification.

        Returns the notification that was emitted, or None. The return value
        exists for tests; callers ignore it.
        """
        return self._consider(row, status_state)

    def sync_remote_rows(
        self,
        *,
        host: str,
        rows: Any,
    ) -> List[Dict[str, Any]]:
        """Diff a remote host's session rows and notify on new transitions.

        Remote Herdr reaches us as whole proxy payloads rather than discrete
        status events, so the transition has to be recovered by comparing each
        row against the state we last saw for it. This is the only way a blocked
        agent on another machine ever reaches this desktop: Herdr's own toast
        fires on the host it runs on, where nobody is sitting.
        """
        host_key = str(host or "").strip().lower()
        seeding = host_key not in self._seeded_hosts
        if host_key:
            self._seeded_hosts.add(host_key)

        emitted: List[Dict[str, Any]] = []
        if not isinstance(rows, list):
            return emitted

        for row in rows:
            if not isinstance(row, dict):
                continue
            status_state = str(row.get("agent_status_state") or "").strip().lower()
            if not status_state:
                continue
            if seeding:
                key = self._session_key(row)
                if key:
                    self._last_state[key] = status_state
                continue
            notification = self._consider(row, status_state)
            if notification is not None:
                emitted.append(notification)
        return emitted

    def forget_host(self, host: str) -> None:
        """Drop a remote host's seed marker so a reconnect re-seeds instead of announcing."""
        host_key = str(host or "").strip().lower()
        self._seeded_hosts.discard(host_key)

    # ------------------------------------------------------------------
    # Core
    # ------------------------------------------------------------------
    def _consider(
        self,
        row: Optional[Dict[str, Any]],
        status_state: str,
    ) -> Optional[Dict[str, Any]]:
        if not self._enabled or not isinstance(row, dict):
            return None

        state = str(status_state or "").strip().lower()
        key = self._session_key(row)
        if not key or not state:
            return None

        previous = self._last_state.get(key, "")
        self._last_state[key] = state

        reason = self._attention_reason(previous, state)
        if reason is None:
            return None

        # Already looking at it. Both flags are required: `focused` is Herdr's
        # own "which pane would I return to", which moves with no sway event, so
        # on its own it would suppress a notification for a pane sitting behind
        # a browser. `is_current_window` is the sway-side half.
        if bool(row.get("focused")) and bool(row.get("is_current_window")):
            return None

        last = self._last_notified_at.get(key)
        if last is not None and (self._now() - last) < self._dedupe_window:
            return None

        notification = self._build(row, reason)
        if notification is None:
            return None
        self._schedule(key, state, notification)
        return notification

    def _schedule(self, key: str, expected_state: str, notification: Dict[str, Any]) -> None:
        """Announce the transition once it has held for the settle window."""
        pending = self._pending.pop(key, None)
        if pending is not None and not pending.done():
            pending.cancel()

        try:
            asyncio.get_running_loop()
        except RuntimeError:
            # No loop (a synchronous caller): the notification is advisory.
            return

        task = asyncio.ensure_future(self._settle(key, expected_state, notification))
        self._pending[key] = task
        task.add_done_callback(lambda finished: self._pending.pop(key, None) if self._pending.get(key) is finished else None)

    async def _settle(self, key: str, expected_state: str, notification: Dict[str, Any]) -> None:
        if self._settle_seconds > 0:
            await asyncio.sleep(self._settle_seconds)
        # The pane moved on while we waited -- a prompt that answered itself, or
        # an idle blip between two tool calls. Nothing to tell the user about.
        if self._last_state.get(key) != expected_state:
            return
        self._last_notified_at[key] = self._now()
        self._dispatch(notification)

    @staticmethod
    def _attention_reason(previous: str, state: str) -> Optional[str]:
        """Return "blocked"/"done" for a transition worth announcing, else None.

        Transitions only -- re-delivery of the same state is not news. "done" is
        reported by Herdr as a working -> idle tail on the agents seen here, so
        both spellings map to the same announcement.
        """
        if state == ATTENTION_BLOCKED:
            return ATTENTION_BLOCKED if previous != ATTENTION_BLOCKED else None
        if state == ATTENTION_DONE:
            return ATTENTION_DONE if previous != ATTENTION_DONE else None
        if state == "idle" and previous == "working":
            return ATTENTION_DONE
        return None

    @staticmethod
    def _session_key(row: Dict[str, Any]) -> str:
        for field in ("session_key", "herdr_session", "render_session_key"):
            value = str(row.get(field) or "").strip()
            if value:
                return value
        pane_id = str(row.get("pane_id") or "").strip()
        return f"herdr:pane:{pane_id}" if pane_id else ""

    def _build(self, row: Dict[str, Any], reason: str) -> Optional[Dict[str, Any]]:
        pane_id = str(row.get("pane_id") or "").strip()
        session_key = self._session_key(row)
        if not session_key:
            return None

        agent = (
            str(row.get("display_tool") or "").strip()
            or str(row.get("tool") or "").strip()
            or str(row.get("agent") or "").strip()
            or "agent"
        )
        host = str(row.get("herdr_host") or row.get("host_name") or "").strip()
        is_remote = bool(row.get("is_remote_herdr"))

        summary = f"{agent} needs attention" if reason == ATTENTION_BLOCKED else f"{agent} finished"
        if is_remote and host:
            summary = f"{summary} on {host}"

        notification = {
            "summary": summary,
            "body": self._body(row),
            "urgency": "normal",
            "session_key": session_key,
            "pane_id": pane_id,
            "host": host,
            "state": reason,
        }
        return notification

    @staticmethod
    def _body(row: Dict[str, Any]) -> str:
        """Repo, branch and session title -- what Herdr's own body replaced with indices."""
        repo = str(row.get("repo_name") or "").strip()
        branch = str(row.get("branch_label") or "").strip()
        title = str(row.get("terminal_title_stripped") or row.get("terminal_title") or "").strip()

        location = f"{repo}:{branch}" if repo and branch else (repo or branch)
        parts = [part for part in (location, title) if part]
        if parts:
            return " · ".join(parts)
        # Nothing git-shaped and no title: the working directory still says more
        # than a bare pane id does.
        return str(row.get("cwd") or row.get("working_dir") or "").strip()

    # ------------------------------------------------------------------
    # Delivery
    # ------------------------------------------------------------------
    def _resolve_notify_send(self) -> str:
        if not self._notify_send_resolved:
            self._notify_send = shutil.which("notify-send") or ""
            self._notify_send_resolved = True
            if not self._notify_send:
                logger.warning(
                    "notify-send not found on PATH; Herdr agent notifications are disabled"
                )
        return self._notify_send or ""

    def _dispatch(self, notification: Dict[str, Any]) -> None:
        binary = self._resolve_notify_send()
        if not binary:
            return
        argv = [
            binary,
            "--app-name=herdr",
            "--icon=utilities-terminal",
            f"--urgency={notification['urgency']}",
            f"--hint=string:{HINT_SESSION}:{notification['session_key']}",
            f"--hint=string:{HINT_STATE}:{notification['state']}",
        ]
        if notification["pane_id"]:
            argv.append(f"--hint=string:{HINT_PANE}:{notification['pane_id']}")
        if notification["host"]:
            argv.append(f"--hint=string:{HINT_HOST}:{notification['host']}")
        # `--` so a summary that begins with a dash is not parsed as a flag.
        argv.extend(["--", notification["summary"], notification["body"]])

        try:
            asyncio.get_running_loop()
        except RuntimeError:
            # No loop (tests, or a synchronous caller): the notification is
            # advisory, so drop it rather than block.
            return
        task = asyncio.ensure_future(self._spawn(argv))
        # Fire and forget, but never let a failure surface as an unretrieved
        # exception on the event loop.
        task.add_done_callback(self._log_spawn_result)

    @staticmethod
    def _log_spawn_result(task: "asyncio.Future[None]") -> None:
        if task.cancelled():
            return
        error = task.exception()
        if error is not None:
            logger.warning("Herdr agent notification failed to send: %s", error)

    @staticmethod
    async def _default_spawn(argv: List[str]) -> None:
        process = await asyncio.create_subprocess_exec(
            *argv,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await process.wait()

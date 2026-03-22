"""Daemon-owned agent harness backed by Codex app-server."""

from __future__ import annotations

import asyncio
import contextlib
import hashlib
import json
import logging
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional

from ..config import atomic_write_json
from ..constants import ConfigPaths

logger = logging.getLogger(__name__)

HarnessSessionChangeCallback = Callable[[Any, Dict[str, Any]], Awaitable[None]]
REQUEST_TIMEOUT_SECONDS = 30.0
STALL_CHECK_INTERVAL_SECONDS = 5.0
STALL_TIMEOUT_SECONDS = 45.0
PERSISTENCE_SCHEMA_VERSION = 1
PERSISTENCE_MAX_SESSIONS = 100
PERSISTENCE_MAX_AGE_DAYS = 30
RECOVERABLE_THREAD_RESUME_ERROR_SNIPPETS = (
    "not found",
    "missing thread",
    "no such thread",
    "unknown thread",
    "does not exist",
)
FATAL_STDERR_PATTERNS = (
    "panicked at ",
    "ThreadPoolBuildError",
    "creating threadpool failed",
    "failed to spawn thread",
    "inner future panicked during poll",
    "Resource temporarily unavailable",
)
RESUMABLE_PROCESS_EXIT_CODES = {-15, 143}


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_iso(value: Any) -> datetime:
    raw = str(value or "").strip()
    if not raw:
        return datetime.fromtimestamp(0, timezone.utc)
    try:
        normalized = raw[:-1] + "+00:00" if raw.endswith("Z") else raw
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return datetime.fromtimestamp(0, timezone.utc)


def _stringify_request_id(value: Any) -> str:
    if isinstance(value, (str, int, float)):
        return str(value)
    return json.dumps(value, sort_keys=True)


def _preview_text(value: Any, limit: int = 120) -> str:
    text = str(value or "").strip()
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)].rstrip() + "…"


def _phase_label(phase: str) -> str:
    normalized = str(phase or "").strip()
    if not normalized:
        return ""
    return normalized.replace("_", " ").title()


def _is_recoverable_thread_resume_error(error: Exception) -> bool:
    message = str(error).lower()
    if "thread/resume" not in message:
        return False
    return any(snippet in message for snippet in RECOVERABLE_THREAD_RESUME_ERROR_SNIPPETS)


def _is_resumable_process_exit_message(message: Any) -> bool:
    raw = str(message or "").strip()
    if not raw:
        return False
    match = re.search(r"exited with code (-?\d+)", raw.lower())
    if not match:
        return False
    try:
        return int(match.group(1)) in RESUMABLE_PROCESS_EXIT_CODES
    except ValueError:
        return False


def _safe_session_file_name(session_key: str) -> str:
    digest = hashlib.sha1(str(session_key or "").encode("utf-8")).hexdigest()
    return f"{digest}.json"


class RecoverableResumeError(RuntimeError):
    """Raised when Codex thread resume should degrade to archived history."""


class AgentHarnessPersistenceStore:
    """Small JSON persistence layer for agent harness session restore/history."""

    def __init__(
        self,
        base_dir: Optional[Path] = None,
        *,
        max_sessions: int = PERSISTENCE_MAX_SESSIONS,
        max_age_days: int = PERSISTENCE_MAX_AGE_DAYS,
    ) -> None:
        self.base_dir = base_dir or (ConfigPaths.LOCAL_SHARE_DIR / "agent-harness")
        self.sessions_dir = self.base_dir / "sessions"
        self.index_file = self.base_dir / "index.json"
        self.max_sessions = max_sessions
        self.max_age_days = max_age_days

    def load(self) -> Dict[str, Any]:
        if not self.index_file.exists():
            return {"active_session_key": "", "records": []}

        try:
            with open(self.index_file, "r", encoding="utf-8") as handle:
                index_data = json.load(handle)
        except Exception:
            logger.exception("Failed to read agent harness index: %s", self.index_file)
            return {"active_session_key": "", "records": []}

        records: List[Dict[str, Any]] = []
        for item in index_data.get("sessions") or []:
            if not isinstance(item, dict):
                continue
            session_key = str(item.get("session_key") or "").strip()
            file_name = str(item.get("file_name") or "").strip()
            if not session_key or not file_name:
                continue
            session_path = self.sessions_dir / file_name
            if not session_path.exists():
                continue
            try:
                with open(session_path, "r", encoding="utf-8") as handle:
                    payload = json.load(handle)
            except Exception:
                logger.exception("Failed to read persisted agent session: %s", session_path)
                continue
            if not isinstance(payload, dict):
                continue
            records.append(payload)

        records = self._prune_records(records)
        active_session_key = str(index_data.get("active_session_key") or "").strip()
        return {
            "active_session_key": active_session_key,
            "records": records,
        }

    def save(self, *, active_session_key: str, records: List[Dict[str, Any]]) -> None:
        self.sessions_dir.mkdir(parents=True, exist_ok=True)
        kept_records = self._prune_records(records)
        kept_by_file: Dict[str, Dict[str, Any]] = {}
        index_sessions: List[Dict[str, Any]] = []

        for record in kept_records:
            session = record.get("session") if isinstance(record, dict) else None
            if not isinstance(session, dict):
                continue
            session_key = str(session.get("session_key") or "").strip()
            if not session_key:
                continue
            file_name = _safe_session_file_name(session_key)
            kept_by_file[file_name] = record
            index_sessions.append({
                "session_key": session_key,
                "file_name": file_name,
                "updated_at": str(session.get("updated_at") or ""),
            })

        for file_name, record in kept_by_file.items():
            atomic_write_json(self.sessions_dir / file_name, record)

        atomic_write_json(
            self.index_file,
            {
                "schema_version": PERSISTENCE_SCHEMA_VERSION,
                "saved_at": _utc_now_iso(),
                "active_session_key": active_session_key,
                "sessions": index_sessions,
            },
        )

        for session_file in self.sessions_dir.glob("*.json"):
            if session_file.name not in kept_by_file:
                with contextlib.suppress(OSError):
                    session_file.unlink()

    def _prune_records(self, records: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        cutoff = datetime.now(timezone.utc) - timedelta(days=self.max_age_days)
        live_records: List[Dict[str, Any]] = []
        archived_records: List[Dict[str, Any]] = []

        for record in records:
            session = record.get("session") if isinstance(record, dict) else None
            if not isinstance(session, dict):
                continue
            updated_at = _parse_iso(session.get("updated_at"))
            persistence_state = str(session.get("persistence_state") or "live").strip().lower()
            if persistence_state == "archived":
                if updated_at >= cutoff:
                    archived_records.append(record)
            else:
                live_records.append(record)

        live_records.sort(
            key=lambda item: _parse_iso(((item.get("session") or {}).get("updated_at"))),
            reverse=True,
        )
        archived_records.sort(
            key=lambda item: _parse_iso(((item.get("session") or {}).get("updated_at"))),
            reverse=True,
        )

        remaining_archived = max(0, self.max_sessions - len(live_records))
        kept_records = live_records + archived_records[:remaining_archived]
        kept_records.sort(
            key=lambda item: _parse_iso(((item.get("session") or {}).get("updated_at"))),
            reverse=True,
        )
        return kept_records


class CodexHarnessSession:
    """Owns a single Codex app-server thread and normalized transcript."""

    def __init__(
        self,
        *,
        cwd: str,
        context: Dict[str, Any],
        model: Optional[str] = None,
        on_change: Optional[HarnessSessionChangeCallback] = None,
        restored_snapshot: Optional[Dict[str, Any]] = None,
        restored_runtime: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.cwd = cwd
        self.context = dict(context or {})
        self.model = str(model or "").strip() or None
        self._on_change = on_change

        self.process: Optional[asyncio.subprocess.Process] = None
        self._stdout_task: Optional[asyncio.Task] = None
        self._stderr_task: Optional[asyncio.Task] = None
        self._wait_task: Optional[asyncio.Task] = None
        self._stall_watchdog_task: Optional[asyncio.Task] = None
        self._request_id = 0
        self._pending_responses: Dict[int, asyncio.Future] = {}
        self._pending_approvals: Dict[str, Dict[str, Any]] = {}
        self._lock = asyncio.Lock()
        self._closing = False
        self._terminal_error_reported = False
        self._last_progress_monotonic = 0.0
        self._last_progress_reason = "session_created"

        self.approval_policy = "on-request"
        self.sandbox = "workspace-write"
        self.experimental_raw_events = False
        self.persist_extended_history = False

        self.thread_id = ""
        self.session_key = ""
        self.current_turn_id = ""
        self.thread_status = "idle"
        self.session_phase = "idle"
        self.turn_owner = "user"
        self.activity_substate = "idle"
        self.last_error = ""
        self.archive_reason = ""
        self.persistence_state = "live"
        self.started_at = _utc_now_iso()
        self.updated_at = self.started_at
        self.session_revision = 0
        self.transcript: List[Dict[str, Any]] = []
        self._transcript_index: Dict[str, int] = {}
        self._resume_thread_id = ""

        if restored_snapshot or restored_runtime:
            self._apply_restored_state(restored_snapshot or {}, restored_runtime or {})

    async def start(self) -> None:
        env = os.environ.copy()
        self._closing = False
        self._terminal_error_reported = False
        env.setdefault("RAYON_NUM_THREADS", "4")
        env.setdefault("TOKIO_WORKER_THREADS", "4")
        self._record_progress("start")
        self.process = await asyncio.create_subprocess_exec(
            "codex",
            "app-server",
            cwd=self.cwd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
        )
        self._stdout_task = asyncio.create_task(self._stdout_loop())
        self._stderr_task = asyncio.create_task(self._stderr_loop())
        self._wait_task = asyncio.create_task(self._wait_for_exit())
        self._stall_watchdog_task = asyncio.create_task(self._stall_watchdog_loop())

        await self._request(
            "initialize",
            {
                "clientInfo": {
                    "name": "i3pm-agent-harness",
                    "version": "0.1.0",
                },
                "capabilities": None,
            },
        )

        thread_params: Dict[str, Any] = {
            "cwd": self.cwd,
            "approvalPolicy": self.approval_policy,
            "sandbox": self.sandbox,
            "experimentalRawEvents": self.experimental_raw_events,
            "persistExtendedHistory": self.persist_extended_history,
        }
        if self.model:
            thread_params["model"] = self.model

        request_method = "thread/start"
        if self._resume_thread_id:
            request_method = "thread/resume"
            thread_params["threadId"] = self._resume_thread_id

        try:
            response = await self._request(request_method, thread_params)
        except Exception as error:
            if request_method == "thread/resume" and _is_recoverable_thread_resume_error(error):
                raise RecoverableResumeError(str(error)) from error
            raise

        thread = dict(response.get("thread") or {})
        self.thread_id = str(thread.get("id") or self.thread_id or "").strip()
        if not self.thread_id:
            raise RuntimeError(f"Codex app-server did not return a thread id for {request_method}")
        self.session_key = self.session_key or f"codex:{self.thread_id}"
        self._resume_thread_id = self.thread_id
        self.last_error = ""
        self.persistence_state = "live"
        self.archive_reason = ""
        self.thread_status = self._normalize_thread_status(thread.get("status"))
        self._recompute_phase()
        await self._notify_change({
            "type": "session_started",
            "reason": "thread_resumed" if request_method == "thread/resume" else "thread_started",
        })

    async def close(self) -> None:
        self._closing = True
        if self.process and self.process.returncode is None:
            self.process.terminate()
            with contextlib.suppress(ProcessLookupError, asyncio.TimeoutError):
                await asyncio.wait_for(self.process.wait(), timeout=2.0)
        self._fail_pending_responses(RuntimeError("Codex app-server closed"))
        for task in [self._stdout_task, self._stderr_task, self._wait_task]:
            if task:
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
        if self._stall_watchdog_task:
            self._stall_watchdog_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._stall_watchdog_task
        self._stdout_task = None
        self._stderr_task = None
        self._wait_task = None
        self._stall_watchdog_task = None
        self.process = None

    async def send_user_message(self, text: str) -> Dict[str, Any]:
        trimmed = str(text or "").strip()
        if not trimmed:
            raise ValueError("Message text is required")
        if self.persistence_state == "archived":
            raise ValueError("Archived sessions are read-only")
        if not self.thread_id:
            raise RuntimeError("Session has not started")

        response = await self._request(
            "turn/start",
            {
                "threadId": self.thread_id,
                "input": [
                    {
                        "type": "text",
                        "text": trimmed,
                        "text_elements": [],
                    }
                ],
            },
        )
        turn = dict(response.get("turn") or {})
        self.current_turn_id = str(turn.get("id") or self.current_turn_id or "").strip()
        self.thread_status = "active"
        self._record_progress("turn_started")
        self._recompute_phase()
        await self._notify_change({"type": "turn_started", "reason": "user_message"})
        return self.snapshot()

    async def interrupt(self) -> Dict[str, Any]:
        if self.persistence_state == "archived":
            raise ValueError("Archived sessions cannot be interrupted")
        if not self.thread_id or not self.current_turn_id:
            raise ValueError("No active turn to interrupt")
        await self._request(
            "turn/interrupt",
            {
                "threadId": self.thread_id,
                "turnId": self.current_turn_id,
            },
        )
        return self.snapshot()

    async def respond_to_approval(self, request_id: str, decision: str) -> Dict[str, Any]:
        if self.persistence_state == "archived":
            raise ValueError("Archived sessions cannot resolve approvals")

        normalized_request_id = _stringify_request_id(request_id)
        pending = self._pending_approvals.get(normalized_request_id)
        if not pending:
            raise ValueError(f"Unknown approval request: {normalized_request_id}")

        method = str(pending.get("method") or "")
        params = dict(pending.get("params") or {})
        response_id = pending.get("raw_request_id")

        if method in {"item/commandExecution/requestApproval", "execCommandApproval"}:
            result = {"decision": "accept" if decision == "approve" else "decline"}
        elif method in {"item/fileChange/requestApproval", "applyPatchApproval"}:
            result = {"decision": "accept" if decision == "approve" else "decline"}
        elif method == "item/permissions/requestApproval":
            if decision == "approve":
                result = {"permissions": params.get("permissions") or {}, "scope": "turn"}
            else:
                result = {"permissions": {}, "scope": "turn"}
        else:
            raise ValueError(f"Unsupported approval request method: {method}")

        await self._send({
            "jsonrpc": "2.0",
            "id": response_id,
            "result": result,
        })
        self._mark_approval_resolved(normalized_request_id, decision)
        self._pending_approvals.pop(normalized_request_id, None)
        self._recompute_phase()
        await self._notify_change({"type": "approval_resolved", "reason": decision})
        return self.snapshot()

    def snapshot(self) -> Dict[str, Any]:
        pending_approval = (
            self.persistence_state != "archived"
            and any(
                item.get("kind") == "approval_request" and item.get("status") == "pending"
                for item in self.transcript
            )
        )
        return {
            "session_key": self.session_key,
            "tool": "codex",
            "provider": "openai",
            "provider_label": "Codex",
            "thread_id": self.thread_id,
            "cwd": self.cwd,
            "context": dict(self.context),
            "title": self._session_title(),
            "thread_status": self.thread_status,
            "session_phase": self.session_phase,
            "state_label": _phase_label(self.session_phase),
            "turn_owner": self.turn_owner,
            "activity_substate": self.activity_substate,
            "updated_at": self.updated_at,
            "started_at": self.started_at,
            "session_revision": self.session_revision,
            "last_error": self.last_error,
            "archive_reason": self.archive_reason,
            "persistence_state": self.persistence_state,
            "resume_supported": self.persistence_state == "live" and bool(self._resume_thread_id or self.thread_id),
            "preview": self._session_preview(),
            "pending_approval": pending_approval,
            "can_send": self.persistence_state != "archived" and self.session_phase in {"idle", "done"},
            "can_cancel": self.persistence_state != "archived" and self.session_phase == "working",
            "transcript": [dict(item) for item in self.transcript],
        }

    def to_persisted_record(self) -> Dict[str, Any]:
        return {
            "schema_version": PERSISTENCE_SCHEMA_VERSION,
            "saved_at": _utc_now_iso(),
            "session": json.loads(json.dumps(self.snapshot())),
            "runtime": {
                "thread_id": self.thread_id,
                "resume_thread_id": self._resume_thread_id or self.thread_id,
                "current_turn_id": self.current_turn_id,
                "cwd": self.cwd,
                "context": dict(self.context),
                "model": self.model,
                "approval_policy": self.approval_policy,
                "sandbox": self.sandbox,
                "experimental_raw_events": self.experimental_raw_events,
                "persist_extended_history": self.persist_extended_history,
            },
        }

    def archive_for_history(self, reason: str) -> None:
        message = str(reason or "").strip()
        if message:
            self.archive_reason = message
        self.persistence_state = "archived"
        self.current_turn_id = ""
        self.thread_status = "idle"
        self.turn_owner = "user"
        self.activity_substate = "history_only"
        self._pending_approvals.clear()

        for entry in self.transcript:
            kind = str(entry.get("kind") or "").strip()
            status = str(entry.get("status") or "").strip().lower()
            if kind == "approval_request" and status == "pending":
                entry["status"] = "expired"
                entry["resolution"] = "expired"
                entry["is_pending"] = False
            elif kind == "tool_call" and status in {"inprogress", "streaming", "running"}:
                entry["status"] = "stopped"
                if message and not entry.get("output"):
                    entry["output"] = message
                entry["preview"] = _preview_text(entry.get("output") or entry.get("title") or message)
            elif kind == "assistant_message" and status == "streaming":
                entry["status"] = "completed"
        self.updated_at = _utc_now_iso()
        self._recompute_phase()

    def _apply_restored_state(self, snapshot: Dict[str, Any], runtime: Dict[str, Any]) -> None:
        snapshot = dict(snapshot or {})
        runtime = dict(runtime or {})

        self.thread_id = str(runtime.get("thread_id") or snapshot.get("thread_id") or "").strip()
        self.session_key = str(snapshot.get("session_key") or "").strip()
        if not self.session_key and self.thread_id:
            self.session_key = f"codex:{self.thread_id}"
        self.current_turn_id = str(runtime.get("current_turn_id") or "").strip()
        self.thread_status = self._normalize_thread_status(snapshot.get("thread_status"))
        self.session_phase = str(snapshot.get("session_phase") or "idle").strip() or "idle"
        self.turn_owner = str(snapshot.get("turn_owner") or "user").strip() or "user"
        self.activity_substate = str(snapshot.get("activity_substate") or "idle").strip() or "idle"
        self.last_error = str(snapshot.get("last_error") or "").strip()
        self.archive_reason = str(snapshot.get("archive_reason") or "").strip()
        self.persistence_state = str(snapshot.get("persistence_state") or "live").strip() or "live"
        self.started_at = str(snapshot.get("started_at") or self.started_at).strip() or self.started_at
        self.updated_at = str(snapshot.get("updated_at") or self.updated_at).strip() or self.updated_at
        self.session_revision = int(snapshot.get("session_revision") or 0)

        self.approval_policy = str(runtime.get("approval_policy") or self.approval_policy).strip() or self.approval_policy
        self.sandbox = str(runtime.get("sandbox") or self.sandbox).strip() or self.sandbox
        self.experimental_raw_events = bool(runtime.get("experimental_raw_events", self.experimental_raw_events))
        self.persist_extended_history = bool(runtime.get("persist_extended_history", self.persist_extended_history))
        self._resume_thread_id = str(runtime.get("resume_thread_id") or self.thread_id or "").strip()

        transcript = snapshot.get("transcript") or []
        if isinstance(transcript, list):
            self.transcript = [dict(item) for item in transcript if isinstance(item, dict)]
        else:
            self.transcript = []
        self._transcript_index = {
            str(item.get("id") or ""): index
            for index, item in enumerate(self.transcript)
            if str(item.get("id") or "").strip()
        }
        self._recompute_phase()

    async def _stdout_loop(self) -> None:
        assert self.process and self.process.stdout
        while True:
            line = await self.process.stdout.readline()
            if not line:
                break
            raw = line.decode(errors="replace").strip()
            if not raw:
                continue
            try:
                message = json.loads(raw)
            except json.JSONDecodeError:
                logger.warning("codex app-server emitted malformed JSON: %s", raw)
                continue
            try:
                await self._handle_message(message)
            except Exception:
                logger.exception("Failed to handle codex app-server message: %s", raw)

    async def _stderr_loop(self) -> None:
        assert self.process and self.process.stderr
        while True:
            line = await self.process.stderr.readline()
            if not line:
                break
            raw = line.decode(errors="replace").strip()
            if raw:
                logger.warning("codex app-server stderr: %s", raw)
                if self._is_fatal_stderr(raw):
                    await self._handle_terminal_error(
                        f"Codex app-server failed: {raw}",
                        reason="fatal_stderr",
                        terminate_process=True,
                    )

    async def _wait_for_exit(self) -> None:
        assert self.process is not None
        returncode = await self.process.wait()
        if self._closing:
            return
        await self._handle_process_exit(returncode)

    async def _handle_process_exit(self, returncode: int) -> None:
        message = f"Codex app-server exited with code {returncode}"
        await self._handle_terminal_error(message, reason="process_exit")

    async def _handle_message(self, message: Dict[str, Any]) -> None:
        if "id" in message and ("result" in message or "error" in message) and "method" not in message:
            response_id = int(message.get("id"))
            future = self._pending_responses.pop(response_id, None)
            if future and not future.done():
                if "error" in message:
                    future.set_exception(
                        RuntimeError(str(message["error"].get("message") or "app-server request failed"))
                    )
                else:
                    future.set_result(message.get("result") or {})
            return

        method = str(message.get("method") or "").strip()
        params = dict(message.get("params") or {})
        if not method:
            return

        if "id" in message:
            self._record_progress(f"server_request:{method}")
            await self._handle_server_request(method, params, message.get("id"))
            self._recompute_phase()
            await self._notify_change({"type": "approval_requested", "reason": method})
            return

        if method == "thread/started":
            thread = dict(params.get("thread") or {})
            self.thread_id = str(thread.get("id") or self.thread_id or "").strip()
            if self.thread_id:
                self._resume_thread_id = self.thread_id
            if self.thread_id and not self.session_key:
                self.session_key = f"codex:{self.thread_id}"
        elif method == "thread/status/changed":
            self.thread_status = self._normalize_thread_status(params.get("status"))
        elif method == "turn/started":
            turn = dict(params.get("turn") or {})
            self.current_turn_id = str(turn.get("id") or self.current_turn_id or "").strip()
        elif method == "turn/completed":
            turn = dict(params.get("turn") or {})
            turn_status = str(turn.get("status") or "").strip()
            self.current_turn_id = ""
            if turn_status == "failed":
                self.last_error = "Turn failed"
            self.thread_status = "idle"
        elif method == "item/started":
            item = dict(params.get("item") or {})
            self._upsert_thread_item(item)
        elif method == "item/completed":
            item = dict(params.get("item") or {})
            self._upsert_thread_item(item)
        elif method == "item/agentMessage/delta":
            self._append_agent_delta(params)
        elif method == "error":
            self.last_error = str(params.get("message") or "Agent error")
            self._upsert_entry(
                {
                    "id": f"error:server:{self.updated_at}",
                    "kind": "error",
                    "display_kind": "error",
                    "label": "Error",
                    "content": self.last_error,
                    "preview": _preview_text(self.last_error),
                    "status": "completed",
                    "timestamp": _utc_now_iso(),
                }
            )
        elif method == "serverRequest/resolved":
            request_id = _stringify_request_id(params.get("requestId"))
            if request_id in self._pending_approvals:
                self._mark_approval_resolved(request_id, "resolved")
                self._pending_approvals.pop(request_id, None)

        self._record_progress(method)
        self._recompute_phase()
        await self._notify_change({"type": "session_updated", "reason": method})

    async def _handle_server_request(self, method: str, params: Dict[str, Any], request_id: Any) -> None:
        normalized_request_id = _stringify_request_id(request_id)
        title = self._approval_title(method)
        details = self._approval_details(method, params)
        entry = {
            "id": f"approval:{normalized_request_id}",
            "kind": "approval_request",
            "display_kind": "approval",
            "label": "Approval",
            "request_id": normalized_request_id,
            "status": "pending",
            "title": title,
            "details": details,
            "preview": _preview_text(details or title),
            "approval_method": method,
            "can_approve": method != "item/tool/requestUserInput",
            "can_deny": method in {
                "item/commandExecution/requestApproval",
                "item/fileChange/requestApproval",
                "item/permissions/requestApproval",
                "execCommandApproval",
                "applyPatchApproval",
            },
            "is_pending": True,
            "timestamp": _utc_now_iso(),
        }
        self._pending_approvals[normalized_request_id] = {
            "method": method,
            "params": params,
            "raw_request_id": request_id,
        }
        self._upsert_entry(entry)

    async def _request(self, method: str, params: Dict[str, Any]) -> Dict[str, Any]:
        async with self._lock:
            self._request_id += 1
            request_id = self._request_id
            future: asyncio.Future = asyncio.get_running_loop().create_future()
            self._pending_responses[request_id] = future
            await self._send(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "method": method,
                    "params": params,
                }
            )
        try:
            return await asyncio.wait_for(future, timeout=REQUEST_TIMEOUT_SECONDS)
        except asyncio.TimeoutError as error:
            self._pending_responses.pop(request_id, None)
            await self._handle_terminal_error(
                f"Codex app-server timed out while handling {method}",
                reason="request_timeout",
                terminate_process=True,
            )
            raise RuntimeError(f"Codex app-server timed out while handling {method}") from error

    async def _send(self, payload: Dict[str, Any]) -> None:
        if not self.process or not self.process.stdin or self.process.returncode is not None:
            raise RuntimeError("Codex app-server is not running")
        encoded = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
        try:
            self.process.stdin.write(encoded)
            await self.process.stdin.drain()
        except (BrokenPipeError, ConnectionResetError) as error:
            raise RuntimeError("Codex app-server is not running") from error

    def _normalize_thread_status(self, status: Any) -> str:
        if isinstance(status, dict):
            return str(status.get("type") or "idle").strip() or "idle"
        if isinstance(status, str):
            return status.strip() or "idle"
        return "idle"

    def _upsert_thread_item(self, item: Dict[str, Any]) -> None:
        item_type = str(item.get("type") or "").strip()
        if not item_type:
            return

        normalized: Dict[str, Any]
        if item_type == "userMessage":
            parts = []
            for content in item.get("content") or []:
                if isinstance(content, dict) and content.get("type") == "text":
                    parts.append(str(content.get("text") or ""))
            combined = "".join(parts).strip()
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "user_message",
                "display_kind": "user",
                "label": "You",
                "content": combined,
                "preview": _preview_text(combined),
                "status": "completed",
                "timestamp": _utc_now_iso(),
            }
        elif item_type == "agentMessage":
            phase = str(item.get("phase") or "")
            text = str(item.get("text") or "")
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "assistant_message",
                "display_kind": "assistant_commentary" if phase == "commentary" else "assistant_final",
                "label": "Commentary" if phase == "commentary" else "Agent",
                "content": text,
                "status": "completed" if text else "streaming",
                "phase": phase,
                "preview": _preview_text(text),
                "timestamp": _utc_now_iso(),
            }
        elif item_type == "reasoning":
            summary = list(item.get("summary") or [])
            content_items = list(item.get("content") or [])
            preview = "\n".join([str(part) for part in summary or content_items])
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "reasoning",
                "display_kind": "reasoning",
                "label": "Reasoning",
                "summary": summary,
                "content_items": content_items,
                "is_empty_reasoning": len(summary) == 0 and len(content_items) == 0,
                "preview": _preview_text(preview),
                "status": "completed",
                "timestamp": _utc_now_iso(),
            }
        elif item_type == "plan":
            text = str(item.get("text") or "")
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "plan",
                "display_kind": "plan",
                "label": "Plan",
                "content": text,
                "preview": _preview_text(text),
                "status": "completed",
                "timestamp": _utc_now_iso(),
            }
        elif item_type in {
            "commandExecution",
            "fileChange",
            "mcpToolCall",
            "dynamicToolCall",
            "webSearch",
            "collabAgentToolCall",
        }:
            normalized = self._normalize_tool_item(item)
        else:
            payload = json.dumps(item, sort_keys=True)
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "status_changed",
                "display_kind": "status",
                "label": item_type,
                "title": item_type,
                "content": payload,
                "preview": _preview_text(payload),
                "status": "completed",
                "timestamp": _utc_now_iso(),
            }
        self._upsert_entry(normalized)

    def _normalize_tool_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
        item_type = str(item.get("type") or "")
        base = {
            "id": str(item.get("id") or ""),
            "kind": "tool_call",
            "display_kind": "tool",
            "label": "Tool",
            "tool_type": item_type,
            "status": "completed",
            "timestamp": _utc_now_iso(),
        }
        if item_type == "commandExecution":
            base.update(
                {
                    "title": str(item.get("command") or ""),
                    "cwd": str(item.get("cwd") or ""),
                    "status": str(item.get("status") or "completed"),
                    "output": str(item.get("aggregatedOutput") or ""),
                    "exit_code": item.get("exitCode"),
                    "duration_ms": item.get("durationMs"),
                    "preview": _preview_text(item.get("aggregatedOutput") or item.get("command") or ""),
                }
            )
        elif item_type == "fileChange":
            changes = list(item.get("changes") or [])
            base.update(
                {
                    "title": "File changes",
                    "status": str(item.get("status") or "completed"),
                    "changes": changes,
                    "preview": _preview_text(json.dumps(changes, sort_keys=True)),
                }
            )
        elif item_type == "mcpToolCall":
            server_name = str(item.get("server") or "").strip()
            tool_name = str(item.get("tool") or "").strip()
            result_value = item.get("result")
            preview_source = result_value or item.get("error") or item.get("arguments") or ""
            label = "Desktop" if server_name == "i3pm-desktop" else "Tool"
            title = tool_name if server_name == "i3pm-desktop" else f"{server_name}:{tool_name}".strip(":")
            if isinstance(result_value, dict):
                preview_source = (
                    result_value.get("result_summary")
                    or result_value.get("structuredContent")
                    or preview_source
                )
            base.update(
                {
                    "label": label,
                    "title": title,
                    "status": str(item.get("status") or "completed"),
                    "arguments": item.get("arguments"),
                    "result": item.get("result"),
                    "error": item.get("error"),
                    "duration_ms": item.get("durationMs"),
                    "preview": _preview_text(preview_source),
                }
            )
        elif item_type == "dynamicToolCall":
            base.update(
                {
                    "title": str(item.get("tool") or "Dynamic tool"),
                    "status": str(item.get("status") or "completed"),
                    "arguments": item.get("arguments"),
                    "result": item.get("contentItems"),
                    "success": item.get("success"),
                    "duration_ms": item.get("durationMs"),
                    "preview": _preview_text(item.get("contentItems") or item.get("tool") or ""),
                }
            )
        elif item_type == "webSearch":
            query = str(item.get("query") or "Web search")
            base.update({"title": query, "status": "completed", "preview": _preview_text(query)})
        else:
            payload = json.dumps(item, sort_keys=True)
            base.update(
                {
                    "title": item_type,
                    "status": str(item.get("status") or "completed"),
                    "payload": item,
                    "preview": _preview_text(payload),
                }
            )
        return base

    def _append_agent_delta(self, params: Dict[str, Any]) -> None:
        item_id = str(params.get("itemId") or "").strip()
        delta = str(params.get("delta") or "")
        if not item_id or delta == "":
            return
        existing = self._get_entry(item_id)
        if existing is None:
            existing = {
                "id": item_id,
                "kind": "assistant_message",
                "display_kind": "assistant_final",
                "label": "Agent",
                "content": "",
                "status": "streaming",
                "phase": "",
                "preview": "",
                "timestamp": _utc_now_iso(),
            }
            self._upsert_entry(existing)
            existing = self._get_entry(item_id)
        if existing is None:
            return
        existing["content"] = str(existing.get("content") or "") + delta
        existing["status"] = "streaming"
        existing["preview"] = _preview_text(existing["content"])
        self.updated_at = _utc_now_iso()

    def _get_entry(self, entry_id: str) -> Optional[Dict[str, Any]]:
        index = self._transcript_index.get(entry_id)
        if index is None or index >= len(self.transcript):
            return None
        return self.transcript[index]

    def _upsert_entry(self, entry: Dict[str, Any]) -> None:
        entry_id = str(entry.get("id") or "").strip()
        if not entry_id:
            return
        existing_index = self._transcript_index.get(entry_id)
        if existing_index is None:
            self._transcript_index[entry_id] = len(self.transcript)
            self.transcript.append(entry)
        else:
            self.transcript[existing_index] = entry
        self.updated_at = _utc_now_iso()

    def _mark_approval_resolved(self, request_id: str, decision: str) -> None:
        entry = self._get_entry(f"approval:{request_id}")
        if not entry:
            return
        entry["status"] = "resolved"
        entry["resolution"] = decision
        entry["is_pending"] = False
        self.updated_at = _utc_now_iso()

    def _session_preview(self) -> str:
        for entry in reversed(self.transcript):
            if (
                self.persistence_state == "live"
                and str(entry.get("kind") or "").strip() == "error"
                and _is_resumable_process_exit_message(entry.get("content"))
            ):
                continue
            preview = str(entry.get("preview") or entry.get("content") or "").strip()
            if preview:
                return _preview_text(preview, limit=96)
        return Path(self.cwd).name

    def _session_title(self) -> str:
        for entry in self.transcript:
            if str(entry.get("kind") or "") != "user_message":
                continue
            content = str(entry.get("content") or entry.get("preview") or "").strip()
            if content:
                return _preview_text(content, limit=56)
        qualified_name = str(self.context.get("qualified_name") or "").strip()
        if qualified_name:
            return qualified_name
        return Path(self.cwd).name

    def _approval_title(self, method: str) -> str:
        if method in {"item/commandExecution/requestApproval", "execCommandApproval"}:
            return "Command approval required"
        if method in {"item/fileChange/requestApproval", "applyPatchApproval"}:
            return "File change approval required"
        if method == "item/permissions/requestApproval":
            return "Permission approval required"
        if method == "item/tool/requestUserInput":
            return "User input required"
        return method

    def _approval_details(self, method: str, params: Dict[str, Any]) -> str:
        if method in {"item/commandExecution/requestApproval", "execCommandApproval"}:
            command = str(params.get("command") or "").strip()
            cwd = str(params.get("cwd") or "").strip()
            reason = str(params.get("reason") or "").strip()
            return "\n".join([bit for bit in [command, cwd, reason] if bit])
        if method in {"item/fileChange/requestApproval", "applyPatchApproval"}:
            reason = str(params.get("reason") or "").strip()
            grant_root = str(params.get("grantRoot") or "").strip()
            return "\n".join([bit for bit in [reason, grant_root] if bit])
        if method == "item/permissions/requestApproval":
            reason = str(params.get("reason") or "").strip()
            permissions = params.get("permissions") or {}
            return "\n".join([bit for bit in [reason, json.dumps(permissions, sort_keys=True)] if bit])
        return json.dumps(params, sort_keys=True)

    def _recompute_phase(self) -> None:
        if self.persistence_state == "archived":
            self.session_phase = "archived"
            self.turn_owner = "user"
            self.activity_substate = "history_only"
            return

        pending_approval = any(
            item.get("kind") == "approval_request" and item.get("status") == "pending"
            for item in self.transcript
        )
        if self.thread_status in {"error", "failed"}:
            self.session_phase = "error"
            self.turn_owner = "user"
            self.activity_substate = "error"
            return
        if pending_approval:
            self.session_phase = "needs_attention"
            self.turn_owner = "blocked"
            self.activity_substate = "waiting_input"
            return
        if self.thread_status == "active" or self.current_turn_id:
            self.session_phase = "working"
            self.turn_owner = "llm"
            self.activity_substate = "streaming"
            return
        if self.transcript:
            last_kind = str(self.transcript[-1].get("kind") or "")
            if last_kind in {"assistant_message", "tool_call", "plan", "reasoning"}:
                self.session_phase = "done"
                self.turn_owner = "user"
                self.activity_substate = "output_ready"
                return
        self.session_phase = "idle"
        self.turn_owner = "user"
        self.activity_substate = "idle"

    def _fail_pending_responses(self, error: Exception) -> None:
        pending = list(self._pending_responses.values())
        self._pending_responses.clear()
        for future in pending:
            if not future.done():
                future.set_exception(error)

    def _record_progress(self, reason: str) -> None:
        self._last_progress_monotonic = asyncio.get_running_loop().time()
        self._last_progress_reason = str(reason or "session_updated")

    def _has_in_progress_tool_call(self) -> bool:
        for item in self.transcript:
            if item.get("kind") != "tool_call":
                continue
            status = str(item.get("status") or "").strip().lower()
            if status in {"inprogress", "streaming", "running"}:
                return True
        return False

    def _should_fail_stalled_turn(self, now_monotonic: float) -> bool:
        if self._closing or self._terminal_error_reported or self.persistence_state == "archived":
            return False
        if self.thread_status != "active" and not self.current_turn_id:
            return False
        if self._last_progress_monotonic <= 0:
            return False
        elapsed = now_monotonic - self._last_progress_monotonic
        if elapsed < STALL_TIMEOUT_SECONDS:
            return False
        if not self._has_in_progress_tool_call() and not self.current_turn_id:
            return False
        return True

    async def _stall_watchdog_loop(self) -> None:
        while True:
            await asyncio.sleep(STALL_CHECK_INTERVAL_SECONDS)
            if not self._should_fail_stalled_turn(asyncio.get_running_loop().time()):
                continue
            await self._handle_terminal_error(
                "Codex turn stalled with no progress for %ds while waiting on tool execution."
                % int(STALL_TIMEOUT_SECONDS),
                reason="stalled_turn",
                terminate_process=True,
            )
            return

    def _is_fatal_stderr(self, raw: str) -> bool:
        lowered = raw.lower()
        return any(pattern.lower() in lowered for pattern in FATAL_STDERR_PATTERNS)

    async def _handle_terminal_error(
        self,
        message: str,
        *,
        reason: str,
        terminate_process: bool = False,
    ) -> None:
        if self._terminal_error_reported:
            return
        self._terminal_error_reported = True
        logger.error(message)
        self.last_error = message
        self.current_turn_id = ""
        self.thread_status = "error"
        for entry in self.transcript:
            if entry.get("kind") != "tool_call":
                continue
            status = str(entry.get("status") or "").strip().lower()
            if status in {"inprogress", "streaming", "running"}:
                entry["status"] = "failed"
                if not entry.get("output"):
                    entry["output"] = message
                entry["preview"] = _preview_text(entry.get("output") or message)
        self._upsert_entry(
            {
                "id": f"error:{reason}:{self.updated_at}",
                "kind": "error",
                "display_kind": "error",
                "label": "Error",
                "content": message,
                "preview": _preview_text(message),
                "status": "completed",
                "timestamp": _utc_now_iso(),
            }
        )
        self._fail_pending_responses(RuntimeError(message))
        self._recompute_phase()
        await self._notify_change({"type": "session_error", "reason": reason})
        if terminate_process and self.process and self.process.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                self.process.terminate()

    async def _notify_change(self, event: Optional[Dict[str, Any]] = None) -> None:
        self.session_revision += 1
        self.updated_at = _utc_now_iso()
        if self._on_change is not None:
            await self._on_change(self, dict(event or {"type": "session_updated"}))


class CodexHarnessManager:
    """Tracks daemon-owned Codex harness sessions."""

    def __init__(
        self,
        *,
        on_change: Optional[Callable[[Dict[str, Any]], Awaitable[None]]] = None,
        persistence_dir: Optional[Path] = None,
    ) -> None:
        self._on_change = on_change
        self._sessions: Dict[str, CodexHarnessSession] = {}
        self._active_session_key = ""
        self._event_sequence = 0
        self._persistence = AgentHarnessPersistenceStore(base_dir=persistence_dir)
        self._restore_complete = False
        self._restore_lock = asyncio.Lock()
        self._persist_task: Optional[asyncio.Task] = None

    async def stop(self) -> None:
        if self._sessions:
            await self._persist_now()
        if self._persist_task:
            with contextlib.suppress(asyncio.CancelledError):
                await self._persist_task
            self._persist_task = None
        for session in list(self._sessions.values()):
            await session.close()

    async def snapshot(self) -> Dict[str, Any]:
        await self._ensure_loaded()
        sessions = [session.snapshot() for session in self._sessions.values()]
        sessions.sort(key=lambda item: str(item.get("updated_at") or ""), reverse=True)
        active_session_key = self._active_session_key
        if not active_session_key and sessions:
            active_session_key = str(sessions[0].get("session_key") or "")
        return {
            "active_session_key": active_session_key,
            "sessions": sessions,
        }

    async def start_session(
        self,
        *,
        cwd: str,
        context: Dict[str, Any],
        model: Optional[str] = None,
    ) -> Dict[str, Any]:
        await self._ensure_loaded()
        session = CodexHarnessSession(
            cwd=cwd,
            context=context,
            model=model,
            on_change=self._emit_change,
        )
        await session.start()
        self._sessions[session.session_key] = session
        self._active_session_key = session.session_key
        self._prune_sessions_in_memory()
        self._schedule_persist()
        return session.snapshot()

    async def send_message(self, session_key: str, text: str) -> Dict[str, Any]:
        await self._ensure_loaded()
        session = self._require_session(session_key)
        if session.persistence_state == "archived":
            raise ValueError("Archived sessions are read-only; start a new session instead")
        self._active_session_key = session.session_key
        return await session.send_user_message(text)

    async def cancel(self, session_key: str) -> Dict[str, Any]:
        await self._ensure_loaded()
        session = self._require_session(session_key)
        return await session.interrupt()

    async def respond_to_approval(self, session_key: str, request_id: str, decision: str) -> Dict[str, Any]:
        await self._ensure_loaded()
        session = self._require_session(session_key)
        self._active_session_key = session.session_key
        return await session.respond_to_approval(request_id, decision)

    def _require_session(self, session_key: str) -> CodexHarnessSession:
        normalized = str(session_key or "").strip()
        session = self._sessions.get(normalized)
        if session is None:
            raise ValueError(f"Unknown agent session: {normalized}")
        return session

    async def _ensure_loaded(self) -> None:
        if self._restore_complete:
            return
        async with self._restore_lock:
            if self._restore_complete:
                return
            payload = await asyncio.to_thread(self._persistence.load)
            active_session_key = str(payload.get("active_session_key") or "").strip()
            for record in payload.get("records") or []:
                await self._restore_persisted_record(record, active_session_key)
            self._active_session_key = active_session_key if active_session_key in self._sessions else self._active_session_key
            self._prune_sessions_in_memory()
            if not self._active_session_key and self._sessions:
                ordered = sorted(
                    self._sessions.values(),
                    key=lambda item: item.updated_at,
                    reverse=True,
                )
                self._active_session_key = ordered[0].session_key
            self._restore_complete = True
            if self._sessions:
                await self._persist_now()

    async def _restore_persisted_record(self, record: Dict[str, Any], active_session_key: str) -> None:
        snapshot = record.get("session") if isinstance(record, dict) else None
        runtime = record.get("runtime") if isinstance(record, dict) else None
        if not isinstance(snapshot, dict):
            return
        if not isinstance(runtime, dict):
            runtime = {}

        cwd = str(runtime.get("cwd") or snapshot.get("cwd") or "").strip()
        if not cwd:
            return
        context = runtime.get("context") if isinstance(runtime.get("context"), dict) else snapshot.get("context")
        if not isinstance(context, dict):
            context = {}
        model = str(runtime.get("model") or "").strip() or None
        session = CodexHarnessSession(
            cwd=cwd,
            context=context,
            model=model,
            on_change=self._emit_change,
            restored_snapshot=snapshot,
            restored_runtime=runtime,
        )
        if not session.session_key:
            return

        should_attempt_resume = self._should_attempt_resume(session, runtime, active_session_key)
        self._sessions[session.session_key] = session

        if not should_attempt_resume:
            if session.persistence_state != "archived":
                session.archive_for_history(session.archive_reason or "Restored from previous daemon session")
            return

        try:
            self._active_session_key = session.session_key
            await session.start()
        except Exception as error:
            await session.close()
            session.archive_for_history(f"Resume failed: {str(error).strip() or 'unknown error'}")

    def _should_attempt_resume(
        self,
        session: CodexHarnessSession,
        runtime: Dict[str, Any],
        active_session_key: str,
    ) -> bool:
        if not session.session_key or session.session_key != active_session_key:
            return False
        if session.persistence_state == "archived":
            return False
        if session.session_phase == "needs_attention":
            return False
        if session.session_phase == "archived":
            return False
        if session.session_phase == "error" and not _is_resumable_process_exit_message(session.last_error):
            return False
        resume_thread_id = str(runtime.get("resume_thread_id") or session.thread_id or "").strip()
        return resume_thread_id != ""

    def _prune_sessions_in_memory(self) -> None:
        cutoff = datetime.now(timezone.utc) - timedelta(days=PERSISTENCE_MAX_AGE_DAYS)
        live_sessions: List[CodexHarnessSession] = []
        archived_sessions: List[CodexHarnessSession] = []

        for session in self._sessions.values():
            if session.persistence_state == "archived":
                if _parse_iso(session.updated_at) >= cutoff:
                    archived_sessions.append(session)
            else:
                live_sessions.append(session)

        live_sessions.sort(key=lambda item: item.updated_at, reverse=True)
        archived_sessions.sort(key=lambda item: item.updated_at, reverse=True)
        allowed_archived = max(0, PERSISTENCE_MAX_SESSIONS - len(live_sessions))
        kept_sessions = live_sessions + archived_sessions[:allowed_archived]
        kept_keys = {session.session_key for session in kept_sessions if session.session_key}
        self._sessions = {key: session for key, session in self._sessions.items() if key in kept_keys}
        if self._active_session_key and self._active_session_key not in self._sessions:
            self._active_session_key = ""

    def _schedule_persist(self) -> None:
        if self._persist_task and not self._persist_task.done():
            return
        self._persist_task = asyncio.create_task(self._persist_after_delay())

    async def _persist_after_delay(self) -> None:
        try:
            await asyncio.sleep(0.2)
            await self._persist_now()
        finally:
            self._persist_task = None

    async def _persist_now(self) -> None:
        self._prune_sessions_in_memory()
        records = [session.to_persisted_record() for session in self._sessions.values()]
        await asyncio.to_thread(
            self._persistence.save,
            active_session_key=self._active_session_key,
            records=records,
        )

    async def _emit_change(self, session: CodexHarnessSession, event: Dict[str, Any]) -> None:
        self._schedule_persist()
        if self._on_change is not None:
            self._event_sequence += 1
            await self._on_change({
                "sequence": self._event_sequence,
                "timestamp": _utc_now_iso(),
                "type": str(event.get("type") or "session_updated"),
                "reason": str(event.get("reason") or ""),
                "active_session_key": self._active_session_key or session.session_key,
                "session": session.snapshot(),
            })

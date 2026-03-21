"""Daemon-owned agent harness backed by Codex app-server."""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _stringify_request_id(value: Any) -> str:
    if isinstance(value, (str, int, float)):
        return str(value)
    return json.dumps(value, sort_keys=True)


class CodexHarnessSession:
    """Owns a single Codex app-server thread and normalized transcript."""

    def __init__(
        self,
        *,
        cwd: str,
        context: Dict[str, Any],
        model: Optional[str] = None,
        on_change: Optional[Callable[[], Awaitable[None]]] = None,
    ) -> None:
        self.cwd = cwd
        self.context = dict(context or {})
        self.model = str(model or "").strip() or None
        self._on_change = on_change

        self.process: Optional[asyncio.subprocess.Process] = None
        self._stdout_task: Optional[asyncio.Task] = None
        self._stderr_task: Optional[asyncio.Task] = None
        self._request_id = 0
        self._pending_responses: Dict[int, asyncio.Future] = {}
        self._pending_approvals: Dict[str, Dict[str, Any]] = {}
        self._lock = asyncio.Lock()

        self.thread_id = ""
        self.session_key = ""
        self.current_turn_id = ""
        self.thread_status = "idle"
        self.session_phase = "idle"
        self.turn_owner = "user"
        self.activity_substate = "idle"
        self.last_error = ""
        self.started_at = _utc_now_iso()
        self.updated_at = self.started_at
        self.transcript: List[Dict[str, Any]] = []
        self._transcript_index: Dict[str, int] = {}

    async def start(self) -> None:
        env = os.environ.copy()
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
            "approvalPolicy": "on-request",
            "sandbox": "workspace-write",
            "experimentalRawEvents": False,
            "persistExtendedHistory": False,
        }
        if self.model:
            thread_params["model"] = self.model

        response = await self._request("thread/start", thread_params)
        thread = dict(response.get("thread") or {})
        self.thread_id = str(thread.get("id") or "").strip()
        if not self.thread_id:
            raise RuntimeError("Codex app-server did not return a thread id")
        self.session_key = f"codex:{self.thread_id}"
        self.thread_status = self._normalize_thread_status(thread.get("status"))
        self._recompute_phase()
        await self._notify_change()

    async def close(self) -> None:
        if self.process and self.process.returncode is None:
            self.process.terminate()
            with contextlib.suppress(ProcessLookupError):
                await asyncio.wait_for(self.process.wait(), timeout=2.0)
        for task in [self._stdout_task, self._stderr_task]:
            if task:
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
        self._stdout_task = None
        self._stderr_task = None
        self.process = None

    async def send_user_message(self, text: str) -> Dict[str, Any]:
        trimmed = str(text or "").strip()
        if not trimmed:
            raise ValueError("Message text is required")
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
        self._recompute_phase()
        await self._notify_change()
        return self.snapshot()

    async def interrupt(self) -> Dict[str, Any]:
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
        normalized_request_id = _stringify_request_id(request_id)
        pending = self._pending_approvals.get(normalized_request_id)
        if not pending:
            raise ValueError(f"Unknown approval request: {normalized_request_id}")

        method = str(pending.get("method") or "")
        params = dict(pending.get("params") or {})
        response_id = pending.get("raw_request_id")

        if method in {"item/commandExecution/requestApproval", "execCommandApproval"}:
            result = {
                "decision": "accept" if decision == "approve" else "decline",
            }
        elif method in {"item/fileChange/requestApproval", "applyPatchApproval"}:
            result = {
                "decision": "accept" if decision == "approve" else "decline",
            }
        elif method == "item/permissions/requestApproval":
            if decision == "approve":
                result = {
                    "permissions": params.get("permissions") or {},
                    "scope": "turn",
                }
            else:
                result = {
                    "permissions": {},
                    "scope": "turn",
                }
        else:
            raise ValueError(f"Unsupported approval request method: {method}")

        await self._send(
            {
                "jsonrpc": "2.0",
                "id": response_id,
                "result": result,
            }
        )
        self._mark_approval_resolved(normalized_request_id, decision)
        self._pending_approvals.pop(normalized_request_id, None)
        self._recompute_phase()
        await self._notify_change()
        return self.snapshot()

    def snapshot(self) -> Dict[str, Any]:
        pending_approval = any(
            item.get("kind") == "approval_request" and item.get("status") == "pending"
            for item in self.transcript
        )
        return {
            "session_key": self.session_key,
            "tool": "codex",
            "provider": "openai",
            "thread_id": self.thread_id,
            "cwd": self.cwd,
            "context": dict(self.context),
            "thread_status": self.thread_status,
            "session_phase": self.session_phase,
            "turn_owner": self.turn_owner,
            "activity_substate": self.activity_substate,
            "updated_at": self.updated_at,
            "started_at": self.started_at,
            "last_error": self.last_error,
            "pending_approval": pending_approval,
            "can_send": self.session_phase in {"idle", "done"},
            "can_cancel": self.session_phase == "working",
            "transcript": [dict(item) for item in self.transcript],
        }

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
            await self._handle_message(message)

    async def _stderr_loop(self) -> None:
        assert self.process and self.process.stderr
        while True:
            line = await self.process.stderr.readline()
            if not line:
                break
            raw = line.decode(errors="replace").strip()
            if raw:
                logger.warning("codex app-server stderr: %s", raw)

    async def _handle_message(self, message: Dict[str, Any]) -> None:
        if "id" in message and ("result" in message or "error" in message) and "method" not in message:
            response_id = int(message.get("id"))
            future = self._pending_responses.pop(response_id, None)
            if future and not future.done():
                if "error" in message:
                    future.set_exception(RuntimeError(str(message["error"].get("message") or "app-server request failed")))
                else:
                    future.set_result(message.get("result") or {})
            return

        method = str(message.get("method") or "").strip()
        params = dict(message.get("params") or {})
        if not method:
            return

        if "id" in message:
            await self._handle_server_request(method, params, message.get("id"))
            return

        if method == "thread/started":
            thread = dict(params.get("thread") or {})
            self.thread_id = str(thread.get("id") or self.thread_id or "").strip()
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
        elif method == "serverRequest/resolved":
            request_id = _stringify_request_id(params.get("requestId"))
            if request_id in self._pending_approvals:
                self._mark_approval_resolved(request_id, "resolved")
                self._pending_approvals.pop(request_id, None)

        self._recompute_phase()
        await self._notify_change()

    async def _handle_server_request(self, method: str, params: Dict[str, Any], request_id: Any) -> None:
        normalized_request_id = _stringify_request_id(request_id)
        title = self._approval_title(method)
        details = self._approval_details(method, params)
        entry = {
            "id": f"approval:{normalized_request_id}",
            "kind": "approval_request",
            "request_id": normalized_request_id,
            "status": "pending",
            "title": title,
            "details": details,
            "approval_method": method,
            "can_approve": method != "item/tool/requestUserInput",
            "can_deny": method in {
                "item/commandExecution/requestApproval",
                "item/fileChange/requestApproval",
                "item/permissions/requestApproval",
                "execCommandApproval",
                "applyPatchApproval",
            },
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
        return await future

    async def _send(self, payload: Dict[str, Any]) -> None:
        if not self.process or not self.process.stdin:
            raise RuntimeError("Codex app-server is not running")
        encoded = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
        self.process.stdin.write(encoded)
        await self.process.stdin.drain()

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
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "user_message",
                "content": "".join(parts).strip(),
                "status": "completed",
                "timestamp": _utc_now_iso(),
            }
        elif item_type == "agentMessage":
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "assistant_message",
                "content": str(item.get("text") or ""),
                "status": "completed" if str(item.get("text") or "") else "streaming",
                "phase": str(item.get("phase") or ""),
                "timestamp": _utc_now_iso(),
            }
        elif item_type == "reasoning":
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "reasoning",
                "summary": list(item.get("summary") or []),
                "content_items": list(item.get("content") or []),
                "status": "completed",
                "timestamp": _utc_now_iso(),
            }
        elif item_type == "plan":
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "plan",
                "content": str(item.get("text") or ""),
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
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "status_changed",
                "title": item_type,
                "content": json.dumps(item, sort_keys=True),
                "status": "completed",
                "timestamp": _utc_now_iso(),
            }
        self._upsert_entry(normalized)

    def _normalize_tool_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
        item_type = str(item.get("type") or "")
        base = {
            "id": str(item.get("id") or ""),
            "kind": "tool_call",
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
                }
            )
        elif item_type == "fileChange":
            base.update(
                {
                    "title": "File changes",
                    "status": str(item.get("status") or "completed"),
                    "changes": list(item.get("changes") or []),
                }
            )
        elif item_type == "mcpToolCall":
            base.update(
                {
                    "title": f"{item.get('server') or ''}:{item.get('tool') or ''}".strip(":"),
                    "status": str(item.get("status") or "completed"),
                    "arguments": item.get("arguments"),
                    "result": item.get("result"),
                    "error": item.get("error"),
                    "duration_ms": item.get("durationMs"),
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
                }
            )
        elif item_type == "webSearch":
            base.update(
                {
                    "title": str(item.get("query") or "Web search"),
                    "status": "completed",
                }
            )
        else:
            base.update(
                {
                    "title": item_type,
                    "status": str(item.get("status") or "completed"),
                    "payload": item,
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
                "content": "",
                "status": "streaming",
                "phase": "",
                "timestamp": _utc_now_iso(),
            }
            self._upsert_entry(existing)
            existing = self._get_entry(item_id)
        if existing is None:
            return
        existing["content"] = str(existing.get("content") or "") + delta
        existing["status"] = "streaming"
        self.updated_at = _utc_now_iso()

    def _get_entry(self, entry_id: str) -> Optional[Dict[str, Any]]:
        index = self._transcript_index.get(entry_id)
        if index is None:
            return None
        if index >= len(self.transcript):
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
        self.updated_at = _utc_now_iso()

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
            bits = [bit for bit in [command, cwd, reason] if bit]
            return "\n".join(bits)
        if method in {"item/fileChange/requestApproval", "applyPatchApproval"}:
            reason = str(params.get("reason") or "").strip()
            grant_root = str(params.get("grantRoot") or "").strip()
            bits = [bit for bit in [reason, grant_root] if bit]
            return "\n".join(bits)
        if method == "item/permissions/requestApproval":
            reason = str(params.get("reason") or "").strip()
            permissions = params.get("permissions") or {}
            return "\n".join(
                [bit for bit in [reason, json.dumps(permissions, sort_keys=True)] if bit]
            )
        return json.dumps(params, sort_keys=True)

    def _recompute_phase(self) -> None:
        pending_approval = any(
            item.get("kind") == "approval_request" and item.get("status") == "pending"
            for item in self.transcript
        )
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

    async def _notify_change(self) -> None:
        if self._on_change is not None:
            await self._on_change()


class CodexHarnessManager:
    """Tracks daemon-owned Codex harness sessions."""

    def __init__(
        self,
        *,
        on_change: Optional[Callable[[], Awaitable[None]]] = None,
    ) -> None:
        self._on_change = on_change
        self._sessions: Dict[str, CodexHarnessSession] = {}
        self._active_session_key = ""

    async def stop(self) -> None:
        for session in list(self._sessions.values()):
            await session.close()

    async def snapshot(self) -> Dict[str, Any]:
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
        session = CodexHarnessSession(
            cwd=cwd,
            context=context,
            model=model,
            on_change=self._emit_change,
        )
        await session.start()
        self._sessions[session.session_key] = session
        self._active_session_key = session.session_key
        await self._emit_change()
        return session.snapshot()

    async def send_message(self, session_key: str, text: str) -> Dict[str, Any]:
        session = self._require_session(session_key)
        self._active_session_key = session.session_key
        return await session.send_user_message(text)

    async def cancel(self, session_key: str) -> Dict[str, Any]:
        session = self._require_session(session_key)
        return await session.interrupt()

    async def respond_to_approval(self, session_key: str, request_id: str, decision: str) -> Dict[str, Any]:
        session = self._require_session(session_key)
        self._active_session_key = session.session_key
        return await session.respond_to_approval(request_id, decision)

    def _require_session(self, session_key: str) -> CodexHarnessSession:
        normalized = str(session_key or "").strip()
        session = self._sessions.get(normalized)
        if session is None:
            raise ValueError(f"Unknown agent session: {normalized}")
        return session

    async def _emit_change(self) -> None:
        if self._on_change is not None:
            await self._on_change()

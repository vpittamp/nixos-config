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

HarnessSessionChangeCallback = Callable[[Any, Dict[str, Any]], Awaitable[None]]


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _stringify_request_id(value: Any) -> str:
    if isinstance(value, (str, int, float)):
        return str(value)
    return json.dumps(value, sort_keys=True)


def _preview_text(value: Any, limit: int = 120) -> str:
    text = str(value or "").strip()
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)].rstrip() + "…"


class CodexHarnessSession:
    """Owns a single Codex app-server thread and normalized transcript."""

    def __init__(
        self,
        *,
        cwd: str,
        context: Dict[str, Any],
        model: Optional[str] = None,
        on_change: Optional[HarnessSessionChangeCallback] = None,
    ) -> None:
        self.cwd = cwd
        self.context = dict(context or {})
        self.model = str(model or "").strip() or None
        self._on_change = on_change

        self.process: Optional[asyncio.subprocess.Process] = None
        self._stdout_task: Optional[asyncio.Task] = None
        self._stderr_task: Optional[asyncio.Task] = None
        self._wait_task: Optional[asyncio.Task] = None
        self._request_id = 0
        self._pending_responses: Dict[int, asyncio.Future] = {}
        self._pending_approvals: Dict[str, Dict[str, Any]] = {}
        self._lock = asyncio.Lock()
        self._closing = False

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
        self.session_revision = 0
        self.transcript: List[Dict[str, Any]] = []
        self._transcript_index: Dict[str, int] = {}

    async def start(self) -> None:
        env = os.environ.copy()
        self._closing = False
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
        await self._notify_change({"type": "session_started", "reason": "thread_started"})

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
        self._stdout_task = None
        self._stderr_task = None
        self._wait_task = None
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
        await self._notify_change({"type": "turn_started", "reason": "user_message"})
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
        await self._notify_change({"type": "approval_resolved", "reason": decision})
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
            "provider_label": "Codex",
            "thread_id": self.thread_id,
            "cwd": self.cwd,
            "context": dict(self.context),
            "title": self._session_title(),
            "thread_status": self.thread_status,
            "session_phase": self.session_phase,
            "state_label": self.session_phase.replace("_", " ").title(),
            "turn_owner": self.turn_owner,
            "activity_substate": self.activity_substate,
            "updated_at": self.updated_at,
            "started_at": self.started_at,
            "session_revision": self.session_revision,
            "last_error": self.last_error,
            "preview": self._session_preview(),
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

    async def _wait_for_exit(self) -> None:
        assert self.process is not None
        returncode = await self.process.wait()
        if self._closing:
            return
        await self._handle_process_exit(returncode)

    async def _handle_process_exit(self, returncode: int) -> None:
        message = f"Codex app-server exited with code {returncode}"
        logger.error(message)
        self.last_error = message
        self.current_turn_id = ""
        self.thread_status = "error"
        self._upsert_entry(
            {
                "id": f"error:process-exit:{returncode}:{self.updated_at}",
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
        await self._notify_change({"type": "session_error", "reason": "process_exit"})

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
            self._recompute_phase()
            await self._notify_change({"type": "approval_requested", "reason": method})
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
        return await future

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
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "user_message",
                "display_kind": "user",
                "label": "You",
                "content": "".join(parts).strip(),
                "preview": _preview_text("".join(parts).strip()),
                "status": "completed",
                "timestamp": _utc_now_iso(),
            }
        elif item_type == "agentMessage":
            phase = str(item.get("phase") or "")
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "assistant_message",
                "display_kind": "assistant_commentary" if phase == "commentary" else "assistant_final",
                "label": "Commentary" if phase == "commentary" else "Agent",
                "content": str(item.get("text") or ""),
                "status": "completed" if str(item.get("text") or "") else "streaming",
                "phase": phase,
                "preview": _preview_text(item.get("text") or ""),
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
            normalized = {
                "id": str(item.get("id") or ""),
                "kind": "plan",
                "display_kind": "plan",
                "label": "Plan",
                "content": str(item.get("text") or ""),
                "preview": _preview_text(item.get("text") or ""),
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
                "display_kind": "status",
                "label": item_type,
                "title": item_type,
                "content": json.dumps(item, sort_keys=True),
                "preview": _preview_text(json.dumps(item, sort_keys=True)),
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
            base.update(
                {
                    "title": "File changes",
                    "status": str(item.get("status") or "completed"),
                    "changes": list(item.get("changes") or []),
                    "preview": _preview_text(json.dumps(item.get("changes") or [], sort_keys=True)),
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
            base.update(
                {
                    "title": str(item.get("query") or "Web search"),
                    "status": "completed",
                    "preview": _preview_text(item.get("query") or ""),
                }
            )
        else:
            base.update(
                {
                    "title": item_type,
                    "status": str(item.get("status") or "completed"),
                    "payload": item,
                    "preview": _preview_text(json.dumps(item, sort_keys=True)),
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
        entry["is_pending"] = False
        self.updated_at = _utc_now_iso()

    def _session_preview(self) -> str:
        for entry in reversed(self.transcript):
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
    ) -> None:
        self._on_change = on_change
        self._sessions: Dict[str, CodexHarnessSession] = {}
        self._active_session_key = ""
        self._event_sequence = 0

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

    async def _emit_change(self, session: CodexHarnessSession, event: Dict[str, Any]) -> None:
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

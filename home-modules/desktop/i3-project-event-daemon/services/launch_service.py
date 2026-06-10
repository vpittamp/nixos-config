"""Launch persistence service for daemon-owned launch specs and status."""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from ..config import atomic_write_json


class LaunchService:
    """Own deterministic launch runtime files, specs, and status payloads."""

    def __init__(
        self,
        *,
        runtime_dir: Callable[[], Path],
        load_json_file: Callable[[Path], Dict[str, Any]],
        normalize_target_host: Callable[[Any], str],
        parse_context_target_host: Callable[[Any], str],
        transport_kind_for_target_host: Callable[[Any], str],
        local_host_alias: Callable[[], str],
    ) -> None:
        self._runtime_dir = runtime_dir
        self._load_json_file = load_json_file
        self._normalize_target_host = normalize_target_host
        self._parse_context_target_host = parse_context_target_host
        self._transport_kind_for_target_host = transport_kind_for_target_host
        self._local_host_alias = local_host_alias

    def runtime_dir(self) -> Path:
        """Return the runtime directory used for deterministic launch specs and status."""
        return self._runtime_dir() / "i3-project-daemon" / "launches"

    def status_file(self, launch_id: str) -> Path:
        """Return the canonical launch-status file for a launch id."""
        return self.runtime_dir() / f"{str(launch_id or '').strip()}.status.json"

    def spec_file(self, launch_id: str) -> Path:
        """Return the canonical launch-spec file for a launch id."""
        return self.runtime_dir() / f"{str(launch_id or '').strip()}.spec.json"

    def read_spec(self, launch_id: str) -> Dict[str, Any]:
        """Return persisted spec for a deterministic launch id."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            return {}
        payload = self._load_json_file(self.spec_file(launch_key))
        if not payload:
            return {}
        payload.setdefault("launch_id", launch_key)
        return payload

    def write_spec_payload(
        self,
        *,
        launch_id: str,
        payload: Dict[str, Any],
    ) -> Path:
        """Persist an exact launch payload for reconciliation and diagnostics."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            raise RuntimeError("launch_id is required for launch spec")
        spec_file = self.spec_file(launch_key)
        spec_file.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_json(spec_file, payload)
        return spec_file

    def write_status(
        self,
        *,
        launch_id: str,
        status: str,
        spec: Optional[Dict[str, Any]] = None,
        error_code: str = "",
        error_message: str = "",
        reason: str = "",
        extra: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Persist deterministic launch status for UI and RPC consumers."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            raise RuntimeError("launch_id is required for launch status")
        payload = {
            "launch_id": launch_key,
            "status": str(status or "").strip() or "queued",
            "error_code": str(error_code or "").strip(),
            "error_message": str(error_message or "").strip(),
            "reason": str(reason or "").strip(),
            "updated_at": int(time.time()),
        }
        if isinstance(spec, dict):
            target_host = (
                spec.get("target_host")
                or self._parse_context_target_host(spec.get("context_key"))
                or ""
            )
            transport_host = (
                spec.get("target_host")
                or self._parse_context_target_host(spec.get("context_key"))
                or self._local_host_alias()
            )
            payload.update({
                "project_name": str(spec.get("project_name") or "").strip(),
                "target_host": self._normalize_target_host(target_host),
                "transport_kind": str(
                    spec.get("transport_kind")
                    or self._transport_kind_for_target_host(transport_host)
                ).strip(),
                "connection_key": str(spec.get("connection_key") or "").strip(),
                "terminal_anchor_id": str(spec.get("terminal_anchor_id") or "").strip(),
                "launch_kind": str(spec.get("launch_kind") or "").strip(),
            })
        if isinstance(extra, dict):
            payload.update(extra)
        status_file = self.status_file(launch_key)
        status_file.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_json(status_file, payload)
        return payload

    def read_status(self, launch_id: str) -> Dict[str, Any]:
        """Return persisted status for a deterministic launch id."""
        launch_key = str(launch_id or "").strip()
        if not launch_key:
            return {}
        payload = self._load_json_file(self.status_file(launch_key))
        if not payload:
            return {}
        payload.setdefault("launch_id", launch_key)
        return payload

    def list_statuses(self, *, limit: int = 20) -> List[Dict[str, Any]]:
        """Return recent persisted launch statuses for dashboard consumers."""
        runtime_dir = self.runtime_dir()
        if not runtime_dir.exists():
            return []
        items: List[Dict[str, Any]] = []
        for path in sorted(runtime_dir.glob("*.status.json"), key=lambda item: item.stat().st_mtime, reverse=True):
            payload = self._load_json_file(path)
            if payload:
                items.append(payload)
            if len(items) >= max(int(limit), 1):
                break
        return items

    def write_remote_spec(
        self,
        *,
        spec: Dict[str, Any],
        launch_kind: str,
    ) -> Path:
        """Persist the exact remote launch payload consumed by the remote launcher."""
        launch = spec.get("launch") or {}
        launch_id = str(launch.get("launch_id") or "").strip()
        if not launch_id:
            raise RuntimeError("remote launch requires a registered launch_id")
        payload = {
            "launch_id": launch_id,
            "launch_kind": str(launch_kind or "").strip(),
            "project_name": str(spec.get("project_name") or "").strip(),
            "target_host": self._normalize_target_host(
                spec.get("target_host") or self._parse_context_target_host(spec.get("context_key"))
            ),
            "transport_kind": str(spec.get("transport_kind") or "").strip(),
            "connection_key": str(spec.get("connection_key") or "").strip(),
            "project_directory": str(spec.get("project_directory") or "").strip(),
            "local_project_directory": str(spec.get("local_project_directory") or "").strip(),
            "terminal_anchor_id": str(spec.get("terminal_anchor_id") or "").strip(),
            "tmux_session_name": str(spec.get("tmux_session_name") or "").strip(),
            "terminal_launch": dict(spec.get("terminal_launch") or {}),
            "environment": dict(spec.get("environment") or {}),
            "launch_transport": str(spec.get("launch_transport") or "").strip(),
            "status_file": str(self.status_file(launch_id)),
        }
        self.write_status(
            launch_id=launch_id,
            status="queued",
            spec=payload,
            reason="queued",
        )
        return self.write_spec_payload(launch_id=launch_id, payload=payload)

    def write_local_spec(
        self,
        *,
        spec: Dict[str, Any],
        launch_kind: str,
    ) -> Path:
        """Persist the exact local launch payload consumed by managed terminal reconciliation."""
        launch = spec.get("launch") or {}
        launch_id = str(launch.get("launch_id") or "").strip()
        if not launch_id:
            raise RuntimeError("local launch requires a registered launch_id")
        payload = {
            "launch_id": launch_id,
            "launch_kind": str(launch_kind or "").strip(),
            "project_name": str(spec.get("project_name") or "").strip(),
            "target_host": self._normalize_target_host(
                spec.get("target_host") or self._parse_context_target_host(spec.get("context_key"))
            ),
            "transport_kind": str(spec.get("transport_kind") or "").strip(),
            "connection_key": str(spec.get("connection_key") or "").strip(),
            "project_directory": str(spec.get("project_directory") or "").strip(),
            "local_project_directory": str(spec.get("local_project_directory") or "").strip(),
            "terminal_anchor_id": str(spec.get("terminal_anchor_id") or "").strip(),
            "tmux_session_name": str(spec.get("tmux_session_name") or "").strip(),
            "terminal_role": str(spec.get("terminal_role") or "").strip(),
            "terminal_launch": dict(spec.get("terminal_launch") or {}),
            "environment": dict(spec.get("environment") or {}),
            "launch_transport": str(spec.get("launch_transport") or "").strip(),
            "status_file": str(self.status_file(launch_id)),
        }
        self.write_status(
            launch_id=launch_id,
            status="queued",
            spec=payload,
            reason="queued",
        )
        return self.write_spec_payload(launch_id=launch_id, payload=payload)

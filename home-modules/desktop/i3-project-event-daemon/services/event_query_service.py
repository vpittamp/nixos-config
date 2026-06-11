"""Event query and serialization service for daemon IPC."""

from __future__ import annotations

import asyncio
import time
from dataclasses import asdict, is_dataclass
from datetime import datetime
from typing import Any, Awaitable, Callable, Dict, List, Optional


EventBufferProvider = Callable[[], Optional[Any]]
LogIpcEvent = Callable[..., Awaitable[None]]
SystemdQuery = Callable[..., List[Any]]


async def _noop_log_ipc_event(**_kwargs: Any) -> None:
    return None


def _json_safe(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [_json_safe(item) for item in value]
    return value


def event_data(event: Any) -> Dict[str, Any]:
    """Return a JSON-safe dict containing the event's native fields."""
    to_dict = getattr(event, "to_dict", None)
    if callable(to_dict):
        return _json_safe(to_dict())
    if is_dataclass(event):
        return _json_safe(
            {key: value for key, value in asdict(event).items() if value is not None}
        )
    return _json_safe(
        {
            key: value
            for key, value in vars(event).items()
            if not key.startswith("_") and value is not None
        }
    )


def _process_start_time_ms(value: Any) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return int(value.timestamp() * 1000)
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


class EventQueryService:
    """Own diagnostic event query payloads independently from IPC dispatch."""

    def __init__(
        self,
        *,
        event_buffer_provider: EventBufferProvider,
        log_ipc_event: LogIpcEvent = _noop_log_ipc_event,
        systemd_query: Optional[SystemdQuery] = None,
    ) -> None:
        self.event_buffer_provider = event_buffer_provider
        self.log_ipc_event = log_ipc_event
        self.systemd_query = systemd_query

    async def get_events(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Return recent events for diagnostics."""
        start_time = time.perf_counter()
        error_msg = None
        events_data: List[Dict[str, Any]] = []

        try:
            limit = params.get("limit", 100)
            event_type = params.get("event_type")
            source = params.get("source")
            since_id = params.get("since_id")
            event_buffer = self.event_buffer_provider()

            if source in ("systemd", "proc", "all"):
                all_events = []

                if source in ("all", "proc") or (event_buffer and source != "systemd"):
                    if event_buffer:
                        buffer_events = event_buffer.get_events(
                            limit=limit,
                            event_type=event_type,
                            source=source if source != "all" else None,
                            since_id=since_id,
                        )
                        all_events.extend(buffer_events)

                if source in ("systemd", "all") and self.systemd_query:
                    since = params.get("since", "1 hour ago")
                    systemd_events = await asyncio.to_thread(
                        self.systemd_query,
                        since=since,
                        limit=limit,
                    )
                    all_events.extend(systemd_events)

                all_events.sort(key=lambda event: event.timestamp)
                all_events = all_events[-limit:]
                events_data = self.convert_events_to_dict(all_events)

                return {
                    "events": events_data,
                    "stats": event_buffer.get_stats() if event_buffer else {
                        "total_events": len(events_data),
                        "buffer_size": 0,
                        "max_size": 0,
                    },
                }

            if not event_buffer:
                return {
                    "events": [],
                    "stats": {"total_events": 0, "buffer_size": 0, "max_size": 0},
                }

            events = event_buffer.get_events(
                limit=limit,
                event_type=event_type,
                source=source,
                since_id=since_id,
            )
            events_data = self.convert_events_to_dict(events)

            return {
                "events": events_data,
                "stats": event_buffer.get_stats(),
            }

        except Exception as exc:
            error_msg = str(exc)
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            await self.log_ipc_event(
                event_type="query::events",
                params={
                    "limit": params.get("limit"),
                    "event_type": params.get("event_type"),
                },
                result_count=len(events_data),
                duration_ms=duration_ms,
                error=error_msg,
            )

    def convert_events_to_dict(self, events: List[Any]) -> List[Dict[str, Any]]:
        """Convert EventEntry-like objects to the legacy events.get response shape."""
        events_data = []
        for event in events:
            event_dict = {
                "event_id": event.event_id,
                "event_type": event.event_type,
                "timestamp": event.timestamp.isoformat(),
                "source": event.source,
                "processing_duration_ms": event.processing_duration_ms,
            }

            if event.window_id is not None:
                event_dict["window_id"] = event.window_id
            if event.window_class:
                event_dict["window_class"] = event.window_class
            if event.workspace_name:
                event_dict["workspace_name"] = event.workspace_name
            if event.project_name:
                event_dict["project_name"] = event.project_name
            if event.tick_payload:
                event_dict["tick_payload"] = event.tick_payload
            if event.error:
                event_dict["error"] = event.error

            if event.systemd_unit:
                event_dict["systemd_unit"] = event.systemd_unit
            if event.systemd_message:
                event_dict["systemd_message"] = event.systemd_message
            if event.systemd_pid is not None:
                event_dict["systemd_pid"] = event.systemd_pid
            if event.journal_cursor:
                event_dict["journal_cursor"] = event.journal_cursor

            if event.process_pid is not None:
                event_dict["process_pid"] = event.process_pid
            if event.process_name:
                event_dict["process_name"] = event.process_name
            if event.process_cmdline:
                event_dict["process_cmdline"] = event.process_cmdline
            if event.process_parent_pid is not None:
                event_dict["process_parent_pid"] = event.process_parent_pid
            process_start_time = _process_start_time_ms(event.process_start_time)
            if process_start_time is not None:
                event_dict["process_start_time"] = process_start_time

            events_data.append(event_dict)

        return events_data

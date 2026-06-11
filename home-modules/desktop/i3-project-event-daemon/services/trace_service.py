"""Trace RPC payload shaping for window tracing and log correlation."""

from __future__ import annotations

import logging
import re
from datetime import datetime
from typing import Any, Callable, Dict, Optional

from .window_tracer import TRACE_TEMPLATES, get_tracer


logger = logging.getLogger(__name__)

I3ConnectionProvider = Callable[[], Optional[Any]]
EventBufferProvider = Callable[[], Optional[Any]]


class TraceService:
    """Own trace RPC behavior independently from JSON-RPC dispatch."""

    def __init__(
        self,
        *,
        i3_connection_provider: I3ConnectionProvider,
        event_buffer_provider: EventBufferProvider,
    ) -> None:
        self.i3_connection_provider = i3_connection_provider
        self.event_buffer_provider = event_buffer_provider

    def _i3_connection(self) -> Optional[Any]:
        return self.i3_connection_provider()

    def _event_buffer(self) -> Optional[Any]:
        return self.event_buffer_provider()

    @staticmethod
    def _connection_has_tree(connection: Any) -> bool:
        return bool(connection and getattr(connection, "conn", None))

    async def start(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Start tracing a window."""
        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        matcher = {}
        for key in ["id", "class", "title", "pid", "app_id"]:
            if key in params and params[key] is not None:
                matcher[key] = str(params[key])

        if not matcher:
            raise ValueError("At least one matcher criterion required (id, class, title, pid, app_id)")

        initial_container = None
        window_id = None
        connection = self._i3_connection()
        if self._connection_has_tree(connection):
            tree = await connection.get_tree()
            for window in tree.leaves():
                if "id" in matcher and window.id == int(matcher["id"]):
                    initial_container = window
                    window_id = window.id
                    break
                if "class" in matcher:
                    window_class = getattr(window, "app_id", None) or getattr(window, "window_class", None) or ""
                    if re.search(matcher["class"], window_class, re.IGNORECASE):
                        initial_container = window
                        window_id = window.id
                        break
                if "title" in matcher:
                    title = window.name or ""
                    if re.search(matcher["title"], title, re.IGNORECASE):
                        initial_container = window
                        window_id = window.id
                        break
                if "pid" in matcher and window.pid == int(matcher["pid"]):
                    initial_container = window
                    window_id = window.id
                    break

        trace_id = await tracer.start_trace(
            matcher=matcher,
            window_id=window_id,
            initial_container=initial_container,
        )

        logger.info("[Feature 101] Started trace %s with matcher %s", trace_id, matcher)

        return {
            "success": True,
            "trace_id": trace_id,
            "matcher": matcher,
            "window_id": window_id,
            "window_found": initial_container is not None,
        }

    async def start_app(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Start tracing for the next launch of an app."""
        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        app_name = params.get("app_name")
        if not app_name:
            raise ValueError("app_name parameter is required")

        timeout = params.get("timeout", 30.0)
        if not isinstance(timeout, (int, float)) or timeout <= 0:
            raise ValueError("timeout must be a positive number")

        trace_id = await tracer.start_app_trace(
            app_name=app_name,
            timeout=float(timeout),
        )

        logger.info(
            "[Feature 101] Started app trace %s for '%s' (timeout=%s)",
            trace_id,
            app_name,
            timeout,
        )

        return {
            "success": True,
            "trace_id": trace_id,
            "app_name": app_name,
            "status": "pending",
            "timeout": timeout,
        }

    async def stop(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Stop a window trace."""
        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        trace_id = params.get("trace_id")
        if not trace_id:
            raise ValueError("trace_id parameter is required")

        trace = await tracer.stop_trace(trace_id)
        if not trace:
            raise ValueError(f"Trace not found: {trace_id}")

        logger.info("[Feature 101] Stopped trace %s (%s events)", trace_id, len(trace.events))

        return {
            "success": True,
            "trace_id": trace_id,
            "event_count": len(trace.events),
            "duration_seconds": trace.duration_seconds,
        }

    async def get(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get trace data."""
        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        trace_id = params.get("trace_id")
        if not trace_id:
            raise ValueError("trace_id parameter is required")

        trace = await tracer.get_trace(trace_id)
        if not trace:
            raise ValueError(f"Trace not found: {trace_id}")

        output_format = params.get("format", "json")
        limit = params.get("limit", 50)

        if output_format == "timeline":
            return {
                "success": True,
                "trace_id": trace_id,
                "format": "timeline",
                "timeline": trace.format_timeline(limit=limit),
            }

        return {
            "success": True,
            "trace_id": trace_id,
            "format": "json",
            "trace": trace.to_dict(),
        }

    async def list(self, _params: Dict[str, Any]) -> Dict[str, Any]:
        """List all traces."""
        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        traces = await tracer.list_traces()

        return {
            "success": True,
            "traces": traces,
            "count": len(traces),
        }

    async def snapshot(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Take a manual snapshot of a traced window's state."""
        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        trace_id = params.get("trace_id")
        if not trace_id:
            raise ValueError("trace_id parameter is required")

        trace = await tracer.get_trace(trace_id)
        if not trace:
            raise ValueError(f"Trace not found: {trace_id}")

        if not trace.window_id or trace.window_id == 0:
            raise ValueError("Trace has no associated window yet")

        connection = self._i3_connection()
        if not self._connection_has_tree(connection):
            raise RuntimeError("i3 connection not available")

        tree = await connection.get_tree()
        container = tree.find_by_id(trace.window_id)
        if not container:
            raise ValueError(f"Window {trace.window_id} not found in tree")

        success = await tracer.take_snapshot(trace_id, container)

        return {
            "success": success,
            "trace_id": trace_id,
        }

    async def list_templates(self, _params: Dict[str, Any]) -> Dict[str, Any]:
        """List available trace templates."""
        return {
            "success": True,
            "templates": [template.to_dict() for template in TRACE_TEMPLATES],
            "count": len(TRACE_TEMPLATES),
        }

    async def start_from_template(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Start a trace using a template configuration."""
        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        template_id = params.get("template_id")
        if not template_id:
            raise ValueError("template_id parameter is required")

        template = next((candidate for candidate in TRACE_TEMPLATES if candidate.id == template_id), None)
        if not template:
            raise ValueError(f"Template not found: {template_id}")

        if template.pre_launch:
            app_name = params.get("app_name")
            if not app_name:
                raise ValueError("app_name parameter is required for pre-launch templates")

            trace_id = await tracer.start_app_trace(app_name)
            return {
                "success": True,
                "trace_id": trace_id,
                "template": template.to_dict(),
                "status": "pending_launch",
                "message": f"Waiting for app '{app_name}' to launch",
            }

        if template.trace_all_scoped:
            return {
                "success": True,
                "template": template.to_dict(),
                "status": "ready",
                "message": "Switch projects to capture visibility changes",
            }

        if template.id == "debug-focus-chain":
            connection = self._i3_connection()
            if not self._connection_has_tree(connection):
                raise RuntimeError("i3 connection not available")

            tree = await connection.get_tree()
            focused = tree.find_focused()
            if not focused:
                raise ValueError("No focused window found")

            trace_id = await tracer.start_trace(
                window_id=focused.id,
                source="template",
                matcher={
                    "template_id": template.id,
                    "window_id": focused.id,
                },
            )

            return {
                "success": True,
                "trace_id": trace_id,
                "template": template.to_dict(),
                "window_id": focused.id,
                "status": "active",
            }

        if template.match_class:
            trace_id = await tracer.start_trace(
                class_pattern=template.match_class,
                source="template",
                matcher={
                    "template_id": template.id,
                    "class_pattern": template.match_class,
                },
            )
            return {
                "success": True,
                "trace_id": trace_id,
                "template": template.to_dict(),
                "status": "active",
            }

        raise ValueError(f"Template '{template_id}' requires additional configuration")

    async def get_cross_reference(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get trace reference for a specific log event."""
        tracer = get_tracer()
        if not tracer:
            return {"has_trace": False, "error": "Window tracer not initialized"}

        event_buffer = self._event_buffer()
        if not event_buffer:
            return {"has_trace": False, "error": "Event buffer not available"}

        event_id = params.get("event_id")
        if event_id is None:
            raise ValueError("event_id parameter is required")

        return await tracer.get_cross_reference(event_id, event_buffer)

    async def events_by_trace(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get log events covered by a specific trace."""
        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        event_buffer = self._event_buffer()
        if not event_buffer:
            raise RuntimeError("Event buffer not available")

        trace_id = params.get("trace_id")
        if not trace_id:
            raise ValueError("trace_id parameter is required")

        limit = params.get("limit", 50)

        trace = await tracer.get_trace(trace_id)
        if not trace:
            raise ValueError(f"Trace not found: {trace_id}")

        events = []
        for event in event_buffer.events:
            if event.trace_id == trace_id:
                events.append({
                    "event_id": event.event_id,
                    "event_type": event.event_type,
                    "timestamp": event.timestamp.isoformat(),
                    "window_id": event.window_id,
                })
            elif (
                event.window_id == trace.window_id
                and trace.started_at <= event.timestamp.timestamp() <= (trace.stopped_at or float("inf"))
            ):
                trace_event_index = None
                for index, trace_event in enumerate(trace.events):
                    if abs(trace_event.timestamp - event.timestamp.timestamp()) < 0.01:
                        trace_event_index = index
                        break
                events.append({
                    "event_id": event.event_id,
                    "event_type": event.event_type,
                    "timestamp": event.timestamp.isoformat(),
                    "window_id": event.window_id,
                    "trace_event_index": trace_event_index,
                })

            if len(events) >= limit:
                break

        return {
            "trace_id": trace_id,
            "events": events,
            "total_count": len(events),
        }

    async def query_window_traces(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """List traces with optional log event references."""
        tracer = get_tracer()
        if not tracer:
            raise RuntimeError("Window tracer not initialized")

        active_only = params.get("active_only", False)
        include_log_refs = params.get("include_log_refs", False)

        if include_log_refs:
            traces = await tracer.query_window_traces_with_log_refs(
                active_only=active_only,
                event_buffer=self._event_buffer(),
            )
        else:
            traces = await tracer.list_traces()
            if active_only:
                traces = [trace for trace in traces if trace.get("is_active", False)]

        return {
            "traces": traces,
        }

    async def causality_chain(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get all events in a causality chain by correlation_id."""
        event_buffer = self._event_buffer()
        if not event_buffer:
            raise RuntimeError("Event buffer not available")

        correlation_id = params.get("correlation_id")
        if not correlation_id:
            raise ValueError("correlation_id parameter is required")

        events = []
        root_event = None
        max_depth = 0

        for event in event_buffer.events:
            if event.correlation_id == correlation_id:
                events.append({
                    "event_id": event.event_id,
                    "event_type": event.event_type,
                    "timestamp": event.timestamp.isoformat(),
                    "causality_depth": event.causality_depth,
                    "window_id": event.window_id,
                })

                if event.causality_depth == 0:
                    root_event = event
                max_depth = max(max_depth, event.causality_depth)

        if not events:
            return {
                "correlation_id": correlation_id,
                "root_event_id": None,
                "event_count": 0,
                "duration_ms": 0,
                "depth": 0,
                "summary": "No events found",
                "events": [],
            }

        events.sort(key=lambda event: event["timestamp"])

        first_ts = events[0]["timestamp"]
        last_ts = events[-1]["timestamp"]
        duration_ms = (datetime.fromisoformat(last_ts) - datetime.fromisoformat(first_ts)).total_seconds() * 1000

        root_type = root_event.event_type if root_event else "unknown"
        summary = f"{root_type} -> {len(events)} events, {duration_ms:.1f}ms"

        return {
            "correlation_id": correlation_id,
            "root_event_id": root_event.event_id if root_event else None,
            "event_count": len(events),
            "duration_ms": duration_ms,
            "depth": max_depth,
            "summary": summary,
            "events": events,
        }

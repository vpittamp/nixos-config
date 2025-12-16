"""OTLP HTTP receiver for OpenTelemetry AI Assistant Monitor.

This module implements an async HTTP server that receives OTLP telemetry
from Claude Code and Codex CLI on port 4318 (standard OTLP HTTP port).

Supports both protobuf and JSON encoding based on Content-Type header.
Endpoints:
- POST /v1/logs - Primary endpoint for log records (used for events)
- POST /v1/traces - Accept but ignore trace data
- POST /v1/metrics - Accept but ignore metric data
- GET /health - Health check endpoint
"""

import json
import logging
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any, Optional

from aiohttp import web

from .models import AITool, EventNames, TelemetryEvent

if TYPE_CHECKING:
    from .session_tracker import SessionTracker

logger = logging.getLogger(__name__)


class OTLPReceiver:
    """OTLP HTTP receiver server.

    Receives OpenTelemetry Protocol HTTP requests and extracts telemetry
    events for session tracking.
    """

    def __init__(self, port: int, tracker: "SessionTracker") -> None:
        """Initialize the OTLP receiver.

        Args:
            port: HTTP port to listen on (default 4318)
            tracker: Session tracker to notify of events
        """
        self.port = port
        self.tracker = tracker
        self.app = web.Application()
        self.runner: Optional[web.AppRunner] = None
        self._setup_routes()

    def _setup_routes(self) -> None:
        """Configure HTTP routes."""
        self.app.router.add_get("/health", self._handle_health)
        self.app.router.add_post("/v1/logs", self._handle_logs)
        self.app.router.add_post("/v1/traces", self._handle_traces)
        self.app.router.add_post("/v1/metrics", self._handle_metrics)

    async def start(self) -> None:
        """Start the HTTP server."""
        self.runner = web.AppRunner(self.app)
        await self.runner.setup()
        site = web.TCPSite(self.runner, "0.0.0.0", self.port)
        await site.start()
        logger.info(f"OTLP receiver listening on http://0.0.0.0:{self.port}")

    async def stop(self) -> None:
        """Stop the HTTP server."""
        if self.runner:
            await self.runner.cleanup()
            logger.info("OTLP receiver stopped")

    async def _handle_health(self, request: web.Request) -> web.Response:
        """Health check endpoint.

        Returns 200 OK with JSON status for monitoring.
        """
        return web.json_response({"status": "ok"})

    async def _handle_logs(self, request: web.Request) -> web.Response:
        """Handle OTLP logs export requests.

        This is the primary endpoint for receiving AI assistant telemetry.
        Parses log records and extracts events for session tracking.
        """
        content_type = request.headers.get("Content-Type", "")

        try:
            if "application/x-protobuf" in content_type:
                events = await self._parse_protobuf_logs(request)
            elif "application/json" in content_type:
                events = await self._parse_json_logs(request)
            else:
                # Default to trying JSON
                events = await self._parse_json_logs(request)

            # Process events through session tracker
            for event in events:
                await self.tracker.process_event(event)

            # Return success response
            return self._create_logs_response(content_type, rejected=0)

        except Exception as e:
            import traceback
            logger.error(f"Error processing logs: {e}\n{traceback.format_exc()}")
            return web.Response(status=400, text=str(e))

    async def _handle_traces(self, request: web.Request) -> web.Response:
        """Handle OTLP traces export requests.

        Accept but ignore trace data - we only need log events.
        """
        content_type = request.headers.get("Content-Type", "")
        return self._create_empty_response(content_type)

    async def _handle_metrics(self, request: web.Request) -> web.Response:
        """Handle OTLP metrics export requests.

        Accept but ignore metric data - we only need log events.
        """
        content_type = request.headers.get("Content-Type", "")
        return self._create_empty_response(content_type)

    async def _parse_protobuf_logs(self, request: web.Request) -> list[TelemetryEvent]:
        """Parse protobuf-encoded OTLP logs request.

        Uses opentelemetry-proto library to parse ExportLogsServiceRequest.
        """
        try:
            from opentelemetry.proto.collector.logs.v1.logs_service_pb2 import (
                ExportLogsServiceRequest,
            )
        except ImportError:
            logger.warning("opentelemetry-proto not available, falling back to JSON")
            return []

        body = await request.read()
        otlp_request = ExportLogsServiceRequest()
        otlp_request.ParseFromString(body)

        events = []
        for resource_logs in otlp_request.resource_logs:
            # Extract service name from resource attributes
            service_name = self._extract_service_name(resource_logs.resource)

            for scope_logs in resource_logs.scope_logs:
                for log_record in scope_logs.log_records:
                    event = self._parse_log_record(log_record, service_name)
                    if event:
                        events.append(event)

        logger.debug(f"Parsed {len(events)} events from protobuf")
        return events

    async def _parse_json_logs(self, request: web.Request) -> list[TelemetryEvent]:
        """Parse JSON-encoded OTLP logs request.

        JSON format uses protobuf field names (snake_case).
        """
        try:
            body = await request.json()
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON: {e}")
            return []

        events = []
        for resource_logs in body.get("resourceLogs", []):
            # Extract service name
            resource = resource_logs.get("resource", {})
            service_name = self._extract_service_name_json(resource)

            for scope_logs in resource_logs.get("scopeLogs", []):
                for log_record in scope_logs.get("logRecords", []):
                    event = self._parse_log_record_json(log_record, service_name)
                    if event:
                        events.append(event)

        logger.debug(f"Parsed {len(events)} events from JSON")
        return events

    def _extract_service_name(self, resource: Any) -> Optional[str]:
        """Extract service.name from protobuf resource attributes."""
        try:
            for attr in resource.attributes:
                if attr.key == "service.name":
                    # Handle AnyValue - check for string_value field
                    if hasattr(attr.value, 'string_value'):
                        return attr.value.string_value
                    elif hasattr(attr.value, 'HasField') and attr.value.HasField("string_value"):
                        return attr.value.string_value
        except Exception as e:
            logger.debug(f"Error extracting service name: {e}")
        return None

    def _extract_service_name_json(self, resource: dict) -> Optional[str]:
        """Extract service.name from JSON resource attributes."""
        for attr in resource.get("attributes", []):
            if attr.get("key") == "service.name":
                value = attr.get("value", {})
                return value.get("stringValue")
        return None

    def _parse_log_record(self, log_record: Any, service_name: Optional[str]) -> Optional[TelemetryEvent]:
        """Parse a protobuf LogRecord into TelemetryEvent."""
        # Extract attributes
        attributes = {}
        session_id = None
        event_name = None

        try:
            for attr in log_record.attributes:
                key = attr.key
                value = None

                # Handle AnyValue - try different accessor patterns
                av = attr.value
                if hasattr(av, 'string_value') and av.string_value:
                    value = av.string_value
                elif hasattr(av, 'int_value') and av.int_value:
                    value = av.int_value
                elif hasattr(av, 'bool_value'):
                    value = av.bool_value
                elif hasattr(av, 'double_value') and av.double_value:
                    value = av.double_value
                elif hasattr(av, 'HasField'):
                    # Try HasField for proper protobuf messages
                    if av.HasField("string_value"):
                        value = av.string_value
                    elif av.HasField("int_value"):
                        value = av.int_value
                    elif av.HasField("bool_value"):
                        value = av.bool_value
                    elif av.HasField("double_value"):
                        value = av.double_value

                if value is None:
                    continue

                attributes[key] = value

                # Look for session identifiers (Claude Code uses session.id)
                if key in ("session.id", "thread_id", "conversation_id", "conversation.id"):
                    session_id = str(value)

                # Look for event name
                if key == "event.name" or key == "name":
                    event_name = str(value)
        except Exception as e:
            logger.debug(f"Error parsing log record attributes: {e}")

        # If no event name in attributes, try the log record body
        try:
            if not event_name:
                body = log_record.body
                if hasattr(body, 'string_value') and body.string_value:
                    event_name = body.string_value
                elif hasattr(body, 'HasField') and body.HasField("string_value"):
                    event_name = body.string_value
        except Exception as e:
            logger.debug(f"Error parsing log record body: {e}")

        if not event_name:
            return None

        # Parse timestamp (nanoseconds since epoch)
        timestamp = datetime.fromtimestamp(
            log_record.time_unix_nano / 1e9, tz=timezone.utc
        )

        # Determine AI tool from event name or service name
        tool = EventNames.get_tool_from_event(event_name)
        if not tool and service_name:
            if "claude" in service_name.lower():
                tool = AITool.CLAUDE_CODE
            elif "codex" in service_name.lower():
                tool = AITool.CODEX_CLI

        # Extract trace context
        trace_id = None
        span_id = None
        if log_record.trace_id:
            trace_id = log_record.trace_id.hex()
        if log_record.span_id:
            span_id = log_record.span_id.hex()

        return TelemetryEvent(
            event_name=event_name,
            timestamp=timestamp,
            session_id=session_id,
            tool=tool,
            attributes=attributes,
            trace_id=trace_id,
            span_id=span_id,
        )

    def _parse_log_record_json(self, log_record: dict, service_name: Optional[str]) -> Optional[TelemetryEvent]:
        """Parse a JSON LogRecord into TelemetryEvent."""
        # Extract attributes
        attributes = {}
        session_id = None
        event_name = None

        for attr in log_record.get("attributes", []):
            key = attr.get("key")
            value_obj = attr.get("value", {})

            # Handle different value types
            if "stringValue" in value_obj:
                value = value_obj["stringValue"]
            elif "intValue" in value_obj:
                value = int(value_obj["intValue"])
            elif "boolValue" in value_obj:
                value = value_obj["boolValue"]
            elif "doubleValue" in value_obj:
                value = float(value_obj["doubleValue"])
            else:
                continue

            attributes[key] = value

            # Look for session identifiers
            if key in ("thread_id", "conversation_id", "conversation.id"):
                session_id = str(value)

            # Look for event name
            if key == "event.name" or key == "name":
                event_name = str(value)

        # If no event name in attributes, try the log record body
        if not event_name:
            body = log_record.get("body", {})
            if "stringValue" in body:
                event_name = body["stringValue"]

        if not event_name:
            return None

        # Parse timestamp (nanoseconds since epoch as string)
        time_str = log_record.get("timeUnixNano", "0")
        timestamp = datetime.fromtimestamp(int(time_str) / 1e9, tz=timezone.utc)

        # Determine AI tool from event name or service name
        tool = EventNames.get_tool_from_event(event_name)
        if not tool and service_name:
            if "claude" in service_name.lower():
                tool = AITool.CLAUDE_CODE
            elif "codex" in service_name.lower():
                tool = AITool.CODEX_CLI

        # Extract trace context
        trace_id = log_record.get("traceId")
        span_id = log_record.get("spanId")

        return TelemetryEvent(
            event_name=event_name,
            timestamp=timestamp,
            session_id=session_id,
            tool=tool,
            attributes=attributes,
            trace_id=trace_id,
            span_id=span_id,
        )

    def _create_logs_response(self, content_type: str, rejected: int = 0) -> web.Response:
        """Create ExportLogsServiceResponse."""
        if "application/x-protobuf" in content_type:
            try:
                from opentelemetry.proto.collector.logs.v1.logs_service_pb2 import (
                    ExportLogsServiceResponse,
                )

                response = ExportLogsServiceResponse()
                if rejected > 0:
                    response.partial_success.rejected_log_records = rejected
                return web.Response(
                    body=response.SerializeToString(),
                    content_type="application/x-protobuf",
                )
            except ImportError:
                pass

        # Default to JSON response
        response_data = {}
        if rejected > 0:
            response_data["partialSuccess"] = {"rejectedLogRecords": rejected}
        return web.json_response(response_data)

    def _create_empty_response(self, content_type: str) -> web.Response:
        """Create empty success response for ignored endpoints."""
        if "application/x-protobuf" in content_type:
            return web.Response(body=b"", content_type="application/x-protobuf")
        return web.json_response({})

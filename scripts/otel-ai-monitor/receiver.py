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

        Parse trace spans and extract events for session tracking.
        Spans like claude.agent.run, tool.read, tool.write contain
        useful telemetry about AI assistant activity.
        """
        content_type = request.headers.get("Content-Type", "")

        try:
            if "application/x-protobuf" in content_type:
                events = await self._parse_protobuf_traces(request)
            elif "application/json" in content_type:
                events = await self._parse_json_traces(request)
            else:
                # Default to trying JSON
                events = await self._parse_json_traces(request)

            # Process events through session tracker
            for event in events:
                await self.tracker.process_event(event)

            # Return success response
            return self._create_traces_response(content_type, rejected=0)

        except Exception as e:
            import traceback
            logger.error(f"Error processing traces: {e}\n{traceback.format_exc()}")
            return web.Response(status=400, text=str(e))

    async def _handle_metrics(self, request: web.Request) -> web.Response:
        """Handle OTLP metrics export requests.

        Metrics serve as a heartbeat - when we receive metrics from Claude Code,
        it indicates the process is still running. We use this to extend the
        quiet period for active sessions.
        """
        content_type = request.headers.get("Content-Type", "")

        # Extract tool info from metrics to use as heartbeat
        tool = await self._extract_tool_from_metrics(request, content_type)
        if tool:
            await self.tracker.process_heartbeat_for_tool(tool)

        return self._create_empty_response(content_type)

    async def _extract_tool_from_metrics(
        self, request: web.Request, content_type: str
    ) -> Optional[AITool]:
        """Extract AI tool type from metrics request for heartbeat tracking.

        Claude Code metrics don't include session_id, so we identify the tool
        from service.name and extend all working sessions for that tool.
        """
        try:
            if "application/x-protobuf" in content_type:
                from opentelemetry.proto.collector.metrics.v1.metrics_service_pb2 import (
                    ExportMetricsServiceRequest,
                )

                body = await request.read()
                otlp_request = ExportMetricsServiceRequest()
                otlp_request.ParseFromString(body)

                # Look for service.name in resource attributes
                for resource_metrics in otlp_request.resource_metrics:
                    attrs = {attr.key: attr.value.string_value for attr in resource_metrics.resource.attributes}
                    service_name = attrs.get("service.name", "")
                    if "claude" in service_name.lower():
                        return AITool.CLAUDE_CODE
                    elif "codex" in service_name.lower():
                        return AITool.CODEX_CLI
            else:
                # JSON format
                body = await request.json()
                for resource_metrics in body.get("resourceMetrics", []):
                    resource = resource_metrics.get("resource", {})
                    for attr in resource.get("attributes", []):
                        if attr.get("key") == "service.name":
                            value = attr.get("value", {})
                            service_name = value.get("stringValue") or value.get("string_value") or ""
                            if "claude" in service_name.lower():
                                return AITool.CLAUDE_CODE
                            elif "codex" in service_name.lower():
                                return AITool.CODEX_CLI
        except Exception as e:
            logger.debug(f"Could not extract tool from metrics: {e}")

        return None

    async def _parse_protobuf_logs(self, request: web.Request) -> list[TelemetryEvent]:
        """Parse protobuf-encoded OTLP logs request.

        Uses opentelemetry-proto library to parse ExportLogsServiceRequest.
        Handles gzip compression if Content-Encoding header is present.
        """
        import gzip

        try:
            from opentelemetry.proto.collector.logs.v1.logs_service_pb2 import (
                ExportLogsServiceRequest,
            )
        except ImportError:
            logger.warning("opentelemetry-proto not available, falling back to JSON")
            return []

        body = await request.read()

        # Handle gzip compression (Rust OTLP exporter uses gzip by default)
        content_encoding = request.headers.get("Content-Encoding", "").lower()
        if content_encoding == "gzip":
            try:
                body = gzip.decompress(body)
            except Exception as e:
                logger.error(f"Failed to decompress gzip body: {e}")
                return []

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

    async def _parse_protobuf_traces(self, request: web.Request) -> list[TelemetryEvent]:
        """Parse protobuf-encoded OTLP traces request.

        Extracts span information and converts to TelemetryEvents.
        Span names like 'claude.agent.run', 'tool.read' become events.
        """
        try:
            from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import (
                ExportTraceServiceRequest,
            )
        except ImportError:
            logger.warning("opentelemetry-proto not available for traces, falling back to JSON")
            return []

        body = await request.read()
        otlp_request = ExportTraceServiceRequest()
        otlp_request.ParseFromString(body)

        events = []
        for resource_spans in otlp_request.resource_spans:
            service_name = self._extract_service_name(resource_spans.resource)

            for scope_spans in resource_spans.scope_spans:
                for span in scope_spans.spans:
                    event = self._parse_span(span, service_name)
                    if event:
                        events.append(event)

        if events:
            logger.info(f"Parsed {len(events)} events from trace spans")
        return events

    async def _parse_json_traces(self, request: web.Request) -> list[TelemetryEvent]:
        """Parse JSON-encoded OTLP traces request.

        Extracts span information from JSON format.
        """
        try:
            body = await request.json()
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON traces: {e}")
            return []

        events = []
        for resource_spans in body.get("resourceSpans", []):
            resource = resource_spans.get("resource", {})
            service_name = self._extract_service_name_json(resource)

            for scope_spans in resource_spans.get("scopeSpans", []):
                for span in scope_spans.get("spans", []):
                    event = self._parse_span_json(span, service_name)
                    if event:
                        events.append(event)

        if events:
            logger.info(f"Parsed {len(events)} events from JSON trace spans")
        return events

    def _parse_span(self, span: Any, service_name: Optional[str]) -> Optional[TelemetryEvent]:
        """Parse a protobuf Span into TelemetryEvent.

        Converts span name to event name (e.g., 'claude.agent.run' -> 'claude_code.agent_run').
        Extracts session ID from span attributes.
        """
        span_name = span.name if hasattr(span, 'name') else None
        if not span_name:
            return None

        # Convert span name to event name format
        # e.g., 'claude.agent.run' -> 'claude_code.agent_run'
        event_name = self._span_name_to_event(span_name)
        if not event_name:
            return None

        # Extract attributes
        attributes = {}
        session_id = None

        try:
            for attr in span.attributes:
                key = attr.key
                value = None

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

                if key in ("session.id", "thread_id", "conversation_id", "conversation.id"):
                    session_id = str(value)
        except Exception as e:
            logger.debug(f"Error parsing span attributes: {e}")

        # Parse timestamp (nanoseconds since epoch)
        try:
            timestamp = datetime.fromtimestamp(
                span.start_time_unix_nano / 1e9, tz=timezone.utc
            )
        except Exception:
            timestamp = datetime.now(tz=timezone.utc)

        # Add span-specific attributes
        try:
            if hasattr(span, 'end_time_unix_nano') and span.end_time_unix_nano:
                duration_ns = span.end_time_unix_nano - span.start_time_unix_nano
                attributes['duration_ms'] = duration_ns / 1e6
        except Exception:
            pass

        # Determine AI tool
        tool = EventNames.get_tool_from_event(event_name)
        if not tool and service_name:
            if "claude" in service_name.lower():
                tool = AITool.CLAUDE_CODE
            elif "codex" in service_name.lower():
                tool = AITool.CODEX_CLI

        # Extract trace context
        trace_id = span.trace_id.hex() if hasattr(span, 'trace_id') and span.trace_id else None
        span_id = span.span_id.hex() if hasattr(span, 'span_id') and span.span_id else None

        logger.debug(f"Parsed span: {span_name} -> {event_name}, session_id: {session_id}")

        return TelemetryEvent(
            event_name=event_name,
            timestamp=timestamp,
            session_id=session_id,
            tool=tool,
            attributes=attributes,
            trace_id=trace_id,
            span_id=span_id,
        )

    def _parse_span_json(self, span: dict, service_name: Optional[str]) -> Optional[TelemetryEvent]:
        """Parse a JSON Span into TelemetryEvent."""
        span_name = span.get("name")
        if not span_name:
            return None

        # Convert span name to event name format
        event_name = self._span_name_to_event(span_name)
        if not event_name:
            return None

        # Extract attributes
        attributes = {}
        session_id = None

        for attr in span.get("attributes", []):
            key = attr.get("key")
            value_obj = attr.get("value", {})

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

            if key in ("session.id", "thread_id", "conversation_id", "conversation.id"):
                session_id = str(value)

        # Parse timestamp
        time_str = span.get("startTimeUnixNano", "0")
        try:
            timestamp = datetime.fromtimestamp(int(time_str) / 1e9, tz=timezone.utc)
        except Exception:
            timestamp = datetime.now(tz=timezone.utc)

        # Add duration
        end_time_str = span.get("endTimeUnixNano", "0")
        if end_time_str and time_str:
            try:
                duration_ns = int(end_time_str) - int(time_str)
                attributes['duration_ms'] = duration_ns / 1e6
            except Exception:
                pass

        # Determine AI tool
        tool = EventNames.get_tool_from_event(event_name)
        if not tool and service_name:
            if "claude" in service_name.lower():
                tool = AITool.CLAUDE_CODE
            elif "codex" in service_name.lower():
                tool = AITool.CODEX_CLI

        # Extract trace context
        trace_id = span.get("traceId")
        span_id = span.get("spanId")

        logger.debug(f"Parsed JSON span: {span_name} -> {event_name}, session_id: {session_id}")

        return TelemetryEvent(
            event_name=event_name,
            timestamp=timestamp,
            session_id=session_id,
            tool=tool,
            attributes=attributes,
            trace_id=trace_id,
            span_id=span_id,
        )

    def _span_name_to_event(self, span_name: str) -> Optional[str]:
        """Convert span name to event name format.

        Maps span names to event names that trigger session state changes.
        e.g., 'claude.agent.run' -> 'claude_code.agent_run'
              'tool.read' -> 'claude_code.tool_result'
        """
        # Map of span name patterns to event names
        span_mappings = {
            # Agent lifecycle spans
            "claude.agent.run": "claude_code.agent_run",
            "agent.run": "claude_code.agent_run",
            # Tool spans - map to tool_result for activity tracking
            "tool.read": "claude_code.tool_result",
            "tool.write": "claude_code.tool_result",
            "tool.bash": "claude_code.tool_result",
            "tool.edit": "claude_code.tool_result",
            "tool.grep": "claude_code.tool_result",
            "tool.glob": "claude_code.tool_result",
            # API spans
            "api.request": "claude_code.api_request",
            "api.response": "claude_code.api_request",
            # User interaction
            "user.prompt": "claude_code.user_prompt",
            "prompt.submit": "claude_code.user_prompt",
        }

        # Check exact match first
        if span_name in span_mappings:
            return span_mappings[span_name]

        # Check for prefix matches (case insensitive)
        span_lower = span_name.lower()
        for pattern, event in span_mappings.items():
            if span_lower.startswith(pattern.lower()):
                return event

        # For unknown spans that contain 'claude' or 'tool', create a generic event
        if "claude" in span_lower or "tool" in span_lower:
            # Convert dots to underscores and prefix with claude_code if needed
            normalized = span_name.replace(".", "_").replace("-", "_")
            if not normalized.startswith("claude_code"):
                normalized = f"claude_code.{normalized}"
            return normalized

        # Ignore other spans
        return None

    def _create_traces_response(self, content_type: str, rejected: int = 0) -> web.Response:
        """Create ExportTraceServiceResponse."""
        if "application/x-protobuf" in content_type:
            try:
                from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import (
                    ExportTraceServiceResponse,
                )

                response = ExportTraceServiceResponse()
                if rejected > 0:
                    response.partial_success.rejected_spans = rejected
                return web.Response(
                    body=response.SerializeToString(),
                    content_type="application/x-protobuf",
                )
            except ImportError:
                pass

        # Default to JSON response
        response_data = {}
        if rejected > 0:
            response_data["partialSuccess"] = {"rejectedSpans": rejected}
        return web.json_response(response_data)

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

        # First, try to get event name from the log record body
        # The body contains the fully qualified event name (e.g., "claude_code.api_request")
        # while the event.name attribute only has the suffix (e.g., "api_request")
        try:
            body = log_record.body
            if hasattr(body, 'string_value') and body.string_value:
                event_name = body.string_value
            elif hasattr(body, 'HasField') and body.HasField("string_value"):
                event_name = body.string_value
        except Exception as e:
            logger.debug(f"Error parsing log record body: {e}")

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

                # Fallback: if body didn't have event name, try event.name attribute
                if not event_name and (key == "event.name" or key == "name"):
                    event_name = str(value)
        except Exception as e:
            logger.debug(f"Error parsing log record attributes: {e}")

        if not event_name:
            logger.debug(f"No event_name found. Attributes: {list(attributes.keys())}, session_id: {session_id}")
            return None

        logger.debug(f"Parsed event: {event_name}, session_id: {session_id}")

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

        # First, try to get event name from the log record body
        # The body contains the fully qualified event name (e.g., "claude_code.api_request")
        # while the event.name attribute only has the suffix (e.g., "api_request")
        body = log_record.get("body", {})
        if "stringValue" in body:
            event_name = body["stringValue"]

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

            # Look for session identifiers (Claude Code uses session.id)
            if key in ("session.id", "thread_id", "conversation_id", "conversation.id"):
                session_id = str(value)

            # Fallback: if body didn't have event name, try event.name attribute
            if not event_name and (key == "event.name" or key == "name"):
                event_name = str(value)

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

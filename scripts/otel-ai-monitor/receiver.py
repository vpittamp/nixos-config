"""OTLP HTTP receiver for OpenTelemetry AI Assistant Monitor.

This module implements an async HTTP server that receives OTLP telemetry
from Claude Code and Codex CLI on port 4318 (standard OTLP HTTP port).

Supports both protobuf and JSON encoding based on Content-Type header.
Endpoints:
- POST /v1/logs - Primary endpoint for log records (used for events)
- POST /v1/traces - Accept but ignore trace data
- POST /v1/metrics - Accept but ignore metric data
- GET /health - Health check endpoint

Feature 132: Langfuse Integration
- Enriches spans with Langfuse-specific attributes (openinference.span.kind)
- Maps session.id to langfuse.session.id for trace grouping
- Adds gen_ai.* semantic convention attributes for proper Langfuse categorization
"""

import json
import logging
import os
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any, Optional

from aiohttp import web

from .models import (
    AITool,
    EventNames,
    LangfuseAttributes,
    Provider,
    PROVIDER_DETECTION,
    SESSION_ID_ATTRIBUTES,
    TOOL_PROVIDER,
    TelemetryEvent,
)

if TYPE_CHECKING:
    from .session_tracker import SessionTracker

logger = logging.getLogger(__name__)

# Feature 132: Check if Langfuse enrichment is enabled
LANGFUSE_ENABLED = os.environ.get("LANGFUSE_ENABLED", "0") == "1"
LANGFUSE_USER_ID = os.environ.get("LANGFUSE_USER_ID")
LANGFUSE_DEFAULT_TAGS = os.environ.get("LANGFUSE_TAGS")


def enrich_span_for_langfuse(
    attributes: dict,
    event_name: str,
    session_id: Optional[str],
    tool: Optional[AITool],
) -> dict:
    """Enrich span attributes with Langfuse-specific fields.

    Feature 132: Add OpenInference semantic convention attributes that
    Langfuse uses to categorize and display observations correctly.

    Args:
        attributes: Original span attributes dict
        event_name: Event name (e.g., claude_code.api_request)
        session_id: Session ID for trace grouping
        tool: AI tool type for provider detection

    Returns:
        Enriched attributes dict (modified in place for efficiency)
    """
    if not LANGFUSE_ENABLED:
        return attributes

    # Determine span kind based on event type
    # LLM for API calls, TOOL for tool operations, CHAIN for sessions
    if event_name in {
        EventNames.CLAUDE_API_REQUEST,
        EventNames.CLAUDE_LLM_CALL,
        EventNames.CODEX_API_REQUEST,
        EventNames.GEMINI_API_REQUEST,
        EventNames.GEMINI_API_REQUEST_DOT,
    }:
        span_kind = LangfuseAttributes.KIND_LLM
    elif "tool" in event_name.lower():
        span_kind = LangfuseAttributes.KIND_TOOL
    elif event_name.endswith(".session") or event_name.endswith("_starts"):
        span_kind = LangfuseAttributes.KIND_CHAIN
    elif event_name.endswith(".agent_run"):
        span_kind = LangfuseAttributes.KIND_AGENT
    else:
        # Default to CHAIN for unknown spans
        span_kind = LangfuseAttributes.KIND_CHAIN

    # Add OpenInference span kind
    attributes[LangfuseAttributes.SPAN_KIND] = span_kind

    # Add Langfuse session ID from session.id if available
    if session_id:
        attributes[LangfuseAttributes.LANGFUSE_SESSION_ID] = session_id

    # Add user ID if configured
    if LANGFUSE_USER_ID:
        attributes[LangfuseAttributes.LANGFUSE_USER_ID] = LANGFUSE_USER_ID

    # Add gen_ai.system based on tool
    if tool:
        provider = TOOL_PROVIDER.get(tool)
        if provider == Provider.ANTHROPIC:
            attributes[LangfuseAttributes.GEN_AI_SYSTEM] = "anthropic"
        elif provider == Provider.OPENAI:
            attributes[LangfuseAttributes.GEN_AI_SYSTEM] = "openai"
        elif provider == Provider.GOOGLE:
            attributes[LangfuseAttributes.GEN_AI_SYSTEM] = "google"

    # Add tags if configured
    if LANGFUSE_DEFAULT_TAGS:
        try:
            tags = json.loads(LANGFUSE_DEFAULT_TAGS)
            if isinstance(tags, list):
                attributes[LangfuseAttributes.LANGFUSE_TAGS] = json.dumps(tags)
        except json.JSONDecodeError:
            pass

    return attributes


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
        user_agent = request.headers.get("User-Agent", "unknown")
        logger.debug(f"Received logs request: Content-Type={content_type}, User-Agent={user_agent}")

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

        Feature 135: Now extracts process.pid for more accurate session correlation.
        """
        content_type = request.headers.get("Content-Type", "")

        # Extract tool info and PID from metrics to use as heartbeat
        tool, pid = await self._extract_tool_and_pid_from_metrics(request, content_type)
        if tool:
            await self.tracker.process_heartbeat_for_tool(tool, pid)

        return self._create_empty_response(content_type)

    async def _extract_tool_and_pid_from_metrics(
        self, request: web.Request, content_type: str
    ) -> tuple[Optional[AITool], Optional[int]]:
        """Extract AI tool type and process PID from metrics request.

        Feature 135: Now extracts process.pid for more accurate session correlation.
        When PID is available, we can target the specific session instead of all
        sessions for that tool.

        Returns:
            Tuple of (tool, pid) where either may be None
        """
        tool = None
        pid = None

        try:
            if "application/x-protobuf" in content_type:
                from opentelemetry.proto.collector.metrics.v1.metrics_service_pb2 import (
                    ExportMetricsServiceRequest,
                )

                body = await request.read()
                otlp_request = ExportMetricsServiceRequest()
                otlp_request.ParseFromString(body)

                # Look for service.name and process.pid in resource attributes
                for resource_metrics in otlp_request.resource_metrics:
                    for attr in resource_metrics.resource.attributes:
                        if attr.key == "service.name":
                            # Handle string value
                            if hasattr(attr.value, 'string_value') and attr.value.string_value:
                                service_name = attr.value.string_value
                            elif hasattr(attr.value, 'HasField') and attr.value.HasField("string_value"):
                                service_name = attr.value.string_value
                            else:
                                continue
                            if "claude" in service_name.lower():
                                tool = AITool.CLAUDE_CODE
                            elif "codex" in service_name.lower():
                                tool = AITool.CODEX_CLI
                            elif "gemini" in service_name.lower():
                                tool = AITool.GEMINI_CLI
                        elif attr.key == "process.pid":
                            # Handle int value
                            if hasattr(attr.value, 'int_value') and attr.value.int_value:
                                pid = attr.value.int_value
                            elif hasattr(attr.value, 'HasField') and attr.value.HasField("int_value"):
                                pid = attr.value.int_value
                    # Found what we need from this resource
                    if tool:
                        break
            else:
                # JSON format
                body = await request.json()
                for resource_metrics in body.get("resourceMetrics", []):
                    resource = resource_metrics.get("resource", {})
                    for attr in resource.get("attributes", []):
                        key = attr.get("key")
                        value = attr.get("value", {})
                        if key == "service.name":
                            service_name = value.get("stringValue") or value.get("string_value") or ""
                            if "claude" in service_name.lower():
                                tool = AITool.CLAUDE_CODE
                            elif "codex" in service_name.lower():
                                tool = AITool.CODEX_CLI
                            elif "gemini" in service_name.lower():
                                tool = AITool.GEMINI_CLI
                        elif key == "process.pid":
                            pid_val = value.get("intValue") or value.get("int_value")
                            if pid_val:
                                pid = int(pid_val)
                    # Found what we need from this resource
                    if tool:
                        break
        except Exception as e:
            logger.debug(f"Could not extract tool/pid from metrics: {e}")

        if pid:
            logger.debug(f"Metrics heartbeat: tool={tool}, pid={pid}")

        return tool, pid

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
        # ONLY decompress if gzip magic bytes are present (0x1f 0x8b)
        # Don't rely on Content-Encoding header alone as it may be incorrect
        if len(body) >= 2 and body[0:2] == b'\x1f\x8b':
            try:
                body = gzip.decompress(body)
                logger.debug("Decompressed gzip body")
            except Exception as e:
                logger.warning(f"Failed to decompress gzip body, trying raw: {e}")
                # Continue with raw body - it might not actually be gzipped

        otlp_request = ExportLogsServiceRequest()
        try:
            otlp_request.ParseFromString(body)
        except Exception as e:
            # Log first few bytes for debugging
            logger.debug(f"Protobuf parse failed: {e}. Body len: {len(body)}, first bytes: {body[:20].hex() if body else 'empty'}")
            # Some OTLP exporters may have schema differences - skip silently for now
            # The process monitor provides fallback detection for Codex
            return []

        events = []
        for resource_logs in otlp_request.resource_logs:
            # Extract service name from resource attributes
            service_name = self._extract_service_name(resource_logs.resource)
            # Feature 135: Extract process.pid and other resource attrs for window correlation
            resource_attrs = self._extract_resource_attributes(resource_logs.resource)

            for scope_logs in resource_logs.scope_logs:
                for log_record in scope_logs.log_records:
                    event = self._parse_log_record(log_record, service_name, resource_attrs)
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
            # Feature 135: Extract process.pid and other resource attrs for window correlation
            resource_attrs = self._extract_resource_attributes_json(resource)

            for scope_logs in resource_logs.get("scopeLogs", []):
                for log_record in scope_logs.get("logRecords", []):
                    event = self._parse_log_record_json(log_record, service_name, resource_attrs)
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
            # Feature 135: Extract process.pid and other resource attrs for window correlation
            resource_attrs = self._extract_resource_attributes(resource_spans.resource)

            for scope_spans in resource_spans.scope_spans:
                for span in scope_spans.spans:
                    event = self._parse_span(span, service_name, resource_attrs)
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
            # Feature 135: Extract process.pid and other resource attrs for window correlation
            resource_attrs = self._extract_resource_attributes_json(resource)

            for scope_spans in resource_spans.get("scopeSpans", []):
                for span in scope_spans.get("spans", []):
                    event = self._parse_span_json(span, service_name, resource_attrs)
                    if event:
                        events.append(event)

        if events:
            logger.info(f"Parsed {len(events)} events from JSON trace spans")
        return events

    def _parse_span(
        self,
        span: Any,
        service_name: Optional[str],
        resource_attrs: Optional[dict] = None,
    ) -> Optional[TelemetryEvent]:
        """Parse a protobuf Span into TelemetryEvent.

        Converts span name to event name (e.g., 'claude.agent.run' -> 'claude_code.agent_run').
        Extracts session ID from span attributes.

        Feature 135: Accepts resource_attrs for process.pid-based window correlation.
        """
        span_name = span.name if hasattr(span, 'name') else None
        if not span_name:
            return None

        # Convert span name to event name format
        # e.g., 'claude.agent.run' -> 'claude_code.agent_run'
        event_name = self._span_name_to_event(span_name, service_name)
        if not event_name:
            return None

        # Feature 135: Start with resource attributes (process.pid, working_directory)
        # These are used for deterministic window correlation in session_tracker
        attributes = dict(resource_attrs) if resource_attrs else {}
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
            elif "gemini" in service_name.lower():
                tool = AITool.GEMINI_CLI

        # Extract trace context
        trace_id = span.trace_id.hex() if hasattr(span, 'trace_id') and span.trace_id else None
        span_id = span.span_id.hex() if hasattr(span, 'span_id') and span.span_id else None

        # Feature 132: Enrich attributes for Langfuse
        attributes = enrich_span_for_langfuse(attributes, event_name, session_id, tool)

        # Feature 135: Extract finish_reason from span name if not in attributes
        # Claude Code encodes stop_reason in span name: "LLM Call: Opus → tools" = tool_use
        # Note: Only Opus/Sonnet indicate turn completion - Haiku is used for titles/summaries
        if "gen_ai.response.finish_reasons" not in attributes:
            if "→ tools" in span_name or "-> tools" in span_name:
                attributes["gen_ai.response.finish_reasons"] = "tool_use"
            elif span_name.startswith("LLM"):
                # Only main models (Opus, Sonnet) indicate turn completion
                # Haiku calls are ancillary (title generation, etc.)
                is_main_model = any(m in span_name for m in ("Opus", "Sonnet", "opus", "sonnet"))
                has_no_tools = "→ tools" not in span_name and "-> tools" not in span_name
                if is_main_model and has_no_tools and "(" in span_name and "tokens)" in span_name:
                    # Pattern: "LLM Call: Opus (X→Y tokens)" = turn complete
                    attributes["gen_ai.response.finish_reasons"] = "end_turn"
                    logger.info(f"Turn complete detected from span: {span_name}")

        logger.debug(
            f"Parsed span: {span_name} -> {event_name}, session_id: {session_id}, trace_id: {trace_id}, span_id: {span_id}"
        )

        return TelemetryEvent(
            event_name=event_name,
            timestamp=timestamp,
            session_id=session_id,
            tool=tool,
            attributes=attributes,
            trace_id=trace_id,
            span_id=span_id,
        )

    def _parse_span_json(
        self,
        span: dict,
        service_name: Optional[str],
        resource_attrs: Optional[dict] = None,
    ) -> Optional[TelemetryEvent]:
        """Parse a JSON Span into TelemetryEvent.

        Feature 135: Accepts resource_attrs for process.pid-based window correlation.
        """
        span_name = span.get("name")
        if not span_name:
            return None

        # Convert span name to event name format
        event_name = self._span_name_to_event(span_name, service_name)
        if not event_name:
            return None

        # Feature 135: Start with resource attributes (process.pid, working_directory)
        # These are used for deterministic window correlation in session_tracker
        attributes = dict(resource_attrs) if resource_attrs else {}
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
            elif "gemini" in service_name.lower():
                tool = AITool.GEMINI_CLI

        # Extract trace context
        trace_id = span.get("traceId")
        span_id = span.get("spanId")

        # Feature 132: Enrich attributes for Langfuse
        attributes = enrich_span_for_langfuse(attributes, event_name, session_id, tool)

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

    def _span_name_to_event(
        self, span_name: str, service_name: Optional[str] = None
    ) -> Optional[str]:
        """Convert span name to event name format.

        Maps span names to event names that trigger session state changes.
        e.g., 'claude.agent.run' -> 'claude_code.agent_run'
              'tool.read' -> 'claude_code.tool_result'
        """
        # We only use trace spans for local session tracking for Claude Code today.
        # Codex/Gemini now emit synthesized OpenInference spans that may also start
        # with `LLM...`; avoid misclassifying those as Claude events.
        span_lower = span_name.lower()
        if span_lower.startswith("llm") and service_name:
            svc = service_name.lower()
            if "claude" not in svc:
                return None

        # Map of span name patterns to event names
        span_mappings = {
            # Agent lifecycle spans
            "claude.agent.run": "claude_code.agent_run",
            "agent.run": "claude_code.agent_run",
            # Feature 135: Tool lifecycle spans (for pending tool tracking)
            "tool.start": "claude_code.tool_start",
            "tool.complete": "claude_code.tool_complete",
            "tool_start": "claude_code.tool_start",
            "tool_complete": "claude_code.tool_complete",
            # Feature 135: Streaming spans (for TTFT metrics)
            "stream.start": "claude_code.stream_start",
            "stream.token": "claude_code.stream_token",
            "stream_start": "claude_code.stream_start",
            "stream_token": "claude_code.stream_token",
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
            # Payload interceptor spans (OpenInference)
            # Note: Claude Code also emits native claude_code.api_request *log events*.
            # Keep these spans distinct to avoid double-counting in the local monitor.
            "LLM": "claude_code.llm_call",
            "Claude Interaction (Payload)": "claude_code.llm_call",  # Legacy name
            "Claude API Payload": "claude_code.llm_call",  # Another legacy variant
            "Claude API Call": "claude_code.llm_call",  # Alloy-enriched name
            # Session spans (multi-span trace root)
            "Claude Session": "claude_code.session",
            "Claude Code Session": "claude_code.session",  # Alloy-enriched name
            # User interaction
            "user.prompt": "claude_code.user_prompt",
            "prompt.submit": "claude_code.user_prompt",
            # Gemini CLI spans (OpenTelemetry GenAI semantic conventions)
            "gen_ai.client.operation": "gemini_cli.api.request",
            "gen_ai.content.prompt": "gemini_cli.user_prompt",
            "gen_ai.content.completion": "gemini_cli.api.request",
            "generate_content": "gemini_cli.api.request",
            "GenerateContent": "gemini_cli.api.request",
            "chat": "gemini_cli.api.request",
            "send_message": "gemini_cli.api.request",
            "gemini": "gemini_cli.api.request",  # Generic gemini spans
            # Codex CLI spans
            "codex.conversation": "codex.conversation_starts",
            "codex.prompt": "codex.user_prompt",
            "codex.api": "codex.api_request",
        }

        # Check exact match first
        if span_name in span_mappings:
            return span_mappings[span_name]

        # Check for prefix matches (case insensitive)
        span_lower = span_name.lower()
        for pattern, event in span_mappings.items():
            if span_lower.startswith(pattern.lower()):
                return event

        # For unknown spans, use service_name to determine provider first,
        # then fall back to span name keywords. This prevents "Tool:" spans from
        # Gemini being incorrectly classified as Claude Code.
        svc_lower = (service_name or "").lower()
        logger.debug(f"_span_name_to_event fallback: span='{span_name[:50]}', service='{service_name}'")

        # Check service name first (most reliable)
        if "gemini" in svc_lower:
            normalized = span_name.replace(".", "_").replace("-", "_")
            if not normalized.startswith("gemini_cli"):
                normalized = f"gemini_cli.{normalized}"
            return normalized

        if "codex" in svc_lower or "openai" in svc_lower:
            normalized = span_name.replace(".", "_").replace("-", "_")
            if not normalized.startswith("codex"):
                normalized = f"codex.{normalized}"
            return normalized

        if "claude" in svc_lower:
            normalized = span_name.replace(".", "_").replace("-", "_")
            if not normalized.startswith("claude_code"):
                normalized = f"claude_code.{normalized}"
            return normalized

        # Fall back to span name keywords only if service_name didn't match
        if "gemini" in span_lower or "gen_ai" in span_lower:
            normalized = span_name.replace(".", "_").replace("-", "_")
            if not normalized.startswith("gemini_cli"):
                normalized = f"gemini_cli.{normalized}"
            return normalized

        if "codex" in span_lower or "openai" in span_lower:
            normalized = span_name.replace(".", "_").replace("-", "_")
            if not normalized.startswith("codex"):
                normalized = f"codex.{normalized}"
            return normalized

        if "claude" in span_lower or "tool" in span_lower:
            # "tool" keyword only applies to Claude Code when service_name is unknown
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

    def _extract_resource_attributes(self, resource: Any) -> dict:
        """Extract useful resource attributes for session correlation.

        Feature 135: Extract process.pid and working_directory from resource
        attributes emitted by the Claude Code interceptor. These are used for
        deterministic window correlation instead of relying on focused-window fallback.

        Args:
            resource: OTLP resource object

        Returns:
            Dict with process.pid, working_directory, etc.
        """
        attrs = {}
        try:
            # Check if resource has attributes at all
            if not resource or not hasattr(resource, 'attributes'):
                return attrs

            for attr in resource.attributes:
                if attr.key in ("process.pid", "working_directory", "host.name"):
                    av = attr.value
                    # Handle intValue (process.pid is emitted as int)
                    if hasattr(av, 'int_value') and av.int_value:
                        attrs[attr.key] = av.int_value
                    elif hasattr(av, 'HasField') and av.HasField("int_value"):
                        attrs[attr.key] = av.int_value
                    # Handle stringValue
                    elif hasattr(av, 'string_value') and av.string_value:
                        attrs[attr.key] = av.string_value
                    elif hasattr(av, 'HasField') and av.HasField("string_value"):
                        attrs[attr.key] = av.string_value
        except Exception as e:
            logger.warning(f"Error extracting resource attributes: {e}")
        if attrs:
            logger.debug(f"Extracted resource attrs: {attrs}")
        return attrs

    def _extract_resource_attributes_json(self, resource: dict) -> dict:
        """Extract useful resource attributes from JSON resource.

        Feature 135: JSON equivalent of _extract_resource_attributes for
        JSON-encoded OTLP requests.

        Args:
            resource: JSON resource dict

        Returns:
            Dict with process.pid, working_directory, etc.
        """
        attrs = {}
        for attr in resource.get("attributes", []):
            key = attr.get("key")
            if key in ("process.pid", "working_directory", "host.name"):
                value_obj = attr.get("value", {})
                if "intValue" in value_obj:
                    attrs[key] = int(value_obj["intValue"])
                elif "stringValue" in value_obj:
                    attrs[key] = value_obj["stringValue"]
        return attrs

    def _parse_log_record(
        self,
        log_record: Any,
        service_name: Optional[str],
        resource_attrs: Optional[dict] = None,
    ) -> Optional[TelemetryEvent]:
        """Parse a protobuf LogRecord into TelemetryEvent.

        Feature 135: Accepts resource_attrs for process.pid-based window correlation.
        Works with all CLIs: Claude Code, Codex CLI, Gemini CLI.
        """
        # Feature 135: Start with resource attributes (process.pid, working_directory)
        # These are used for deterministic window correlation in session_tracker
        attributes = dict(resource_attrs) if resource_attrs else {}
        session_id = None
        event_name = None

        # First, try to get event name from the log record body
        # The body contains the fully qualified event name (e.g., "claude_code.api_request")
        # while the event.name attribute only has the suffix (e.g., "api_request")
        # NOTE: Gemini CLI's log body contains descriptive text (e.g., "GenAI operation details...")
        # not the event type, so we validate the body looks like a known event name.
        body_value = None
        try:
            body = log_record.body
            if hasattr(body, 'string_value') and body.string_value:
                body_value = body.string_value
            elif hasattr(body, 'HasField') and body.HasField("string_value"):
                body_value = body.string_value
        except Exception as e:
            logger.debug(f"Error parsing log record body: {e}")

        # Only use body as event_name if it looks like a valid event prefix
        # (Claude Code uses body for event name, Gemini CLI uses it for description)
        if body_value:
            valid_prefixes = ("claude_code.", "codex.", "gemini_cli.", "gen_ai.")
            if any(body_value.startswith(p) for p in valid_prefixes):
                event_name = body_value

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

        # Determine AI tool from event name or service name
        tool = EventNames.get_tool_from_event(event_name)
        logger.debug(f"Identifying tool for event '{event_name}' (service: '{service_name}'): tool={tool}")
        if not tool and service_name:
            if "claude" in service_name.lower():
                tool = AITool.CLAUDE_CODE
            elif "codex" in service_name.lower():
                tool = AITool.CODEX_CLI
            elif "gemini" in service_name.lower():
                tool = AITool.GEMINI_CLI

        # Parse timestamp (nanoseconds since epoch)
        try:
            timestamp = datetime.fromtimestamp(
                log_record.time_unix_nano / 1e9, tz=timezone.utc
            )
        except Exception:
            timestamp = datetime.now(tz=timezone.utc)

        # Extract trace context
        trace_id = None
        span_id = None
        if log_record.trace_id:
            trace_id = log_record.trace_id.hex()
        if log_record.span_id:
            span_id = log_record.span_id.hex()

        # Feature 132: Enrich attributes for Langfuse
        attributes = enrich_span_for_langfuse(attributes, event_name, session_id, tool)

        token_preview = ""
        if event_name in ("claude_code.api_request", "codex.api_request", "gemini_cli.api_request", "gemini_cli.api.request"):
            token_preview = (
                f", model={attributes.get('model')}, input_tokens={attributes.get('input_tokens')}, "
                f"output_tokens={attributes.get('output_tokens')}, cost_usd={attributes.get('cost_usd')}"
            )

        logger.debug(
            f"Parsed event: {event_name}, session_id: {session_id}, trace_id: {trace_id}, span_id: {span_id}{token_preview}"
        )

        return TelemetryEvent(
            event_name=event_name,
            timestamp=timestamp,
            session_id=session_id,
            tool=tool,
            attributes=attributes,
            trace_id=trace_id,
            span_id=span_id,
        )

    def _parse_log_record_json(
        self,
        log_record: dict,
        service_name: Optional[str],
        resource_attrs: Optional[dict] = None,
    ) -> Optional[TelemetryEvent]:
        """Parse a JSON LogRecord into TelemetryEvent.

        Feature 135: Accepts resource_attrs for process.pid-based window correlation.
        Works with all CLIs: Claude Code, Codex CLI, Gemini CLI.
        """
        # Feature 135: Start with resource attributes (process.pid, working_directory)
        # These are used for deterministic window correlation in session_tracker
        attributes = dict(resource_attrs) if resource_attrs else {}
        session_id = None
        event_name = None

        # First, try to get event name from the log record body
        # The body contains the fully qualified event name (e.g., "claude_code.api_request")
        # while the event.name attribute only has the suffix (e.g., "api_request")
        # NOTE: Gemini CLI's log body contains descriptive text (e.g., "GenAI operation details...")
        # not the event type, so we validate the body looks like a known event name.
        body = log_record.get("body", {})
        if "stringValue" in body:
            body_value = body["stringValue"]
            valid_prefixes = ("claude_code.", "codex.", "gemini_cli.", "gen_ai.")
            if any(body_value.startswith(p) for p in valid_prefixes):
                event_name = body_value

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
            elif "gemini" in service_name.lower():
                tool = AITool.GEMINI_CLI

        # Extract trace context
        trace_id = log_record.get("traceId")
        span_id = log_record.get("spanId")

        # Feature 132: Enrich attributes for Langfuse
        attributes = enrich_span_for_langfuse(attributes, event_name, session_id, tool)

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


def detect_provider(service_name: Optional[str], gen_ai_system: Optional[str] = None) -> Optional[Provider]:
    """Detect provider from service.name or gen_ai.system attribute.

    Args:
        service_name: Value of service.name resource attribute
        gen_ai_system: Value of gen_ai.system span attribute

    Returns:
        Detected Provider enum value, or None if unknown
    """
    # Check gen_ai.system first (more specific)
    if gen_ai_system:
        system_lower = gen_ai_system.lower()
        for key, provider in PROVIDER_DETECTION.items():
            if key in system_lower:
                return provider

    # Fall back to service.name
    if service_name:
        name_lower = service_name.lower()
        for key, provider in PROVIDER_DETECTION.items():
            if key in name_lower:
                return provider

    return None


def extract_session_id_for_provider(
    provider: Provider,
    attributes: dict,
) -> Optional[str]:
    """Extract session ID using provider-specific attribute priority.

    Args:
        provider: Detected provider
        attributes: Span/log record attributes

    Returns:
        Session ID string, or None if not found
    """
    attr_priority = SESSION_ID_ATTRIBUTES.get(provider, ["session.id"])

    for attr_name in attr_priority:
        if attr_name in attributes:
            return str(attributes[attr_name])

    return None

"""JSON-RPC 2.0 server over Unix socket

Provides daemon API for CLI clients.

Protocol: JSON-RPC 2.0
Transport: Unix domain socket (SOCK_STREAM)
Message format: Newline-delimited JSON

Performance targets:
- <1ms ping
- <2ms query_events (50 events)
- <5ms get_event (with diff)
"""

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Callable, Dict, Optional

from ..buffer.event_buffer import TreeEventBuffer
from ..diff.differ import TreeDiffer


logger = logging.getLogger(__name__)


class RPCError(Exception):
    """Custom exception for RPC errors with error codes"""
    def __init__(self, code: int, message: str, data: Any = None):
        self.code = code
        self.message = message
        self.data = data
        super().__init__(message)


class RPCServer:
    """
    JSON-RPC 2.0 server for daemon API.

    Listens on Unix socket and handles client requests.
    """

    def __init__(
        self,
        socket_path: Optional[Path],
        event_buffer: TreeEventBuffer,
        differ: TreeDiffer
    ):
        """
        Initialize RPC server.

        Args:
            socket_path: Unix socket path (default: XDG_RUNTIME_DIR/sway-tree-monitor.sock)
            event_buffer: Event buffer to query
            differ: Tree differ for statistics
        """
        import os
        if socket_path is None:
            runtime_dir = os.getenv('XDG_RUNTIME_DIR', '/run/user/1000')
            socket_path = Path(runtime_dir) / 'sway-tree-monitor.sock'

        self.socket_path = socket_path
        self.event_buffer = event_buffer
        self.differ = differ
        self.server: Optional[asyncio.Server] = None
        self._methods: Dict[str, Callable] = {}

        # Register RPC methods
        self._register_methods()

    def _register_methods(self):
        """Register all RPC methods"""
        self._methods['ping'] = self.handle_ping
        self._methods['query_events'] = self.handle_query_events
        self._methods['get_event'] = self.handle_get_event
        self._methods['get_statistics'] = self.handle_get_statistics
        self._methods['get_daemon_status'] = self.handle_get_daemon_status

    async def start(self):
        """Start RPC server listening on Unix socket"""
        # Remove existing socket if present
        if self.socket_path.exists():
            self.socket_path.unlink()

        # Ensure parent directory exists
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)

        # Create Unix socket server
        self.server = await asyncio.start_unix_server(
            self._handle_client,
            path=str(self.socket_path)
        )

        # Set socket permissions (owner read/write only)
        self.socket_path.chmod(0o600)

        logger.info(f"RPC server listening on {self.socket_path}")

    async def stop(self):
        """Stop RPC server"""
        if self.server:
            self.server.close()
            await self.server.wait_closed()

        # Remove socket file
        if self.socket_path.exists():
            self.socket_path.unlink()

        logger.info("RPC server stopped")

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """
        Handle client connection.

        Reads JSON-RPC requests, processes them, sends responses.
        """
        addr = writer.get_extra_info('sockname')
        logger.debug(f"Client connected: {addr}")

        try:
            while True:
                # Read newline-delimited JSON
                data = await reader.readline()
                if not data:
                    break  # Client disconnected

                # Parse JSON-RPC request
                try:
                    request = json.loads(data.decode('utf-8'))
                except json.JSONDecodeError as e:
                    # Invalid JSON
                    response = self._error_response(None, -32700, "Parse error", str(e))
                    writer.write(json.dumps(response).encode('utf-8') + b'\n')
                    await writer.drain()
                    continue

                # Process request
                response = await self._process_request(request)

                # Send response
                writer.write(json.dumps(response).encode('utf-8') + b'\n')
                await writer.drain()

        except Exception as e:
            logger.error(f"Error handling client: {e}", exc_info=True)
        finally:
            writer.close()
            await writer.wait_closed()
            logger.debug(f"Client disconnected: {addr}")

    async def _process_request(self, request: dict) -> dict:
        """
        Process JSON-RPC 2.0 request.

        Args:
            request: JSON-RPC request object

        Returns:
            JSON-RPC response object
        """
        # Validate request
        if not isinstance(request, dict):
            return self._error_response(None, -32600, "Invalid Request", "Request must be an object")

        if request.get('jsonrpc') != '2.0':
            return self._error_response(request.get('id'), -32600, "Invalid Request", "Must be JSON-RPC 2.0")

        method = request.get('method')
        if not method:
            return self._error_response(request.get('id'), -32600, "Invalid Request", "Missing 'method' field")

        params = request.get('params', {})
        request_id = request.get('id')

        # Dispatch to method handler
        if method not in self._methods:
            return self._error_response(request_id, -32601, "Method not found", f"Method '{method}' not found")

        try:
            handler = self._methods[method]
            result = await handler(params)
            return self._success_response(request_id, result)
        except RPCError as e:
            # Custom RPC error with specific error code
            logger.warning(f"RPC error in method '{method}': {e.message}")
            return self._error_response(request_id, e.code, e.message, e.data)
        except Exception as e:
            logger.error(f"Error in method '{method}': {e}", exc_info=True)
            return self._error_response(request_id, -32603, "Internal error", str(e))

    def _success_response(self, request_id: Any, result: Any) -> dict:
        """Create JSON-RPC success response"""
        return {
            'jsonrpc': '2.0',
            'result': result,
            'id': request_id
        }

    def _error_response(self, request_id: Any, code: int, message: str, data: Any = None) -> dict:
        """Create JSON-RPC error response"""
        error = {
            'code': code,
            'message': message
        }
        if data is not None:
            error['data'] = data

        return {
            'jsonrpc': '2.0',
            'error': error,
            'id': request_id
        }

    # =========================================================================
    # RPC Method Handlers
    # =========================================================================

    async def handle_ping(self, params: dict) -> dict:
        """
        Handle 'ping' method - health check.

        Returns daemon status and basic info.
        """
        import time

        buffer_stats = self.event_buffer.stats()

        return {
            'status': 'ok',
            'version': '1.0.0',
            'uptime_seconds': 0,  # TODO: Track uptime
            'buffer_size': buffer_stats['max_size'],
            'event_count': buffer_stats['size']
        }

    async def handle_query_events(self, params: dict) -> dict:
        """
        Handle 'query_events' method - query event buffer.

        Params:
            - last: Last N events
            - since_ms: Since timestamp
            - until_ms: Until timestamp
            - event_types: List of event types
            - min_significance: Minimum significance score
            - user_initiated_only: Only user-initiated events
        """
        import time

        start = time.time()

        # Extract parameters
        last = params.get('last')
        since_ms = params.get('since_ms')
        until_ms = params.get('until_ms')
        event_types = params.get('event_types')
        min_significance = params.get('min_significance')
        user_initiated_only = params.get('user_initiated_only', False)

        # Support single event_type parameter (convert to list for buffer)
        event_type = params.get('event_type')
        if event_type and not event_types:
            event_types = [event_type]

        # Query buffer
        events = self.event_buffer.get_events(
            last=last,
            since_ms=since_ms,
            until_ms=until_ms,
            event_types=event_types,
            min_significance=min_significance,
            user_initiated_only=user_initiated_only
        )

        # Serialize events (simplified)
        event_summaries = []
        for event in events:
            # Serialize correlations
            correlations_list = []
            for corr in event.correlations:
                correlations_list.append({
                    'action': {
                        'timestamp_ms': corr.action.timestamp_ms,
                        'action_type': corr.action.action_type.name,
                        'binding_command': corr.action.binding_command,
                        'input_type': corr.action.input_type
                    },
                    'confidence': corr.confidence,
                    'time_delta_ms': corr.time_delta_ms,
                    'reasoning': corr.reasoning
                })

            summary = {
                'event_id': event.event_id,
                'timestamp_ms': event.timestamp_ms,
                'event_type': event.event_type,
                'sway_change': event.sway_change,
                'container_id': event.container_id,
                'diff': {
                    'total_changes': event.diff.total_changes,
                    'significance_level': event.diff.significance_level,
                    'significance_score': event.diff.significance_score,
                    'computation_time_ms': event.diff.computation_time_ms
                },
                'correlations': correlations_list
            }

            event_summaries.append(summary)

        query_time_ms = (time.time() - start) * 1000

        return {
            'events': event_summaries,
            'total_matched': len(event_summaries),
            'buffer_size': self.event_buffer.size(),
            'query_time_ms': round(query_time_ms, 3)
        }

    async def handle_get_event(self, params: dict) -> dict:
        """
        Handle 'get_event' method - get detailed event with diff and enrichment.

        Params:
            - event_id: Event ID to retrieve
            - include_snapshots: Include full tree snapshots (default: False)
            - include_enrichment: Include enriched context (default: True)
        """
        event_id = params.get('event_id')
        if event_id is None:
            raise ValueError("Missing required parameter: event_id")

        # Convert event_id to int (accept both string and int from RPC client)
        try:
            event_id = int(event_id)
        except (ValueError, TypeError):
            raise ValueError(f"Invalid event_id: must be an integer or numeric string, got {event_id!r}")

        include_snapshots = params.get('include_snapshots', False)
        include_enrichment = params.get('include_enrichment', True)

        event = self.event_buffer.get_event_by_id(event_id)
        if not event:
            raise RPCError(-32000, "Event not found", f"Event ID {event_id} does not exist in buffer")

        # Build detailed event response
        result = {
            'event_id': event.event_id,
            'timestamp_ms': event.timestamp_ms,
            'event_type': event.event_type,
            'sway_change': event.sway_change,
            'container_id': event.container_id,
        }

        # Serialize diff with detailed field changes
        if event.diff:
            result['diff'] = {
                'diff_id': event.diff.diff_id,
                'before_snapshot_id': event.diff.before_snapshot_id,
                'after_snapshot_id': event.diff.after_snapshot_id,
                'total_changes': event.diff.total_changes,
                'significance_score': event.diff.significance_score,
                'significance_level': event.diff.significance_level,
                'computation_time_ms': event.diff.computation_time_ms,
                'node_changes': self._serialize_node_changes(event.diff.node_changes)
            }

        # Serialize correlations
        correlations_list = []
        for corr in event.correlations:
            correlations_list.append({
                'action': {
                    'timestamp_ms': corr.action.timestamp_ms,
                    'action_type': corr.action.action_type.name,
                    'binding_command': corr.action.binding_command,
                    'input_type': corr.action.input_type
                },
                'confidence': corr.confidence,
                'confidence_level': corr.confidence_level.name if hasattr(corr, 'confidence_level') else 'unknown',
                'time_delta_ms': corr.time_delta_ms,
                'reasoning': corr.reasoning
            })
        result['correlations'] = correlations_list

        # Include full snapshots if requested
        if include_snapshots:
            result['snapshots'] = {
                'before': None,  # TreeEvent doesn't store before snapshot (only diff)
                'after': event.snapshot.tree_data if event.snapshot else None
            }

        # Include enriched context (Phase 5 - User Story 3)
        if include_enrichment and event.snapshot:
            result['enrichment'] = self._serialize_enrichment(event.snapshot.enriched_data)

        return result

    def _serialize_node_changes(self, node_changes: list) -> list:
        """
        Serialize NodeChange list with full field details.

        Args:
            node_changes: List of NodeChange objects

        Returns:
            List of serialized node changes
        """
        serialized = []

        for node_change in node_changes:
            # Serialize field changes
            field_changes = []
            for fc in node_change.field_changes:
                field_changes.append({
                    'field_path': fc.field_path,
                    'old_value': fc.old_value,
                    'new_value': fc.new_value,
                    'change_type': fc.change_type.name,
                    'significance_score': fc.significance_score
                })

            serialized.append({
                'node_id': node_change.node_id,
                'node_type': node_change.node_type,
                'node_path': node_change.node_path,
                'change_type': node_change.change_type.name,
                'field_changes': field_changes
            })

        return serialized

    def _serialize_enrichment(self, enriched_data: dict) -> dict:
        """
        Serialize enriched window contexts.

        Args:
            enriched_data: Dict[window_id, WindowContext]

        Returns:
            Serialized enrichment data
        """
        serialized = {}

        for window_id, context in enriched_data.items():
            serialized[str(window_id)] = {
                'window_id': context.window_id,
                'pid': context.pid,
                'i3pm_app_id': context.i3pm_app_id,
                'i3pm_app_name': context.i3pm_app_name,
                'i3pm_project_name': context.i3pm_project_name,
                'i3pm_scope': context.i3pm_scope,
                'project_marks': context.project_marks,
                'app_marks': context.app_marks,
                'launch_timestamp_ms': context.launch_timestamp_ms,
                'launch_action': context.launch_action
            }

        return serialized

    async def handle_get_statistics(self, params: dict) -> dict:
        """
        Handle 'get_statistics' method - get buffer statistics.

        Params:
            - since_ms: Analyze events since timestamp
        """
        since_ms = params.get('since_ms')

        # Get all events (or filtered by time)
        events = self.event_buffer.get_events(since_ms=since_ms)

        # Compute statistics
        event_type_distribution = {}
        diff_times = []
        user_initiated_count = 0
        high_confidence_count = 0

        for event in events:
            # Event type distribution
            event_type_distribution[event.event_type] = \
                event_type_distribution.get(event.event_type, 0) + 1

            # Diff computation times
            diff_times.append(event.diff.computation_time_ms)

            # Correlation stats
            best_corr = event.get_best_correlation()
            if best_corr:
                user_initiated_count += 1
                if best_corr.confidence_score >= 0.90:
                    high_confidence_count += 1

        # Calculate percentiles
        if diff_times:
            diff_times_sorted = sorted(diff_times)
            p50_idx = len(diff_times_sorted) // 2
            p95_idx = int(len(diff_times_sorted) * 0.95)
            p99_idx = int(len(diff_times_sorted) * 0.99)

            performance = {
                'avg_diff_computation_ms': round(sum(diff_times) / len(diff_times), 2),
                'p50_diff_computation_ms': round(diff_times_sorted[p50_idx], 2),
                'p95_diff_computation_ms': round(diff_times_sorted[p95_idx], 2),
                'p99_diff_computation_ms': round(diff_times_sorted[p99_idx], 2),
                'max_diff_computation_ms': round(max(diff_times), 2)
            }
        else:
            performance = {}

        buffer_stats = self.event_buffer.stats()

        return {
            'event_type_distribution': event_type_distribution,
            'performance': performance,
            'correlation': {
                'user_initiated_count': user_initiated_count,
                'high_confidence_count': high_confidence_count,
                'no_correlation_count': len(events) - user_initiated_count
            },
            'buffer': buffer_stats
        }

    async def handle_get_daemon_status(self, params: dict) -> dict:
        """
        Handle 'get_daemon_status' method - comprehensive daemon status.
        """
        buffer_stats = self.event_buffer.stats()
        differ_stats = self.differ.stats()

        return {
            'version': '1.0.0',
            'uptime_seconds': 0,  # TODO
            'buffer': {
                'max_size': buffer_stats['max_size'],
                'current_size': buffer_stats['size'],
                'is_full': buffer_stats['is_full']
            },
            'performance': {
                'diffs_computed': differ_stats['diffs_computed'],
                'cache_size': differ_stats['cache']['size'],
                'cache_memory_kb': differ_stats['cache']['memory_kb']
            }
        }

    def _generate_event_summary(self, event) -> str:
        """
        Generate human-readable summary of event.

        Args:
            event: TreeEvent

        Returns:
            Summary string
        """
        # Simplified summary
        # TODO: Implement more detailed summaries based on event type
        return f"{event.event_type} (ID: {event.event_id})"

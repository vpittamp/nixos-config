"""JSON-RPC 2.0 client for daemon communication

Provides high-level API for CLI to interact with daemon.

Performance: <2ms round-trip for typical queries
"""

import json
import socket
from pathlib import Path
from typing import Any, Dict, List, Optional


class RPCError(Exception):
    """JSON-RPC error response"""

    def __init__(self, code: int, message: str, data: Any = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.data = data


class RPCClient:
    """
    JSON-RPC 2.0 client for communicating with daemon.

    Usage:
        client = RPCClient()
        result = client.ping()
        events = client.query_events(last=10)
    """

    def __init__(self, socket_path: Optional[Path] = None):
        """
        Initialize RPC client.

        Args:
            socket_path: Path to Unix socket (default: XDG_RUNTIME_DIR/sway-tree-monitor.sock)
        """
        import os
        if socket_path is None:
            runtime_dir = os.getenv('XDG_RUNTIME_DIR', '/run/user/1000')
            socket_path = Path(runtime_dir) / 'sway-tree-monitor.sock'

        self.socket_path = socket_path
        self._request_id = 0

    def _call(self, method: str, params: Optional[Dict] = None) -> Any:
        """
        Make JSON-RPC 2.0 call to daemon.

        Args:
            method: RPC method name
            params: Method parameters (optional)

        Returns:
            Result from server

        Raises:
            RPCError: If server returns error
            ConnectionError: If cannot connect to daemon
        """
        if params is None:
            params = {}

        # Generate request ID
        self._request_id += 1
        request_id = self._request_id

        # Build JSON-RPC request
        request = {
            'jsonrpc': '2.0',
            'method': method,
            'params': params,
            'id': request_id
        }

        # Connect to Unix socket
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(str(self.socket_path))
        except (FileNotFoundError, ConnectionRefusedError) as e:
            raise ConnectionError(
                f"Cannot connect to daemon at {self.socket_path}. "
                "Is the daemon running?"
            ) from e

        try:
            # Send request (newline-delimited JSON)
            request_json = json.dumps(request)
            sock.sendall(request_json.encode('utf-8') + b'\n')

            # Receive response
            response_data = b''
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response_data += chunk
                if b'\n' in response_data:
                    break

            # Parse response
            response = json.loads(response_data.decode('utf-8'))

        finally:
            sock.close()

        # Validate response
        if response.get('jsonrpc') != '2.0':
            raise ValueError("Invalid JSON-RPC response")

        if response.get('id') != request_id:
            raise ValueError("Response ID mismatch")

        # Check for error
        if 'error' in response:
            error = response['error']
            raise RPCError(
                code=error['code'],
                message=error['message'],
                data=error.get('data')
            )

        # Return result
        return response.get('result')

    # =========================================================================
    # High-Level API Methods
    # =========================================================================

    def ping(self) -> Dict[str, Any]:
        """
        Ping daemon (health check).

        Returns:
            Status dict with version, uptime, buffer size
        """
        return self._call('ping')

    def query_events(
        self,
        last: Optional[int] = None,
        since_ms: Optional[int] = None,
        until_ms: Optional[int] = None,
        event_types: Optional[List[str]] = None,
        min_significance: Optional[float] = None,
        user_initiated_only: bool = False
    ) -> Dict[str, Any]:
        """
        Query events from buffer.

        Args:
            last: Return last N events
            since_ms: Events after this timestamp
            until_ms: Events before this timestamp
            event_types: Filter by event types
            min_significance: Minimum significance score
            user_initiated_only: Only user-initiated events

        Returns:
            Dict with 'events' list and metadata
        """
        params = {}
        if last is not None:
            params['last'] = last
        if since_ms is not None:
            params['since_ms'] = since_ms
        if until_ms is not None:
            params['until_ms'] = until_ms
        if event_types is not None:
            params['event_types'] = event_types
        if min_significance is not None:
            params['min_significance'] = min_significance
        if user_initiated_only:
            params['user_initiated_only'] = True

        return self._call('query_events', params)

    def get_event(
        self,
        event_id: int,
        include_snapshots: bool = False,
        include_diff: bool = True
    ) -> Dict[str, Any]:
        """
        Get detailed information for a specific event.

        Args:
            event_id: Event ID
            include_snapshots: Include full tree snapshots
            include_diff: Include detailed diff

        Returns:
            Detailed event information
        """
        params = {
            'event_id': event_id,
            'include_snapshots': include_snapshots,
            'include_diff': include_diff
        }
        return self._call('get_event', params)

    def get_statistics(self, since_ms: Optional[int] = None) -> Dict[str, Any]:
        """
        Get buffer statistics.

        Args:
            since_ms: Analyze events since this timestamp

        Returns:
            Statistics dict with event type distribution, performance metrics
        """
        params = {}
        if since_ms is not None:
            params['since_ms'] = since_ms

        return self._call('get_statistics', params)

    def get_daemon_status(self) -> Dict[str, Any]:
        """
        Get comprehensive daemon status.

        Returns:
            Status dict with daemon info, buffer stats, performance metrics
        """
        return self._call('get_daemon_status')

    def is_daemon_running(self) -> bool:
        """
        Check if daemon is running.

        Returns:
            True if daemon is reachable, False otherwise
        """
        try:
            self.ping()
            return True
        except (ConnectionError, RPCError):
            return False

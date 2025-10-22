"""Mock daemon client for isolated TUI testing.

Provides mock implementations of daemon operations without requiring actual daemon.
Captures all IPC calls for verification in test assertions.
"""

from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class MockRequest:
    """Captured daemon request."""
    method: str
    params: Dict[str, Any]
    timestamp: datetime = field(default_factory=datetime.now)


class MockDaemonClient:
    """Mock daemon client implementing IMockDaemonClient contract."""

    def __init__(self):
        """Initialize mock daemon client."""
        self.captured_requests: List[MockRequest] = []
        self.mock_responses: Dict[str, Any] = {}
        self.simulated_events: List[Dict[str, Any]] = []

    async def send_request(self, method: str, params: Dict[str, Any]) -> Any:
        """Mock daemon request.

        Records request for verification and returns mock response.

        Args:
            method: JSON-RPC method name
            params: Request parameters

        Returns:
            Mock response based on method
        """
        # Capture request
        self.captured_requests.append(MockRequest(method=method, params=params))

        # Return mock response if configured
        if method in self.mock_responses:
            return self.mock_responses[method]

        # Default responses for common methods
        default_responses = {
            "daemon.status": {
                "running": True,
                "uptime": 123.45,
                "events_processed": 42,
                "memory_mb": 12.5
            },
            "project.list": [],
            "project.current": {"name": "test-project", "directory": "/tmp/test-project"},
            "project.switch": {"success": True},
            "layout.save": {"success": True, "layout_name": "test-layout"},
            "layout.restore": {"success": True, "windows_launched": 3},
            "workspace.get_config": [],
            "workspace.redistribute": {"success": True, "workspaces_moved": 2}
        }

        return default_responses.get(method, {"success": True})

    def get_captured_requests(self) -> List[Dict[str, Any]]:
        """Get list of all captured requests for assertion verification.

        Returns:
            List of request dicts with method and params
        """
        return [
            {"method": req.method, "params": req.params, "timestamp": req.timestamp.isoformat()}
            for req in self.captured_requests
        ]

    async def simulate_event(self, event_type: str, event_data: Dict[str, Any]) -> None:
        """Simulate daemon event for testing event handlers.

        Args:
            event_type: Event type (e.g., "layout::saved")
            event_data: Event payload
        """
        self.simulated_events.append({
            "type": event_type,
            "data": event_data,
            "timestamp": datetime.now().isoformat()
        })

    def set_mock_response(self, method: str, response: Any) -> None:
        """Configure mock response for specific method.

        Args:
            method: Method name to mock
            response: Response to return
        """
        self.mock_responses[method] = response

    def clear_captured_requests(self) -> None:
        """Clear all captured requests."""
        self.captured_requests.clear()

    def get_requests_by_method(self, method: str) -> List[MockRequest]:
        """Get all captured requests for specific method.

        Args:
            method: Method name to filter by

        Returns:
            List of matching requests
        """
        return [req for req in self.captured_requests if req.method == method]

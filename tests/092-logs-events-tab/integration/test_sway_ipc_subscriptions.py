"""
Integration test for i3ipc.aio window event subscription (Feature 092 - T014)

Tests that the backend can subscribe to Sway IPC events via i3ipc.aio.

NOTE: This is a PLACEHOLDER test. Actual implementation will be completed after
backend streaming functions (query_events_data, stream_events) are implemented.
"""

import pytest

# TODO: Implement after T016-T021 (backend streaming implementation)
pytest.skip("Integration test pending backend implementation", allow_module_level=True)

# This test will verify:
# - i3ipc.aio.Connection can connect to Sway IPC
# - window event subscription works
# - workspace event subscription works
# - events are received and can be parsed
# - events can be converted to Event Pydantic models

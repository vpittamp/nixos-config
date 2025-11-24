"""
Unit tests for Event Pydantic model validation (Feature 092 - T012)

Tests Event model field validation, timestamp handling, icon/color assignment.
"""

import pytest
import time
from typing import Dict, Any

# Import from monitoring_data.py
import sys
from pathlib import Path

# Add home-modules to path for imports
sys.path.insert(0, str(Path(__file__).parents[3] / "home-modules/tools"))

from i3_project_manager.cli.monitoring_data import (
    Event,
    SwayEventPayload,
    EventEnrichment,
    EventsViewData,
    EVENT_ICONS,
)


class TestEventModel:
    """Test Event Pydantic model."""

    def test_event_creation_minimal(self):
        """Test creating Event with minimal required fields."""
        current_time = time.time()
        event = Event(
            timestamp=current_time,
            timestamp_friendly="Just now",
            event_type="window::new",
            payload=SwayEventPayload(),
            icon="󰖲",
            color="#89b4fa",
            category="window",
            searchable_text="test window",
        )

        assert event.timestamp == current_time
        assert event.event_type == "window::new"
        assert event.icon == "󰖲"
        assert event.color == "#89b4fa"
        assert event.category == "window"

    def test_event_with_enrichment(self):
        """Test Event with enrichment metadata."""
        enrichment = EventEnrichment(
            window_id=12345,
            pid=67890,
            app_name="terminal",
            project_name="nixos",
            scope="scoped",
            workspace_number=1,
            daemon_available=True,
        )

        event = Event(
            timestamp=time.time(),
            timestamp_friendly="1s ago",
            event_type="window::focus",
            payload=SwayEventPayload(container={"id": 12345}),
            enrichment=enrichment,
            icon="󰋁",
            color="#74c7ec",
            category="window",
            searchable_text="terminal nixos 1",
        )

        assert event.enrichment is not None
        assert event.enrichment.app_name == "terminal"
        assert event.enrichment.project_name == "nixos"
        assert event.enrichment.scope == "scoped"

    def test_event_icon_color_mapping(self):
        """Test that event icons and colors match EVENT_ICONS dictionary."""
        assert "window::new" in EVENT_ICONS
        assert "window::close" in EVENT_ICONS
        assert "workspace::focus" in EVENT_ICONS

        # Verify icon structure
        window_new_icon = EVENT_ICONS["window::new"]
        assert "icon" in window_new_icon
        assert "color" in window_new_icon
        assert window_new_icon["color"].startswith("#")

    def test_event_timestamp_validation(self):
        """Test timestamp must be a valid float."""
        with pytest.raises(Exception):  # Pydantic validation error
            Event(
                timestamp="invalid",  # Should be float
                timestamp_friendly="Just now",
                event_type="window::new",
                payload=SwayEventPayload(),
                icon="󰖲",
                color="#89b4fa",
                category="window",
                searchable_text="test",
            )

    def test_event_type_literal_validation(self):
        """Test event_type must be valid EventType literal."""
        with pytest.raises(Exception):  # Pydantic validation error
            Event(
                timestamp=time.time(),
                timestamp_friendly="Just now",
                event_type="invalid::type",  # Not a valid EventType
                payload=SwayEventPayload(),
                icon="󰖲",
                color="#89b4fa",
                category="window",
                searchable_text="test",
            )


class TestSwayEventPayload:
    """Test SwayEventPayload Pydantic model."""

    def test_payload_with_container(self):
        """Test payload with window container data."""
        payload = SwayEventPayload(
            container={"id": 123, "app_id": "firefox", "focused": True}
        )

        assert payload.container is not None
        assert payload.container["id"] == 123
        assert payload.container["app_id"] == "firefox"

    def test_payload_with_workspace_events(self):
        """Test payload with workspace focus change."""
        payload = SwayEventPayload(
            current={"num": 3, "name": "3"},
            old={"num": 1, "name": "1"},
        )

        assert payload.current is not None
        assert payload.old is not None
        assert payload.current["num"] == 3
        assert payload.old["num"] == 1


class TestEventEnrichment:
    """Test EventEnrichment Pydantic model."""

    def test_enrichment_full_data(self):
        """Test enrichment with all fields populated."""
        enrichment = EventEnrichment(
            window_id=12345,
            pid=67890,
            app_name="terminal",
            app_id="terminal-nixos-123",
            project_name="nixos",
            scope="scoped",
            workspace_number=1,
            workspace_name="1",
            output_name="HEADLESS-1",
            is_pwa=False,
            daemon_available=True,
            enrichment_latency_ms=15.3,
        )

        assert enrichment.window_id == 12345
        assert enrichment.pid == 67890
        assert enrichment.app_name == "terminal"
        assert enrichment.project_name == "nixos"
        assert enrichment.scope == "scoped"
        assert enrichment.is_pwa is False
        assert enrichment.daemon_available is True

    def test_enrichment_optional_fields(self):
        """Test enrichment with minimal fields (daemon unavailable)."""
        enrichment = EventEnrichment(daemon_available=False)

        assert enrichment.window_id is None
        assert enrichment.app_name is None
        assert enrichment.project_name is None
        assert enrichment.daemon_available is False


class TestEventsViewData:
    """Test EventsViewData response structure."""

    def test_view_data_success_state(self):
        """Test EventsViewData in success state."""
        current_time = time.time()
        event = Event(
            timestamp=current_time,
            timestamp_friendly="Just now",
            event_type="window::new",
            payload=SwayEventPayload(),
            icon="󰖲",
            color="#89b4fa",
            category="window",
            searchable_text="test",
        )

        view_data = EventsViewData(
            status="ok",
            events=[event],
            event_count=1,
            oldest_timestamp=current_time,
            newest_timestamp=current_time,
            daemon_available=True,
            ipc_connected=True,
            timestamp=current_time,
            timestamp_friendly="Just now",
        )

        assert view_data.status == "ok"
        assert view_data.error is None
        assert len(view_data.events) == 1
        assert view_data.event_count == 1
        assert view_data.daemon_available is True
        assert view_data.ipc_connected is True

    def test_view_data_error_state(self):
        """Test EventsViewData in error state."""
        current_time = time.time()
        view_data = EventsViewData(
            status="error",
            error="Sway IPC connection failed",
            events=[],
            event_count=0,
            daemon_available=False,
            ipc_connected=False,
            timestamp=current_time,
            timestamp_friendly="Just now",
        )

        assert view_data.status == "error"
        assert view_data.error == "Sway IPC connection failed"
        assert len(view_data.events) == 0
        assert view_data.daemon_available is False
        assert view_data.ipc_connected is False

    def test_view_data_json_serialization(self):
        """Test that EventsViewData can be serialized to JSON."""
        current_time = time.time()
        view_data = EventsViewData(
            status="ok",
            events=[],
            event_count=0,
            timestamp=current_time,
            timestamp_friendly="Just now",
        )

        # Pydantic models can be serialized via model_dump()
        json_dict = view_data.model_dump()
        assert json_dict["status"] == "ok"
        assert "events" in json_dict
        assert "timestamp" in json_dict

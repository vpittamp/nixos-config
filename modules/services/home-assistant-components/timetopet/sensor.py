"""Sensor platform for Time To Pet."""

from __future__ import annotations

from typing import Any

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorStateClass,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity
from homeassistant.util import dt as dt_util

from .api import is_cancelled, parse_event_time, summarize_event
from .const import DOMAIN
from .coordinator import TimeToPetCoordinator


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up the Time To Pet sensors."""
    coordinator: TimeToPetCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities(
        [
            TimeToPetNextVisitSensor(coordinator, entry),
            TimeToPetUpcomingVisitsSensor(coordinator, entry),
            TimeToPetVisitsTodaySensor(coordinator, entry),
            TimeToPetLastCompletedVisitSensor(coordinator, entry),
            TimeToPetPendingRequestsSensor(coordinator, entry),
        ]
    )


def _device_info(entry: ConfigEntry) -> DeviceInfo:
    return DeviceInfo(
        identifiers={(DOMAIN, entry.entry_id)},
        name="Time To Pet",
        manufacturer="Time To Pet",
    )


def _events_data(coordinator: TimeToPetCoordinator) -> list[dict]:
    if isinstance(coordinator.data, dict):
        return coordinator.data.get("events", [])
    if isinstance(coordinator.data, list):
        return coordinator.data
    return []


def _pending_data(coordinator: TimeToPetCoordinator) -> list[dict]:
    if isinstance(coordinator.data, dict):
        return coordinator.data.get("pending", [])
    return []


def _live_events(coordinator: TimeToPetCoordinator) -> list[dict]:
    """Events that are not cancelled."""
    return [e for e in _events_data(coordinator) if not is_cancelled(e)]


def _upcoming_events(coordinator: TimeToPetCoordinator) -> list[dict]:
    """Non-completed events whose end time has not passed, soonest first."""
    now = dt_util.now()
    events = []
    for event in _live_events(coordinator):
        if event.get("status") == "Completed" and not event.get("inProgress"):
            continue
        end = parse_event_time(event.get("end"))
        start = parse_event_time(event.get("start"))
        if end is None or start is None:
            continue
        if end > now:
            events.append(event)
    return sorted(events, key=lambda e: parse_event_time(e.get("start")))


def _completed_events(coordinator: TimeToPetCoordinator) -> list[dict]:
    """Completed events, newest first."""
    events = []
    for event in _live_events(coordinator):
        if event.get("status") == "Completed" and not event.get("inProgress"):
            events.append(event)
    return sorted(
        events,
        key=lambda e: parse_event_time(e.get("end")) or dt_util.now(),
        reverse=True,
    )


class TimeToPetNextVisitSensor(
    CoordinatorEntity[TimeToPetCoordinator], SensorEntity
):
    """Start time of the next scheduled visit."""

    _attr_has_entity_name = True
    _attr_name = "Next visit"
    _attr_icon = "mdi:dog-service"
    _attr_device_class = SensorDeviceClass.TIMESTAMP

    def __init__(
        self, coordinator: TimeToPetCoordinator, entry: ConfigEntry
    ) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_next_visit"
        self._attr_device_info = _device_info(entry)

    @property
    def native_value(self):
        upcoming = _upcoming_events(self.coordinator)
        if not upcoming:
            return None
        return parse_event_time(upcoming[0].get("start"))

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        upcoming = _upcoming_events(self.coordinator)
        if not upcoming:
            return {}
        return summarize_event(upcoming[0])


class TimeToPetUpcomingVisitsSensor(
    CoordinatorEntity[TimeToPetCoordinator], SensorEntity
):
    """Number of scheduled visits remaining in the feed window."""

    _attr_has_entity_name = True
    _attr_name = "Upcoming visits"
    _attr_icon = "mdi:calendar-clock"
    _attr_native_unit_of_measurement = "visits"
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(
        self, coordinator: TimeToPetCoordinator, entry: ConfigEntry
    ) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_upcoming_visits"
        self._attr_device_info = _device_info(entry)

    @property
    def native_value(self) -> int:
        return len(_upcoming_events(self.coordinator))

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        return {
            "visits": [summarize_event(e) for e in _upcoming_events(self.coordinator)]
        }


class TimeToPetVisitsTodaySensor(
    CoordinatorEntity[TimeToPetCoordinator], SensorEntity
):
    """Number of visits (any status) on today's schedule."""

    _attr_has_entity_name = True
    _attr_name = "Visits today"
    _attr_icon = "mdi:calendar-today"
    _attr_native_unit_of_measurement = "visits"
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(
        self, coordinator: TimeToPetCoordinator, entry: ConfigEntry
    ) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_visits_today"
        self._attr_device_info = _device_info(entry)

    def _todays_events(self) -> list[dict]:
        today = dt_util.now().date()
        return [
            e
            for e in _live_events(self.coordinator)
            if (start := parse_event_time(e.get("start"))) is not None
            and start.astimezone(dt_util.now().tzinfo).date() == today
        ]

    @property
    def native_value(self) -> int:
        return len(self._todays_events())

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        return {"visits": [summarize_event(e) for e in self._todays_events()]}


class TimeToPetLastCompletedVisitSensor(
    CoordinatorEntity[TimeToPetCoordinator], SensorEntity
):
    """Timestamp and summary of the most recently completed visit."""

    _attr_has_entity_name = True
    _attr_name = "Last completed visit"
    _attr_icon = "mdi:check-circle-outline"
    _attr_device_class = SensorDeviceClass.TIMESTAMP

    def __init__(
        self, coordinator: TimeToPetCoordinator, entry: ConfigEntry
    ) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_last_completed_visit"
        self._attr_device_info = _device_info(entry)

    @property
    def native_value(self):
        completed = _completed_events(self.coordinator)
        if not completed:
            return None
        return parse_event_time(completed[0].get("end"))

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        completed = _completed_events(self.coordinator)
        if not completed:
            return {}
        return summarize_event(completed[0])


class TimeToPetPendingRequestsSensor(
    CoordinatorEntity[TimeToPetCoordinator], SensorEntity
):
    """Number of service requests awaiting company approval."""

    _attr_has_entity_name = True
    _attr_name = "Pending requests"
    _attr_icon = "mdi:clock-alert-outline"
    _attr_native_unit_of_measurement = "requests"
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(
        self, coordinator: TimeToPetCoordinator, entry: ConfigEntry
    ) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_pending_requests"
        self._attr_device_info = _device_info(entry)

    @property
    def native_value(self) -> int:
        return len(_pending_data(self.coordinator))

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        return {
            "requests": [summarize_event(e) for e in _pending_data(self.coordinator)]
        }

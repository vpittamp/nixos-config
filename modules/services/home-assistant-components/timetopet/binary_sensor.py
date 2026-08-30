"""Binary sensor platform for Time To Pet."""

from __future__ import annotations

from typing import Any

from homeassistant.components.binary_sensor import BinarySensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .api import is_cancelled, summarize_event
from .const import DOMAIN
from .coordinator import TimeToPetCoordinator


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up the Time To Pet binary sensors."""
    coordinator: TimeToPetCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([TimeToPetVisitInProgressSensor(coordinator, entry)])


class TimeToPetVisitInProgressSensor(
    CoordinatorEntity[TimeToPetCoordinator], BinarySensorEntity
):
    """On while a staff member has a visit in progress (checked in)."""

    _attr_has_entity_name = True
    _attr_name = "Visit in progress"
    _attr_icon = "mdi:account-clock"

    def __init__(
        self, coordinator: TimeToPetCoordinator, entry: ConfigEntry
    ) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.entry_id}_visit_in_progress"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, entry.entry_id)},
            name="Time To Pet",
            manufacturer="Time To Pet",
        )

    def _in_progress_events(self) -> list[dict]:
        return [
            e
            for e in (self.coordinator.data or [])
            if e.get("inProgress") and not is_cancelled(e)
        ]

    @property
    def is_on(self) -> bool:
        return bool(self._in_progress_events())

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        return {
            "visits": [summarize_event(e) for e in self._in_progress_events()]
        }

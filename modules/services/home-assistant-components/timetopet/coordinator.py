"""DataUpdateCoordinator for Time To Pet."""

from __future__ import annotations

import datetime as dt
import logging
from datetime import timedelta

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ConfigEntryAuthFailed
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed
from homeassistant.util import dt as dt_util

from .api import TimeToPetApiError, TimeToPetAuthError, TimeToPetClient
from .const import DEFAULT_SCAN_INTERVAL, DOMAIN, FEED_DAYS_AHEAD, FEED_DAYS_BACK

_LOGGER = logging.getLogger(__name__)


class TimeToPetCoordinator(DataUpdateCoordinator[dict[str, list[dict]]]):
    """Polls the Time To Pet client portal for scheduled visits and pending requests."""

    def __init__(
        self, hass: HomeAssistant, client: TimeToPetClient, entry: ConfigEntry
    ) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name=DOMAIN,
            update_interval=timedelta(seconds=DEFAULT_SCAN_INTERVAL),
        )
        self.client = client
        self.entry = entry

    async def _async_update_data(self) -> dict[str, list[dict]]:
        today = dt_util.now().date()
        start = today - timedelta(days=FEED_DAYS_BACK)
        end = today + timedelta(days=FEED_DAYS_AHEAD)
        try:
            return await self.client.async_get_data(start, end)
        except TimeToPetAuthError as err:
            raise ConfigEntryAuthFailed(str(err)) from err
        except TimeToPetApiError as err:
            raise UpdateFailed(str(err)) from err

"""Config flow for Time To Pet."""

from __future__ import annotations

from typing import Any

import voluptuous as vol
from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.const import CONF_EMAIL, CONF_PASSWORD

from .api import TimeToPetApiError, TimeToPetAuthError, TimeToPetClient
from .const import DOMAIN

STEP_USER_DATA_SCHEMA = vol.Schema(
    {
        vol.Required(CONF_EMAIL): str,
        vol.Required(CONF_PASSWORD): str,
    }
)


class TimeToPetConfigFlow(ConfigFlow, domain=DOMAIN):
    """Handle a config flow for Time To Pet."""

    VERSION = 1

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Handle the initial step."""
        errors: dict[str, str] = {}
        if user_input is not None:
            await self.async_set_unique_id(user_input[CONF_EMAIL].lower())
            self._abort_if_unique_id_configured()

            client = TimeToPetClient(
                user_input[CONF_EMAIL],
                user_input[CONF_PASSWORD],
            )
            try:
                await client.async_validate()
            except TimeToPetAuthError:
                errors["base"] = "invalid_auth"
            except TimeToPetApiError:
                errors["base"] = "cannot_connect"
            else:
                return self.async_create_entry(
                    title=f"Time To Pet ({user_input[CONF_EMAIL]})",
                    data=user_input,
                )
            finally:
                await client.async_close()

        return self.async_show_form(
            step_id="user", data_schema=STEP_USER_DATA_SCHEMA, errors=errors
        )

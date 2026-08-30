"""Time To Pet client-portal API client (async).

Authenticates against the same client portal a pet owner's browser uses
(https://www.timetopet.com/portal/login): fetch the login page for its CSRF
token, POST credentials to ajaxProcessLogin, then poll the schedule page's
JSON event feeds with the resulting session cookie. There is no official
client-side API — Time To Pet's Zapier/API surface is business-account only.
"""

from __future__ import annotations

import datetime as dt
import logging
import re

import aiohttp

from .const import (
    EVENT_FEED_URL,
    LOGIN_AJAX_URL,
    LOGIN_PAGE_URL,
    USER_AGENT,
)

_LOGGER = logging.getLogger(__name__)

_CSRF_RE = re.compile(r"CSRF_TOKEN = '([^']+)'")

# Event start/end format: "2026-08-25T12:00:00-0400"
EVENT_TIME_FORMAT = "%Y-%m-%dT%H:%M:%S%z"


class TimeToPetAuthError(Exception):
    """Raised when credentials are rejected or the session is lost."""


class TimeToPetApiError(Exception):
    """Raised on a transient network/API failure."""


def parse_event_time(value: str | None) -> dt.datetime | None:
    """Parse the feed's timestamp format into an aware datetime."""
    if not value:
        return None
    try:
        return dt.datetime.strptime(value, EVENT_TIME_FORMAT)
    except (ValueError, TypeError):
        _LOGGER.debug("Unparseable event timestamp: %r", value)
        return None


def is_cancelled(event: dict) -> bool:
    """Return True when the event's status marks it cancelled."""
    return str(event.get("status") or "").lower().startswith("cancel")


def summarize_event(event: dict) -> dict:
    """Extract the human-friendly fields from a feed event."""
    start = parse_event_time(event.get("start"))
    end = parse_event_time(event.get("end"))
    out = {
        "service": event.get("service_name") or event.get("title"),
        "staff": event.get("staff_name"),
        "start": start.isoformat() if start else None,
        "end": end.isoformat() if end else None,
        "status": event.get("status"),
        "in_progress": bool(event.get("inProgress")),
        "pets": event.get("pet_string"),
        "id": event.get("id"),
    }
    return {k: v for k, v in out.items() if v not in (None, "")}


class TimeToPetClient:
    """Logs in to the Time To Pet client portal and fetches scheduled visits."""

    def __init__(self, email: str, password: str) -> None:
        self._email = email
        self._password = password
        self._session: aiohttp.ClientSession | None = None
        self._logged_in = False

    async def async_close(self) -> None:
        """Close the underlying HTTP session."""
        if self._session is not None and not self._session.closed:
            await self._session.close()
        self._session = None
        self._logged_in = False

    async def _ensure_session(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            # A dedicated session with its own cookie jar: the portal session
            # is cookie-based and must not leak into HA's shared client session.
            self._session = aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=30),
                cookie_jar=aiohttp.CookieJar(),
                headers={"User-Agent": USER_AGENT},
            )
            self._logged_in = False
        return self._session

    async def _login(self) -> None:
        session = await self._ensure_session()
        try:
            async with session.get(LOGIN_PAGE_URL) as resp:
                resp.raise_for_status()
                text = await resp.text()
        except aiohttp.ClientError as err:
            raise TimeToPetApiError(f"Login page fetch failed: {err}") from err

        match = _CSRF_RE.search(text)
        if not match:
            raise TimeToPetApiError("Could not find CSRF token on the login page")

        data = {
            "email": self._email,
            "password": self._password,
            "sessionCompanyId": "",
            "_token": match.group(1),
        }
        try:
            async with session.post(LOGIN_AJAX_URL, data=data) as resp:
                resp.raise_for_status()
                payload = await resp.json(content_type=None)
        except (aiohttp.ClientError, ValueError) as err:
            raise TimeToPetApiError(f"Login request failed: {err}") from err

        body = payload.get("data") if isinstance(payload, dict) else None
        if not isinstance(body, dict) or body.get("status") != "success":
            errors = (body or {}).get("errors") or "unknown error"
            raise TimeToPetAuthError(f"Login rejected: {errors}")

        self._logged_in = True

    async def async_validate(self) -> None:
        """Validate credentials (used by the config flow)."""
        await self._login()

    async def async_get_events(
        self, start: dt.date, end: dt.date
    ) -> list[dict]:
        """Return scheduled/completed visit records in [start, end)."""
        if not self._logged_in:
            await self._login()
        try:
            return await self._fetch_feed(start, end)
        except TimeToPetAuthError:
            # Session cookie expired — log in once more and retry.
            await self._login()
            return await self._fetch_feed(start, end)

    async def _fetch_feed(self, start: dt.date, end: dt.date) -> list[dict]:
        session = await self._ensure_session()
        params = {"start": start.isoformat(), "end": end.isoformat()}
        try:
            async with session.get(
                EVENT_FEED_URL, params=params, allow_redirects=False
            ) as resp:
                if resp.status in (301, 302, 303, 307, 308, 401, 403):
                    raise TimeToPetAuthError("Portal session expired")
                resp.raise_for_status()
                try:
                    data = await resp.json(content_type=None)
                except ValueError as err:
                    # Logged-out responses come back as the HTML login page.
                    raise TimeToPetAuthError("Portal session expired") from err
        except aiohttp.ClientError as err:
            raise TimeToPetApiError(f"Event feed fetch failed: {err}") from err

        if not isinstance(data, list):
            raise TimeToPetApiError(
                f"Unexpected event feed payload: {type(data).__name__}"
            )
        return data

#!/usr/bin/env python3
"""Call one Home Assistant service. The thing the generated catalog runs.

    ha-call light turn_off light.kitchen_main_lights
    ha-call light turn_on light.kitchen_island_lights brightness_pct=30
    ha-call cover close_cover cover.bedroom_shade_1_top cover.bedroom_shade_2_top
    ha-call light turn_off all

A binary rather than an HTTP case inside the dispatcher, so the argv template
that runs `swaymsg` and the one that dims a lamp are the same kind of thing —
and so this is testable on its own, without a model in the loop.

Arguments after the service are entity ids, except anything containing `=`,
which is service data. That split is what lets one template carry both a room's
worth of entity ids and a brightness.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

from jev_api import JevError, hass_token

TIMEOUT = float(os.environ.get("HASS_TIMEOUT", "15"))


def fail(message: str) -> int:
    print(f"ha-call: {message}", file=sys.stderr)
    return 1


def coerce(value: str):
    """Service data is typed: brightness_pct=30 must be a number, not "30"."""
    lowered = value.lower()
    if lowered in ("true", "false"):
        return lowered == "true"
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return float(value)
    except ValueError:
        return value


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        return fail("usage: ha-call <domain> <service> [entity_id ...] [key=value ...]")

    domain, service = argv[0], argv[1]
    entities: list[str] = []
    data: dict = {}
    for argument in argv[2:]:
        if "=" in argument and not argument.startswith("="):
            key, _, value = argument.partition("=")
            data[key] = coerce(value)
        else:
            entities.append(argument)

    if entities:
        # "all" is Home Assistant's own word for every entity in the domain,
        # and must not be wrapped in a list.
        data["entity_id"] = "all" if entities == ["all"] else entities

    base = (os.environ.get("HASS_URL") or "http://homeassistant.local:8123").rstrip("/")
    try:
        auth = hass_token()
    except JevError as exc:
        return fail(str(exc))

    request = urllib.request.Request(
        f"{base}/api/services/{domain}/{service}",
        data=json.dumps(data).encode(),
        method="POST",
        headers={"Authorization": f"Bearer {auth}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            body = response.read().decode(errors="replace")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:300]
        return fail(f"{domain}.{service} -> HTTP {exc.code}: {detail}")
    except urllib.error.URLError as exc:
        return fail(f"could not reach Home Assistant at {base}: {exc.reason}")

    # The response is the list of states the call changed, which is the only
    # confirmation the API offers that anything actually happened.
    try:
        changed = json.loads(body)
        names = [e.get("entity_id") for e in changed if isinstance(e, dict)]
    except (json.JSONDecodeError, TypeError):
        names = []
    target = data.get("entity_id")
    print(f"{domain}.{service} {target if target else ''}"
          + (f" -> changed {', '.join(n for n in names if n)}" if names else " -> ok"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

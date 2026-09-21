"""The TypeSafe plumbing shared by everything that asks jev a question.

One place that knows how to find the key and how to make the call, so the
command dispatcher and the agent judge cannot drift apart on either — and so
the `op://` reference, retries and back-off are written once.
"""

from __future__ import annotations

import json
import os
import random
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

API_URL = "https://api.typesafe.ai/v1/systemone"


class JevError(RuntimeError):
    """Anything the user should see as a one-line failure, not a traceback."""


def state_dir() -> Path:
    raw = os.environ.get("JEV_STATE_DIR")
    if not raw:
        runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        raw = f"{runtime}/jev"
    path = Path(raw)
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


def cached_secret(cache_name: str, direct_var: str, ref_var: str, label: str) -> str:
    """A secret from the environment, a runtime cache, or 1Password — in that order.

    The cache is what stops 1Password prompting on every single action. `op
    read` costs the best part of a second AND, with desktop-app integration,
    puts an approval dialog in front of the user; doing that per keystroke, per
    light, and once an hour for a catalog refresh is unusable. The resolved
    value lands in the runtime directory: tmpfs, mode 0600, gone at logout, and
    never in the Nix store or $HOME.

    Shared by every secret this package reads, because the first version grew a
    second uncached copy of this logic and the prompts came straight back.
    """
    direct = os.environ.get(direct_var, "").strip()
    if direct:
        return direct

    cache = state_dir() / cache_name
    ttl = int(os.environ.get("JEV_SECRET_TTL", os.environ.get("JEV_API_KEY_TTL", "43200")))
    try:
        if cache.is_file() and (time.time() - cache.stat().st_mtime) < ttl:
            cached = cache.read_text().strip()
            if cached:
                return cached
    except OSError:
        pass

    ref = os.environ.get(ref_var, "").strip()
    if not ref:
        raise JevError(f"no {label}: set {direct_var}, or {ref_var} to an op:// reference")

    op = "/run/wrappers/bin/op"
    if not os.access(op, os.X_OK):
        op = os.environ.get("JEV_OP_BIN", "op")
    try:
        done = subprocess.run(
            [op, "read", "--no-newline", ref],
            capture_output=True,
            text=True,
            timeout=25,
        )
    except FileNotFoundError:
        raise JevError(f"1Password CLI not found; cannot read {ref}") from None
    except subprocess.TimeoutExpired:
        raise JevError(f"1Password timed out reading {ref}; is the desktop app unlocked?") from None

    value = done.stdout.strip()
    if done.returncode != 0 or not value:
        detail = (done.stderr or "").strip().splitlines()
        hint = detail[-1] if detail else "no output"
        raise JevError(f"could not read {ref} from 1Password: {hint}")

    try:
        fd = os.open(cache, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as handle:
            handle.write(value)
    except OSError:
        pass  # a cache we cannot write is a slow path, not a failure
    return value


def api_key() -> str:
    return cached_secret("api-key", "TYPESAFE_API_KEY", "JEV_API_KEY_REF", "TypeSafe key")


def hass_token() -> str:
    return cached_secret("hass-token", "HASS_TOKEN", "HASS_TOKEN_OP_REF",
                         "Home Assistant token")


def evaluate(state: str, questions: dict[str, Any], spec: dict[str, Any] | None = None) -> dict[str, Any]:
    body = json.dumps(
        {
            "state": state,
            "model": os.environ.get("JEV_MODEL") or (spec or {}).get("model") or "jev-latest",
            "questions": questions,
        }
    ).encode()

    request = urllib.request.Request(
        API_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key()}",
            "Content-Type": "application/json",
        },
    )

    timeout = float(os.environ.get("JEV_TIMEOUT", "30"))
    attempts = int(os.environ.get("JEV_RETRIES", "3"))
    started = time.monotonic()
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = json.loads(response.read().decode())
                payload["latencyMs"] = round((time.monotonic() - started) * 1000)
                return payload
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:400]
            # 429 and 529 are the documented back-off codes; everything else is
            # ours to fix, so retrying it would only delay the message.
            if exc.code in (429, 529) and attempt < attempts - 1:
                time.sleep((2**attempt) * 0.5 + random.uniform(0, 0.25))
                continue
            if exc.code == 401:
                raise JevError("TypeSafe rejected the API key (401)") from None
            raise JevError(f"TypeSafe returned HTTP {exc.code}: {detail}") from None
        except urllib.error.URLError as exc:
            if attempt < attempts - 1:
                time.sleep((2**attempt) * 0.5)
                continue
            raise JevError(f"could not reach TypeSafe: {exc.reason}") from None
    raise JevError("could not reach TypeSafe")


def noul_confidence(probability: float) -> float:
    """How sure a yes/no is: distance from the coin flip, not the raw value.

    A 0.04 is a confident *no*, and reporting it as 0.04 would drag the call's
    confidence — the minimum over every judgement — down for an argument the
    model was certain about.
    """
    return max(probability, 1.0 - probability)



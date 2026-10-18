#!/usr/bin/env python3
"""Collect Google Antigravity / Gemini usage into one display-ready JSON record.

Local stats come from Antigravity CLI transcripts under
~/.gemini/antigravity-cli/brain/*/.system_generated/logs/transcript.jsonl;
authoritative quota buckets and subscription tier come from the Cloud Code
v1internal endpoints (loadCodeAssist, retrieveUserQuota,
retrieveUserQuotaSummary) using the CLI's keyring or file OAuth credentials.
"""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

AGENT_ID = "gemini"
AGENT_NAME = "Antigravity"
AUTH_HELP = "Run `agy` to authenticate with Google Antigravity."
CLOUDCODE_BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal"
OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token"
PROBE_MIN_INTERVAL_SECONDS = 15
SCAN_REUSE_SECONDS = 20
LIMITS_ONLY_REUSE_SECONDS = 900

MODEL_SELECTION_RE = re.compile(r"Model Selection` from [^\s]+ to ([^.\n]+)\.")


def gemini_dir() -> Path:
  return Path(os.path.expandvars(os.path.expanduser(os.environ.get("GEMINI_CONFIG_DIR") or "~/.gemini"))).resolve()


def agy_dir() -> Path:
  return gemini_dir() / "antigravity-cli"


def cache_root() -> Path:
  root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell-runtime-shell" / "agent-usage"
  root.mkdir(parents=True, exist_ok=True)
  return root


def date_string(value: dt.date) -> str:
  return value.strftime("%Y-%m-%d")


def local_date_string() -> str:
  return date_string(dt.datetime.now().date())


def recent_date_strings() -> list[str]:
  today = dt.datetime.now().date()
  return [date_string(today - dt.timedelta(days=offset)) for offset in range(6, -1, -1)]


def local_date_from_timestamp(value: Any) -> str:
  if value is None:
    return local_date_string()
  if isinstance(value, (int, float)):
    try:
      seconds = float(value) / 1000.0 if float(value) > 10_000_000_000 else float(value)
      return date_string(dt.datetime.fromtimestamp(seconds).date())
    except Exception:
      return local_date_string()
  raw = str(value).strip()
  if not raw:
    return local_date_string()
  try:
    parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    if parsed.tzinfo is not None:
      parsed = parsed.astimezone()
    return date_string(parsed.date())
  except Exception:
    return local_date_string()


def number(value: Any) -> int:
  try:
    n = float(value or 0)
    return round(n) if n == n else 0
  except Exception:
    return 0


def empty_bucket() -> dict[str, int]:
  return {
    "inputTokens": 0,
    "outputTokens": 0,
    "cacheReadInputTokens": 0,
    "cacheCreationInputTokens": 0,
  }


def read_fresh_json(path: Path, max_age_seconds: float) -> dict[str, Any] | None:
  if max_age_seconds <= 0 or not path.exists():
    return None
  try:
    age = time.time() - path.stat().st_mtime
    if 0 <= age <= max_age_seconds:
      return json.loads(path.read_text(encoding="utf-8"))
  except Exception:
    return None
  return None


def write_json(path: Path, payload: dict[str, Any], mode: int = 0o644) -> None:
  handle_fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
  tmp = Path(tmp_name)
  try:
    with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
      handle.write(json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")
    tmp.chmod(mode)
    tmp.replace(path)
  except BaseException:
    tmp.unlink(missing_ok=True)
    raise


# ---------------------------------------------------------------- local scan


def scan_brain_transcripts(brain_path: Path) -> dict[str, Any]:
  today = local_date_string()
  recent_dates = recent_date_strings()
  recent = {day: {"date": day, "messageCount": 0} for day in recent_dates}

  sessions: set[str] = set()
  active_days: set[str] = set()
  today_sessions: set[str] = set()
  today_tokens: dict[str, int] = {}
  usage_by_model: dict[str, dict[str, int]] = {}
  prompts = 0
  today_prompt_count = 0
  today_token_total = 0

  files = sorted(brain_path.glob("*/.system_generated/logs/transcript.jsonl")) if brain_path.is_dir() else []
  for path in files:
    session_key = path.parent.parent.parent.name
    current_model = "Gemini 4 Argon"
    try:
      with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
          if '"USER_INPUT"' in line and "Model Selection" in line:
            try:
              user_entry = json.loads(line)
              if user_entry.get("type") == "USER_INPUT":
                match = MODEL_SELECTION_RE.search(str(user_entry.get("content") or ""))
                if match:
                  current_model = match.group(1).strip() or current_model
            except Exception:
              pass
            continue
          if '"PLANNER_RESPONSE"' not in line:
            continue
          try:
            entry = json.loads(line)
          except Exception:
            continue
          if entry.get("type") != "PLANNER_RESPONSE":
            continue

          input_tokens = number(entry.get("input_tokens"))
          output_tokens = number(entry.get("output_tokens"))
          cache_read = number(entry.get("cache_read_tokens"))
          cache_write = number(entry.get("cache_creation_tokens"))
          total = input_tokens + output_tokens + cache_read + cache_write
          if total <= 0:
            continue

          day = local_date_from_timestamp(entry.get("created_at"))
          sessions.add(session_key)
          active_days.add(day)
          prompts += 1

          bucket = usage_by_model.setdefault(current_model, empty_bucket())
          bucket["inputTokens"] += input_tokens
          bucket["outputTokens"] += output_tokens
          bucket["cacheReadInputTokens"] += cache_read
          bucket["cacheCreationInputTokens"] += cache_write

          if day in recent:
            recent[day]["messageCount"] += total

          if day == today:
            today_prompt_count += 1
            today_sessions.add(session_key)
            today_token_total += total
            today_tokens[current_model] = today_tokens.get(current_model, 0) + total
    except Exception as exc:
      print(f"Ignoring unreadable Antigravity transcript {path}: {exc}", file=sys.stderr)

  return {
    "todayPrompts": today_prompt_count,
    "todaySessions": len(today_sessions),
    "todayTotalTokens": today_token_total,
    "todayTokensByModel": today_tokens,
    "recentDays": [recent[day] for day in recent_dates],
    "modelUsage": usage_by_model,
    "totalPrompts": prompts,
    "totalSessions": len(sessions),
    "activeDays": len(active_days),
    "activeDates": sorted(active_days),
  }


def cached_scan(brain_path: Path, max_age_seconds: float) -> dict[str, Any]:
  digest = hashlib.sha1(str(brain_path).encode("utf-8")).hexdigest()[:16]
  root = cache_root()
  cache_file = root / f"gemini-scan-{digest}.json"
  lock_file = root / f"gemini-scan-{digest}.lock"
  today = local_date_string()

  cached = read_fresh_json(cache_file, max_age_seconds)
  if isinstance(cached, dict) and cached.get("scanDate") == today and isinstance(cached.get("stats"), dict):
    return cached["stats"]

  try:
    with lock_file.open("w") as lock:
      fcntl.flock(lock, fcntl.LOCK_EX)
      cached = read_fresh_json(cache_file, max_age_seconds)
      if isinstance(cached, dict) and cached.get("scanDate") == today and isinstance(cached.get("stats"), dict):
        return cached["stats"]
      stats = scan_brain_transcripts(brain_path)
      write_json(cache_file, {"scanDate": today, "stats": stats})
      return stats
  except Exception:
    return scan_brain_transcripts(brain_path)


# ------------------------------------------------------------------- limits


def parse_expiry_ms(value: Any) -> int:
  if value is None:
    return 0
  if isinstance(value, (int, float)):
    n = int(value)
    return n * 1000 if 0 < n < 10_000_000_000 else n
  raw = str(value).strip()
  if not raw:
    return 0
  if raw.isdigit():
    n = int(raw)
    return n * 1000 if 0 < n < 10_000_000_000 else n
  try:
    parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    return round(parsed.timestamp() * 1000)
  except Exception:
    return 0


def extract_token_bundle(payload: dict[str, Any]) -> tuple[str, str, int]:
  tok = payload.get("token")
  if isinstance(tok, str):
    try:
      tok = json.loads(tok)
    except Exception:
      tok = None
  if isinstance(tok, dict):
    access = str(tok.get("access_token") or "")
    refresh = str(tok.get("refresh_token") or "")
    expiry_ms = parse_expiry_ms(tok.get("expiry") or tok.get("expiry_date"))
    return access, refresh, expiry_ms
  access = str(payload.get("access_token") or "")
  refresh = str(payload.get("refresh_token") or "")
  expiry_ms = parse_expiry_ms(payload.get("expiry_date") or payload.get("expiry"))
  return access, refresh, expiry_ms


def load_keyring_credentials() -> tuple[str, str, int]:
  secret_tool = shutil.which("secret-tool")
  if not secret_tool:
    return "", "", 0
  try:
    proc = subprocess.run(
      [secret_tool, "lookup", "service", "gemini", "username", "antigravity"],
      capture_output=True,
      text=True,
      timeout=2,
      check=False,
    )
    if proc.returncode == 0 and proc.stdout.strip():
      data = json.loads(proc.stdout)
      if isinstance(data, dict):
        return extract_token_bundle(data)
  except Exception:
    pass
  return "", "", 0


def load_file_credentials() -> tuple[str, str, int]:
  candidates = [
    agy_dir() / "antigravity-oauth-token",
    gemini_dir() / "oauth_creds.json",
  ]
  for path in candidates:
    if not path.is_file():
      continue
    try:
      data = json.loads(path.read_text(encoding="utf-8"))
      if isinstance(data, dict):
        access, refresh, expiry_ms = extract_token_bundle(data)
        if access or refresh:
          return access, refresh, expiry_ms
    except Exception:
      continue
  return "", "", 0


def discover_oauth_clients() -> list[tuple[str, str]]:
  agy_bin = shutil.which("agy") or f"/etc/profiles/per-user/{os.environ.get('USER', 'vpittamp')}/bin/agy"
  agy_path = Path(agy_bin)
  if not agy_path.is_file():
    return []
  libexec_path = agy_path
  try:
    head = agy_path.read_bytes()[:4096]
    if head.startswith(b"#!"):
      text = head.decode("utf-8", errors="ignore")
      match = re.search(r"(/nix/store/[^\s\"']+/libexec/antigravity)", text)
      if match:
        libexec_path = Path(match.group(1))
  except Exception:
    return []

  if not libexec_path.is_file():
    return []

  cache_file = cache_root() / "gemini-oauth-clients.json"
  cached = read_fresh_json(cache_file, float("inf"))
  if isinstance(cached, dict) and cached.get("binary") == str(libexec_path):
    pairs = cached.get("clients")
    if isinstance(pairs, list) and pairs:
      return [(str(p[0]), str(p[1])) for p in pairs if isinstance(p, list) and len(p) == 2]

  try:
    blob = libexec_path.read_bytes()
    ids = sorted({m.decode("utf-8", "ignore") for m in re.findall(rb"[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com", blob)})
    secrets = sorted({m.decode("utf-8", "ignore") for m in re.findall(rb"GOCSPX-[A-Za-z0-9_-]{28}", blob)})
    clients = [(cid, csec) for cid in ids for csec in secrets]
    if clients:
      write_json(cache_file, {"binary": str(libexec_path), "clients": clients}, mode=0o600)
    return clients
  except Exception:
    return []


def refresh_access_token(refresh_token: str) -> tuple[str, int]:
  if not refresh_token:
    return "", 0
  token_cache = cache_root() / "gemini-token.json"
  cached = read_fresh_json(token_cache, 3000)
  if isinstance(cached, dict):
    cached_access = str(cached.get("accessToken") or "")
    cached_expiry = number(cached.get("expiresAtMs"))
    if cached_access and cached_expiry > (time.time() + 60) * 1000:
      return cached_access, cached_expiry

  for client_id, client_secret in discover_oauth_clients():
    body = urllib.parse.urlencode({
      "client_id": client_id,
      "client_secret": client_secret,
      "refresh_token": refresh_token,
      "grant_type": "refresh_token",
    }).encode("utf-8")
    req = urllib.request.Request(OAUTH_TOKEN_URL, data=body)
    try:
      with urllib.request.urlopen(req, timeout=8) as resp:
        payload = json.loads(resp.read().decode("utf-8", errors="replace"))
      access = str(payload.get("access_token") or "")
      expires_in = number(payload.get("expires_in") or 3600)
      if access:
        expires_at_ms = round((time.time() + expires_in) * 1000)
        try:
          write_json(token_cache, {"accessToken": access, "expiresAtMs": expires_at_ms}, mode=0o600)
        except Exception:
          pass
        return access, expires_at_ms
    except Exception:
      continue
  return "", 0


def resolve_access_token() -> tuple[str, bool]:
  access, refresh, expiry_ms = load_keyring_credentials()
  now_ms = (time.time() + 60) * 1000
  if access and (expiry_ms <= 0 or expiry_ms > now_ms):
    return access, True
  if refresh:
    refreshed, _ = refresh_access_token(refresh)
    if refreshed:
      return refreshed, True

  file_access, file_refresh, file_expiry_ms = load_file_credentials()
  if file_access and (file_expiry_ms <= 0 or file_expiry_ms > now_ms):
    return file_access, True
  if file_refresh:
    refreshed, _ = refresh_access_token(file_refresh)
    if refreshed:
      return refreshed, True

  return "", bool(access or refresh or file_access or file_refresh)


def normalize_reset_at(value: Any) -> str:
  if value is None:
    return ""
  raw = str(value).strip()
  if not raw:
    return ""
  try:
    parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    return parsed.isoformat()
  except Exception:
    return raw


def cloudcode_post(access_token: str, method: str, payload: dict[str, Any]) -> dict[str, Any]:
  request = urllib.request.Request(
    f"{CLOUDCODE_BASE}:{method}",
    data=json.dumps(payload).encode("utf-8"),
    headers={
      "Authorization": "Bearer " + access_token,
      "Content-Type": "application/json",
      "Accept": "application/json",
      "User-Agent": "antigravity/1.3.4 linux/amd64",
    },
  )
  with urllib.request.urlopen(request, timeout=10) as response:
    data = json.loads(response.read().decode("utf-8", errors="replace"))
    return data if isinstance(data, dict) else {}


def used_percent_from_remaining(remaining: Any) -> float:
  try:
    rem = float(remaining)
  except Exception:
    return -1.0
  if not (0.0 <= rem <= 1.0):
    return -1.0
  return max(0.0, min(1.0, 1.0 - rem))


def probe_limits(access_token: str) -> dict[str, Any]:
  try:
    lca = cloudcode_post(
      access_token,
      "loadCodeAssist",
      {
        "metadata": {
          "ideType": "ANTIGRAVITY",
          "platform": "LINUX_AMD64",
          "pluginType": "GEMINI",
        }
      },
    )
  except urllib.error.HTTPError as error:
    return {
      "ok": False,
      "helpText": f"Antigravity Cloud Code endpoint returned status {error.code}. Local stats are still shown.",
    }
  except Exception:
    return {
      "ok": False,
      "transport": True,
      "helpText": "Couldn't reach Antigravity's Cloud Code endpoint. Retrying shortly. Local stats are still shown.",
    }

  project = str(lca.get("cloudaicompanionProject") or "").strip()
  paid_tier = lca.get("paidTier") if isinstance(lca.get("paidTier"), dict) else {}
  current_tier = lca.get("currentTier") if isinstance(lca.get("currentTier"), dict) else {}
  tier_label = str(paid_tier.get("name") or current_tier.get("name") or "").strip()
  if tier_label.lower() == "antigravity":
    tier_label = ""

  req_body = {"project": project} if project else {}
  limits: list[dict[str, Any]] = []

  try:
    quota = cloudcode_post(access_token, "retrieveUserQuota", req_body)
  except Exception:
    quota = {}

  gemini_used = -1.0
  gemini_reset = ""
  for bucket in quota.get("buckets") or []:
    if not isinstance(bucket, dict):
      continue
    model_id = str(bucket.get("modelId") or "").strip().lower()
    if not model_id.startswith("gemini-"):
      continue
    used = used_percent_from_remaining(bucket.get("remainingFraction"))
    if used < 0:
      continue
    reset = normalize_reset_at(bucket.get("resetTime"))
    if used > gemini_used or (used == gemini_used and reset and not gemini_reset):
      gemini_used = used
      gemini_reset = reset

  if gemini_used >= 0:
    limits.append({
      "label": "Gemini (5-hour)",
      "percent": gemini_used,
      "resetsAt": gemini_reset,
    })

  try:
    summary = cloudcode_post(access_token, "retrieveUserQuotaSummary", req_body)
  except Exception:
    summary = {}

  for group in summary.get("groups") or []:
    if not isinstance(group, dict):
      continue
    group_name = str(group.get("displayName") or "").strip()
    is_gemini_group = "gemini" in group_name.lower()
    buckets = [b for b in (group.get("buckets") or []) if isinstance(b, dict) and not b.get("disabled")]
    # Put 5-hour before weekly inside each group to match Claude/Codex ordering.
    buckets.sort(key=lambda b: 0 if str(b.get("window") or "") != "weekly" else 1)
    for bucket in buckets:
      used = used_percent_from_remaining(bucket.get("remainingFraction"))
      if used < 0:
        continue
      window = str(bucket.get("window") or "").strip().lower()
      reset = normalize_reset_at(bucket.get("resetTime"))
      if is_gemini_group:
        label = "Weekly (7-day)" if window == "weekly" else "Gemini (5-hour)"
      else:
        label = "3P Weekly (7-day)" if window == "weekly" else "3P Session (5-hour)"
      limits.append({
        "label": label,
        "percent": used,
        "resetsAt": reset,
      })

  if not limits:
    return {
      "ok": False,
      "tierLabel": tier_label,
      "helpText": "Antigravity returned no quota buckets. Local stats are still shown.",
    }
  return {"ok": True, "tierLabel": tier_label, "limits": limits}


def limit_window_open(entry: dict[str, Any], now: dt.datetime) -> bool:
  raw = str(entry.get("resetsAt") or "")
  if not raw:
    return True
  try:
    resets_at = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
  except Exception:
    return True
  if resets_at.tzinfo is None:
    resets_at = resets_at.replace(tzinfo=dt.timezone.utc)
  return resets_at > now


def usable_cached_limits(cached: dict[str, Any]) -> list[dict[str, Any]]:
  entries = cached.get("limits")
  if not isinstance(entries, list):
    return []
  now = dt.datetime.now(dt.timezone.utc)
  return [entry for entry in entries if isinstance(entry, dict) and limit_window_open(entry, now)]


def collect_limits(force: bool) -> dict[str, Any]:
  result: dict[str, Any] = {
    "limits": [],
    "tierLabel": "",
    "usageStatusText": "",
    "authHelpText": AUTH_HELP,
  }

  probe_cache = cache_root() / "gemini-limits.json"
  cached = read_fresh_json(probe_cache, float("inf")) or {}
  fallback = usable_cached_limits(cached)
  cached_tier = str(cached.get("tierLabel") or "")

  access_token, had_creds = resolve_access_token()
  if not access_token:
    result["limits"] = fallback
    result["tierLabel"] = cached_tier
    result["usageStatusText"] = "Sign-in expired" if had_creds else "Waiting for auth"
    return result

  fetched_at = number(cached.get("fetchedAtMs")) / 1000
  if fallback and not force and time.time() - fetched_at < PROBE_MIN_INTERVAL_SECONDS:
    result["limits"] = fallback
    result["tierLabel"] = cached_tier
    return result

  probe = probe_limits(access_token)
  if probe.get("ok"):
    result["limits"] = probe["limits"]
    result["tierLabel"] = str(probe.get("tierLabel") or cached_tier)
    write_json(
      probe_cache,
      {
        "fetchedAtMs": round(time.time() * 1000),
        "tierLabel": result["tierLabel"],
        "limits": probe["limits"],
      },
    )
    return result

  if probe.get("transport"):
    result["retryAdvised"] = True
  result["tierLabel"] = str(probe.get("tierLabel") or cached_tier)
  if fallback:
    result["limits"] = fallback
  else:
    result["usageStatusText"] = "Antigravity limits unavailable"
    result["authHelpText"] = str(probe.get("helpText") or AUTH_HELP)
  return result


def main() -> int:
  parser = argparse.ArgumentParser()
  parser.add_argument("--force", action="store_true")
  parser.add_argument("--limits-only", action="store_true")
  args = parser.parse_args()

  scan_age = 0 if args.force else (LIMITS_ONLY_REUSE_SECONDS if args.limits_only else SCAN_REUSE_SECONDS)
  stats = cached_scan(agy_dir() / "brain", scan_age)
  limits = collect_limits(args.force)

  record: dict[str, Any] = {
    "schemaVersion": 1,
    "id": AGENT_ID,
    "name": AGENT_NAME,
    "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    "ready": number(stats.get("totalPrompts")) > 0 or len(limits["limits"]) > 0,
    "hasLocalStats": True,
    "tierLabel": limits["tierLabel"],
    "usageStatusText": limits["usageStatusText"],
    "authHelpText": limits["authHelpText"],
    "limits": limits["limits"],
  }
  if limits.get("retryAdvised"):
    record["retryAdvised"] = True
  record.update(stats)
  print(json.dumps(record, separators=(",", ":"), sort_keys=True))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

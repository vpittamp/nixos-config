{ config, pkgs, lib, osConfig ? null, ... }:

let
  # Use Nix package reference for 1Password browser support
  onePasswordBrowserSupport = "/run/wrappers/bin/1Password-BrowserSupport";
  hostName =
    if osConfig != null && osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else "";

  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib hostName; };
  pwaSites = pwaSitesConfig.pwaSites;

  pwaRouteEntries =
    builtins.concatMap
      (pwa:
        let
          domains = if pwa ? routing_domains && pwa.routing_domains != [ ] then pwa.routing_domains else [ pwa.domain ];
          paths = if pwa ? routing_paths then pwa.routing_paths else [ ];
          mkEntry = key: {
            name = key;
            value = {
              name = pwa.name;
              ulid = pwa.ulid;
              domain = pwa.domain;
              url = pwa.url;
              icon = pwa.icon;
            };
          };
          domainEntries = map mkEntry domains;
          pathEntries =
            builtins.concatMap
              (path:
                let
                  normalizedPath = if lib.hasPrefix "/" path then path else "/${path}";
                  cleanPath = lib.removeSuffix "/" normalizedPath;
                in
                map (domain: mkEntry "${domain}${cleanPath}") domains)
              paths;
        in
        domainEntries ++ pathEntries)
      pwaSites;
  pwaRouteRegistry = builtins.toJSON {
    version = "1.0.0";
    routes = builtins.listToAttrs pwaRouteEntries;
  };
  chromeUrlExtensionKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwPb3yBRBCTWkrOzCu2hgivv/RKEa5eejkBfJhm4IGbs1jdFbJOPQXrPYAlMA6LrcqflQ6/IWvKOc4YXdoQdBNLbMQjzwkFn/tHWXyE/6YM94/trhQh4a44rDDTaYyhEUb8/3S6n8DGPjXw517zz4Edz0Q2Z5q2BbFZ5k3c0UJ3HoA1S23JwcusAkS87wrh+rb6Xo7jEhH0uI7xyDuvppShSvDP3WfXSo4lxLB7hgTyGQ42HSevRzsvjKFl2iBSDkPWKjEMPi4a2/SyfnotZ0yXyvz4iKCBOYKdpII+GeX6YCjjOs2V9kXxEX0OGXtt5lqvSoFUstmfurzCncxJB9wwIDAQAB";
  chromeUrlExtensionId = "ihkjhjanceajnkgdnoapidhndainfcko";

  chromeUrlToolPy = pkgs.writeText "chrome-url-tool.py" ''
    #!${lib.getExe pkgs.python3}
    import json
    import os
    import shutil
    import sqlite3
    import struct
    import subprocess
    import sys
    import tempfile
    import time
    from datetime import datetime, timezone
    from pathlib import Path
    from typing import Dict, Iterable, List, Optional
    from urllib.parse import parse_qsl, quote_plus, urlsplit, urlunsplit

    HOME = Path.home()
    STATE_DIR = HOME / ".local" / "state" / "i3pm"
    CACHE_PATH = STATE_DIR / "chrome-url-index.json"
    ROUTES_PATH = HOME / ".config" / "i3" / "chrome-url-pwa-routes.json"
    CHROME_ROOT = HOME / ".config" / "google-chrome"
    PWA_ROOT = HOME / ".local" / "share" / "webapps"
    CACHE_MAX_AGE_SECONDS = 900


    def utc_now() -> str:
        return datetime.now(timezone.utc).isoformat()


    def read_json(path: Path, default):
        try:
            with path.open("r", encoding="utf-8") as handle:
                return json.load(handle)
        except Exception:
            return default


    def write_json(path: Path, payload) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
        tmp.replace(path)


    def normalize_url(url: str) -> str:
        try:
            parsed = urlsplit((url or "").strip())
        except Exception:
            return (url or "").strip()
        if parsed.scheme not in {"http", "https"}:
            return (url or "").strip()
        cleaned_query = [
            (key, value)
            for key, value in parse_qsl(parsed.query, keep_blank_values=True)
            if not key.lower().startswith("utm_")
        ]
        path = parsed.path or "/"
        return urlunsplit(
            (
                parsed.scheme.lower(),
                parsed.netloc.lower(),
                path,
                "&".join(f"{quote_plus(key)}={quote_plus(value)}" for key, value in cleaned_query),
                "",
            )
        )


    def coerce_http_url(raw: str) -> str:
        value = (raw or "").strip()
        if not value:
            return value
        if value.startswith("http://") or value.startswith("https://"):
            return value
        if value.startswith("www.") or "." in value.split("/")[0]:
            return "https://" + value
        return value


    def looks_like_url(query: str) -> bool:
        value = (query or "").strip()
        if not value:
            return False
        if value.startswith(("http://", "https://")):
            return True
        if " " in value:
            return False
        head = value.split("/", 1)[0]
        return "." in head


    def web_search_url(query: str) -> str:
        return "https://www.google.com/search?q=" + quote_plus(query) + "&udm=14"


    def webkit_to_epoch(value) -> float:
        try:
            numeric = int(value)
        except Exception:
            return 0.0
        return max(0.0, numeric / 1_000_000 - 11644473600)


    def profile_dirs() -> List[Path]:
        if not CHROME_ROOT.exists():
            return []
        profiles = []
        for child in sorted(CHROME_ROOT.iterdir()):
            if not child.is_dir():
                continue
            name = child.name
            if name == "Default" or name.startswith("Profile "):
                profiles.append(child)
        return profiles


    def copy_sqlite(path: Path) -> Optional[Path]:
        if not path.exists():
            return None
        tmpdir = Path(tempfile.mkdtemp(prefix="chrome-url-"))
        target = tmpdir / path.name
        try:
            shutil.copy2(path, target)
        except Exception:
            shutil.rmtree(tmpdir, ignore_errors=True)
            return None
        return target


    def cleanup_copy(path: Optional[Path]) -> None:
        if not path:
            return
        shutil.rmtree(path.parent, ignore_errors=True)


    def read_history(profile: Path, limit: int = 400) -> List[dict]:
        history_path = profile / "History"
        copied = copy_sqlite(history_path)
        if copied is None:
            return []
        rows: List[dict] = []
        try:
            conn = sqlite3.connect(str(copied))
            conn.row_factory = sqlite3.Row
            cursor = conn.execute(
                """
                SELECT url, IFNULL(title, "") AS title, last_visit_time, visit_count, typed_count
                FROM urls
                WHERE url LIKE 'http%'
                ORDER BY last_visit_time DESC
                LIMIT ?
                """,
                (int(limit),),
            )
            for row in cursor.fetchall():
                url = str(row["url"] or "").strip()
                if not url:
                    continue
                rows.append(
                    {
                        "url": url,
                        "normalized_url": normalize_url(url),
                        "title": str(row["title"] or "").strip(),
                        "domain": urlsplit(url).netloc.lower(),
                        "source": "history",
                        "profile": profile.name,
                        "last_visited_at": webkit_to_epoch(row["last_visit_time"]),
                        "visit_count": int(row["visit_count"] or 0),
                        "typed_count": int(row["typed_count"] or 0),
                    }
                )
        except Exception:
            rows = []
        finally:
            try:
                conn.close()
            except Exception:
                pass
            cleanup_copy(copied)
        return rows


    def flatten_bookmark_nodes(nodes: Iterable[dict], profile_name: str) -> Iterable[dict]:
        for node in nodes:
            if not isinstance(node, dict):
                continue
            node_type = str(node.get("type", "") or "")
            if node_type == "url":
                url = str(node.get("url", "") or "").strip()
                if not url.startswith(("http://", "https://")):
                    continue
                yield {
                    "url": url,
                    "normalized_url": normalize_url(url),
                    "title": str(node.get("name", "") or "").strip(),
                    "domain": urlsplit(url).netloc.lower(),
                    "source": "bookmark",
                    "profile": profile_name,
                    "last_visited_at": 0,
                    "visit_count": 0,
                    "typed_count": 0,
                }
                continue
            for child in node.get("children", []) or []:
                yield from flatten_bookmark_nodes([child], profile_name)


    def read_bookmarks(profile: Path) -> List[dict]:
        bookmarks_path = profile / "Bookmarks"
        payload = read_json(bookmarks_path, {})
        roots = payload.get("roots", {}) if isinstance(payload, dict) else {}
        entries: List[dict] = []
        for key in ("bookmark_bar", "other", "synced"):
            node = roots.get(key)
            if isinstance(node, dict):
                entries.extend(flatten_bookmark_nodes(node.get("children", []) or [], profile.name))
        return entries


    def dedupe_records(records: Iterable[dict]) -> List[dict]:
        priority = {"tab": 4, "bookmark": 3, "history": 2, "typed": 5, "pwa": 1}
        grouped: Dict[str, dict] = {}
        for record in records:
            url_key = record.get("normalized_url") or normalize_url(record.get("url", ""))
            if not url_key:
                continue
            current = grouped.get(url_key)
            sources = sorted(set((current or {}).get("sources", []) + [record.get("source", "")]))
            next_record = dict(current or {})
            candidate = dict(record)
            if current is None or (
                priority.get(candidate.get("source", ""), 0) > priority.get(current.get("source", ""), 0)
            ) or (
                priority.get(candidate.get("source", ""), 0) == priority.get(current.get("source", ""), 0)
                and float(candidate.get("last_visited_at", 0) or 0) > float(current.get("last_visited_at", 0) or 0)
            ):
                next_record.update(candidate)
            next_record["normalized_url"] = url_key
            next_record["sources"] = sources
            grouped[url_key] = next_record
        return list(grouped.values())


    def load_routes() -> Dict[str, dict]:
        payload = read_json(ROUTES_PATH, {"routes": {}})
        routes = payload.get("routes", {}) if isinstance(payload, dict) else {}
        return routes if isinstance(routes, dict) else {}


    def pwa_match(url: str, routes: Dict[str, dict]) -> Optional[dict]:
        try:
            parsed = urlsplit(url)
        except Exception:
            return None
        host = parsed.netloc.lower().split(":", 1)[0]
        if not host:
            return None
        path = parsed.path or ""
        candidates: List[str] = []
        current_path = path.rstrip("/")
        while current_path:
            candidates.append(host + current_path)
            current_path = current_path.rsplit("/", 1)[0]
        candidates.append(host)
        if host.startswith("www."):
            bare = host[4:]
            current_path = path.rstrip("/")
            while current_path:
                candidates.append(bare + current_path)
                current_path = current_path.rsplit("/", 1)[0]
            candidates.append(bare)
        for key in candidates:
            route = routes.get(key)
            if isinstance(route, dict):
                return route
        return None


    def source_badge(record: dict) -> str:
        source = str(record.get("source", "") or "")
        mapping = {
            "tab": "Open tab",
            "bookmark": "Bookmark",
            "history": "History",
            "typed": "Typed",
            "search": "Search",
        }
        return mapping.get(source, source.title() or "URL")


    def record_matches(record: dict, query: str) -> bool:
        tokens = [token for token in query.lower().split() if token]
        if not tokens:
            return True
        haystack = " ".join(
            [
                str(record.get("title", "") or ""),
                str(record.get("url", "") or ""),
                str(record.get("domain", "") or ""),
                str(record.get("matched_pwa_name", "") or ""),
            ]
        ).lower()
        return all(token in haystack for token in tokens)


    def record_sort_key(record: dict, query: str):
        query_lower = query.lower().strip()
        title = str(record.get("title", "") or "").lower()
        url = str(record.get("url", "") or "").lower()
        domain = str(record.get("domain", "") or "").lower()
        exact = 1 if query_lower and (query_lower == title or query_lower == domain or query_lower == url) else 0
        prefix = 1 if query_lower and (title.startswith(query_lower) or domain.startswith(query_lower)) else 0
        source_rank = {"typed": 5, "tab": 4, "bookmark": 3, "history": 2, "pwa": 1, "search": 0}.get(
            str(record.get("source", "") or ""),
            0,
        )
        recency = float(record.get("last_visited_at", 0) or 0)
        return (-exact, -prefix, -source_rank, -recency, title or url)


    def load_cache() -> dict:
        payload = read_json(CACHE_PATH, {})
        return payload if isinstance(payload, dict) else {}


    def refresh_cache(limit: int = 400) -> dict:
        profiles = profile_dirs()
        history: List[dict] = []
        bookmarks: List[dict] = []
        for profile in profiles:
            history.extend(read_history(profile, limit=limit))
            bookmarks.extend(read_bookmarks(profile))
        cache = load_cache()
        tabs = cache.get("tabs", []) if isinstance(cache.get("tabs", []), list) else []
        next_payload = {
            "version": 1,
            "updated_at": utc_now(),
            "tabs": tabs,
            "history": dedupe_records(history),
            "bookmarks": dedupe_records(bookmarks),
            "sources": {
                "profiles": [profile.name for profile in profiles],
                "refreshed_from_profiles_at": utc_now(),
                "extension_updated_at": cache.get("sources", {}).get("extension_updated_at", ""),
            },
        }
        write_json(CACHE_PATH, next_payload)
        return next_payload


    def ensure_cache() -> dict:
        cache = load_cache()
        updated = str(cache.get("updated_at", "") or "")
        try:
            age = time.time() - datetime.fromisoformat(updated).timestamp() if updated else 10**9
        except Exception:
            age = 10**9
        if not cache or age >= CACHE_MAX_AGE_SECONDS:
            cache = refresh_cache()
        return cache


    def sanitize_url_records(items: Iterable[dict], source_name: str) -> List[dict]:
        sanitized: List[dict] = []
        for item in items or []:
            if not isinstance(item, dict):
                continue
            url = str(item.get("url", "") or "").strip()
            if not url.startswith(("http://", "https://")):
                continue
            sanitized.append(
                {
                    "url": url,
                    "normalized_url": normalize_url(url),
                    "title": str(item.get("title", "") or "").strip(),
                    "domain": str(item.get("domain", "") or urlsplit(url).netloc.lower()),
                    "source": source_name,
                    "profile": str(item.get("profile", "") or ""),
                    "last_visited_at": float(item.get("last_visited_at", 0) or 0),
                    "visit_count": int(item.get("visit_count", 0) or 0),
                    "typed_count": int(item.get("typed_count", 0) or 0),
                }
            )
        return dedupe_records(sanitized)


    def merge_extension_snapshot(message: dict) -> dict:
        cache = ensure_cache()
        tabs = sanitize_url_records(message.get("tabs", []), "tab")
        history = sanitize_url_records(message.get("history", []), "history") or cache.get("history", [])
        bookmarks = sanitize_url_records(message.get("bookmarks", []), "bookmark") or cache.get("bookmarks", [])
        sources = dict(cache.get("sources", {}) if isinstance(cache.get("sources", {}), dict) else {})
        sources["extension_updated_at"] = utc_now()
        next_payload = {
            "version": 1,
            "updated_at": utc_now(),
            "tabs": tabs,
            "history": history,
            "bookmarks": bookmarks,
            "sources": sources,
        }
        write_json(CACHE_PATH, next_payload)
        return next_payload


    def build_entries(query: str, limit: int) -> List[dict]:
        cache = ensure_cache()
        routes = load_routes()
        records = []
        records.extend(cache.get("tabs", []) if isinstance(cache.get("tabs", []), list) else [])
        records.extend(cache.get("bookmarks", []) if isinstance(cache.get("bookmarks", []), list) else [])
        records.extend(cache.get("history", []) if isinstance(cache.get("history", []), list) else [])
        merged = []
        for record in dedupe_records(records):
            route = pwa_match(str(record.get("url", "") or ""), routes)
            next_record = dict(record)
            if route:
                next_record["matched_pwa_ulid"] = str(route.get("ulid", "") or "")
                next_record["matched_pwa_name"] = str(route.get("name", "") or "")
                next_record["icon"] = str(route.get("icon", "") or "")
            merged.append(next_record)

        entries = []
        query_trimmed = query.strip()
        if looks_like_url(query_trimmed):
            typed_url = coerce_http_url(query_trimmed)
            route = pwa_match(typed_url, routes)
            entries.append(
                {
                    "kind": "url",
                    "identifier": normalize_url(typed_url),
                    "text": typed_url,
                    "subtext": "Direct URL  •  " + typed_url,
                    "url": typed_url,
                    "domain": urlsplit(typed_url).netloc.lower(),
                    "source": "typed",
                    "icon": str(route.get("icon", "") or "web-browser") if route else "web-browser",
                    "matched_pwa_ulid": str(route.get("ulid", "") or "") if route else "",
                    "matched_pwa_name": str(route.get("name", "") or "") if route else "",
                    "state": ["typed"] + (["pwa"] if route else []),
                }
            )

        for record in merged:
            if not record_matches(record, query_trimmed):
                continue
            title = str(record.get("title", "") or "").strip() or str(record.get("url", "") or "")
            subtitle_bits = [source_badge(record), str(record.get("domain", "") or "")]
            if record.get("matched_pwa_name"):
                subtitle_bits.append("PWA " + str(record.get("matched_pwa_name")))
            subtitle_bits.append(str(record.get("url", "") or ""))
            entries.append(
                {
                    "kind": "url",
                    "identifier": str(record.get("normalized_url", "") or record.get("url", "")),
                    "text": title,
                    "subtext": "  •  ".join(bit for bit in subtitle_bits if bit),
                    "url": str(record.get("url", "") or ""),
                    "domain": str(record.get("domain", "") or ""),
                    "source": str(record.get("source", "") or ""),
                    "icon": str(record.get("icon", "") or "web-browser"),
                    "matched_pwa_ulid": str(record.get("matched_pwa_ulid", "") or ""),
                    "matched_pwa_name": str(record.get("matched_pwa_name", "") or ""),
                    "state": list(record.get("sources", [])) + (["pwa"] if record.get("matched_pwa_ulid") else []),
                    "last_visited_at": float(record.get("last_visited_at", 0) or 0),
                }
            )

        if query_trimmed:
            entries.append(
                {
                    "kind": "search",
                    "identifier": "search::" + query_trimmed,
                    "text": 'Search Google AI for "' + query_trimmed + '"',
                    "subtext": web_search_url(query_trimmed),
                    "url": web_search_url(query_trimmed),
                    "domain": "search",
                    "source": "search",
                    "icon": "google-chrome",
                    "matched_pwa_ulid": "",
                    "matched_pwa_name": "",
                    "state": ["search"],
                    "last_visited_at": 0,
                }
            )

        deduped_entries = dedupe_records(entries)
        deduped_entries.sort(key=lambda item: record_sort_key(item, query_trimmed))
        for entry in deduped_entries:
            entry.pop("last_visited_at", None)
        return deduped_entries[: max(1, limit)]


    def copy_text(value: str) -> int:
        commands = [
            ["${pkgs.wl-clipboard}/bin/wl-copy"],
            ["${pkgs.xclip}/bin/xclip", "-selection", "clipboard"],
        ]
        for command in commands:
            try:
                subprocess.run(command, input=value.encode("utf-8"), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return 0
            except Exception:
                continue
        return 1


    def pwa_launch(url: str) -> int:
        route = pwa_match(url, load_routes())
        if not route:
            return 1
        os.execvp("launch-pwa-by-name", ["launch-pwa-by-name", str(route.get("ulid", "")), url])
        return 1


    def browser_open(url: str) -> int:
        os.execvp("google-chrome-i3pm", ["google-chrome-i3pm", url])
        return 1


    def read_native_message():
        raw_length = sys.stdin.buffer.read(4)
        if not raw_length:
            return None
        message_length = struct.unpack("=I", raw_length)[0]
        if message_length <= 0:
            return None
        data = sys.stdin.buffer.read(message_length)
        if not data:
            return None
        return json.loads(data.decode("utf-8"))


    def write_native_message(payload):
        encoded = json.dumps(payload).encode("utf-8")
        sys.stdout.buffer.write(struct.pack("=I", len(encoded)))
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()


    def run_host() -> int:
        while True:
            message = read_native_message()
            if message is None:
                return 0
            message_type = str(message.get("type", "") or "")
            if message_type == "ping":
                write_native_message({"ok": True, "pong": True})
                continue
            if message_type == "syncSnapshot":
                payload = merge_extension_snapshot(message)
                write_native_message(
                    {
                        "ok": True,
                        "updated_at": payload.get("updated_at", ""),
                        "tab_count": len(payload.get("tabs", [])),
                        "history_count": len(payload.get("history", [])),
                        "bookmark_count": len(payload.get("bookmarks", [])),
                    }
                )
                continue
            if message_type == "openUrl":
                url = str(message.get("url", "") or "")
                mode = str(message.get("mode", "preferred") or "preferred")
                if mode == "browser":
                    browser_open(url)
                else:
                    if pwa_launch(url) != 0:
                        browser_open(url)
                continue
            write_native_message({"ok": False, "error": "unsupported message type"})


    def main(argv: List[str]) -> int:
        command = argv[1] if len(argv) > 1 else "list"
        if command == "refresh":
            refresh_cache()
            return 0
        if command == "list":
            query = argv[2] if len(argv) > 2 else ""
            try:
                limit = int(argv[3]) if len(argv) > 3 else 20
            except ValueError:
                limit = 20
            print(json.dumps(build_entries(query, limit)))
            return 0
        if command == "debug":
            cache = ensure_cache()
            payload = {
                "updated_at": cache.get("updated_at", ""),
                "tab_count": len(cache.get("tabs", [])),
                "history_count": len(cache.get("history", [])),
                "bookmark_count": len(cache.get("bookmarks", [])),
                "profiles": cache.get("sources", {}).get("profiles", []),
            }
            print(json.dumps(payload, indent=2, sort_keys=True))
            return 0
        if command == "open":
            mode = argv[2] if len(argv) > 2 else "preferred"
            url = argv[3] if len(argv) > 3 else ""
            if not url:
                print("missing url", file=sys.stderr)
                return 1
            if mode == "copy":
                return copy_text(url)
            if mode == "browser":
                return browser_open(url)
            if pwa_launch(url) != 0:
                return browser_open(url)
            return 0
        if command == "host":
            return run_host()
        print(f"unsupported chrome-url-tool command: {command}", file=sys.stderr)
        return 1


    if __name__ == "__main__":
        raise SystemExit(main(sys.argv))
  '';

  chromeUrlToolWrapper = name: args:
    pkgs.writeShellScriptBin name ''
      set -euo pipefail
      exec ${lib.getExe pkgs.python3} ${chromeUrlToolPy} ${args} "$@"
    '';

  chromeUrlList = chromeUrlToolWrapper "chrome-url-list" "list";
  chromeUrlRefresh = chromeUrlToolWrapper "chrome-url-refresh" "refresh";
  chromeUrlDebug = chromeUrlToolWrapper "chrome-url-debug" "debug";
  chromeUrlOpen = chromeUrlToolWrapper "chrome-url-open" "open";
  chromeUrlHost = chromeUrlToolWrapper "chrome-url-host" "host";

  chromeUrlExtension = pkgs.runCommandLocal "i3pm-chrome-url-extension" { } ''
    mkdir -p "$out"
    cat >"$out/manifest.json" <<'EOF'
    ${builtins.toJSON {
      manifest_version = 3;
      name = "i3pm URL Bridge";
      version = "1.0.0";
      description = "QuickShell launcher companion for Chrome history, bookmarks, and tabs.";
      key = chromeUrlExtensionKey;
      permissions = [ "tabs" "bookmarks" "history" "alarms" "storage" "nativeMessaging" ];
      background.service_worker = "service-worker.js";
      minimum_chrome_version = "139";
    }}
    EOF
    cat >"$out/service-worker.js" <<'EOF'
    const HOST = "com.vpittamp.i3pm_url_bridge";
    const HISTORY_LIMIT = 300;
    const ALARM_NAME = "i3pm-url-sync";

    function safeUrl(value) {
      return typeof value === "string" && /^https?:\/\//.test(value) ? value : "";
    }

    async function collectTabs() {
      const tabs = await chrome.tabs.query({});
      return tabs
        .map(tab => ({
          url: safeUrl(tab.url || ""),
          title: tab.title || "",
          domain: (() => {
            try {
              return new URL(tab.url).host.toLowerCase();
            } catch (_error) {
              return "";
            }
          })(),
          profile: "Default",
          last_visited_at: Date.now() / 1000,
          visit_count: 0,
          typed_count: 0
        }))
        .filter(item => item.url);
    }

    function flattenBookmarks(nodes, output) {
      for (const node of nodes || []) {
        if (!node || typeof node !== "object") {
          continue;
        }
        if (node.url && /^https?:\/\//.test(node.url)) {
          output.push({
            url: node.url,
            title: node.title || "",
            domain: (() => {
              try {
                return new URL(node.url).host.toLowerCase();
              } catch (_error) {
                return "";
              }
            })(),
            profile: "Default",
            last_visited_at: 0,
            visit_count: 0,
            typed_count: 0
          });
        }
        flattenBookmarks(node.children || [], output);
      }
    }

    async function collectBookmarks() {
      const tree = await chrome.bookmarks.getTree();
      const output = [];
      flattenBookmarks(tree, output);
      return output.slice(0, HISTORY_LIMIT);
    }

    async function collectHistory() {
      const items = await chrome.history.search({
        text: "",
        maxResults: HISTORY_LIMIT,
        startTime: Date.now() - 1000 * 60 * 60 * 24 * 180
      });
      return items
        .map(item => ({
          url: safeUrl(item.url || ""),
          title: item.title || "",
          domain: (() => {
            try {
              return new URL(item.url).host.toLowerCase();
            } catch (_error) {
              return "";
            }
          })(),
          profile: "Default",
          last_visited_at: Math.round((item.lastVisitTime || 0) / 1000),
          visit_count: item.visitCount || 0,
          typed_count: item.typedCount || 0
        }))
        .filter(item => item.url);
    }

    async function syncSnapshot(reason) {
      try {
        const [tabs, bookmarks, history] = await Promise.all([
          collectTabs(),
          collectBookmarks(),
          collectHistory()
        ]);
        await chrome.runtime.sendNativeMessage(HOST, {
          type: "syncSnapshot",
          reason: reason || "manual",
          tabs,
          bookmarks,
          history
        });
      } catch (error) {
        console.warn("i3pm-url-bridge sync failed", error);
      }
    }

    function scheduleSync(reason) {
      chrome.alarms.create(ALARM_NAME, { when: Date.now() + 750 });
      chrome.storage.session.set({ pendingReason: reason || "event" }).catch(() => {});
    }

    chrome.runtime.onInstalled.addListener(() => {
      chrome.alarms.create(ALARM_NAME, { periodInMinutes: 5 });
      syncSnapshot("installed");
    });

    chrome.runtime.onStartup.addListener(() => {
      chrome.alarms.create(ALARM_NAME, { periodInMinutes: 5 });
      syncSnapshot("startup");
    });

    chrome.alarms.onAlarm.addListener(async alarm => {
      if (!alarm || alarm.name !== ALARM_NAME) {
        return;
      }
      const payload = await chrome.storage.session.get("pendingReason").catch(() => ({}));
      syncSnapshot(payload.pendingReason || "alarm");
    });

    chrome.tabs.onUpdated.addListener(() => scheduleSync("tabs.onUpdated"));
    chrome.tabs.onRemoved.addListener(() => scheduleSync("tabs.onRemoved"));
    chrome.tabs.onActivated.addListener(() => scheduleSync("tabs.onActivated"));
    chrome.bookmarks.onCreated.addListener(() => scheduleSync("bookmarks.onCreated"));
    chrome.bookmarks.onRemoved.addListener(() => scheduleSync("bookmarks.onRemoved"));
    chrome.bookmarks.onChanged.addListener(() => scheduleSync("bookmarks.onChanged"));
    chrome.history.onVisited.addListener(() => scheduleSync("history.onVisited"));
    chrome.history.onVisitRemoved.addListener(() => scheduleSync("history.onVisitRemoved"));
    EOF
  '';

  chromeWrapper = pkgs.writeShellScriptBin "google-chrome-i3pm" ''
    set -euo pipefail
    exec ${pkgs.google-chrome}/bin/google-chrome-stable \
      --load-extension=${chromeUrlExtension} \
      "$@"
  '';

  # Cluster CA certificate for *.cnoe.localtest.me
  # This is the CA certificate (with CA:TRUE) that signs the server certificates
  # Chrome requires separate NSS database configuration
  clusterCaCert = pkgs.writeText "cnoe-ca.pem" ''
    -----BEGIN CERTIFICATE-----
    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
    CBn6
    -----END CERTIFICATE-----
  '';

in
{
  # Google Chrome browser configuration
  # Switched from Chromium to Chrome for Claude in Chrome compatibility
  # Claude in Chrome requires Google Chrome for full functionality
  home.packages =
    [
      pkgs.google-chrome
      chromeWrapper
      chromeUrlList
      chromeUrlRefresh
      chromeUrlDebug
      chromeUrlOpen
      chromeUrlHost
    ]
    ++ lib.optionals (pkgs ? google-chrome-beta) [ pkgs.google-chrome-beta ]
    ++ lib.optionals (pkgs ? google-chrome-unstable) [ pkgs.google-chrome-unstable ];

  home.file.".config/google-chrome/NativeMessagingHosts/com.vpittamp.i3pm_url_bridge.json".text =
    builtins.toJSON {
      name = "com.vpittamp.i3pm_url_bridge";
      description = "i3pm QuickShell URL bridge";
      path = "${chromeUrlHost}/bin/chrome-url-host";
      type = "stdio";
      allowed_origins = [ "chrome-extension://${chromeUrlExtensionId}/" ];
    };

  home.file.".config/i3/chrome-url-pwa-routes.json".text = pwaRouteRegistry;
  home.file.".local/share/applications/google-chrome-i3pm.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=Google Chrome
    Comment=Google Chrome with i3pm URL bridge
    Exec=${chromeWrapper}/bin/google-chrome-i3pm %U
    Terminal=false
    Icon=google-chrome
    Categories=Network;WebBrowser;
    MimeType=text/html;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/about;x-scheme-handler/unknown;x-scheme-handler/ftp;x-scheme-handler/mailto;x-scheme-handler/webcal;application/pdf;
    StartupWMClass=Google-chrome
  '';

  # Chrome's managed policy is configured at the system level in
  # modules/services/onepassword.nix via /etc/opt/chrome/policies/managed/.

  # Let 1Password manage per-user Chrome native messaging manifests itself.
  # System-level Chrome manifests are provided in modules/services/onepassword.nix,
  # and 1Password also attempts to install/update the user-level manifest on Linux.
  # Managing ~/.config/google-chrome/NativeMessagingHosts with Home Manager makes
  # that path read-only via Nix store symlinks and breaks 1Password's installer.

  # Claude Code manages its own native messaging host file at:
  # ~/.config/google-chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json
  # We don't manage it with Nix because Claude Code needs to write to it.
  #
  # However, Claude Code generates ~/.claude/chrome/chrome-native-host with #!/bin/bash shebang
  # which doesn't work on NixOS. We fix this with an activation script below.

  # Fix Claude Code's native host script shebang on activation
  # This runs after Claude Code creates the file, replacing the broken #!/bin/bash shebang
  home.activation.fixClaudeNativeHost = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -f "$HOME/.claude/chrome/chrome-native-host" ]; then
      # Check if the shebang is the problematic #!/bin/bash
      if head -1 "$HOME/.claude/chrome/chrome-native-host" | grep -q '^#!/bin/bash'; then
        echo "Fixing Claude native host shebang for NixOS..."
        # Get the node and cli paths from the existing script
        NODE_PATH=$(grep -o '/nix/store/[^/]*/bin/node' "$HOME/.claude/chrome/chrome-native-host" | head -1)
        CLI_PATH=$(grep -o '/nix/store/[^"]*cli\.js' "$HOME/.claude/chrome/chrome-native-host" | head -1)
        if [ -n "$NODE_PATH" ] && [ -n "$CLI_PATH" ]; then
          cat > "$HOME/.claude/chrome/chrome-native-host" << EOF
#!/usr/bin/env bash
# Chrome native host wrapper script - Fixed for NixOS
exec "$NODE_PATH" "$CLI_PATH" --chrome-native-host
EOF
          chmod +x "$HOME/.claude/chrome/chrome-native-host"
        fi
      fi
    fi
  '';

  # Configure 1Password browser integration settings
  home.file.".config/1Password/settings/browser-support.json" = {
    text = builtins.toJSON {
      "browser.autoFillShortcut" = {
        "enabled" = true;
        "shortcut" = "Ctrl+Shift+L";
      };
      "browser.showSavePrompts" = true;
      "browser.theme" = "system";
      "security.authenticatedUnlock.enabled" = true;
      "security.authenticatedUnlock.method" = "system";
      "security.autolock.minutes" = 60;
      "security.clipboardClearAfterSeconds" = 90;
    };
  };

  # Shell aliases for convenience
  home.shellAliases = {
    chrome = "google-chrome-i3pm";
    browser = "google-chrome-i3pm";
    chrome-beta = "google-chrome-beta";
    chrome-dev = "google-chrome-unstable";
  };

  # Add cluster CA certificate to Chrome's NSS database for HTTPS trust
  # Chrome uses ~/.pki/nssdb/ for certificate storage (separate from system CA store)
  # This makes Chrome trust *.cnoe.localtest.me self-signed certificates
  home.activation.chromeTrustClusterCert = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    NSS_DB="$HOME/.pki/nssdb"
    CERT_NICKNAME="CNOE-Local-Dev-CA"

    # Ensure NSS database directory exists with proper permissions
    mkdir -p "$NSS_DB"

    # Initialize NSS database if it doesn't exist
    if [ ! -f "$NSS_DB/cert9.db" ]; then
      echo "Initializing Chrome NSS database..."
      ${pkgs.nssTools}/bin/certutil -d sql:"$NSS_DB" -N --empty-password
    fi

    # Check if certificate already exists
    if ${pkgs.nssTools}/bin/certutil -d sql:"$NSS_DB" -L -n "$CERT_NICKNAME" >/dev/null 2>&1; then
      # Certificate exists - delete and re-add to ensure it's current
      ${pkgs.nssTools}/bin/certutil -d sql:"$NSS_DB" -D -n "$CERT_NICKNAME" 2>/dev/null || true
    fi

    # Add the cluster CA certificate as trusted for SSL (CT,C,C = trusted for SSL/email/code)
    echo "Adding cluster CA certificate to Chrome trust store..."
    ${pkgs.nssTools}/bin/certutil -d sql:"$NSS_DB" -A -n "$CERT_NICKNAME" -t "CT,C,C" -i "${clusterCaCert}"
  '';
}

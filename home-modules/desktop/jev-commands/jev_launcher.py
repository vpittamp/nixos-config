#!/usr/bin/env python3
"""Jev-powered launcher search engine for QuickShell.

Ranks candidate files and Chrome URLs/tabs using TypeSafe SystemOne (jev),
returning the most likely file that the user is looking for or activating the right URL
in Chrome.

Usage:
  jev_launcher.py [mode] [query] [limit]

Modes:
  mixed : Searches both files and Chrome URLs/tabs (default)
  files : Searches files only
  urls  : Searches Chrome URLs/tabs only
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# Resolve jev_api
try:
    from jev_api import evaluate, JevError
except ImportError:
    script_dir = Path(__file__).resolve().parent
    sys.path.append(str(script_dir))
    try:
        from jev_api import evaluate, JevError
    except ImportError:
        evaluate = None  # Fallback gracefully if API unavailable
        JevError = RuntimeError


def get_active_worktree_dir() -> Optional[Path]:
    """Retrieve the current active worktree directory from i3pm context."""
    context_file = Path.home() / ".config" / "i3" / "active-worktree.json"
    if context_file.is_file():
        try:
            data = json.loads(context_file.read_text(encoding="utf-8"))
            local_dir = data.get("local_directory") or data.get("directory")
            if local_dir:
                p = Path(local_dir).expanduser()
                if p.is_dir():
                    return p
        except Exception:
            pass
    return None


def get_recent_files(worktree_dir: Optional[Path], limit: int = 30) -> List[Path]:
    """Gather recently accessed files from GTK xbel and active git worktree."""
    recent_paths: List[Path] = []
    seen: Set[str] = set()

    # 1. From ~/.local/share/recently-used.xbel
    xbel_path = Path.home() / ".local" / "share" / "recently-used.xbel"
    if xbel_path.is_file():
        try:
            tree = ET.parse(xbel_path)
            # Most recent items are usually at the end of the XML
            bookmarks = tree.findall(".//bookmark")
            for bm in reversed(bookmarks):
                href = bm.get("href", "")
                if href.startswith("file://"):
                    raw_path = urllib.parse.unquote(href[7:])
                    p = Path(raw_path)
                    p_str = str(p)
                    if p_str not in seen and p.exists():
                        seen.add(p_str)
                        recent_paths.append(p)
                        if len(recent_paths) >= limit:
                            break
        except Exception:
            pass

    # 2. From active worktree git status / git log
    if worktree_dir and (worktree_dir / ".git").exists() and len(recent_paths) < limit:
        try:
            git_run = subprocess.run(
                ["git", "-C", str(worktree_dir), "status", "--porcelain"],
                capture_output=True,
                text=True,
                timeout=1,
                check=False,
            )
            for line in git_run.stdout.splitlines():
                parts = line.strip().split(maxsplit=1)
                if len(parts) == 2:
                    file_rel = parts[1].strip('"')
                    p = (worktree_dir / file_rel).resolve()
                    p_str = str(p)
                    if p_str not in seen and p.exists():
                        seen.add(p_str)
                        recent_paths.append(p)
                        if len(recent_paths) >= limit:
                            break

            if len(recent_paths) < limit:
                log_run = subprocess.run(
                    ["git", "-C", str(worktree_dir), "log", "-n", "10", "--name-only", "--pretty=format:"],
                    capture_output=True,
                    text=True,
                    timeout=1,
                    check=False,
                )
                for line in log_run.stdout.splitlines():
                    val = line.strip().strip('"')
                    if val:
                        p = (worktree_dir / val).resolve()
                        p_str = str(p)
                        if p_str not in seen and p.exists():
                            seen.add(p_str)
                            recent_paths.append(p)
                            if len(recent_paths) >= limit:
                                break
        except Exception:
            pass

    return recent_paths


STOP_WORDS: Set[str] = {
    "a", "an", "the", "in", "on", "at", "to", "for", "of", "and", "or",
    "is", "are", "where", "what", "which", "my", "me", "i", "by", "with",
    "about", "defined", "find", "get", "show", "open", "please", "can",
    "how", "do", "does", "file", "url", "tab", "page", "website",
    "app", "apps", "launch", "run", "start"
}


def filter_tokens(query: str) -> List[str]:
    """Extract meaningful search tokens, stripping common conversational words."""
    raw_tokens = [t.lower().strip(".,!?:;\"'()[]{}") for t in query.split()]
    tokens = [t for t in raw_tokens if t and t not in STOP_WORDS and len(t) > 1]
    return tokens or [t for t in raw_tokens if t]


def search_candidate_files(query: str, limit: int = 20) -> List[Dict[str, Any]]:
    """Find candidate files from active worktree, home documents/repos, and recents."""
    home = Path.home()
    worktree_dir = get_active_worktree_dir()
    recent_paths = get_recent_files(worktree_dir, limit=40)

    query_trimmed = query.strip()
    tokens = filter_tokens(query_trimmed)

    candidates: List[Dict[str, Any]] = []
    seen: Set[str] = set()

    def add_file_candidate(path: Path, base_score: float = 0.0) -> None:
        p_str = str(path.resolve())
        if p_str in seen or not path.exists():
            return
        seen.add(p_str)
        is_dir = path.is_dir()
        display_name = path.name or p_str
        if is_dir and not display_name.endswith("/"):
            display_name += "/"

        # Compute lexical match score
        name_lower = display_name.lower()
        path_lower = p_str.lower()
        score = base_score
        if tokens:
            for t in tokens:
                if t in name_lower:
                    score += 12.0 + (6.0 if name_lower.startswith(t) else 0.0)
                elif t in path_lower:
                    score += 5.0
        else:
            score += 1.0

        candidates.append({
            "kind": "file",
            "identifier": p_str,
            "text": display_name,
            "subtext": str(path.parent if not is_dir else path),
            "icon": "folder" if is_dir else "",
            "state": ["directory"] if is_dir else ["file"],
            "actions": ["open", "opendir"],
            "provider": "jev",
            "_score": score,
        })

    # If empty query, return recents + worktree top files
    if not tokens:
        for p in recent_paths:
            add_file_candidate(p, base_score=10.0)
        if worktree_dir and len(candidates) < limit:
            try:
                for entry in sorted(worktree_dir.iterdir()):
                    if entry.name.startswith("."):
                        continue
                    add_file_candidate(entry, base_score=5.0)
            except Exception:
                pass
        candidates.sort(key=lambda x: -x["_score"])
        for c in candidates:
            c.pop("_score", None)
        return candidates[:limit]

    # 1. Search files in active worktree (very high relevance)
    if worktree_dir:
        # Check git ls-files if git repository
        if (worktree_dir / ".git").exists():
            try:
                ls_run = subprocess.run(
                    ["git", "-C", str(worktree_dir), "ls-files"],
                    capture_output=True,
                    text=True,
                    timeout=1,
                    check=False,
                )
                for line in ls_run.stdout.splitlines():
                    val = line.strip().strip('"')
                    if val and any(t in val.lower() for t in tokens):
                        add_file_candidate(worktree_dir / val, base_score=12.0)
                        if len(candidates) >= limit * 2:
                            break
            except Exception:
                pass

        # Also direct walk in worktree if few candidates found
        if len(candidates) < 5:
            try:
                for root, dirs, files in os.walk(worktree_dir):
                    dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "target", "result")]
                    for f in files:
                        if any(t in f.lower() for t in tokens):
                            add_file_candidate(Path(root) / f, base_score=10.0)
                            if len(candidates) >= limit:
                                break
                    if len(candidates) >= limit:
                        break
            except Exception:
                pass

    # 2. Check recent paths for matches
    for p in recent_paths:
        p_str = str(p).lower()
        if any(t in p_str for t in tokens):
            add_file_candidate(p, base_score=8.0)

    # 3. Search targeted directories using fd for the top search tokens
    fd_bin = shutil.which("fd") or "/run/current-system/sw/bin/fd"
    search_roots: List[str] = [
        str(home / "repos"),
        str(home / "Documents"),
        str(home / "Downloads"),
        "/etc/nixos",
    ]
    valid_roots = [r for r in search_roots if Path(r).is_dir()]

    if fd_bin and os.path.exists(fd_bin) and valid_roots:
        # Search for up to 3 meaningful tokens
        for token in tokens[:3]:
            cmd = [
                fd_bin,
                "--hidden",
                "--exclude", ".git",
                "--exclude", "node_modules",
                "--exclude", ".cache",
                "--exclude", ".direnv",
                "--exclude", ".npm",
                "--exclude", ".cargo",
                "--max-results", "25",
                token,
                *valid_roots,
            ]
            try:
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=2, check=False)
                for line in res.stdout.splitlines():
                    val = line.strip()
                    if val:
                        add_file_candidate(Path(val), base_score=5.0)
            except Exception:
                pass

    # Sort candidates by lexical match score initially
    candidates.sort(key=lambda x: -x["_score"])
    return candidates[:limit]


def get_chrome_and_pwa_windows() -> List[Dict[str, Any]]:
    """Read open Chrome and PWA windows from Sway IPC tree."""
    windows: List[Dict[str, Any]] = []
    swaymsg = shutil.which("swaymsg") or "/run/current-system/sw/bin/swaymsg"
    if not swaymsg:
        return windows

    try:
        run = subprocess.run([swaymsg, "-t", "get_tree"], capture_output=True, text=True, timeout=1, check=False)
        tree = json.loads(run.stdout) if run.stdout else {}
    except Exception:
        return windows

    def walk_tree(node: Any) -> None:
        if isinstance(node, dict):
            app_id = str(node.get("app_id") or "")
            props = node.get("window_properties") or {}
            w_class = str(props.get("class") or "")
            name = str(node.get("name") or "")

            is_chrome = "chrome" in app_id.lower() or "chrome" in w_class.lower()
            if is_chrome and name:
                title = name
                if title.endswith(" - Google Chrome"):
                    title = title[:-16]

                # Check if title looks like a URL
                url = ""
                if title.startswith(("http://", "https://", "raw.githubusercontent.com", "github.com")):
                    url = title if title.startswith("http") else "https://" + title

                node_id = node.get("id")
                windows.append({
                    "kind": "url",
                    "identifier": f"sway:{node_id}",
                    "text": title,
                    "subtext": f"Open Window  •  {app_id}",
                    "url": url,
                    "domain": app_id,
                    "source": "window",
                    "icon": "google-chrome",
                    "sway_window_id": node_id,
                    "state": ["window", "open"],
                    "actions": ["preferred", "browser", "copy"],
                    "provider": "jev",
                    "_score": 15.0,  # Open windows receive high priority
                })

            for child in (node.get("nodes") or []) + (node.get("floating_nodes") or []):
                walk_tree(child)

    walk_tree(tree)
    return windows


def search_candidate_urls(query: str, limit: int = 20) -> List[Dict[str, Any]]:
    """Gather candidate URLs from open Sway windows, tabs, bookmarks, and Chrome history."""
    query_trimmed = query.strip()
    tokens = filter_tokens(query_trimmed)

    candidates: List[Dict[str, Any]] = []
    seen_urls: Set[str] = set()

    # 1. Open windows from Sway
    for win in get_chrome_and_pwa_windows():
        w_text = (win["text"] + " " + win["subtext"]).lower()
        if not tokens or any(t in w_text for t in tokens):
            if win["url"]:
                seen_urls.add(win["url"].lower())
            candidates.append(win)

    # 2. Chrome URL Index (~/.local/state/i3pm/chrome-url-index.json)
    index_path = Path.home() / ".local" / "state" / "i3pm" / "chrome-url-index.json"
    if index_path.is_file():
        try:
            data = json.loads(index_path.read_text(encoding="utf-8"))
            records: List[Dict[str, Any]] = []
            records.extend(data.get("tabs") or [])
            records.extend(data.get("bookmarks") or [])
            records.extend(data.get("history") or [])

            for rec in records:
                url = str(rec.get("url") or "").strip()
                if not url or url.lower() in seen_urls:
                    continue
                title = str(rec.get("title") or url).strip()
                domain = str(rec.get("domain") or "")
                source = str(rec.get("source") or "url")
                matched_pwa = str(rec.get("matched_pwa_name") or "")

                haystack = f"{title} {domain} {url} {matched_pwa}".lower()
                if tokens:
                    score = 0.0
                    for t in tokens:
                        if t in title.lower():
                            score += 8.0
                        elif t in domain.lower():
                            score += 5.0
                        elif t in haystack:
                            score += 2.0
                    if score <= 0.0:
                        continue
                else:
                    score = 5.0 if source == "bookmark" else 1.0

                seen_urls.add(url.lower())
                sub_parts = [source.title(), domain]
                if matched_pwa:
                    sub_parts.append(f"PWA {matched_pwa}")
                sub_parts.append(url)

                candidates.append({
                    "kind": "url",
                    "identifier": url,
                    "text": title,
                    "subtext": "  •  ".join(bit for bit in sub_parts if bit),
                    "url": url,
                    "domain": domain,
                    "source": source,
                    "icon": "google-chrome",
                    "matched_pwa_name": matched_pwa,
                    "state": [source] + (["pwa"] if matched_pwa else []),
                    "actions": ["preferred", "browser", "copy"],
                    "provider": "jev",
                    "_score": score,
                })
        except Exception:
            pass

    # Direct URL match if query looks like a domain or URL
    if query_trimmed and ("." in query_trimmed or query_trimmed.startswith("http")):
        typed_url = query_trimmed if query_trimmed.startswith("http") else f"https://{query_trimmed}"
        if typed_url.lower() not in seen_urls:
            candidates.insert(0, {
                "kind": "url",
                "identifier": typed_url,
                "text": typed_url,
                "subtext": f"Direct URL  •  {typed_url}",
                "url": typed_url,
                "domain": urllib.parse.urlsplit(typed_url).netloc.lower(),
                "source": "typed",
                "icon": "google-chrome",
                "state": ["typed"],
                "actions": ["preferred", "browser", "copy"],
                "provider": "jev",
                "_score": 25.0,
            })

    candidates.sort(key=lambda x: -x["_score"])
    return candidates[:limit]


def search_candidate_apps(query: str, limit: int = 20) -> List[Dict[str, Any]]:
    """Gather candidate applications from application-registry.json and system .desktop files."""
    query_trimmed = query.strip()
    tokens = filter_tokens(query_trimmed)

    candidates: List[Dict[str, Any]] = []
    seen_ids: Set[str] = set()

    # 1. Load from application-registry.json or base.json
    registry_paths = [
        Path.home() / ".config" / "i3" / "application-registry.json",
        Path.home() / ".local" / "share" / "i3pm" / "registry" / "base.json",
    ]
    raw_apps: List[Dict[str, Any]] = []
    for reg_path in registry_paths:
        if reg_path.is_file():
            try:
                data = json.loads(reg_path.read_text(encoding="utf-8"))
                apps = data.get("applications") or []
                if isinstance(apps, list) and apps:
                    raw_apps = apps
                    break
            except Exception:
                pass

    for app in raw_apps:
        if not isinstance(app, dict):
            continue
        name = str(app.get("name") or "").strip()
        display_name = str(app.get("display_name") or name).strip()
        if not name or not display_name:
            continue

        seen_ids.add(name.lower())
        is_pwa = name.endswith("-pwa")
        description = str(app.get("description") or "").strip()
        workspace = app.get("preferred_workspace")
        scope = str(app.get("scope") or "").strip()
        aliases = app.get("aliases") or []
        pwa_domain = str(app.get("pwa_domain") or "").strip()

        # Build subtext
        sub_parts = []
        if description:
            sub_parts.append(description)
        if workspace is not None:
            sub_parts.append(f"WS{workspace}")
        if scope:
            sub_parts.append(scope)
        subtext = " • ".join(sub_parts) if sub_parts else "Application"

        # Calculate lexical score
        name_lower = name.lower()
        disp_lower = display_name.lower()
        words = disp_lower.split() + name_lower.replace("-", " ").replace("_", " ").split()
        alias_strs = [str(a).lower() for a in aliases]
        aliases_joined = " ".join(alias_strs)
        haystack = f"{name_lower} {disp_lower} {description.lower()} {pwa_domain.lower()} {aliases_joined}"

        if tokens:
            score = 0.0
            for t in tokens:
                if t == name_lower or t == disp_lower:
                    score += 35.0
                elif t in words:
                    score += 30.0
                elif any(w.startswith(t) for w in words):
                    score += 22.0
                elif name_lower.startswith(t) or disp_lower.startswith(t):
                    score += 20.0
                elif any(t == a for a in alias_strs):
                    score += 20.0
                elif t in name_lower or t in disp_lower:
                    score += 15.0
                elif any(t in a for a in alias_strs):
                    score += 12.0
                elif t in haystack:
                    score += 4.0
            if score <= 0.0:
                continue
            score -= len(words) * 0.2
        else:
            if name in ("terminal", "code", "google-chrome", "firefox", "ghostty"):
                score = 15.0
            else:
                score = 5.0

        candidates.append({
            "kind": "app",
            "identifier": name,
            "text": display_name,
            "subtext": subtext,
            "icon": str(app.get("icon") or ""),
            "state": ["app"] + (["pwa"] if is_pwa else []),
            "actions": ["open"],
            "provider": "jev",
            "_score": score,
        })

    # 2. Check installed .desktop files for any desktop apps not in application-registry.json
    desktop_dirs = [
        Path.home() / ".local" / "share" / "i3pm-applications" / "applications",
        Path.home() / ".local" / "share" / "applications",
        Path("/run/current-system/sw/share/applications"),
        Path.home() / ".nix-profile" / "share" / "applications",
    ]
    for d in desktop_dirs:
        if not d.is_dir():
            continue
        try:
            for entry in d.glob("*.desktop"):
                app_id = entry.stem.lower()
                if app_id in seen_ids:
                    continue
                seen_ids.add(app_id)

                disp_name = entry.stem
                comment = ""
                icon = ""
                nodisplay = False
                try:
                    for line in entry.read_text(encoding="utf-8", errors="ignore").splitlines():
                        line = line.strip()
                        if line.startswith("Name=") and disp_name == entry.stem:
                            disp_name = line[5:].strip()
                        elif line.startswith("Comment=") and not comment:
                            comment = line[8:].strip()
                        elif line.startswith("Icon=") and not icon:
                            icon = line[5:].strip()
                        elif line.lower() == "nodisplay=true":
                            nodisplay = True
                            break
                except Exception:
                    pass

                if nodisplay:
                    continue

                disp_lower = disp_name.lower()
                haystack = f"{app_id} {disp_lower} {comment.lower()}"
                if tokens:
                    score = 0.0
                    for t in tokens:
                        if t == app_id or t == disp_lower:
                            score += 25.0
                        elif disp_lower.startswith(t) or app_id.startswith(t):
                            score += 16.0
                        elif t in disp_lower or t in app_id:
                            score += 10.0
                        elif t in haystack:
                            score += 3.0
                    if score <= 0.0:
                        continue
                else:
                    score = 2.0

                candidates.append({
                    "kind": "app",
                    "identifier": entry.stem,
                    "text": disp_name,
                    "subtext": comment or "Application",
                    "icon": icon,
                    "state": ["app"],
                    "actions": ["open"],
                    "provider": "jev",
                    "_score": score,
                })
        except Exception:
            pass

    candidates.sort(key=lambda x: -x["_score"])
    return candidates[:limit]


def rank_with_jev(
    query: str,
    candidates: List[Dict[str, Any]],
    mode: str = "mixed",
) -> List[Dict[str, Any]]:
    """Use TypeSafe SystemOne (jev) to evaluate and rank the candidates."""
    if not query.strip() or not candidates or evaluate is None:
        return candidates

    # Build choice criteria
    criteria: Dict[str, str] = {}
    key_to_candidate: Dict[str, Dict[str, Any]] = {}

    for idx, cand in enumerate(candidates):
        cid = f"c_{idx}"
        key_to_candidate[cid] = cand
        if cand["kind"] == "file":
            criteria[cid] = f"File: {cand['text']} in {cand['subtext']} (path: {cand['identifier']})"
        elif cand["kind"] == "app":
            criteria[cid] = f"Application: {cand['text']} ({cand['subtext']})"
        else:
            source = cand.get("source", "url").title()
            criteria[cid] = f"Chrome {source}: {cand['text']} ({cand.get('domain', '')} — {cand.get('url', cand['identifier'])})"

    criteria["none"] = "None of these match what the user is looking for"

    if mode == "files":
        instructions = "The user typed a query into their desktop file finder. Which file or directory are they most likely looking for?"
    elif mode == "urls":
        instructions = "The user typed a query to find or activate a Chrome tab, bookmark or web URL. Which URL are they looking for?"
    elif mode == "apps":
        instructions = "The user typed a query to launch an application. Which application are they most likely looking for?"
    else:
        instructions = (
            "The user typed a query into their desktop launcher to launch an application, find a file, or open/activate a Chrome tab or URL. "
            "Which candidate application, file, or URL is the user most likely looking for?"
        )

    questions = {
        "pick": {
            "type": "choice",
            "instructions": instructions,
            "criteria": criteria,
        }
    }

    try:
        response = evaluate(state=query, questions=questions)
        answer = response.get("answers", {}).get("pick", {})
        probabilities = answer.get("probabilities") or answer.get("distribution") or {}

        # Annotate candidates with Jev confidence
        for cid, cand in key_to_candidate.items():
            prob = float(probabilities.get(cid, 0.0) or 0.0)
            cand["confidence"] = round(prob, 2)
            if prob >= 0.05:
                cand["confidence_label"] = f"✦ {int(prob * 100)}%"

        # Sort candidates primarily by Jev confidence, secondarily by lexical score
        candidates.sort(key=lambda x: (-float(x.get("confidence", 0.0)), -float(x.get("_score", 0.0))))

    except Exception as exc:
        # On API failure/timeout, fall back gracefully to lexical sort
        for cand in candidates:
            cand.setdefault("confidence", 0.0)

    # Clean up private score
    for cand in candidates:
        cand.pop("_score", None)

    return candidates


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "mixed"
    query = sys.argv[2] if len(sys.argv) > 2 else ""
    try:
        limit = int(sys.argv[3]) if len(sys.argv) > 3 else 25
    except ValueError:
        limit = 25

    candidates: List[Dict[str, Any]] = []

    if mode == "files":
        candidates = search_candidate_files(query, limit=max(limit, 20))
    elif mode == "urls":
        candidates = search_candidate_urls(query, limit=max(limit, 20))
    elif mode == "apps":
        candidates = search_candidate_apps(query, limit=max(limit, 20))
    else:
        # Mixed mode: gather apps, files, and URLs
        part = max(8, limit // 3)
        apps = search_candidate_apps(query, limit=part)
        files = search_candidate_files(query, limit=part)
        urls = search_candidate_urls(query, limit=part)
        candidates = apps + files + urls

    ranked = rank_with_jev(query, candidates, mode=mode)
    print(json.dumps(ranked[:limit]))


if __name__ == "__main__":
    main()

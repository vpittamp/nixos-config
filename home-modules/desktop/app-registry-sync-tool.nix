{ pkgs, lib ? pkgs.lib }:

pkgs.writeShellScriptBin "i3pm-app-registry-sync" ''
  set -euo pipefail

  exec ${lib.getExe pkgs.python3} - "$@" <<'PY'
import json
import os
import sys
import tempfile
from pathlib import Path

VERSION = "1.0.0"
EDITABLE_FIELDS = (
    "aliases",
    "description",
    "display_name",
    "fallback_behavior",
    "floating",
    "floating_size",
    "icon",
    "multi_instance",
    "preferred_monitor_role",
    "preferred_workspace",
)
NULLABLE_STRING_FIELDS = {"fallback_behavior", "floating_size", "preferred_monitor_role"}
ENUM_FIELDS = {
    "fallback_behavior": {"skip", "use_home", "error"},
    "floating_size": {"scratchpad", "small", "medium", "large"},
    "preferred_monitor_role": {"primary", "secondary", "tertiary"},
}


def fail(message: str) -> "None":
    print(message, file=sys.stderr)
    raise SystemExit(1)


def parse_config_root(raw: str | None) -> Path | None:
    value = str(raw or "").strip()
    if not value:
        return None
    value = value.split("#", 1)[0].strip()
    if not value:
        return None
    if value.endswith("/flake.nix"):
        value = value[: -len("/flake.nix")]
    return Path(value)


def resolve_repo_override_path() -> Path:
    direct = str(os.environ.get("I3PM_APP_REGISTRY_REPO_OVERRIDE_PATH") or "").strip()
    if direct:
        return Path(direct)

    for key in ("I3PM_CONFIG_ROOT", "FLAKE_ROOT", "NH_FLAKE", "NH_OS_FLAKE"):
        root = parse_config_root(os.environ.get(key))
        if root is None:
            continue
        candidate = root / "shared" / "app-registry-overrides.json"
        if candidate.exists() or candidate.parent.exists():
            return candidate

    return Path("/etc/nixos/shared/app-registry-overrides.json")


def runtime_paths() -> dict[str, Path]:
    home = Path.home()
    return {
        "base": home / ".local" / "share" / "i3pm" / "registry" / "base.json",
        "declarative": home / ".local" / "share" / "i3pm" / "registry" / "declarative-overrides.json",
        "effective": home / ".config" / "i3" / "application-registry.json",
        "repo": resolve_repo_override_path(),
        "working": home / ".config" / "i3" / "app-registry-working-copy.json",
    }


def load_json(path: Path, default=None):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return default
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON at {path}: {exc}")
    except OSError as exc:
        fail(f"unable to read {path}: {exc}")


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_path = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2)
            handle.write("\n")
        os.replace(temp_path, path)
    except Exception:
        try:
            os.unlink(temp_path)
        except FileNotFoundError:
            pass
        raise


def sanitize_override(value: dict) -> dict:
    sanitized: dict = {}
    for field in EDITABLE_FIELDS:
        if field not in value:
            continue
        field_value = value[field]
        if field_value is None:
            sanitized[field] = None
            continue
        if isinstance(field_value, str):
            trimmed = field_value.strip()
            if not trimmed:
                if field in NULLABLE_STRING_FIELDS:
                    sanitized[field] = None
                continue
            sanitized[field] = trimmed
            continue
        if isinstance(field_value, list):
            cleaned = [str(item).strip() for item in field_value if str(item).strip()]
            if cleaned:
                sanitized[field] = cleaned
            continue
        sanitized[field] = field_value
    return validate_override("<inline>", sanitized)


def validate_override(name: str, value) -> dict:
    if not isinstance(value, dict):
        fail(f"override for '{name}' must be an object")

    result: dict = {}
    for key, raw_value in value.items():
        if key not in EDITABLE_FIELDS:
            fail(f"override for '{name}' contains unsupported field '{key}'")

        if key == "aliases":
            if not isinstance(raw_value, list) or not all(isinstance(item, str) for item in raw_value):
                fail(f"override field '{name}.aliases' must be an array of strings")
            result[key] = [item for item in raw_value if item.strip()]
            continue

        if key in ("description", "display_name", "icon"):
            if not isinstance(raw_value, str):
                fail(f"override field '{name}.{key}' must be a string")
            result[key] = raw_value.strip()
            continue

        if key == "preferred_workspace":
            if raw_value is not None and (isinstance(raw_value, bool) or not isinstance(raw_value, int)):
                fail(f"override field '{name}.preferred_workspace' must be an integer or null")
            result[key] = raw_value
            continue

        if key in ("floating", "multi_instance"):
            if raw_value is not None and not isinstance(raw_value, bool):
                fail(f"override field '{name}.{key}' must be a boolean or null")
            result[key] = raw_value
            continue

        if key in NULLABLE_STRING_FIELDS:
            if raw_value is not None and not isinstance(raw_value, str):
                fail(f"override field '{name}.{key}' must be a string or null")
            if isinstance(raw_value, str):
                raw_value = raw_value.strip() or None
            if raw_value is not None and raw_value not in ENUM_FIELDS[key]:
                allowed = ", ".join(sorted(ENUM_FIELDS[key]))
                fail(f"override field '{name}.{key}' must be one of {allowed} or null")
            result[key] = raw_value
            continue

    return result


def empty_overrides() -> dict:
    return {"version": VERSION, "applications": {}}


def load_overrides(path: Path) -> dict:
    raw = load_json(path, None)
    if raw is None:
        return empty_overrides()
    if not isinstance(raw, dict):
        fail(f"overrides file at {path} must be a JSON object")

    applications = raw.get("applications", {})
    if not isinstance(applications, dict):
        fail(f"overrides file at {path} must contain an 'applications' object")

    result = empty_overrides()
    result["version"] = str(raw.get("version") or VERSION)
    for name, override in applications.items():
        result["applications"][str(name)] = validate_override(str(name), override)
    return result


def load_base_registry(path: Path) -> dict:
    raw = load_json(path, None)
    if raw is None:
        fail(f"base registry not found at {path}")
    if not isinstance(raw, dict):
        fail(f"base registry at {path} must be a JSON object")
    applications = raw.get("applications")
    if not isinstance(applications, list):
        fail(f"base registry at {path} must contain an 'applications' array")
    return raw


def ensure_working_copy(paths: dict[str, Path]) -> dict:
    if not paths["working"].exists():
        declarative = load_overrides(paths["declarative"])
        write_json(paths["working"], declarative)
        return declarative
    return load_overrides(paths["working"])


def apply_override(app: dict, override: dict | None) -> dict:
    if not override:
        return dict(app)
    merged = dict(app)
    for field in EDITABLE_FIELDS:
        if field not in override:
            continue
        value = override[field]
        if value is None:
            merged.pop(field, None)
        else:
            merged[field] = value
    return merged


def validate_workspace_assignments(applications: list[dict]) -> None:
    assignments: dict[int, list[str]] = {}
    invalid: list[str] = []

    for app in applications:
        if not isinstance(app, dict):
            continue

        name = str(app.get("name") or "<unnamed>").strip()
        display_name = str(app.get("display_name") or name).strip() or name
        scratchpad = bool(app.get("scratchpad", False))
        workspace = app.get("preferred_workspace")

        if scratchpad:
            if workspace != 0:
                invalid.append(f"{display_name} ({name}) must use workspace 0 while scratchpad=true")
            continue

        if workspace is None:
            continue
        if isinstance(workspace, bool) or not isinstance(workspace, int):
            invalid.append(f"{display_name} ({name}) has invalid preferred_workspace={workspace!r}")
            continue
        if workspace < 1:
            invalid.append(f"{display_name} ({name}) must use a workspace >= 1")
            continue

        assignments.setdefault(workspace, []).append(display_name)

    if invalid:
        fail("invalid preferred_workspace values:\n  " + "\n  ".join(invalid))

    duplicates = {
        workspace: names
        for workspace, names in assignments.items()
        if len(names) > 1
    }
    if duplicates:
        lines = [
            f"WS {workspace}: {', '.join(sorted(names))}"
            for workspace, names in sorted(duplicates.items())
        ]
        fail("duplicate preferred_workspace assignments:\n  " + "\n  ".join(lines))


def merge_registry(base_registry: dict, declarative: dict, working_copy: dict) -> dict:
    merged_apps = []
    for app in base_registry.get("applications", []):
        if not isinstance(app, dict):
            continue
        name = str(app.get("name") or "").strip()
        merged = apply_override(app, declarative["applications"].get(name))
        merged = apply_override(merged, working_copy["applications"].get(name))
        merged_apps.append(merged)
    validate_workspace_assignments(merged_apps)
    return {
        "version": str(base_registry.get("version") or VERSION),
        "applications": merged_apps,
    }


def render_live(paths: dict[str, Path]) -> dict:
    base_registry = load_base_registry(paths["base"])
    declarative = load_overrides(paths["declarative"])
    working_copy = ensure_working_copy(paths)
    merged = merge_registry(base_registry, declarative, working_copy)
    write_json(paths["effective"], merged)
    return {
        "ok": True,
        "action": "render-live",
        "applications": len(merged["applications"]),
        "effective_path": str(paths["effective"]),
    }


def diff_overrides(before: dict, after: dict) -> list[dict]:
    names = sorted(set(before["applications"]) | set(after["applications"]))
    result = []
    for name in names:
        left = sanitize_override(before["applications"].get(name, {}))
        right = sanitize_override(after["applications"].get(name, {}))
        if left != right:
            result.append({"name": name, "before": left, "after": right})
    return result


def apply_working_copy(paths: dict[str, Path]) -> dict:
    base_registry = load_base_registry(paths["base"])
    working_copy = ensure_working_copy(paths)
    known_names = {
        str(app.get("name") or "").strip()
        for app in base_registry.get("applications", [])
        if isinstance(app, dict)
    }
    cleaned = empty_overrides()
    for name, override in working_copy["applications"].items():
        if name not in known_names:
            fail(f"working copy contains unknown application '{name}'")
        sanitized = sanitize_override(override)
        if sanitized:
            cleaned["applications"][name] = sanitized

    repo_path = paths["repo"]
    if not repo_path.parent.exists():
        fail(f"config root is not writable: {repo_path.parent} does not exist")
    write_json(repo_path, cleaned)
    render_live(paths)
    return {
        "ok": True,
        "action": "apply",
        "changedApplications": sorted(cleaned["applications"]),
        "repoOverridePath": str(repo_path),
        "workingCopyPath": str(paths["working"]),
        "effectivePath": str(paths["effective"]),
        "message": f"Wrote declarative overrides to {repo_path}",
    }


def reset_working_copy(paths: dict[str, Path]) -> dict:
    declarative = load_overrides(paths["declarative"])
    write_json(paths["working"], declarative)
    render_live(paths)
    return {
        "ok": True,
        "action": "reset-working-copy",
        "workingCopyPath": str(paths["working"]),
        "effectivePath": str(paths["effective"]),
        "message": "Reset working copy from declarative overrides",
    }


def validate(paths: dict[str, Path]) -> dict:
    load_base_registry(paths["base"])
    load_overrides(paths["declarative"])
    if paths["working"].exists():
        load_overrides(paths["working"])
    if paths["repo"].exists():
        load_overrides(paths["repo"])
    return {
        "ok": True,
        "action": "validate",
        "paths": {key: str(value) for key, value in paths.items()},
    }


def main(argv: list[str]) -> int:
    action = argv[1] if len(argv) > 1 else ""
    paths = runtime_paths()

    if action == "render-live":
        print(json.dumps(render_live(paths)))
        return 0
    if action == "apply":
        print(json.dumps(apply_working_copy(paths)))
        return 0
    if action == "reset-working-copy":
        print(json.dumps(reset_working_copy(paths)))
        return 0
    if action == "diff":
        repo_path = paths["repo"] if paths["repo"].exists() else paths["declarative"]
        print(json.dumps(diff_overrides(load_overrides(repo_path), ensure_working_copy(paths))))
        return 0
    if action == "validate":
        print(json.dumps(validate(paths)))
        return 0

    fail("usage: i3pm-app-registry-sync <render-live|apply|reset-working-copy|diff|validate>")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
PY
''

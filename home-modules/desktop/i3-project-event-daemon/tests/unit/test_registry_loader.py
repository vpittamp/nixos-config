"""Unit tests for application registry auto-reload behavior."""

from __future__ import annotations

import importlib
import importlib.util
import json
import time
import sys
from pathlib import Path


PACKAGE_ROOT = Path(__file__).parent.parent.parent


if "i3_project_daemon" not in sys.modules:
    package_spec = importlib.util.spec_from_file_location(
        "i3_project_daemon",
        PACKAGE_ROOT / "__init__.py",
        submodule_search_locations=[str(PACKAGE_ROOT)],
    )
    package_module = importlib.util.module_from_spec(package_spec)
    sys.modules["i3_project_daemon"] = package_module
    assert package_spec.loader is not None
    package_spec.loader.exec_module(package_module)


registry_module = importlib.import_module("i3_project_daemon.services.registry_loader")

RegistryLoader = registry_module.RegistryLoader


def write_registry(path: Path, app_name: str) -> None:
    path.write_text(json.dumps({
        "version": "1.0.0",
        "applications": [
            {
                "name": app_name,
                "display_name": app_name.title(),
                "icon": "icon",
                "command": app_name,
                "parameters": [],
                "terminal": False,
                "expected_class": app_name,
                "scope": "global",
                "fallback_behavior": "skip",
                "multi_instance": False,
            }
        ],
    }))


def test_registry_loader_ensure_current_reloads_changed_file(tmp_path: Path):
    registry_path = tmp_path / "application-registry.json"
    write_registry(registry_path, "first-app")

    loader = RegistryLoader(registry_path)
    loader.load()

    assert loader.get("first-app") is not None
    assert loader.get("second-app") is None

    time.sleep(0.01)
    write_registry(registry_path, "second-app")
    loader.ensure_current()

    assert loader.get("first-app") is None
    assert loader.get("second-app") is not None

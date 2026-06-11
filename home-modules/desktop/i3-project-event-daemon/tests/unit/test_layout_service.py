"""Unit tests for layout RPC payload shaping."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

import pytest


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


layout_module = importlib.import_module("i3_project_daemon.services.layout_service")
LayoutService = layout_module.LayoutService


def _service(**overrides):
    params = {
        "i3_connection_provider": lambda: "i3-connection",
    }
    params.update(overrides)
    return LayoutService(**params)


@pytest.mark.asyncio
async def test_save_captures_layout_persists_and_logs(tmp_path) -> None:
    logged = []
    captured_args = {}
    snapshot = SimpleNamespace(
        workspace_layouts=[object(), object()],
        metadata={"total_windows": 5},
        focused_workspace=3,
    )

    async def capture_layout(**kwargs):
        captured_args.update(kwargs)
        return snapshot

    async def log_ipc_event(**kwargs):
        logged.append(kwargs)

    service = _service(
        capture_layout_fn=capture_layout,
        save_layout_fn=lambda captured: tmp_path / f"{captured.metadata['total_windows']}.json",
        log_ipc_event=log_ipc_event,
    )

    result = await service.save({"project": "demo", "name": "main"})

    assert captured_args == {
        "i3_connection": "i3-connection",
        "name": "main",
        "project": "demo",
    }
    assert result == {
        "success": True,
        "layout_path": str(tmp_path / "5.json"),
        "workspace_count": 2,
        "window_count": 5,
        "focused_workspace": 3,
    }
    assert logged[0]["event_type"] == "layout::capture"
    assert logged[0]["project_name"] == "demo"


@pytest.mark.asyncio
async def test_restore_maps_restore_result_to_legacy_response() -> None:
    logged = []
    restore_args = {}

    async def restore_workflow(**kwargs):
        restore_args.update(kwargs)
        return SimpleNamespace(
            status="partial",
            apps_already_running=["terminal"],
            apps_launched=["browser"],
            apps_failed=["editor"],
            elapsed_seconds=1.25,
            total_apps=3,
            success_rate=66.7,
        )

    async def log_ipc_event(**kwargs):
        logged.append(kwargs)

    service = _service(
        load_layout_fn=lambda name, project: {"name": name, "project": project},
        restore_workflow_fn=restore_workflow,
        log_ipc_event=log_ipc_event,
    )

    result = await service.restore({"project": "demo", "name": "main"})

    assert restore_args == {
        "layout": {"name": "main", "project": "demo"},
        "project": "demo",
        "i3_connection": "i3-connection",
    }
    assert result["success"] is False
    assert result["status"] == "partial"
    assert result["apps_already_running"] == ["terminal"]
    assert result["apps_launched"] == ["browser"]
    assert result["apps_failed"] == ["editor"]
    assert result["windows_launched"] == 1
    assert result["windows_matched"] == 0
    assert result["windows_timeout"] == 0
    assert result["windows_failed"] == 1
    assert logged[0]["event_type"] == "layout::restore"


@pytest.mark.asyncio
async def test_list_filters_auto_saves_and_logs() -> None:
    logged = []

    async def log_ipc_event(**kwargs):
        logged.append(kwargs)

    service = _service(
        list_layouts_fn=lambda project: [
            {
                "name": "manual",
                "created_at": "2026-01-01T12:00:00",
                "total_windows": 3,
                "file_path": f"/layouts/{project}/manual.json",
            },
            {
                "name": "auto-20260101",
                "created_at": "2026-01-01T12:05:00",
                "total_windows": 4,
                "file_path": f"/layouts/{project}/auto.json",
            },
        ],
        log_ipc_event=log_ipc_event,
    )

    result = await service.list({"project_name": "demo", "include_auto_saves": False})

    assert result == {
        "project": "demo",
        "layouts": [
            {
                "layout_name": "manual",
                "timestamp": "2026-01-01T12:00:00",
                "windows_count": 3,
                "file_path": "/layouts/demo/manual.json",
                "is_auto_save": False,
            }
        ],
        "total_count": 1,
    }
    assert logged[0]["event_type"] == "query::layout_list"


@pytest.mark.asyncio
async def test_delete_reports_missing_layout_and_still_logs() -> None:
    logged = []

    async def log_ipc_event(**kwargs):
        logged.append(kwargs)

    service = _service(
        delete_layout_fn=lambda _name, _project: False,
        log_ipc_event=log_ipc_event,
    )

    with pytest.raises(RuntimeError, match="Layout not found"):
        await service.delete({"project_name": "demo", "layout_name": "missing"})

    assert logged[0]["event_type"] == "layout::delete"
    assert logged[0]["project_name"] == "demo"


@pytest.mark.asyncio
async def test_info_shapes_snapshot_details() -> None:
    snapshot = SimpleNamespace(
        name="main",
        project="demo",
        created_at=datetime(2026, 1, 1, 12, 0, 0),
        metadata={"total_windows": 2, "total_workspaces": 1, "total_monitors": 1},
        workspace_layouts=[
            SimpleNamespace(
                workspace_num=1,
                workspace_name="1",
                output="eDP-1",
                windows=[object(), object()],
            )
        ],
        monitor_config=SimpleNamespace(
            monitors=[
                SimpleNamespace(
                    name="eDP-1",
                    resolution=SimpleNamespace(width=1920, height=1200),
                    primary=True,
                )
            ]
        ),
    )
    service = _service(load_layout_fn=lambda name, project: snapshot)

    result = await service.info({"project": "demo", "name": "main"})

    assert result == {
        "name": "main",
        "project": "demo",
        "created_at": "2026-01-01T12:00:00",
        "total_windows": 2,
        "total_workspaces": 1,
        "total_monitors": 1,
        "workspaces": [
            {
                "workspace_num": 1,
                "workspace_name": "1",
                "output": "eDP-1",
                "window_count": 2,
            }
        ],
        "monitors": [
            {
                "name": "eDP-1",
                "width": 1920,
                "height": 1200,
                "primary": True,
            }
        ],
    }

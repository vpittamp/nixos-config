import importlib
import importlib.util
import sys
from pathlib import Path

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


window_filter_module = importlib.import_module("i3_project_daemon.services.window_filter")
read_process_environ = window_filter_module.read_process_environ


def test_read_process_environ_logs_permission_denied_at_debug(monkeypatch, caplog):
    environ_path = Path("/proc/2147/environ")

    def fake_open(*args, **kwargs):
        raise PermissionError("permission denied")

    monkeypatch.setattr("builtins.open", fake_open)

    with caplog.at_level("DEBUG"):
        with pytest.raises(PermissionError):
            read_process_environ(2147)

    assert "Permission denied reading /proc/2147/environ" in caplog.text
    assert "WARNING" not in caplog.text

import importlib.util
import sys
import types
from pathlib import Path


if "aiohttp" not in sys.modules:
    aiohttp_stub = types.ModuleType("aiohttp")
    aiohttp_stub.web = types.SimpleNamespace(
        Request=object,
        Response=object,
        Application=lambda **kwargs: types.SimpleNamespace(kwargs=kwargs, router=types.SimpleNamespace(add_get=lambda *a, **k: None, add_post=lambda *a, **k: None)),
        AppRunner=object,
        TCPSite=object,
        json_response=lambda *args, **kwargs: {},
    )
    sys.modules["aiohttp"] = aiohttp_stub


def _load_otel_monitor_package():
    pkg_dir = (
        Path(__file__).resolve().parents[2]
        / "scripts"
        / "otel-ai-monitor"
    )
    spec = importlib.util.spec_from_file_location(
        "otel_ai_monitor",
        pkg_dir / "__init__.py",
        submodule_search_locations=[str(pkg_dir)],
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load otel_ai_monitor package")
    module = importlib.util.module_from_spec(spec)
    sys.modules["otel_ai_monitor"] = module
    spec.loader.exec_module(module)
    return module


_load_otel_monitor_package()
from otel_ai_monitor.models import AITool  # type: ignore  # noqa: E402
from otel_ai_monitor.receiver import OTLPReceiver, _receiver_max_request_bytes  # type: ignore  # noqa: E402


def _make_receiver() -> OTLPReceiver:
    return object.__new__(OTLPReceiver)


def test_receiver_max_request_bytes_defaults_to_32_mib(monkeypatch):
    monkeypatch.delenv("OTEL_AI_MONITOR_MAX_REQUEST_MIB", raising=False)

    assert _receiver_max_request_bytes() == 32 * 1024 * 1024


def test_receiver_max_request_bytes_clamps_invalid_values(monkeypatch):
    monkeypatch.setenv("OTEL_AI_MONITOR_MAX_REQUEST_MIB", "bogus")
    assert _receiver_max_request_bytes() == 32 * 1024 * 1024

    monkeypatch.setenv("OTEL_AI_MONITOR_MAX_REQUEST_MIB", "0")
    assert _receiver_max_request_bytes() == 1 * 1024 * 1024


def test_parse_log_record_json_normalizes_claude_short_event_name():
    receiver = _make_receiver()
    log_record = {
        "timeUnixNano": "1771931000000000000",
        "attributes": [
            {"key": "event.name", "value": {"stringValue": "api_request"}},
            {"key": "session.id", "value": {"stringValue": "sid-claude-1"}},
        ],
    }

    event = receiver._parse_log_record_json(
        log_record=log_record,
        service_name="claude-code",
        resource_attrs={"process.pid": 1234},
    )

    assert event is not None
    assert event.event_name == "claude_code.api_request"
    assert event.tool == AITool.CLAUDE_CODE
    assert event.attributes.get("process.pid") == 1234


def test_parse_log_record_json_keeps_qualified_event_name_from_body():
    receiver = _make_receiver()
    log_record = {
        "timeUnixNano": "1771931000000000000",
        "body": {"stringValue": "claude_code.user_prompt"},
        "attributes": [
            {"key": "event.name", "value": {"stringValue": "user_prompt"}},
            {"key": "session.id", "value": {"stringValue": "sid-claude-2"}},
        ],
    }

    event = receiver._parse_log_record_json(
        log_record=log_record,
        service_name="claude-code",
        resource_attrs={},
    )

    assert event is not None
    assert event.event_name == "claude_code.user_prompt"
    assert event.tool == AITool.CLAUDE_CODE


def test_parse_log_record_json_does_not_force_prefix_without_service_hint():
    receiver = _make_receiver()
    log_record = {
        "timeUnixNano": "1771931000000000000",
        "attributes": [
            {"key": "event.name", "value": {"stringValue": "api_request"}},
        ],
    }

    event = receiver._parse_log_record_json(
        log_record=log_record,
        service_name=None,
        resource_attrs={},
    )

    assert event is not None
    assert event.event_name == "api_request"
    assert event.tool is None


def test_parse_log_record_json_normalizes_gemini_short_event_name():
    receiver = _make_receiver()
    log_record = {
        "timeUnixNano": "1771931000000000000",
        "body": {"stringValue": "GenAI operation details..."},
        "attributes": [
            {"key": "event.name", "value": {"stringValue": "api_request"}},
            {"key": "session.id", "value": {"stringValue": "sid-gemini-1"}},
        ],
    }

    event = receiver._parse_log_record_json(
        log_record=log_record,
        service_name="gemini-cli",
        resource_attrs={"process.pid": 4321},
    )

    assert event is not None
    assert event.event_name == "gemini_cli.api_request"
    assert event.tool == AITool.GEMINI_CLI
    assert event.attributes.get("process.pid") == 4321

"""Unit tests for pane-addressable Herdr agent notifications."""

from __future__ import annotations

import asyncio
import importlib
import importlib.util
import sys
from pathlib import Path
from typing import Any, Dict, List

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

herdr_notifier_module = importlib.import_module(
    "i3_project_daemon.services.herdr_notifier"
)

HerdrNotifier = herdr_notifier_module.HerdrNotifier
HINT_SESSION = herdr_notifier_module.HINT_SESSION
HINT_PANE = herdr_notifier_module.HINT_PANE
HINT_HOST = herdr_notifier_module.HINT_HOST


class Recorder:
    """Capture the argv the notifier would hand to notify-send."""

    def __init__(self) -> None:
        self.calls: List[List[str]] = []

    async def spawn(self, argv: List[str]) -> None:
        self.calls.append(list(argv))


def build_notifier(recorder: Recorder, **kwargs: Any) -> Any:
    clock = {"value": 1000.0}
    kwargs.setdefault("settle_seconds", 0.0)
    notifier = HerdrNotifier(
        notify_send="/usr/bin/notify-send",
        spawn=recorder.spawn,
        now=lambda: clock["value"],
        **kwargs,
    )
    notifier._test_clock = clock  # type: ignore[attr-defined]
    return notifier


def row(**overrides: Any) -> Dict[str, Any]:
    base = {
        "pane_id": "wB:p5",
        "session_key": "herdr:pane:wB:p5",
        "display_tool": "claude",
        "repo_name": "nixos-config",
        "branch_label": "fix/topbar",
        "terminal_title_stripped": "Quickshell topbar flickering",
        "herdr_host": "ryzen",
        "is_remote_herdr": False,
        "focused": False,
        "is_current_window": False,
    }
    base.update(overrides)
    return base


async def drain() -> None:
    """Let the settle task and the fire-and-forget spawn task run."""
    for _ in range(8):
        await asyncio.sleep(0)


@pytest.mark.asyncio
async def test_blocked_transition_carries_pane_identity():
    recorder = Recorder()
    notifier = build_notifier(recorder)

    notifier.note_local_status(row=row(), status_state="working")
    notifier.note_local_status(row=row(), status_state="blocked")
    await drain()

    assert len(recorder.calls) == 1
    argv = recorder.calls[0]
    assert f"--hint=string:{HINT_SESSION}:herdr:pane:wB:p5" in argv
    assert f"--hint=string:{HINT_PANE}:wB:p5" in argv
    assert f"--hint=string:{HINT_HOST}:ryzen" in argv
    assert "--app-name=herdr" in argv
    # Summary and body come last, after the `--` guard.
    assert argv[-2] == "claude needs attention"
    assert argv[-1] == "nixos-config:fix/topbar · Quickshell topbar flickering"


@pytest.mark.asyncio
async def test_working_to_idle_reads_as_finished():
    recorder = Recorder()
    notifier = build_notifier(recorder)

    notifier.note_local_status(row=row(), status_state="working")
    notifier.note_local_status(row=row(), status_state="idle")
    await drain()

    assert len(recorder.calls) == 1
    assert recorder.calls[0][-2] == "claude finished"


@pytest.mark.asyncio
async def test_idle_without_preceding_work_is_not_news():
    recorder = Recorder()
    notifier = build_notifier(recorder)

    notifier.note_local_status(row=row(), status_state="unknown")
    notifier.note_local_status(row=row(), status_state="idle")
    await drain()

    assert recorder.calls == []


@pytest.mark.asyncio
async def test_repeated_blocked_delivery_notifies_once():
    recorder = Recorder()
    notifier = build_notifier(recorder)

    notifier.note_local_status(row=row(), status_state="working")
    notifier.note_local_status(row=row(), status_state="blocked")
    notifier.note_local_status(row=row(), status_state="blocked")
    await drain()

    assert len(recorder.calls) == 1


@pytest.mark.asyncio
async def test_pane_the_user_is_looking_at_stays_quiet():
    recorder = Recorder()
    notifier = build_notifier(recorder)
    focused = row(focused=True, is_current_window=True)

    notifier.note_local_status(row=focused, status_state="working")
    notifier.note_local_status(row=focused, status_state="blocked")
    await drain()

    assert recorder.calls == []


@pytest.mark.asyncio
async def test_herdr_focus_alone_does_not_suppress():
    """`focused` moves with no sway event, so it cannot stand in for "on screen"."""
    recorder = Recorder()
    notifier = build_notifier(recorder)
    behind_a_browser = row(focused=True, is_current_window=False)

    notifier.note_local_status(row=behind_a_browser, status_state="working")
    notifier.note_local_status(row=behind_a_browser, status_state="blocked")
    await drain()

    assert len(recorder.calls) == 1


@pytest.mark.asyncio
async def test_dedupe_window_expires():
    recorder = Recorder()
    notifier = build_notifier(recorder, dedupe_window=8.0)

    async def blocked_cycle():
        notifier.note_local_status(row=row(), status_state="working")
        notifier.note_local_status(row=row(), status_state="blocked")
        await drain()

    await blocked_cycle()
    assert len(recorder.calls) == 1

    await blocked_cycle()
    assert len(recorder.calls) == 1, "second cycle falls inside the dedupe window"

    notifier._test_clock["value"] += 30.0
    await blocked_cycle()
    assert len(recorder.calls) == 2


@pytest.mark.asyncio
async def test_transient_blocked_that_clears_is_never_announced():
    """Agent detection reads the screen, so a momentary prompt-shaped frame is not news."""
    recorder = Recorder()
    notifier = build_notifier(recorder)

    notifier.note_local_status(row=row(), status_state="working")
    notifier.note_local_status(row=row(), status_state="blocked")
    # Back to work before the announcement settles.
    notifier.note_local_status(row=row(), status_state="working")
    await drain()

    assert recorder.calls == []


@pytest.mark.asyncio
async def test_idle_blip_between_tool_calls_is_never_announced():
    """An agent that touches idle mid-turn has not finished anything."""
    recorder = Recorder()
    notifier = build_notifier(recorder)

    notifier.note_local_status(row=row(), status_state="working")
    notifier.note_local_status(row=row(), status_state="idle")
    notifier.note_local_status(row=row(), status_state="working")
    await drain()

    assert recorder.calls == []


@pytest.mark.asyncio
async def test_settle_window_is_actually_awaited():
    """The drop above must come from the timer, not from same-tick ordering."""
    recorder = Recorder()
    notifier = build_notifier(recorder, settle_seconds=0.05)

    notifier.note_local_status(row=row(), status_state="working")
    notifier.note_local_status(row=row(), status_state="blocked")
    await drain()
    assert recorder.calls == [], "nothing fires before the window elapses"

    await asyncio.sleep(0.12)
    assert len(recorder.calls) == 1


@pytest.mark.asyncio
async def test_two_agents_in_one_workspace_stay_distinct():
    """The exact case Herdr's own toast could not express."""
    recorder = Recorder()
    notifier = build_notifier(recorder)
    tab4 = row(pane_id="wB:p4", session_key="herdr:pane:wB:p4")
    tab3 = row(pane_id="wB:p3", session_key="herdr:pane:wB:p3")

    for pane in (tab4, tab3):
        notifier.note_local_status(row=pane, status_state="working")
    notifier.note_local_status(row=tab4, status_state="blocked")
    notifier.note_local_status(row=tab3, status_state="idle")
    await drain()

    assert len(recorder.calls) == 2
    panes = [
        arg.split(":", 2)[2]
        for call in recorder.calls
        for arg in call
        if arg.startswith(f"--hint=string:{HINT_PANE}:")
    ]
    assert panes == ["wB:p4", "wB:p3"]


@pytest.mark.asyncio
async def test_remote_first_payload_seeds_without_announcing():
    recorder = Recorder()
    notifier = build_notifier(recorder)
    blocked = row(
        pane_id="wR:p1",
        session_key="herdr:pane:wR:p1",
        agent_status_state="blocked",
        herdr_host="thinkpad",
        is_remote_herdr=True,
    )

    notifier.sync_remote_rows(host="thinkpad", rows=[blocked])
    await drain()

    assert recorder.calls == []


@pytest.mark.asyncio
async def test_remote_transition_after_seeding_announces_with_host():
    recorder = Recorder()
    notifier = build_notifier(recorder)
    working = row(
        pane_id="wR:p1",
        session_key="herdr:pane:wR:p1",
        agent_status_state="working",
        herdr_host="thinkpad",
        is_remote_herdr=True,
    )
    blocked = dict(working, agent_status_state="blocked")

    notifier.sync_remote_rows(host="thinkpad", rows=[working])
    notifier.sync_remote_rows(host="thinkpad", rows=[blocked])
    await drain()

    assert len(recorder.calls) == 1
    assert recorder.calls[0][-2] == "claude needs attention on thinkpad"


@pytest.mark.asyncio
async def test_reconnect_reseeds_instead_of_announcing_backlog():
    recorder = Recorder()
    notifier = build_notifier(recorder)
    working = row(
        pane_id="wR:p1",
        session_key="herdr:pane:wR:p1",
        agent_status_state="working",
        herdr_host="thinkpad",
        is_remote_herdr=True,
    )
    blocked = dict(working, agent_status_state="blocked")

    notifier.sync_remote_rows(host="thinkpad", rows=[working])
    notifier.forget_host("thinkpad")
    notifier.sync_remote_rows(host="thinkpad", rows=[blocked])
    await drain()

    assert recorder.calls == []


@pytest.mark.asyncio
async def test_body_falls_back_to_cwd_when_nothing_git_shaped():
    recorder = Recorder()
    notifier = build_notifier(recorder)
    bare = row(
        repo_name="",
        branch_label="",
        terminal_title_stripped="",
        cwd="/tmp/scratch",
    )

    notifier.note_local_status(row=bare, status_state="working")
    notifier.note_local_status(row=bare, status_state="blocked")
    await drain()

    assert recorder.calls[0][-1] == "/tmp/scratch"


@pytest.mark.asyncio
async def test_row_without_a_session_key_is_addressed_by_pane():
    recorder = Recorder()
    notifier = build_notifier(recorder)
    thin = {"pane_id": "wB:p9", "display_tool": "codex"}

    notifier.note_local_status(row=dict(thin), status_state="working")
    notifier.note_local_status(row=dict(thin), status_state="blocked")
    await drain()

    assert f"--hint=string:{HINT_SESSION}:herdr:pane:wB:p9" in recorder.calls[0]

"""Regression tests for daemon user service packaging."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
I3_PROJECT_DAEMON_NIX = REPO_ROOT / "home-modules" / "services" / "i3-project-daemon.nix"


def test_daemon_stop_notification_is_neutral_until_systemd_result_is_known():
    text = I3_PROJECT_DAEMON_NIX.read_text()

    assert 'ExecStopPost = "-${daemonNotifyScript}/bin/i3pm-daemon-notify stopped";' in text
    assert 'ExecStopPost = "-${daemonNotifyScript}/bin/i3pm-daemon-notify failed";' not in text
    assert "stopped|failed)" in text
    assert 'if [ "$RESULT" = "success" ] || { [ "$EXIT_CODE" = "exited" ] && [ "$EXIT_STATUS" = "0" ]; }; then' in text


def test_daemon_does_not_schedule_clean_restart_churn():
    text = I3_PROJECT_DAEMON_NIX.read_text()

    assert 'Restart = "on-failure";' in text
    assert 'Restart = "always";' not in text
    assert "RuntimeMaxSec" not in text

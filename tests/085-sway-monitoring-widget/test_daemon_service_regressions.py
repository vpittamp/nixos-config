"""Regression tests for daemon user service packaging."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
I3_PROJECT_DAEMON_NIX = REPO_ROOT / "home-modules" / "services" / "i3-project-daemon.nix"
IPC_SERVER_PY = REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon" / "ipc_server.py"
MONITOR_PROFILE_SERVICE_PY = REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon" / "monitor_profile_service.py"


def test_daemon_stop_notification_is_neutral_until_systemd_result_is_known():
    text = I3_PROJECT_DAEMON_NIX.read_text()

    assert 'ExecStopPost = "-${daemonNotifyScript}/bin/i3pm-daemon-notify stopped";' in text
    assert 'ExecStopPost = "-${daemonNotifyScript}/bin/i3pm-daemon-notify failed";' not in text
    assert "stopped|failed)" in text
    assert 'success|unknown|"")' in text
    assert '[ "$EXIT_STATUS" = "143" ]' in text
    assert "exit-code|signal|core-dump|watchdog|timeout|oom-kill" in text


def test_daemon_does_not_schedule_clean_restart_churn():
    text = I3_PROJECT_DAEMON_NIX.read_text()

    assert 'Restart = "on-failure";' in text
    assert 'Restart = "always";' not in text
    assert 'RestartSec = "750ms";' in text
    assert 'SuccessExitStatus = "SIGTERM SIGINT SIGHUP 143";' in text
    assert 'RestartPreventExitStatus = "SIGTERM SIGINT SIGHUP 143";' in text
    assert "RuntimeMaxSec" not in text


def test_daemon_service_has_ipc_readiness_probe_and_no_cpu_throttle():
    text = I3_PROJECT_DAEMON_NIX.read_text()

    assert 'daemonReadyScript = pkgs.writeShellScriptBin "i3pm-daemon-ready"' in text
    assert "${config.home.profileDirectory}/bin/i3pm daemon ping" in text
    assert '"${daemonReadyScript}/bin/i3pm-daemon-ready"' in text
    assert "CPUQuota" not in text


def test_expected_ipc_client_disconnects_are_not_error_logs():
    text = IPC_SERVER_PY.read_text()

    assert "except (BrokenPipeError, ConnectionError, ConnectionResetError, asyncio.IncompleteReadError) as e:" in text
    assert 'logger.debug("Client %s disconnected during request handling: %s", addr, e)' in text
    assert "logger.error(f\"Error handling client {addr}: {e}\", exc_info=True)" in text


def test_monitor_profile_notifications_are_quiet_when_notify_send_missing():
    text = MONITOR_PROFILE_SERVICE_PY.read_text()

    assert "import shutil" in text
    assert 'notify_send = shutil.which("notify-send")' in text
    assert 'logger.debug("Skipping desktop notification; notify-send is not available")' in text
    assert '"notify-send",' not in text

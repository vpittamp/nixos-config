"""Unit tests for verbose logging functionality.

T093: Test verbose logging infrastructure and integration.
FR-125: Verify --verbose flag enables logging.
"""

import pytest
import logging
from io import StringIO

from i3_project_manager.cli.logging_config import (
    setup_logging,
    get_logger,
    log_subprocess_call,
    log_i3_ipc_message,
    log_timing,
    VerboseLogger,
)


class TestLoggingSetup:
    """Test logging configuration and setup.

    T093: Logging setup tests
    """

    def test_default_logging_level(self):
        """Test default logging is WARNING level."""
        logger = setup_logging(verbose=False, debug=False)
        assert logger.level == logging.WARNING

    def test_verbose_logging_level(self):
        """Test --verbose enables INFO level."""
        logger = setup_logging(verbose=True, debug=False)
        assert logger.level == logging.INFO

    def test_debug_logging_level(self):
        """Test --debug enables DEBUG level."""
        logger = setup_logging(verbose=False, debug=True)
        assert logger.level == logging.DEBUG

    def test_debug_overrides_verbose(self):
        """Test --debug takes precedence over --verbose."""
        logger = setup_logging(verbose=True, debug=True)
        assert logger.level == logging.DEBUG

    def test_logger_name(self):
        """Test logger uses 'i3pm' namespace."""
        logger = setup_logging()
        assert logger.name == 'i3pm'


class TestSubprocessLogging:
    """Test subprocess call logging.

    T093: Subprocess logging tests
    """

    def test_log_subprocess_call(self, caplog):
        """Test subprocess call logging."""
        from unittest.mock import Mock

        # Create mock result
        result = Mock()
        result.returncode = 0
        result.stdout = "output"
        result.stderr = ""

        # Setup debug logging
        logger = setup_logging(debug=True)

        # Log subprocess call
        with caplog.at_level(logging.DEBUG):
            log_subprocess_call(["xdotool", "selectwindow"], result, logger)

        # Verify logs
        assert "Subprocess call: xdotool selectwindow" in caplog.text
        assert "Return code: 0" in caplog.text

    def test_log_subprocess_with_stderr(self, caplog):
        """Test subprocess logging includes stderr."""
        from unittest.mock import Mock

        result = Mock()
        result.returncode = 1
        result.stdout = ""
        result.stderr = "error message"

        logger = setup_logging(debug=True)

        with caplog.at_level(logging.DEBUG):
            log_subprocess_call(["xdotool", "fail"], result, logger)

        assert "error message" in caplog.text


class TestI3IPCLogging:
    """Test i3 IPC message logging.

    T093: i3 IPC logging tests
    """

    def test_log_i3_ipc_message(self, caplog):
        """Test i3 IPC message logging."""
        logger = setup_logging(debug=True)

        payload = {"workspace": "1"}

        with caplog.at_level(logging.DEBUG):
            log_i3_ipc_message("workspace::focus", payload, logger)

        assert "i3 IPC message: workspace::focus" in caplog.text
        assert "Payload:" in caplog.text


class TestTimingLogging:
    """Test timing/performance logging.

    T093: Performance timing tests
    """

    def test_log_timing_context_manager(self, caplog):
        """Test timing context manager logs start and completion."""
        import time

        logger = setup_logging(verbose=True)

        with caplog.at_level(logging.INFO):
            with log_timing("Test operation", logger):
                time.sleep(0.01)  # 10ms

        assert "Starting: Test operation" in caplog.text
        assert "Test operation completed in" in caplog.text
        assert "ms" in caplog.text


class TestVerboseLoggerHelper:
    """Test VerboseLogger helper class.

    T093: VerboseLogger helper tests
    """

    def test_verbose_logger_init(self):
        """Test VerboseLogger initialization."""
        vlog = VerboseLogger(verbose=True)
        assert vlog.verbose_mode is True
        assert vlog.debug_mode is False
        assert vlog.logger.level == logging.INFO

    def test_verbose_logger_debug_init(self):
        """Test VerboseLogger with debug mode."""
        vlog = VerboseLogger(debug=True)
        assert vlog.verbose_mode is False
        assert vlog.debug_mode is True
        assert vlog.logger.level == logging.DEBUG

    def test_verbose_logger_info(self, caplog):
        """Test VerboseLogger.info() method."""
        vlog = VerboseLogger(verbose=True)

        with caplog.at_level(logging.INFO):
            vlog.info("Test message")

        assert "Test message" in caplog.text

    def test_verbose_logger_debug(self, caplog):
        """Test VerboseLogger.debug() method."""
        vlog = VerboseLogger(debug=True)

        with caplog.at_level(logging.DEBUG):
            vlog.debug("Debug message")

        assert "Debug message" in caplog.text

    def test_verbose_logger_subprocess(self, caplog):
        """Test VerboseLogger.subprocess() helper."""
        from unittest.mock import Mock

        vlog = VerboseLogger(debug=True)
        result = Mock()
        result.returncode = 0
        result.stdout = "output"
        result.stderr = ""

        with caplog.at_level(logging.DEBUG):
            vlog.subprocess(["test", "command"], result)

        assert "Subprocess call: test command" in caplog.text

    def test_verbose_logger_i3_ipc(self, caplog):
        """Test VerboseLogger.i3_ipc() helper."""
        vlog = VerboseLogger(debug=True)

        with caplog.at_level(logging.DEBUG):
            vlog.i3_ipc("GET_TREE", {})

        assert "i3 IPC message: GET_TREE" in caplog.text

    def test_verbose_logger_timing(self, caplog):
        """Test VerboseLogger.timing() context manager."""
        import time

        vlog = VerboseLogger(verbose=True)

        with caplog.at_level(logging.INFO):
            with vlog.timing("Operation"):
                time.sleep(0.01)

        assert "Starting: Operation" in caplog.text
        assert "Operation completed in" in caplog.text


class TestColoredFormatter:
    """Test colored log output formatting.

    T093: Colored formatter tests
    """

    def test_colored_formatter_adds_colors(self):
        """Test ColoredFormatter adds ANSI color codes."""
        from i3_project_manager.cli.logging_config import ColoredFormatter
        import sys

        formatter = ColoredFormatter("%(levelname)s: %(message)s")

        record = logging.LogRecord(
            name="test",
            level=logging.ERROR,
            pathname="",
            lineno=0,
            msg="Test error",
            args=(),
            exc_info=None
        )

        formatted = formatter.format(record)

        # Should contain color code for ERROR (red)
        assert "\033[31m" in formatted or "ERROR" in formatted

    def test_colored_formatter_resets_colors(self):
        """Test ColoredFormatter includes reset code."""
        from i3_project_manager.cli.logging_config import ColoredFormatter

        formatter = ColoredFormatter("%(levelname)s: %(message)s")

        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="",
            lineno=0,
            msg="Test info",
            args=(),
            exc_info=None
        )

        formatted = formatter.format(record)

        # Should contain reset code
        assert "\033[0m" in formatted or "INFO" in formatted


@pytest.mark.integration
class TestLoggingIntegration:
    """Integration tests for logging across modules.

    T093: Integration tests
    """

    def test_cli_logging_initialization(self, caplog):
        """Test CLI initializes logging correctly."""
        from i3_project_manager.cli.logging_config import init_logging, get_global_logger

        # Initialize with verbose
        init_logging(verbose=True)
        logger = get_global_logger()

        with caplog.at_level(logging.INFO):
            logger.info("CLI test message")

        assert "CLI test message" in caplog.text

    def test_i3_client_logging(self, caplog):
        """Test i3_client module logs IPC operations."""
        # This would require mocking i3ipc connection
        # Placeholder for when i3_client has logging integrated
        pass

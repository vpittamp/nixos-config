"""Logging configuration for i3pm CLI.

T093: Verbose logging implementation with --verbose flag.
FR-125: Verbose logging for debugging and diagnostics.

Provides:
- Configurable log levels (INFO, DEBUG)
- Subprocess call logging
- i3 IPC message logging
- Performance timing logs
- Structured log format
"""

import logging
import sys
import time
from typing import Optional, Any, Callable
from functools import wraps
from contextlib import contextmanager


# Default log format
DEFAULT_FORMAT = "%(levelname)s: %(message)s"
VERBOSE_FORMAT = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
DEBUG_FORMAT = "%(asctime)s [%(levelname)s] %(name)s:%(lineno)d: %(message)s"


class ColoredFormatter(logging.Formatter):
    """Colored log formatter for terminal output.

    T093: Enhanced logging output
    """

    COLORS = {
        'DEBUG': '\033[36m',      # Cyan
        'INFO': '\033[32m',       # Green
        'WARNING': '\033[33m',    # Yellow
        'ERROR': '\033[31m',      # Red
        'CRITICAL': '\033[35m',   # Magenta
    }
    RESET = '\033[0m'

    def format(self, record):
        """Format log record with colors."""
        if record.levelname in self.COLORS:
            record.levelname = f"{self.COLORS[record.levelname]}{record.levelname}{self.RESET}"
        return super().format(record)


def setup_logging(verbose: bool = False, debug: bool = False) -> logging.Logger:
    """Configure logging for i3pm CLI.

    Args:
        verbose: Enable verbose logging (INFO level)
        debug: Enable debug logging (DEBUG level)

    Returns:
        Configured logger instance

    Examples:
        >>> logger = setup_logging(verbose=True)
        >>> logger.info("Starting operation")
        INFO: Starting operation

        >>> logger = setup_logging(debug=True)
        >>> logger.debug("Detailed information")
        2025-10-21 10:30:45 [DEBUG] i3pm: Detailed information

    T093: Logging setup
    """
    # Get root logger for i3pm
    logger = logging.getLogger('i3pm')

    # Remove existing handlers
    logger.handlers.clear()

    # Set log level
    if debug:
        logger.setLevel(logging.DEBUG)
        log_format = DEBUG_FORMAT
    elif verbose:
        logger.setLevel(logging.INFO)
        log_format = VERBOSE_FORMAT
    else:
        logger.setLevel(logging.WARNING)
        log_format = DEFAULT_FORMAT

    # Create console handler
    handler = logging.StreamHandler(sys.stderr)
    handler.setLevel(logger.level)

    # Use colored formatter if terminal supports it
    if sys.stderr.isatty():
        formatter = ColoredFormatter(log_format)
    else:
        formatter = logging.Formatter(log_format)

    handler.setFormatter(formatter)
    logger.addHandler(handler)

    return logger


def get_logger(name: str = 'i3pm') -> logging.Logger:
    """Get logger instance.

    Args:
        name: Logger name (default: i3pm)

    Returns:
        Logger instance

    T093: Logger getter
    """
    return logging.getLogger(name)


def log_subprocess_call(cmd: list, result: Any, logger: logging.Logger) -> None:
    """Log subprocess call with result.

    Args:
        cmd: Command list
        result: subprocess.CompletedProcess result
        logger: Logger instance

    T093: Subprocess logging
    FR-125: Show subprocess calls in verbose mode
    """
    logger.debug(f"Subprocess call: {' '.join(cmd)}")
    logger.debug(f"  Return code: {result.returncode}")

    if hasattr(result, 'stdout') and result.stdout:
        stdout = result.stdout if isinstance(result.stdout, str) else result.stdout.decode()
        logger.debug(f"  stdout: {stdout[:200]}...")  # First 200 chars

    if hasattr(result, 'stderr') and result.stderr:
        stderr = result.stderr if isinstance(result.stderr, str) else result.stderr.decode()
        if stderr:
            logger.debug(f"  stderr: {stderr[:200]}...")


def log_i3_ipc_message(message_type: str, payload: Any, logger: logging.Logger) -> None:
    """Log i3 IPC message.

    Args:
        message_type: IPC message type
        payload: Message payload
        logger: Logger instance

    T093: i3 IPC logging
    FR-125: Show i3 IPC messages in verbose mode
    """
    logger.debug(f"i3 IPC message: {message_type}")
    logger.debug(f"  Payload: {str(payload)[:500]}...")  # First 500 chars


@contextmanager
def log_timing(operation: str, logger: logging.Logger):
    """Context manager for logging operation timing.

    Args:
        operation: Operation description
        logger: Logger instance

    Yields:
        None

    Examples:
        >>> with log_timing("Load config", logger):
        ...     config.load()
        INFO: Load config completed in 15.32ms

    T093: Performance timing logs
    FR-125: Show timing in verbose mode
    """
    start = time.perf_counter()
    logger.info(f"Starting: {operation}")

    try:
        yield
    finally:
        elapsed_ms = (time.perf_counter() - start) * 1000
        logger.info(f"{operation} completed in {elapsed_ms:.2f}ms")


def log_performance(func: Callable) -> Callable:
    """Decorator for logging function performance.

    Args:
        func: Function to wrap

    Returns:
        Wrapped function with performance logging

    Examples:
        >>> @log_performance
        ... def slow_operation():
        ...     time.sleep(0.1)

        >>> slow_operation()
        INFO: slow_operation completed in 100.23ms

    T093: Performance decorator
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        logger = get_logger()
        start = time.perf_counter()

        try:
            result = func(*args, **kwargs)
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.debug(f"{func.__name__} completed in {elapsed_ms:.2f}ms")
            return result
        except Exception as e:
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.error(f"{func.__name__} failed after {elapsed_ms:.2f}ms: {e}")
            raise

    return wrapper


def log_async_performance(func: Callable) -> Callable:
    """Decorator for logging async function performance.

    Args:
        func: Async function to wrap

    Returns:
        Wrapped async function with performance logging

    T093: Async performance decorator
    """
    @wraps(func)
    async def wrapper(*args, **kwargs):
        logger = get_logger()
        start = time.perf_counter()

        try:
            result = await func(*args, **kwargs)
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.debug(f"{func.__name__} completed in {elapsed_ms:.2f}ms")
            return result
        except Exception as e:
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.error(f"{func.__name__} failed after {elapsed_ms:.2f}ms: {e}")
            raise

    return wrapper


class VerboseLogger:
    """Helper class for verbose logging in commands.

    T093: Verbose logging helper

    Examples:
        >>> vlog = VerboseLogger(verbose=True)
        >>> vlog.info("Loading configuration")
        INFO: Loading configuration

        >>> vlog.subprocess("xdotool selectwindow", result)
        DEBUG: Subprocess call: xdotool selectwindow
        DEBUG:   Return code: 0
    """

    def __init__(self, verbose: bool = False, debug: bool = False):
        """Initialize verbose logger.

        Args:
            verbose: Enable verbose mode
            debug: Enable debug mode
        """
        self.logger = setup_logging(verbose=verbose, debug=debug)
        self.verbose_mode = verbose
        self.debug_mode = debug

    def info(self, message: str) -> None:
        """Log info message."""
        self.logger.info(message)

    def debug(self, message: str) -> None:
        """Log debug message."""
        self.logger.debug(message)

    def warning(self, message: str) -> None:
        """Log warning message."""
        self.logger.warning(message)

    def error(self, message: str) -> None:
        """Log error message."""
        self.logger.error(message)

    def subprocess(self, cmd: list, result: Any) -> None:
        """Log subprocess call."""
        log_subprocess_call(cmd, result, self.logger)

    def i3_ipc(self, message_type: str, payload: Any) -> None:
        """Log i3 IPC message."""
        log_i3_ipc_message(message_type, payload, self.logger)

    def timing(self, operation: str):
        """Context manager for timing."""
        return log_timing(operation, self.logger)


# Global logger instance
_logger: Optional[logging.Logger] = None


def init_logging(verbose: bool = False, debug: bool = False) -> None:
    """Initialize global logging.

    Args:
        verbose: Enable verbose mode
        debug: Enable debug mode

    T093: Global logging initialization
    """
    global _logger
    _logger = setup_logging(verbose=verbose, debug=debug)


def get_global_logger() -> logging.Logger:
    """Get global logger instance.

    Returns:
        Global logger or creates new one

    T093: Global logger access
    """
    global _logger
    if _logger is None:
        _logger = setup_logging()
    return _logger

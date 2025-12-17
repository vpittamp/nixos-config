"""eBPF-based AI Agent Process Monitor.

This package provides kernel-level monitoring for AI agent processes
(Claude Code, Codex CLI) using eBPF syscall tracing. It detects when
AI processes transition from active processing to waiting-for-input
state and triggers desktop notifications.

Architecture:
    - System-level systemd service running as root (required for eBPF)
    - BCC/BPF programs for efficient kernel-space syscall filtering
    - Badge files written to $XDG_RUNTIME_DIR for eww panel integration
    - Desktop notifications via D-Bus/notify-send

Modules:
    - models: Pydantic data models (ProcessState, BadgeState, DaemonState)
    - bpf_probes: BCC eBPF program definitions and management
    - process_tracker: Process tree resolution and window ID mapping
    - badge_writer: Badge file management for eww panel
    - notifier: Desktop notification integration
    - daemon: Main daemon loop and state management
"""

import logging
from importlib.metadata import version, PackageNotFoundError

__version__ = "0.1.0"
__author__ = "vpittamp"

# Package-level exports
__all__ = [
    "__version__",
    "configure_logging",
    "get_logger",
]


def configure_logging(
    level: str = "INFO",
    format_string: str | None = None,
) -> logging.Logger:
    """Configure package-level logging.

    Args:
        level: Log level name (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        format_string: Custom format string. Defaults to standard format
            with timestamp, level, module, and message.

    Returns:
        Configured logger instance for the ebpf_ai_monitor package.

    Example:
        >>> from ebpf_ai_monitor import configure_logging
        >>> logger = configure_logging("DEBUG")
        >>> logger.debug("Starting monitor...")
    """
    if format_string is None:
        format_string = "%(asctime)s - %(levelname)s - %(name)s - %(message)s"

    logger = logging.getLogger("ebpf_ai_monitor")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))

    # Remove existing handlers to avoid duplicates
    logger.handlers.clear()

    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter(format_string))
    logger.addHandler(handler)

    return logger


def get_logger(name: str | None = None) -> logging.Logger:
    """Get a logger instance for the ebpf_ai_monitor package.

    Args:
        name: Optional submodule name. If provided, returns
            logger named 'ebpf_ai_monitor.{name}'. If None,
            returns the root package logger.

    Returns:
        Logger instance.

    Example:
        >>> from ebpf_ai_monitor import get_logger
        >>> logger = get_logger("daemon")
        >>> logger.info("Daemon started")
    """
    if name:
        return logging.getLogger(f"ebpf_ai_monitor.{name}")
    return logging.getLogger("ebpf_ai_monitor")

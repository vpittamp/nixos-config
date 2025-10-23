"""systemd journal query module for i3pm event system.

This module provides functionality to query systemd's journal via journalctl
and convert journal entries into unified EventEntry objects.

Feature: 029-linux-system-log
User Story: US1 - View System Service Launches
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional

logger = logging.getLogger(__name__)


# Import EventEntry model
from .models import EventEntry


async def query_systemd_journal(
    since: str,
    until: Optional[str] = None,
    unit_pattern: Optional[str] = None,
    limit: int = 1000,
    timeout: float = 10.0
) -> List[EventEntry]:
    """Query systemd journal and convert entries to EventEntry objects.

    Args:
        since: Time specification for --since parameter (e.g., "1 hour ago", "today", ISO timestamp)
        until: Optional time specification for --until parameter
        unit_pattern: Optional unit name pattern filter (applied in Python after query)
        limit: Maximum number of entries to return (default 1000)
        timeout: Query timeout in seconds (default 10.0)

    Returns:
        List of EventEntry objects with source="systemd"
        Empty list if journalctl unavailable or query fails

    Implementation notes:
    - Uses asyncio.create_subprocess_exec() for non-blocking execution
    - Parses newline-delimited JSON (one object per line, NOT a JSON array)
    - Filters after parsing for complex logic (unit pattern matching)
    - Graceful degradation: returns empty list on error with warning log

    Feature 029: Task T011 - Core journalctl query function
    """
    # Build journalctl command
    cmd = [
        "journalctl",
        "--user",
        "--output=json",
        f"--since={since}",
        f"--lines={limit}",
    ]

    if until:
        cmd.append(f"--until={until}")

    logger.debug(f"Executing journalctl query: {' '.join(cmd)}")

    try:
        # Execute journalctl asynchronously with timeout
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        # Wait for completion with timeout
        try:
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(),
                timeout=timeout
            )
        except asyncio.TimeoutError:
            logger.warning(f"journalctl query timed out after {timeout}s")
            proc.kill()
            await proc.wait()
            return []

        # Check return code
        if proc.returncode != 0:
            stderr_text = stderr.decode('utf-8', errors='replace')
            logger.warning(f"journalctl query failed (exit code {proc.returncode}): {stderr_text}")
            return []

        # Parse newline-delimited JSON output
        # Feature 029: Task T012 - JSON parsing
        stdout_text = stdout.decode('utf-8', errors='replace')
        journal_entries = _parse_journalctl_output(stdout_text)

        # Filter by unit pattern if specified
        # Feature 029: Task T013 - Event filtering
        if unit_pattern:
            journal_entries = _filter_by_unit_pattern(journal_entries, unit_pattern)
        else:
            # Default filter: only application-related units
            journal_entries = _filter_application_units(journal_entries)

        # Convert to EventEntry objects
        # Feature 029: Task T014 - EventEntry creation
        events = []
        for idx, entry in enumerate(journal_entries):
            try:
                event = _create_event_from_journal_entry(entry, event_id=idx)
                events.append(event)
            except Exception as e:
                logger.warning(f"Failed to create EventEntry from journal entry: {e}")
                continue

        logger.info(f"Retrieved {len(events)} systemd events from journal (since={since})")
        return events

    except FileNotFoundError:
        # Feature 029: Task T015 - Error handling
        logger.warning("journalctl command not found - systemd journal queries unavailable")
        return []
    except Exception as e:
        logger.error(f"Unexpected error querying systemd journal: {e}", exc_info=True)
        return []


def _parse_journalctl_output(stdout_text: str) -> List[Dict[str, Any]]:
    """Parse newline-delimited JSON output from journalctl.

    Feature 029: Task T012 - JSON parsing implementation

    Args:
        stdout_text: Raw stdout from journalctl --output=json

    Returns:
        List of parsed journal entry dictionaries

    Note: journalctl --output=json produces newline-delimited JSON,
    where each line is a separate JSON object (NOT a JSON array).
    """
    entries = []
    for line_num, line in enumerate(stdout_text.splitlines(), start=1):
        line = line.strip()
        if not line:
            continue

        try:
            entry = json.loads(line)
            entries.append(entry)
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse JSON on line {line_num}: {e}")
            continue

    return entries


def _filter_by_unit_pattern(entries: List[Dict[str, Any]], pattern: str) -> List[Dict[str, Any]]:
    """Filter journal entries by unit name pattern.

    Feature 029: Task T013 - Event filtering (custom pattern)

    Args:
        entries: List of journal entry dictionaries
        pattern: Unit name pattern (supports simple glob-style matching with *)

    Returns:
        Filtered list of entries matching the pattern
    """
    import re

    # Convert glob pattern to regex (simple implementation)
    # Example: "app-*.service" -> "^app-.*\.service$"
    regex_pattern = pattern.replace(".", r"\.").replace("*", ".*")
    regex_pattern = f"^{regex_pattern}$"

    try:
        regex = re.compile(regex_pattern)
    except re.error as e:
        logger.warning(f"Invalid unit pattern '{pattern}': {e}")
        return entries  # Return unfiltered on pattern error

    filtered = []
    for entry in entries:
        # Check both _SYSTEMD_USER_UNIT (for user services) and _SYSTEMD_UNIT (for system services)
        unit = entry.get("_SYSTEMD_USER_UNIT") or entry.get("_SYSTEMD_UNIT", "")
        if regex.match(unit):
            filtered.append(entry)

    return filtered


def _filter_application_units(entries: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Filter journal entries to application-related units only.

    Feature 029: Task T013 - Event filtering (default filter)

    Default filter matches:
    - app-*.service (systemd transient application services)
    - *.desktop units (desktop application services)

    Args:
        entries: List of journal entry dictionaries

    Returns:
        Filtered list containing only application launch events
    """
    filtered = []
    for entry in entries:
        # Check both _SYSTEMD_USER_UNIT (for user services) and _SYSTEMD_UNIT (for system services)
        unit = entry.get("_SYSTEMD_USER_UNIT") or entry.get("_SYSTEMD_UNIT", "")

        # Match application service patterns
        if unit.startswith("app-") and unit.endswith(".service"):
            filtered.append(entry)
        elif unit.endswith(".desktop"):
            filtered.append(entry)

    return filtered


def _create_event_from_journal_entry(entry: Dict[str, Any], event_id: int) -> EventEntry:
    """Convert systemd journal entry to EventEntry object.

    Feature 029: Task T014 - EventEntry creation from journal data

    Args:
        entry: Parsed journal entry dictionary from journalctl JSON output
        event_id: Unique event ID (temporary - will be assigned by database)

    Returns:
        EventEntry object with source="systemd" and populated systemd fields

    Journal field mapping:
        __REALTIME_TIMESTAMP -> timestamp (convert microseconds to datetime)
        _SYSTEMD_UNIT -> systemd_unit
        MESSAGE -> systemd_message
        _PID -> systemd_pid
        __CURSOR -> journal_cursor
    """
    # Parse timestamp from __REALTIME_TIMESTAMP (microseconds since epoch)
    timestamp_us = int(entry.get("__REALTIME_TIMESTAMP", 0))
    timestamp = datetime.fromtimestamp(timestamp_us / 1_000_000)

    # Extract systemd fields
    # Check both _SYSTEMD_USER_UNIT (for user services) and _SYSTEMD_UNIT (for system services)
    systemd_unit = entry.get("_SYSTEMD_USER_UNIT") or entry.get("_SYSTEMD_UNIT", "")
    systemd_message = entry.get("MESSAGE", "")
    systemd_pid = entry.get("_PID")
    journal_cursor = entry.get("__CURSOR")

    # Convert PID to int if present
    if systemd_pid is not None:
        try:
            systemd_pid = int(systemd_pid)
        except (ValueError, TypeError):
            systemd_pid = None

    # Determine event type based on unit name and message
    event_type = _determine_systemd_event_type(systemd_unit, systemd_message)

    # Create EventEntry
    return EventEntry(
        event_id=event_id,
        timestamp=timestamp,
        event_type=event_type,
        source="systemd",
        correlation_id=None,
        processing_duration_ms=0.0,

        # systemd-specific fields
        systemd_unit=systemd_unit,
        systemd_message=systemd_message,
        systemd_pid=systemd_pid,
        journal_cursor=journal_cursor,
    )


def _determine_systemd_event_type(unit: str, message: str) -> str:
    """Determine event_type from systemd unit and message.

    Feature 029: Task T014 - Event type classification

    Args:
        unit: Systemd unit name (e.g., "app-firefox-123.service")
        message: Systemd message text (e.g., "Started Firefox")

    Returns:
        Event type string in format "systemd::<category>::<action>"

    Event type patterns:
        - "systemd::service::start" - Service started
        - "systemd::service::stop" - Service stopped
        - "systemd::service::failed" - Service failed
        - "systemd::unit::event" - Other unit events
    """
    # Check for service start messages
    if any(keyword in message.lower() for keyword in ["started", "starting"]):
        return "systemd::service::start"

    # Check for service stop messages
    if any(keyword in message.lower() for keyword in ["stopped", "stopping"]):
        return "systemd::service::stop"

    # Check for service failures
    if any(keyword in message.lower() for keyword in ["failed", "failure", "error"]):
        return "systemd::service::failed"

    # Default for other unit events
    return "systemd::unit::event"

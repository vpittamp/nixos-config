"""Unified event type definitions for Feature 102.

This module provides the single source of truth for all event types
across Log and Trace views, enabling unified filtering and cross-referencing.

Feature 102: Unified Event Tracing System
"""

from enum import Enum
from typing import Set


class EventSource(str, Enum):
    """Event origin classification."""
    SWAY = "sway"       # Raw Sway IPC events
    I3PM = "i3pm"       # i3pm daemon internal events


class EventCategory(str, Enum):
    """High-level event grouping for filters."""
    WINDOW = "window"
    WORKSPACE = "workspace"
    OUTPUT = "output"
    PROJECT = "project"
    VISIBILITY = "visibility"
    COMMAND = "command"
    LAUNCH = "launch"
    STATE = "state"
    TRACE = "trace"
    SYSTEM = "system"


class UnifiedEventType(str, Enum):
    """All event types unified across Log and Trace views.

    Feature 102: Provides 35+ event types with derived source and category.
    """

    # Window Events (Sway)
    WINDOW_NEW = "window::new"
    WINDOW_CLOSE = "window::close"
    WINDOW_FOCUS = "window::focus"
    WINDOW_BLUR = "window::blur"           # Feature 102: Logged to buffer
    WINDOW_MOVE = "window::move"
    WINDOW_FLOATING = "window::floating"
    WINDOW_FULLSCREEN = "window::fullscreen_mode"
    WINDOW_TITLE = "window::title"
    WINDOW_MARK = "window::mark"
    WINDOW_URGENT = "window::urgent"

    # Workspace Events (Sway)
    WORKSPACE_FOCUS = "workspace::focus"
    WORKSPACE_INIT = "workspace::init"
    WORKSPACE_EMPTY = "workspace::empty"
    WORKSPACE_MOVE = "workspace::move"
    WORKSPACE_RENAME = "workspace::rename"
    WORKSPACE_URGENT = "workspace::urgent"
    WORKSPACE_RELOAD = "workspace::reload"

    # Output Events (Enhanced - Feature 102)
    OUTPUT_CONNECTED = "output::connected"
    OUTPUT_DISCONNECTED = "output::disconnected"
    OUTPUT_PROFILE_CHANGED = "output::profile_changed"
    OUTPUT_UNSPECIFIED = "output::unspecified"

    # Project Events (i3pm)
    PROJECT_SWITCH = "project::switch"
    PROJECT_CLEAR = "project::clear"

    # Visibility Events (i3pm)
    VISIBILITY_HIDDEN = "visibility::hidden"
    VISIBILITY_SHOWN = "visibility::shown"
    SCRATCHPAD_MOVE = "scratchpad::move"

    # Command Events (i3pm - Feature 102)
    COMMAND_QUEUED = "command::queued"
    COMMAND_EXECUTED = "command::executed"
    COMMAND_RESULT = "command::result"
    COMMAND_BATCH = "command::batch"

    # Launch Events (i3pm)
    LAUNCH_INTENT = "launch::intent"
    LAUNCH_NOTIFICATION = "launch::notification"
    LAUNCH_ENV_INJECTED = "launch::env_injected"
    LAUNCH_CORRELATED = "launch::correlated"

    # State Events (i3pm)
    STATE_SAVED = "state::saved"
    STATE_LOADED = "state::loaded"
    STATE_CONFLICT = "state::conflict"

    # Mark Events (i3pm)
    MARK_ADDED = "mark::added"
    MARK_REMOVED = "mark::removed"

    # Environment Events (i3pm)
    ENV_DETECTED = "env::detected"
    ENV_CHANGED = "env::changed"

    # Trace Events (i3pm)
    TRACE_START = "trace::start"
    TRACE_STOP = "trace::stop"
    TRACE_SNAPSHOT = "trace::snapshot"

    # System Events (Sway)
    BINDING_RUN = "binding::run"
    MODE_CHANGE = "mode::change"
    SHUTDOWN_EXIT = "shutdown::exit"
    TICK_MANUAL = "tick::manual"

    @classmethod
    def get_source(cls, event_type: "UnifiedEventType") -> EventSource:
        """Determine event source from type.

        Args:
            event_type: The event type to classify

        Returns:
            EventSource.SWAY for raw Sway events, EventSource.I3PM for daemon events
        """
        sway_types: Set[UnifiedEventType] = {
            cls.WINDOW_NEW, cls.WINDOW_CLOSE, cls.WINDOW_FOCUS, cls.WINDOW_BLUR,
            cls.WINDOW_MOVE, cls.WINDOW_FLOATING, cls.WINDOW_FULLSCREEN,
            cls.WINDOW_TITLE, cls.WINDOW_MARK, cls.WINDOW_URGENT,
            cls.WORKSPACE_FOCUS, cls.WORKSPACE_INIT, cls.WORKSPACE_EMPTY,
            cls.WORKSPACE_MOVE, cls.WORKSPACE_RENAME, cls.WORKSPACE_URGENT,
            cls.WORKSPACE_RELOAD,
            cls.OUTPUT_CONNECTED, cls.OUTPUT_DISCONNECTED, cls.OUTPUT_PROFILE_CHANGED,
            cls.OUTPUT_UNSPECIFIED,
            cls.BINDING_RUN, cls.MODE_CHANGE, cls.SHUTDOWN_EXIT, cls.TICK_MANUAL,
        }
        return EventSource.SWAY if event_type in sway_types else EventSource.I3PM

    @classmethod
    def get_category(cls, event_type: "UnifiedEventType") -> EventCategory:
        """Determine event category from type.

        Args:
            event_type: The event type to classify

        Returns:
            EventCategory for the given event type
        """
        categories = {
            EventCategory.WINDOW: {
                cls.WINDOW_NEW, cls.WINDOW_CLOSE, cls.WINDOW_FOCUS,
                cls.WINDOW_BLUR, cls.WINDOW_MOVE, cls.WINDOW_FLOATING,
                cls.WINDOW_FULLSCREEN, cls.WINDOW_TITLE, cls.WINDOW_MARK,
                cls.WINDOW_URGENT
            },
            EventCategory.WORKSPACE: {
                cls.WORKSPACE_FOCUS, cls.WORKSPACE_INIT,
                cls.WORKSPACE_EMPTY, cls.WORKSPACE_MOVE,
                cls.WORKSPACE_RENAME, cls.WORKSPACE_URGENT,
                cls.WORKSPACE_RELOAD
            },
            EventCategory.OUTPUT: {
                cls.OUTPUT_CONNECTED, cls.OUTPUT_DISCONNECTED,
                cls.OUTPUT_PROFILE_CHANGED, cls.OUTPUT_UNSPECIFIED
            },
            EventCategory.PROJECT: {
                cls.PROJECT_SWITCH, cls.PROJECT_CLEAR
            },
            EventCategory.VISIBILITY: {
                cls.VISIBILITY_HIDDEN, cls.VISIBILITY_SHOWN,
                cls.SCRATCHPAD_MOVE
            },
            EventCategory.COMMAND: {
                cls.COMMAND_QUEUED, cls.COMMAND_EXECUTED,
                cls.COMMAND_RESULT, cls.COMMAND_BATCH
            },
            EventCategory.LAUNCH: {
                cls.LAUNCH_INTENT, cls.LAUNCH_NOTIFICATION,
                cls.LAUNCH_ENV_INJECTED, cls.LAUNCH_CORRELATED
            },
            EventCategory.STATE: {
                cls.STATE_SAVED, cls.STATE_LOADED, cls.STATE_CONFLICT
            },
            EventCategory.TRACE: {
                cls.TRACE_START, cls.TRACE_STOP, cls.TRACE_SNAPSHOT,
                cls.MARK_ADDED, cls.MARK_REMOVED, cls.ENV_DETECTED,
                cls.ENV_CHANGED
            },
            EventCategory.SYSTEM: {
                cls.BINDING_RUN, cls.MODE_CHANGE, cls.SHUTDOWN_EXIT,
                cls.TICK_MANUAL
            },
        }
        for category, types in categories.items():
            if event_type in types:
                return category
        return EventCategory.SYSTEM

    @classmethod
    def from_string(cls, event_type_str: str) -> "UnifiedEventType":
        """Convert string to UnifiedEventType enum.

        Args:
            event_type_str: Event type string (e.g., "window::new")

        Returns:
            Corresponding UnifiedEventType enum value

        Raises:
            ValueError: If string doesn't match any event type
        """
        for event_type in cls:
            if event_type.value == event_type_str:
                return event_type
        raise ValueError(f"Unknown event type: {event_type_str}")

    @classmethod
    def is_i3pm_event(cls, event_type_str: str) -> bool:
        """Check if an event type string represents an i3pm event.

        Args:
            event_type_str: Event type string to check

        Returns:
            True if this is an i3pm-generated event, False for Sway events
        """
        try:
            event_type = cls.from_string(event_type_str)
            return cls.get_source(event_type) == EventSource.I3PM
        except ValueError:
            return False


# Filter category definitions for UI
FILTER_CATEGORIES = {
    "window_events": [
        UnifiedEventType.WINDOW_NEW,
        UnifiedEventType.WINDOW_CLOSE,
        UnifiedEventType.WINDOW_FOCUS,
        UnifiedEventType.WINDOW_BLUR,
        UnifiedEventType.WINDOW_MOVE,
        UnifiedEventType.WINDOW_FLOATING,
        UnifiedEventType.WINDOW_FULLSCREEN,
        UnifiedEventType.WINDOW_TITLE,
        UnifiedEventType.WINDOW_MARK,
        UnifiedEventType.WINDOW_URGENT,
    ],
    "workspace_events": [
        UnifiedEventType.WORKSPACE_FOCUS,
        UnifiedEventType.WORKSPACE_INIT,
        UnifiedEventType.WORKSPACE_EMPTY,
        UnifiedEventType.WORKSPACE_MOVE,
        UnifiedEventType.WORKSPACE_RENAME,
        UnifiedEventType.WORKSPACE_URGENT,
        UnifiedEventType.WORKSPACE_RELOAD,
    ],
    "output_events": [
        UnifiedEventType.OUTPUT_CONNECTED,
        UnifiedEventType.OUTPUT_DISCONNECTED,
        UnifiedEventType.OUTPUT_PROFILE_CHANGED,
        UnifiedEventType.OUTPUT_UNSPECIFIED,
    ],
    "i3pm_events": [
        UnifiedEventType.PROJECT_SWITCH,
        UnifiedEventType.PROJECT_CLEAR,
        UnifiedEventType.VISIBILITY_HIDDEN,
        UnifiedEventType.VISIBILITY_SHOWN,
        UnifiedEventType.SCRATCHPAD_MOVE,
        UnifiedEventType.COMMAND_QUEUED,
        UnifiedEventType.COMMAND_EXECUTED,
        UnifiedEventType.COMMAND_RESULT,
        UnifiedEventType.COMMAND_BATCH,
        UnifiedEventType.LAUNCH_INTENT,
        UnifiedEventType.LAUNCH_NOTIFICATION,
        UnifiedEventType.LAUNCH_ENV_INJECTED,
        UnifiedEventType.LAUNCH_CORRELATED,
        UnifiedEventType.STATE_SAVED,
        UnifiedEventType.STATE_LOADED,
        UnifiedEventType.STATE_CONFLICT,
        UnifiedEventType.MARK_ADDED,
        UnifiedEventType.MARK_REMOVED,
        UnifiedEventType.ENV_DETECTED,
        UnifiedEventType.ENV_CHANGED,
        UnifiedEventType.TRACE_START,
        UnifiedEventType.TRACE_STOP,
        UnifiedEventType.TRACE_SNAPSHOT,
    ],
    "system_events": [
        UnifiedEventType.BINDING_RUN,
        UnifiedEventType.MODE_CHANGE,
        UnifiedEventType.SHUTDOWN_EXIT,
        UnifiedEventType.TICK_MANUAL,
    ],
}

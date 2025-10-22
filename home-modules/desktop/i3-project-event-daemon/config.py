"""Configuration loader for i3 project event daemon.

Handles loading and saving project configurations, application classification,
active project state, and window rules from JSON files.
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, List, Callable
import tempfile
import os

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, FileModifiedEvent

from .models import ApplicationClassification, ActiveProjectState
from .window_rules import WindowRule, load_window_rules as _load_window_rules_impl

# Initialize logger first (before any usage)
logger = logging.getLogger(__name__)

# Import Project from i3pm
try:
    from i3_project_manager.core.models import Project
except ImportError:
    logger.warning("i3pm not installed, using minimal project loading")
    Project = None  # type: ignore


def load_project_configs(config_dir: Path) -> Dict[str, "Project"]:
    """Load all project configurations from JSON files using i3pm.

    Args:
        config_dir: Directory containing project JSON files (~/.config/i3/projects)

    Returns:
        Dictionary mapping project names to Project objects (from i3pm)

    Raises:
        ValueError: If project configurations are invalid
    """
    projects: Dict[str, "Project"] = {}

    if not config_dir.exists():
        logger.warning(f"Project config directory does not exist: {config_dir}")
        config_dir.mkdir(parents=True, exist_ok=True)
        return projects

    # Use i3pm's Project.list_all() method for consistent loading
    if Project:
        try:
            all_projects = Project.list_all(config_dir)
            for project in all_projects:
                projects[project.name] = project
                logger.debug(f"Loaded project: {project.name}")
            logger.info(f"Loaded {len(projects)} project(s) via i3pm")
        except Exception as e:
            logger.error(f"Failed to load projects via i3pm: {e}")
    else:
        logger.error("i3pm not available, cannot load projects")

    return projects


def load_app_classification(config_file: Path) -> ApplicationClassification:
    """Load application classification from JSON file using i3pm model.

    Args:
        config_file: Path to app-classes.json

    Returns:
        ApplicationClassification object from i3pm with patterns support

    Raises:
        ValueError: If configuration is invalid
    """
    # Use i3pm's AppClassification.load() method
    try:
        from i3_project_manager.core.models import AppClassification as I3pmAppClassification

        app_class = I3pmAppClassification.load(config_file)

        # Convert to daemon's ApplicationClassification model (if different)
        # For now, log and return compatible structure
        logger.info(
            f"Loaded application classification: "
            f"{len(app_class.scoped_classes)} scoped, "
            f"{len(app_class.global_classes)} global, "
            f"{len(app_class.class_patterns)} patterns"
        )

        # Return daemon's ApplicationClassification from sets
        return ApplicationClassification(
            scoped_classes=set(app_class.scoped_classes),
            global_classes=set(app_class.global_classes),
        )

    except ImportError:
        logger.warning("i3pm not available, using default classification")
        return ApplicationClassification(
            scoped_classes={"Code", "ghostty", "Alacritty", "Yazi"},
            global_classes={"firefox", "chromium-browser", "k9s"},
        )
    except Exception as e:
        logger.error(f"Failed to load application classification: {e}")
        raise


def save_active_project(state: ActiveProjectState, config_file: Path) -> None:
    """Save active project state to JSON file (atomic write).

    Uses temp file + rename pattern to prevent corruption.

    Args:
        state: Active project state to save
        config_file: Path to active-project.json
    """
    try:
        # Ensure parent directory exists
        config_file.parent.mkdir(parents=True, exist_ok=True)

        # Prepare data
        data = {
            "project_name": state.project_name,
            "activated_at": state.activated_at.isoformat(),
            "previous_project": state.previous_project,
        }

        # Atomic write using temp file + rename
        fd, temp_path = tempfile.mkstemp(
            dir=config_file.parent, prefix=".active-project-", suffix=".json"
        )

        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())  # Ensure data is written to disk

            # Atomic rename
            os.rename(temp_path, config_file)
            logger.debug(f"Saved active project state: {state.project_name}")

        except Exception:
            # Clean up temp file on error
            if Path(temp_path).exists():
                os.unlink(temp_path)
            raise

    except Exception as e:
        logger.error(f"Failed to save active project state: {e}")
        raise


def load_active_project(config_file: Path) -> Optional[ActiveProjectState]:
    """Load active project state from JSON file.

    Args:
        config_file: Path to active-project.json

    Returns:
        ActiveProjectState object or None if file doesn't exist
    """
    if not config_file.exists():
        logger.debug(f"Active project file does not exist: {config_file}")
        return None

    try:
        with open(config_file, "r") as f:
            data = json.load(f)

        state = ActiveProjectState(
            project_name=data.get("project_name"),
            activated_at=datetime.fromisoformat(data["activated_at"]),
            previous_project=data.get("previous_project"),
        )

        logger.info(f"Loaded active project: {state.project_name}")
        return state

    except (json.JSONDecodeError, KeyError, ValueError) as e:
        logger.error(f"Failed to load active project state: {e}")
        return None


def reload_window_rules(config_file: Path, previous_rules: Optional[List[WindowRule]] = None) -> List[WindowRule]:
    """Reload window rules from JSON file with error handling.

    This function is designed for daemon reload scenarios:
    - Validates JSON before applying
    - Retains previous config on error
    - Logs reload success/failure
    - Shows desktop notification on error (optional)

    Args:
        config_file: Path to window-rules.json
        previous_rules: Previously loaded rules (retained on error)

    Returns:
        List of WindowRule objects (previous_rules on error if provided, empty list otherwise)

    Examples:
        >>> rules = reload_window_rules(Path("~/.config/i3/window-rules.json"))
        >>> len(rules)
        5
    """
    try:
        rules = _load_window_rules_impl(str(config_file))
        logger.info(f"Reloaded {len(rules)} window rule(s) from {config_file}")
        return rules

    except ValueError as e:
        logger.error(f"Failed to reload window rules: {e}")

        # Show desktop notification on error (optional, requires notify-send)
        try:
            import subprocess
            subprocess.run(
                ["notify-send", "-u", "critical",
                 "i3pm Window Rules Error",
                 f"Failed to reload window-rules.json:\n{str(e)[:100]}"],
                check=False,
                timeout=5
            )
        except Exception:
            pass  # Notification is optional

        # Retain previous config on error
        if previous_rules is not None:
            logger.warning(f"Retaining previous {len(previous_rules)} window rule(s)")
            return previous_rules
        else:
            logger.warning("No previous rules to retain, returning empty list")
            return []

    except Exception as e:
        logger.exception(f"Unexpected error reloading window rules: {e}")
        return previous_rules if previous_rules is not None else []


class DebouncedReloadHandler(FileSystemEventHandler):
    """File system event handler with debounced reload callback.

    Debounces rapid file modifications (e.g., editor save sequences)
    to prevent excessive reload operations.
    """

    def __init__(self, callback: Callable[[], None], debounce_ms: int = 100):
        """Initialize debounced reload handler.

        Args:
            callback: Function to call after debounce period
            debounce_ms: Debounce timeout in milliseconds (default: 100ms)
        """
        super().__init__()
        self.callback = callback
        self.debounce_seconds = debounce_ms / 1000
        self._debounce_task: Optional[asyncio.Task] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    def set_event_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        """Set the asyncio event loop for scheduling callbacks.

        Args:
            loop: Asyncio event loop
        """
        self._loop = loop

    def on_modified(self, event: FileModifiedEvent) -> None:
        """Handle file modification event.

        Args:
            event: File system event
        """
        if event.is_directory:
            return

        # Cancel existing debounce task
        if self._debounce_task and not self._debounce_task.done():
            self._debounce_task.cancel()

        # Schedule new debounced callback
        if self._loop:
            self._debounce_task = self._loop.create_task(self._debounced_callback())
        else:
            # Fallback: call immediately if no event loop
            logger.warning("No event loop set for debounced handler, calling immediately")
            self.callback()

    async def _debounced_callback(self) -> None:
        """Execute callback after debounce delay."""
        try:
            await asyncio.sleep(self.debounce_seconds)
            self.callback()
        except asyncio.CancelledError:
            logger.debug("Debounced callback cancelled (rapid file changes)")


class WindowRulesWatcher:
    """File system watcher for window-rules.json with auto-reload.

    Uses watchdog library for cross-platform file monitoring and debounces
    rapid changes to prevent excessive reload operations.
    """

    def __init__(self,
                 config_file: Path,
                 reload_callback: Callable[[], List[WindowRule]],
                 debounce_ms: int = 100):
        """Initialize window rules file watcher.

        Args:
            config_file: Path to window-rules.json
            reload_callback: Function to call on file modification (should return updated rules)
            debounce_ms: Debounce timeout in milliseconds (default: 100ms)
        """
        self.config_file = config_file
        self.reload_callback = reload_callback
        self.observer = Observer()
        self.handler = DebouncedReloadHandler(reload_callback, debounce_ms)
        self._started = False

    def set_event_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        """Set the asyncio event loop for debounced callbacks.

        Args:
            loop: Asyncio event loop
        """
        self.handler.set_event_loop(loop)

    def start(self) -> None:
        """Start watching window-rules.json for modifications.

        Watches the parent directory since some editors use atomic save
        (create temp file + rename) which doesn't trigger inotify on the file itself.
        """
        if self._started:
            logger.warning("Window rules watcher already started")
            return

        watch_dir = self.config_file.parent

        # Ensure directory exists
        watch_dir.mkdir(parents=True, exist_ok=True)

        # Start watchdog observer
        self.observer.schedule(self.handler, str(watch_dir), recursive=False)
        self.observer.start()
        self._started = True

        logger.info(f"Started watching {self.config_file} for modifications")

    def stop(self) -> None:
        """Stop watching for file modifications."""
        if not self._started:
            return

        self.observer.stop()
        self.observer.join(timeout=5.0)
        self._started = False

        logger.info(f"Stopped watching {self.config_file}")

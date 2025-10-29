"""
File watcher for Sway configuration files.

Monitors configuration files for changes and triggers automatic reload.
"""

import asyncio
import logging
from pathlib import Path
from typing import Callable, Optional, Set

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, FileSystemEvent

logger = logging.getLogger(__name__)


class ConfigFileHandler(FileSystemEventHandler):
    """Handles file system events for configuration files."""

    def __init__(self, callback: Callable, debounce_ms: int = 500):
        """
        Initialize file handler.

        Args:
            callback: Async function to call on file changes
            debounce_ms: Debounce delay in milliseconds
        """
        super().__init__()
        self.callback = callback
        self.debounce_ms = debounce_ms
        self.pending_events: Set[str] = set()
        self.debounce_task: Optional[asyncio.Task] = None
        self.loop = asyncio.get_event_loop()

    def on_modified(self, event: FileSystemEvent):
        """Handle file modification event."""
        if event.is_directory:
            return

        path = Path(event.src_path)

        # Only watch specific config files
        if path.suffix not in [".toml", ".json"] or path.name.startswith("."):
            return

        logger.debug(f"File modified: {path}")
        self.pending_events.add(str(path))

        # Schedule debounced reload
        if self.debounce_task:
            self.debounce_task.cancel()

        self.debounce_task = self.loop.create_task(self._debounced_reload())

    async def _debounced_reload(self):
        """Execute debounced reload after delay."""
        try:
            # Wait for debounce period
            await asyncio.sleep(self.debounce_ms / 1000.0)

            if self.pending_events:
                files = list(self.pending_events)
                self.pending_events.clear()

                logger.info(f"Triggering reload for {len(files)} changed files")
                await self.callback(files)

        except asyncio.CancelledError:
            # Debounce was cancelled - another event came in
            pass
        except Exception as e:
            logger.error(f"Error in debounced reload: {e}")


class FileWatcher:
    """Watches configuration files and triggers reloads."""

    def __init__(self, config_dir: Path, reload_callback: Callable, debounce_ms: int = 500):
        """
        Initialize file watcher.

        Args:
            config_dir: Configuration directory to watch
            reload_callback: Async function to call on file changes
            debounce_ms: Debounce delay in milliseconds
        """
        self.config_dir = config_dir
        self.reload_callback = reload_callback
        self.debounce_ms = debounce_ms

        self.observer: Optional[Observer] = None
        self.handler: Optional[ConfigFileHandler] = None
        self.running = False

    def start(self):
        """Start file watcher."""
        if self.running:
            logger.warning("File watcher already running")
            return

        logger.info(f"Starting file watcher for {self.config_dir}")

        self.handler = ConfigFileHandler(
            callback=self.reload_callback,
            debounce_ms=self.debounce_ms
        )

        self.observer = Observer()
        self.observer.schedule(
            self.handler,
            path=str(self.config_dir),
            recursive=True
        )

        self.observer.start()
        self.running = True

        logger.info("File watcher started")

    def stop(self):
        """Stop file watcher."""
        if not self.running:
            return

        logger.info("Stopping file watcher")

        if self.observer:
            self.observer.stop()
            self.observer.join()

        self.running = False
        logger.info("File watcher stopped")

    def is_running(self) -> bool:
        """
        Check if file watcher is running.

        Returns:
            True if running, False otherwise
        """
        return self.running
